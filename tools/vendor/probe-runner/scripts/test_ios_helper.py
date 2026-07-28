#!/usr/bin/env python3
"""Tests for _ios.py — booted-sim discovery, no-target auto-recovery, and
the actionable remediation message.

Runnable: python3 scripts/test_ios_helper.py   (also pytest-collectable)
No framework — assert-based, mirrors test_color_assert.py's style.
Fully offline: subprocess.run and shutil.which are stubbed; no simulator,
no idb, no xcrun is ever invoked for real.
"""
from __future__ import annotations

import contextlib
import io
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _ios  # noqa: E402

UDID = "CAFC93F7-5815-4A86-B9FA-95123DE3018C"
OTHER = "11111111-2222-3333-4444-555555555555"
IDB = "/usr/local/bin/idb"
XCRUN = "/usr/bin/xcrun"

NO_COMPANION_ERR = ("No udid provided and there no companions, unclear which "
                    "target to run against. Please specify a UDID")


def _cp(argv, rc, stdout=None, stderr=None):
    return subprocess.CompletedProcess(argv, rc, stdout, stderr)


def _simctl_json(*pairs):
    """pairs of (udid, state) -> `simctl list devices --json` payload."""
    return json.dumps({"devices": {
        "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [
            {"udid": u, "state": s, "name": f"sim-{u}"} for u, s in pairs]}})


class _FakeProc:
    """Minimal Popen stand-in: rc=None means 'still running'."""
    def __init__(self, argv, rc, out="", err=""):
        self.argv = argv
        self._rc = rc
        self._out = out
        self._err = err
        self.stdout = io.StringIO(out)
        self.stderr = io.StringIO(err)

    def poll(self):
        return self._rc

    @property
    def returncode(self):
        return self._rc

    def communicate(self):
        return self._out, self._err

    def terminate(self):
        self._rc = 0


class _Env:
    """Swap in a scripted subprocess.run (+ optional Popen) + shutil.which;
    restore on exit.

    script(argv, kw) -> CompletedProcess. popen(argv, kw) -> _FakeProc.
    Every invocation is recorded in .calls / .popen_calls as plain argv lists.
    """
    def __init__(self, script, which=None, popen=None):
        self.calls = []
        self.popen_calls = []
        self._script = script
        self._popen = popen
        self._which = which if which is not None else {"idb": IDB, "xcrun": XCRUN}

    def __enter__(self):
        self._saved = (subprocess.run, subprocess.Popen, shutil.which)

        def fake_run(argv, **kw):
            argv = list(argv)
            self.calls.append(argv)
            return self._script(argv, kw)

        def fake_popen(argv, **kw):
            argv = list(argv)
            self.popen_calls.append(argv)
            return self._popen(argv, kw)

        subprocess.run = fake_run
        if self._popen is not None:
            subprocess.Popen = fake_popen
        shutil.which = lambda b: self._which.get(b)
        return self

    def __exit__(self, *exc):
        subprocess.run, subprocess.Popen, shutil.which = self._saved
        return False

    def count(self, *fragments):
        """Calls whose argv contains every fragment (in order given)."""
        return sum(1 for c in self.calls
                   if all(any(f in a for a in c) for f in fragments))


@contextlib.contextmanager
def _pinned(udid):
    """Set PROBE_RUNNER_IOS_UDID for the block; restore on exit."""
    old = os.environ.get(_ios.ENV_UDID)
    os.environ[_ios.ENV_UDID] = udid
    try:
        yield
    finally:
        if old is None:
            os.environ.pop(_ios.ENV_UDID, None)
        else:
            os.environ[_ios.ENV_UDID] = old


def _die_message(fn):
    """Run fn expecting SystemExit; return (exit_code, captured stderr)."""
    buf = io.StringIO()
    code = None
    with contextlib.redirect_stderr(buf):
        try:
            fn()
        except SystemExit as e:
            code = e.code
    assert code is not None, "expected SystemExit"
    return code, buf.getvalue()


# ─── _is_no_target_failure ───────────────────────────────────────────────────

def test_predicate_matches_idb_wordings():
    assert _ios._is_no_target_failure(NO_COMPANION_ERR)
    assert _ios._is_no_target_failure("No Companion Connected")
    assert _ios._is_no_target_failure("... and there no companions ...")
    # case-insensitive
    assert _ios._is_no_target_failure("NO UDID PROVIDED")
    assert _ios._is_no_target_failure("no companion connected")
    # stale companion socket (process died, socket file left behind)
    assert _ios._is_no_target_failure(
        "Failed to connect to companion at address "
        "DomainSocketAddress(path='/tmp/idb/X_companion.sock'): "
        "[Errno 61] Connection refused")


