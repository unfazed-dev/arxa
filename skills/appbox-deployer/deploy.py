#!/usr/bin/env python3
"""appbox-deployer — the deploy mechanics, behind the strictest human gate.

Architecture §17 / plan 11. The deploy kit (`appbox_kit_deploy`, vendored as a
skill, vendored as kit/deploy) is pure-Dart, standalone, registry
`phase: stable`. Its targets:

    fastlane-android / fastlane-ios   wired
    shorebird-release / shorebird-patch   wired
    cloudflare-pages   wired
    vercel   STUB — throws UnimplementedError, NEVER offered

This module drives those targets' external CLIs through a `ProcessRunner` port
(mirrors the deploy kit's KitProcessRunner seam, and appboxd/lib/tier1.dart).
The scripted runner asserts every command shape with NO toolchain, NO
credentials, NO signing identity — the one property that makes a deploy stage
self-testable (§17). A deploy normally cannot be self-tested; this one can.

THE TWO THINGS THIS MODULE WILL NOT DO
  1. Mint an approval token. Deploy is the third human gate (§17): it names the
     target, the version and the account, and a person confirms that exact
     triple. `deploy()` REQUIRES that approval as an argument; an automated run
     reaches the gate and halts, minting nothing. The confirmation itself lives
     in pipeline state (approvalTokens.deploy) and is asserted by gates/deploy.
  2. Offer vercel. It throws; it is excluded from OFFERED. gates/advertise
     independently rejects any offer of a stub-tier provider — two enforcements
     of the same rule.

Usage:
  deploy.py --self-test                      # assert all shapes, no credentials
  deploy.py doctor [--config <f>]            # preflight readiness report (NOT a gate)
  deploy.py deploy --target T --version V --account A --approval <tok> [--ledger <f>]

Ledger path defaults to pipeline/state/deploy-ledger.json (derived from the repo
root, never a literal — R3), overridable via --ledger or APPBOX_DEPLOY_LEDGER.
The ledger is append-only and records EVERY attempt, including one that halted
at the gate. Stdlib only.
"""
from __future__ import annotations
import argparse
import json
import os
import sys
import time
from dataclasses import dataclass, field, asdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # skills/appbox-deployer/ -> repo root
DEF_LEDGER = ROOT / "pipeline" / "state" / "deploy-ledger.json"


# --------------------------------------------------------------------------- #
# Process runner port (mirrors the deploy kit's KitProcessRunner seam,
# and appboxd/lib/tier1.dart — same shape, one place to fake the world)
# --------------------------------------------------------------------------- #
class CompletedProc:
    def __init__(self, exit_code, stdout="", stderr=""):
        self.exit_code = exit_code
        self.stdout = stdout
        self.stderr = stderr

    @property
    def ok(self):
        return self.exit_code == 0


class RealRunner:
    """Shells out to a real CLI. Unused by the self-test (Tier-1 needs no
    toolchain) — present so the port's real path is honest, not hidden."""

    def run(self, argv, env=None):
        import subprocess
        r = subprocess.run(argv, env=env, capture_output=True, text=True)
        return CompletedProc(r.returncode, r.stdout, r.stderr)


class ScriptedRunner:
    """Fake runner: preloaded with the exact commands the port must issue, in
    order. Each `run` asserts the argv matches the next expectation and returns
    its canned result. Proves the port calls the CLI correctly."""

    def __init__(self, expectations):
        # expectations: list of (argv_prefix, result)
        self._expectations = list(expectations)
        self._i = 0

    def run(self, argv, env=None):
        if self._i >= len(self._expectations):
            raise AssertionError(
                f"port issued an unexpected extra command: {argv} "
                f"(suite expected only {len(self._expectations)})")
        want_prefix, result = self._expectations[self._i]
        if list(argv[:len(want_prefix)]) != list(want_prefix):
            raise AssertionError(
                f"port called the wrong command:\n  expected prefix {want_prefix}\n"
                f"  got                  {list(argv[:len(want_prefix)])}")
        self._i += 1
        return result


# --------------------------------------------------------------------------- #
# Deploy result + attempt (ledger row)
# --------------------------------------------------------------------------- #
@dataclass
class DeployResult:
    ok: bool
    target: str
    artefact_id: str | None = None
    error: str | None = None
    halted: bool = False


@dataclass
class DeployAttempt:
    """One row in the deploy ledger. Records EVERY attempt — shipped or halted."""
    target: str
    version: str
    account: str
    approver: str | None        # None until a person confirms (a halted run mints none)
    timestamp: str
    artefact_id: str | None     # None for a halted run
    status: str                 # "shipped" | "halted"


# --------------------------------------------------------------------------- #
# Target ports — each builds the external CLI command shape and reads the result.
# The argv is the contract the scripted runner asserts; the real runner shells out.
# --------------------------------------------------------------------------- #
def fastlane_ios(runner, version):
    """iOS store lane: build (gym) -> sign (match) -> upload to TestFlight.
    `fastlane run <action>` is the real CLI form for each lane action."""
    runner.run(["fastlane", "run", "gym", "--version", version])
    runner.run(["fastlane", "run", "match"])
    up = runner.run(["fastlane", "run", "upload_to_testflight"])
    if not up.ok:
        return DeployResult(False, "fastlane-ios", error="testflight upload failed: " + up.stderr)
    return DeployResult(True, "fastlane-ios", artefact_id=up.stdout.strip() or "tf_build_demo")


def fastlane_android(runner, version):
    """Android store lane: build aab -> upload to Play (internal track)."""
    runner.run(["flutter", "build", "appbundle", "--build-name", version])
    up = runner.run(["fastlane", "run", "upload_to_play_store", "--track", "internal"])
    if not up.ok:
        return DeployResult(False, "fastlane-android", error="play upload failed: " + up.stderr)
    return DeployResult(True, "fastlane-android", artefact_id=up.stdout.strip() or "play_vc_demo")


def shorebird_release(runner, version):
    """Shorebird full release (native + Dart) -> a shorebird release id."""
    r = runner.run(["shorebird", "release", "release-version", "--version", version])
    if not r.ok:
        return DeployResult(False, "shorebird-release", error="shorebird release failed: " + r.stderr)
    return DeployResult(True, "shorebird-release", artefact_id=r.stdout.strip() or "shorebird_rel_demo")


def shorebird_patch(runner, version):
    """Shorebird OTA Dart patch (no store round-trip). Patches Dart only."""
    r = runner.run(["shorebird", "release", "patch", "--version", version])
    if not r.ok:
        return DeployResult(False, "shorebird-patch", error="shorebird patch failed: " + r.stderr)
    return DeployResult(True, "shorebird-patch", artefact_id=r.stdout.strip() or "shorebird_patch_demo")


def cloudflare_pages(runner, version):
    """Cloudflare Pages deploy via wrangler -> a deployment URL."""
    r = runner.run(["wrangler", "pages", "deploy", "--commit-dirty", "--version", version])
    if not r.ok:
        return DeployResult(False, "cloudflare-pages", error="pages deploy failed: " + r.stderr)
    return DeployResult(True, "cloudflare-pages", artefact_id=r.stdout.strip() or "https://demo.pages.dev")


def vercel(runner, version):
    """STUB. Throws UnimplementedError — vercel is not wired and is NEVER offered
    (plan 11.2; gates/advertise rejects stub-tier providers). Do not remove the
    throw to 'wire it quickly' — the whole point is honest non-availability."""
    raise NotImplementedError("vercel deploy is a stub (phase-later); not offered")


# The deploy contract: name -> (port, status). status is "wired" or "stub".
# These are the kit's fixed target vocabulary (like tier1's provider ports), not
# project-varying config — version/account/approver/ledger-path are the config.
TARGETS = {
    "fastlane-ios":     (fastlane_ios,        "wired"),
    "fastlane-android": (fastlane_android,    "wired"),
    "shorebird-release": (shorebird_release,  "wired"),
    "shorebird-patch":  (shorebird_patch,     "wired"),
    "cloudflare-pages": (cloudflare_pages,    "wired"),
    "vercel":           (vercel,              "stub"),
}

# OFFERED = wired targets only. vercel (stub) is excluded — plan 11.2.
# gates/advertise independently enforces this against the registry; this is the
# skill-side defence in depth (a stub target is never surfaced to an operator).
OFFERED = sorted(n for n, (_, s) in TARGETS.items() if s == "wired")