def test_predicate_rejects_other_failures():
    assert not _ios._is_no_target_failure("")
    assert not _ios._is_no_target_failure("idb ui tap failed rc=1")
    assert not _ios._is_no_target_failure("Target is not booted")


# ─── _booted_udids ───────────────────────────────────────────────────────────

def test_booted_udids_parses_only_booted():
    def script(argv, kw):
        return _cp(argv, 0, stdout=_simctl_json(
            ("SHUT-1", "Shutdown"), (UDID, "Booted"), (OTHER, "Booted")))
    with _Env(script):
        assert _ios._booted_udids() == [UDID, OTHER]


def test_booted_udids_xcrun_missing_returns_empty():
    with _Env(lambda a, k: _cp(a, 0), which={"idb": IDB}):  # no xcrun on PATH
        assert _ios._booted_udids() == []


def test_booted_udids_bad_json_returns_empty():
    with _Env(lambda a, k: _cp(a, 0, stdout="not json")):
        assert _ios._booted_udids() == []


def test_booted_udids_simctl_failure_returns_empty():
    with _Env(lambda a, k: _cp(a, 1, stdout="", stderr="boom")):
        assert _ios._booted_udids() == []


def test_booted_udids_oserror_returns_empty():
    def boom(argv, kw):
        raise OSError("no such file")
    with _Env(boom):
        assert _ios._booted_udids() == []


# ─── idb_run: auto-recovery ──────────────────────────────────────────────────

def test_no_companion_one_booted_sim_connects_and_retries_once():
    """idb fails no-companion, exactly one sim booted -> one `idb connect`,
    original command retried exactly once, retry's result returned."""
    taps = {"n": 0}

    def script(argv, kw):
        if "simctl" in argv:
            return _cp(argv, 0, stdout=_simctl_json((UDID, "Booted")))
        if argv[1:2] == ["connect"]:
            return _cp(argv, 0, stdout="", stderr="")
        taps["n"] += 1
        if taps["n"] == 1:
            return _cp(argv, 1, stdout="", stderr=NO_COMPANION_ERR)
        return _cp(argv, 0, stdout="tapped", stderr="")

    with _Env(script) as env:
        r = _ios.idb_run(["ui", "tap", "100", "200"], capture=True)
        assert r.returncode == 0 and r.stdout == "tapped"
        assert env.count("connect", UDID) == 1, env.calls
        assert env.count("ui", "tap") == 2, env.calls
        # order: tap -> simctl -> connect -> tap
        seq = [("connect" if "connect" in c else
                "simctl" if "simctl" in c else "tap") for c in env.calls]
        assert seq == ["tap", "simctl", "connect", "tap"], seq


def test_persistent_failure_dies_with_actionable_remediation():
    """Retry also fails -> SystemExit; message keeps the probe-runner prefix,
    the original idb stderr, and states the exact fix commands with the
    booted UDID filled in. Never loops: connect x1, command x2."""
    def script(argv, kw):
        if "simctl" in argv:
            return _cp(argv, 0, stdout=_simctl_json((UDID, "Booted")))
        return _cp(argv, 1, stdout="", stderr=NO_COMPANION_ERR)

    with _Env(script) as env:
        code, err = _die_message(
            lambda: _ios.idb_run(["ui", "tap", "100", "200"], capture=True))
        assert code == 1, code
        assert err.startswith("probe-runner: "), err
        assert NO_COMPANION_ERR in err                       # original stderr kept
        assert f"idb_companion --udid {UDID}" in err, err    # exact commands,
        assert f"idb connect {UDID}" in err, err             # UDID filled in
        assert "--udid" in err                               # explicit-flag escape hatch
        assert env.count("connect", UDID) == 1, env.calls    # one connect, no loop
        assert env.count("ui", "tap") == 2, env.calls        # one retry, no loop


def test_success_first_try_no_connect_no_simctl():
    """idb succeeds -> zero recovery machinery (no connect, no simctl)."""
    def script(argv, kw):
        return _cp(argv, 0, stdout='{"ok": true}', stderr="")

    with _Env(script) as env:
        r = _ios.idb_run(["describe", "--json"], capture=True)
        assert r.returncode == 0
        assert env.calls == [[IDB, "describe", "--json"]], env.calls