# --------------------------------------------------------------------------- #
# doctor — preflight readiness report. NOT a gate (§17 / 11.3).
# --------------------------------------------------------------------------- #
def doctor(config=None):
    """Report what is wired and what is configured. Returns a report dict; never
    raises on a missing config and never decides whether a deploy may proceed —
    that is the gate's job (gates/deploy asserts a VALUE). doctor reports only."""
    configured = []
    if config and os.path.isfile(config):
        try:
            with open(config, encoding="utf-8") as f:
                cfg = json.load(f)
            if isinstance(cfg, dict):
                configured = sorted(cfg.get("targets", []) or [])
        except (OSError, ValueError):
            configured = []
    return {
        "offered": OFFERED,
        "stub_not_offered": sorted(n for n, (_, s) in TARGETS.items() if s == "stub"),
        "configured_targets": configured,
        "ready": "preflight report — the gates/deploy gate asserts the deploy triple, not this",
    }


# --------------------------------------------------------------------------- #
# Ledger — append-only, records every attempt (shipped AND halted). 11.6.
# --------------------------------------------------------------------------- #
def record_ledger(attempt: DeployAttempt, ledger_path):
    ledger_path = Path(ledger_path)
    ledger = {"attempts": []}
    if ledger_path.is_file():
        try:
            with open(ledger_path, encoding="utf-8") as f:
                ledger = json.load(f)
            if not isinstance(ledger, dict) or not isinstance(ledger.get("attempts"), list):
                ledger = {"attempts": []}
        except (OSError, ValueError):
            ledger = {"attempts": []}
    ledger["attempts"].append(asdict(attempt))
    ledger_path.parent.mkdir(parents=True, exist_ok=True)
    with open(ledger_path, "w", encoding="utf-8") as f:
        f.write(json.dumps(ledger, indent=2, ensure_ascii=False) + "\n")


# --------------------------------------------------------------------------- #
# deploy — the mechanics. REQUIRES the human approval; never mints it (11.5).
# --------------------------------------------------------------------------- #
class DeployHalted(Exception):
    """Raised when deploy() is asked to run without the confirmed triple +
    approval. The automated run reached the gate and stopped, minting nothing."""


def deploy(target, version, account, approval, runner, ledger_path):
    """Run a target's command shapes through `runner` and record the attempt.

    The triple (target, version, account) and a non-empty approval MUST all be
    present — this is the gate contract (§17). If any is missing, the attempt is
    recorded as HALTED (no artefact, no recorded approver) and DeployHalted is
    raised. The function never synthesises an approval token: an automated run
    that reaches this point without a human's confirmation stops here.
    """
    missing = [n for n, v in (("target", target), ("version", version),
                              ("account", account), ("approval", approval)) if not v]
    ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    if missing:
        # Record the halted attempt — the ledger shows the run reached the gate.
        record_ledger(DeployAttempt(
            target=target or "", version=version or "", account=account or "",
            approver=None, timestamp=ts, artefact_id=None, status="halted"), ledger_path)
        raise DeployHalted(
            "deploy halted at the gate — missing " + ", ".join(missing) +
            ". An agent may prepare and preflight but never mint the approval token.")
    if target not in TARGETS:
        record_ledger(DeployAttempt(
            target=target, version=version, account=account, approver=approval,
            timestamp=ts, artefact_id=None, status="halted"), ledger_path)
        raise DeployHalted(f"deploy halted — unknown target '{target}'")
    port, status = TARGETS[target]
    if status == "stub":
        record_ledger(DeployAttempt(
            target=target, version=version, account=account, approver=approval,
            timestamp=ts, artefact_id=None, status="halted"), ledger_path)
        raise DeployHalted(f"deploy halted — target '{target}' is a stub and is not offered")
    res = port(runner, version)
    record_ledger(DeployAttempt(
        target=target, version=version, account=account, approver=approval,
        timestamp=ts, artefact_id=res.artefact_id,
        status="shipped" if res.ok else "halted"), ledger_path)
    if not res.ok:
        raise DeployHalted(f"deploy halted — {target} failed: {res.error}")
    return res


# --------------------------------------------------------------------------- #
# Self-test — assert-based, no framework. Exercises every shape under the
# scripted runner with no toolchain and no credentials (11.7).
# --------------------------------------------------------------------------- #
def _expect(expectations, action):
    r = ScriptedRunner(expectations)
    return r, action(r)


def test_fastlane_ios_shape():
    r, res = _expect([
        (["fastlane", "run", "gym"], CompletedProc(0)),
        (["fastlane", "run", "match"], CompletedProc(0)),
        (["fastlane", "run", "upload_to_testflight"], CompletedProc(0, "tf_build_77")),
    ], lambda run: fastlane_ios(run, "1.2.3"))
    assert r._i == 3, "fastlane-ios did not issue gym -> match -> upload"
    assert res.ok and res.artefact_id == "tf_build_77", res.__dict__
    # upload failure is surfaced, not swallowed
    r, res = _expect([
        (["fastlane", "run", "gym"], CompletedProc(0)),
        (["fastlane", "run", "match"], CompletedProc(0)),
        (["fastlane", "run", "upload_to_testflight"], CompletedProc(1, stderr="api 401")),
    ], lambda run: fastlane_ios(run, "1.2.3"))
    assert not res.ok and "api 401" in res.error, res.__dict__


def test_fastlane_android_shape():
    r, res = _expect([
        (["flutter", "build", "appbundle"], CompletedProc(0)),
        (["fastlane", "run", "upload_to_play_store"], CompletedProc(0, "play_vc_401")),
    ], lambda run: fastlane_android(run, "1.2.3"))
    assert r._i == 2, "fastlane-android did not issue build -> upload"
    assert res.ok and res.artefact_id == "play_vc_401", res.__dict__


def test_shorebird_release_shape():
    r, res = _expect([
        (["shorebird", "release", "release-version"], CompletedProc(0, "shorebird_rel_9")),
    ], lambda run: shorebird_release(run, "1.2.3"))
    assert res.ok and res.artefact_id == "shorebird_rel_9", res.__dict__


def test_shorebird_patch_shape():
    r, res = _expect([
        (["shorebird", "release", "patch"], CompletedProc(0, "shorebird_patch_3")),
    ], lambda run: shorebird_patch(run, "1.2.4"))
    assert res.ok and res.artefact_id == "shorebird_patch_3", res.__dict__


def test_cloudflare_pages_shape():
    r, res = _expect([
        (["wrangler", "pages", "deploy"], CompletedProc(0, "https://app.pages.dev")),
    ], lambda run: cloudflare_pages(run, "1.2.3"))
    assert res.ok and res.artefact_id == "https://app.pages.dev", res.__dict__


def test_vercel_is_stub_and_not_offered():
    # vercel throws (honest non-availability) — Done-when #2
    try:
        vercel(ScriptedRunner([]), "1.2.3")
    except NotImplementedError as e:
        assert "stub" in str(e).lower(), e
    else:
        raise AssertionError("vercel must throw UnimplementedError (it is a stub)")
    # and it is not surfaced to an operator
    assert "vercel" not in OFFERED, OFFERED
    assert TARGETS["vercel"][1] == "stub"


def test_offered_is_exactly_the_wired_set():
    assert OFFERED == ["cloudflare-pages", "fastlane-android", "fastlane-ios",
                       "shorebird-patch", "shorebird-release"], OFFERED


def test_doctor_is_preflight_not_gate():
    # doctor returns a report; it never decides whether a deploy may proceed.
    rep = doctor()
    assert "ready" in rep and "gate" in rep["ready"], rep
    assert "vercel" in rep["stub_not_offered"], rep
    assert rep["offered"] == OFFERED, rep