def test_non_no_target_failure_does_not_connect():
    """Predicate miss (some other idb error) -> no connect attempted; the
    death message still carries actionable remediation for the one booted sim."""
    def script(argv, kw):
        if "simctl" in argv:
            return _cp(argv, 0, stdout=_simctl_json((UDID, "Booted")))
        return _cp(argv, 3, stdout="", stderr="some unrelated idb error")

    with _Env(script) as env:
        code, err = _die_message(
            lambda: _ios.idb_run(["ui", "tap", "1", "2"], capture=True))
        assert code == 3, code
        assert "some unrelated idb error" in err
        assert f"idb connect {UDID}" in err                  # remediation, not recovery
        assert env.count("connect") == 0, env.calls          # ...but no connect run
        assert env.count("ui", "tap") == 1, env.calls        # no retry either


def test_capture_false_path_no_regression():
    """capture=False -> stderr/stdout are None: predicate cannot match, so no
    recovery; the fallback 'failed rc=N' message plus remediation still print."""
    def script(argv, kw):
        if "simctl" in argv:
            return _cp(argv, 0, stdout=_simctl_json((UDID, "Booted")))
        return _cp(argv, 1)  # stdout=None, stderr=None

    with _Env(script) as env:
        code, err = _die_message(lambda: _ios.idb_run(["ui", "tap", "1", "2"]))
        assert code == 1, code
        assert "idb ui tap 1 2 failed rc=1" in err, err
        assert f"idb connect {UDID}" in err, err
        assert env.count("connect") == 0, env.calls


def test_multiple_booted_sims_recovers_first_with_warning():
    """2 booted, no env pin -> warn loudly (naming the pick + env override),
    connect the FIRST booted, retry pinned to it via --udid. (New contract —
    was: refuse to guess and only list the UDIDs.)"""
    taps = {"n": 0}

    def script(argv, kw):
        if "simctl" in argv:
            return _cp(argv, 0, stdout=_simctl_json(
                (UDID, "Booted"), (OTHER, "Booted")))
        if argv[1:2] == ["connect"]:
            return _cp(argv, 0)
        taps["n"] += 1
        if taps["n"] == 1:
            return _cp(argv, 1, stdout="", stderr=NO_COMPANION_ERR)
        return _cp(argv, 0, stdout="tapped", stderr="")

    buf = io.StringIO()
    with _Env(script) as env, contextlib.redirect_stderr(buf):
        r = _ios.idb_run(["ui", "tap", "1", "2"], capture=True)
        assert r.returncode == 0
        assert env.count("connect", UDID) == 1, env.calls
        retries = [c for c in env.calls if "tap" in c]
        assert retries[-1][-2:] == ["--udid", UDID], retries
        warn = buf.getvalue()
        assert "multiple booted sims" in warn, warn
        assert UDID in warn and OTHER in warn, warn
        assert _ios.ENV_UDID in warn, warn


def test_multiple_booted_persistent_failure_lists_all_and_env_var():
    """Recovery tried once (connect first + retry), still failing -> die
    message lists every booted UDID and names the env-var override."""
    def script(argv, kw):
        if "simctl" in argv:
            return _cp(argv, 0, stdout=_simctl_json(
                (UDID, "Booted"), (OTHER, "Booted")))
        return _cp(argv, 1, stdout="", stderr=NO_COMPANION_ERR)

    with _Env(script) as env:
        code, err = _die_message(
            lambda: _ios.idb_run(["ui", "tap", "1", "2"], capture=True))
        assert code == 1, code
        assert UDID in err and OTHER in err, err
        assert _ios.ENV_UDID in err, err
        assert env.count("connect", UDID) == 1, env.calls
        assert env.count("ui", "tap") == 2, env.calls


def test_env_pin_injects_udid_on_first_attempt():
    """PROBE_RUNNER_IOS_UDID pins the target: --udid is appended before the
    first attempt, and booted-sim discovery is never consulted."""
    def script(argv, kw):
        return _cp(argv, 0, stdout="ok", stderr="")

    with _pinned(OTHER), _Env(script) as env:
        r = _ios.idb_run(["describe", "--json"], capture=True)
        assert r.returncode == 0
        assert env.calls[0] == [IDB, "describe", "--json", "--udid", OTHER], env.calls
        assert not any("simctl" in c for c in env.calls), env.calls


def test_env_pin_does_not_override_callers_own_udid():
    """A --udid already in args always wins over the env pin."""
    def script(argv, kw):
        return _cp(argv, 0, stdout="ok", stderr="")

    with _pinned(OTHER), _Env(script) as env:
        r = _ios.idb_run(["ui", "tap", "1", "2", "--udid", UDID], capture=True)
        assert r.returncode == 0
        assert env.calls[0] == [IDB, "ui", "tap", "1", "2", "--udid", UDID], env.calls


def test_streaming_stdout_failure_classifies_and_recovers():
    """stdout streamed (file object): stderr is still captured, so the
    no-target class recovers exactly like the captured path (connect + one
    retry). Previously this path could not classify at all."""
    runs = {"n": 0}

    def script(argv, kw):
        if "simctl" in argv:
            return _cp(argv, 0, stdout=_simctl_json((UDID, "Booted")))
        if argv[1:2] == ["connect"]:
            return _cp(argv, 0)
        runs["n"] += 1
        if runs["n"] == 1:
            return _cp(argv, 1, stdout="", stderr=NO_COMPANION_ERR)
        return _cp(argv, 0, stdout="", stderr="")

    with _Env(script) as env:
        r = _ios.idb_run(["log"], stdout=io.StringIO())
        assert r.returncode == 0
        assert env.count("connect", UDID) == 1, env.calls
        assert sum(1 for c in env.calls if "log" in c) == 2, env.calls


def test_streaming_stdout_success_relays_stderr():
    """Streaming success: captured stderr is relayed to our stderr so idb's
    connection chatter is not hidden."""
    def script(argv, kw):
        return _cp(argv, 0, stdout="", stderr="companion chatter\n")

    with _Env(script):
        buf = io.StringIO()
        with contextlib.redirect_stderr(buf):
            r = _ios.idb_run(["log"], stdout=io.StringIO())
        assert r.returncode == 0
        assert "companion chatter" in buf.getvalue(), buf.getvalue()


def test_popen_alive_after_grace_returns_handle_no_recovery():
    """Stream survives the grace window -> live handle, zero recovery."""
    def popen(argv, kw):
        return _FakeProc(argv, None)

    def script(argv, kw):
        return _cp(argv, 0)

    with _Env(script, popen=popen) as env:
        proc = _ios.idb_popen(["log"], grace=0.01)
        assert proc.poll() is None
        assert env.calls == [], env.calls          # no simctl, no connect
        assert env.popen_calls == [[IDB, "log"]], env.popen_calls


def test_popen_early_no_target_exit_recovers_and_returns_live_handle():
    """Early exit with the no-companion error -> connect resolved target,
    respawn once pinned to it, return the live handle."""
    procs = {"n": 0}

    def popen(argv, kw):
        procs["n"] += 1
        if procs["n"] == 1:
            return _FakeProc(argv, 1, "", NO_COMPANION_ERR)
        return _FakeProc(argv, None)

    def script(argv, kw):
        if "simctl" in argv:
            return _cp(argv, 0, stdout=_simctl_json((UDID, "Booted")))
        return _cp(argv, 0)

    with _Env(script, popen=popen) as env:
        proc = _ios.idb_popen(["log"], grace=0.01)
        assert proc.poll() is None
        assert procs["n"] == 2, procs
        assert env.count("connect", UDID) == 1, env.calls
        assert env.popen_calls[-1][-2:] == ["--udid", UDID], env.popen_calls


def test_popen_persistent_early_exit_dies_with_remediation():
    """Respawn also dies early -> _die with the original error + actionable
    remediation; never loops (exactly 2 spawns)."""
    procs = {"n": 0}

    def popen(argv, kw):
        procs["n"] += 1
        return _FakeProc(argv, 1, "", NO_COMPANION_ERR)

    def script(argv, kw):
        if "simctl" in argv:
            return _cp(argv, 0, stdout=_simctl_json((UDID, "Booted")))
        return _cp(argv, 0)

    with _Env(script, popen=popen):
        code, err = _die_message(lambda: _ios.idb_popen(["log"], grace=0.01))
        assert code == 1, code
        assert NO_COMPANION_ERR in err, err
        assert f"idb connect {UDID}" in err, err
        assert procs["n"] == 2, procs


def test_no_booted_sim_generic_remediation():
    """Nothing booted -> no connect; message still gives the two commands
    with a <udid> placeholder."""
    def script(argv, kw):
        if "simctl" in argv:
            return _cp(argv, 0, stdout=_simctl_json(("SHUT-1", "Shutdown")))
        return _cp(argv, 1, stdout="", stderr=NO_COMPANION_ERR)

    with _Env(script) as env:
        code, err = _die_message(
            lambda: _ios.idb_run(["ui", "tap", "1", "2"], capture=True))
        assert code == 1, code
        assert "idb_companion --udid <udid>" in err, err
        assert "idb connect <udid>" in err, err
        assert env.count("connect") == 0, env.calls


def _run():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    passed = 0
    for t in tests:
        try:
            t()
            print(f"PASS {t.__name__}")
            passed += 1
        except AssertionError as e:
            print(f"FAIL {t.__name__}: {e}")
            return 1
    print(f"\nALL GREEN ({passed}/{len(tests)} checks)")
    return 0


if __name__ == "__main__":
    sys.exit(_run())