def test_deploy_halts_without_approval(tmp_ledger):
    # Done-when #4: an automated run reaches the gate and halts, minting nothing.
    # No approval token -> DeployHalted, no artefact, no recorded approver.
    try:
        deploy("fastlane-ios", "1.2.3", "totem-labs", "", ScriptedRunner([]), tmp_ledger)
    except DeployHalted as e:
        assert "approval" in str(e), e
    else:
        raise AssertionError("deploy without approval must halt")
    led = json.load(open(tmp_ledger))["attempts"]
    assert len(led) == 1 and led[0]["status"] == "halted", led
    assert led[0]["artefact_id"] is None and led[0]["approver"] is None, led
    # missing version / account / target each halt too
    for kw, kwvars in (("version", dict(target="fastlane-ios", version="", account="a", approval="ok")),
                       ("account", dict(target="fastlane-ios", version="1", account="", approval="ok")),
                       ("target", dict(target="", version="1", account="a", approval="ok"))):
        try:
            deploy(runner=ScriptedRunner([]), ledger_path=tmp_ledger, **kwvars)
        except DeployHalted as e:
            assert kw in str(e), (kw, e)
        else:
            raise AssertionError(f"deploy missing {kw} must halt")


def test_deploy_records_full_attempt(tmp_ledger):
    # Done-when #5: a confirmed deploy records a full ledger row with an artefact id.
    r, res = _expect([
        (["fastlane", "run", "gym"], CompletedProc(0)),
        (["fastlane", "run", "match"], CompletedProc(0)),
        (["fastlane", "run", "upload_to_testflight"], CompletedProc(0, "tf_build_512")),
    ], lambda run: deploy("fastlane-ios", "1.2.3", "totem-labs", "ops@totem",
                          run, tmp_ledger))
    assert res.ok and res.artefact_id == "tf_build_512", res.__dict__
    led = json.load(open(tmp_ledger))["attempts"]
    row = led[-1]
    assert row["status"] == "shipped" and row["artefact_id"] == "tf_build_512", row
    assert row["target"] == "fastlane-ios" and row["version"] == "1.2.3", row
    assert row["account"] == "totem-labs" and row["approver"] == "ops@totem", row
    assert row["timestamp"] and row["timestamp"].endswith("Z"), row


def test_deploy_rejects_stub_target(tmp_ledger):
    # A stub target halts even WITH approval — vercel is never shipped.
    try:
        deploy("vercel", "1.2.3", "totem-labs", "ops@totem", ScriptedRunner([]), tmp_ledger)
    except DeployHalted as e:
        assert "stub" in str(e), e
    else:
        raise AssertionError("a stub target must halt even with approval")


SUITE = [
    test_fastlane_ios_shape,
    test_fastlane_android_shape,
    test_shorebird_release_shape,
    test_shorebird_patch_shape,
    test_cloudflare_pages_shape,
    test_vercel_is_stub_and_not_offered,
    test_offered_is_exactly_the_wired_set,
    test_doctor_is_preflight_not_gate,
    test_deploy_halts_without_approval,
    test_deploy_records_full_attempt,
    test_deploy_rejects_stub_target,
]


def _self_test():
    import tempfile
    tmp = Path(tempfile.mkdtemp()) / "deploy-ledger.json"
    # bind the ledger fixture into the tests that need it
    gl = {"tmp_ledger": str(tmp)}
    for fn in SUITE:
        import inspect
        kwargs = {k: gl[k] for k in inspect.signature(fn).parameters if k in gl}
        fn(**kwargs)
        print(f"  PASS  {fn.__name__}")
    print(f"deploy self-test: {len(SUITE)} passed")


def main(argv):
    ap = argparse.ArgumentParser(description="appbox-deployer mechanics (plan 11)")
    ap.add_argument("--self-test", action="store_true")
    sub = ap.add_subparsers(dest="cmd")
    d = sub.add_parser("doctor", help="preflight readiness report (NOT a gate)")
    d.add_argument("--config")
    p = sub.add_parser("deploy", help="run a target's command shapes (requires approval)")
    p.add_argument("--target", required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--account", required=True)
    p.add_argument("--approval", required=True)
    p.add_argument("--ledger", default=os.environ.get("APPBOX_DEPLOY_LEDGER", str(DEF_LEDGER)))
    args = ap.parse_args(argv)

    if args.self_test:
        _self_test()
        return 0
    if args.cmd == "doctor":
        print(json.dumps(doctor(args.config), indent=2))
        return 0
    if args.cmd == "deploy":
        try:
            res = deploy(args.target, args.version, args.account, args.approval,
                         RealRunner(), args.ledger)
        except DeployHalted as e:
            print(f"HALT: {e}", file=sys.stderr)
            return 1
        print(json.dumps(asdict(res), indent=2))
        return 0 if res.ok else 1
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
