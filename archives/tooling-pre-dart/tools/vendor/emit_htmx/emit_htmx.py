#!/usr/bin/env python3
"""emit_htmx.py — render each screen of the design/new-htmx htmx+Nunjucks
producer to a chrome-stripped, self-contained static HTML surface at
design/new-htmx/surfaces/<surface>.html.

The htmx sibling of tools/emit_playground (which freezes the React+Babel
producer to design/surfaces/). Same operational contract — same CLI, same
write-on-diff semantics, same exit discipline — over a different producer:
the htmx tree is a live node server, not a static bundle, so this tool boots
it, drives it, and always tears it down.

DESTINATION: design/new-htmx/surfaces/ — deliberately NOT design/new/surfaces/, which
is emit_playground's committed, diff-clean output. Two producers, two frozen
trees; clobbering one from the other would silently destroy an SSOT.

Usage:
  emit_htmx.py [--app <app-root>]     emit (default app root: $APPBOX_APP)
  emit_htmx.py --app <r> --check      pre-gate drift guard (writes nothing)
  emit_htmx.py --self-test            hermetic calibration (fixtures/)
  EMIT_RENDER=skip emit_htmx.py       skip the browser pass entirely

Exit discipline (freeze_design.sh precedent): 0 = every emitted surface
rendered error-free · 1 = registry missing / render, placeholder or extraction
failure / (with --check) drift · 2 = environment (no app root, no render
backend, no node, server failed to boot). Gates never auto-install: the
render-backend cascade is `uv run --with playwright` -> system python3 with
playwright importable -> exit 2 with install instructions.

Contract:
  - boot `node --import frozen_clock.mjs server.js` in <app>/design/new-htmx/
    on an ephemeral port, wait for its ready line on stdout, and ALWAYS tear
    it down (success, failure, or exception). A server that dies during the
    wait surfaces its own stderr and exits 2 — the usual cause is an absent
    node_modules (the tree gitignores it; `npm install` in new-htmx/).
  - the frozen clock is load-bearing, not a nicety: the tree reads Date.now()
    while rendering (player_facade.js), so without it train.player's elapsed
    timer moves between runs and write-on-diff can never be a no-op. See
    frozen_clock.mjs.
  - read models/screens_model/registry.json — [{id, label, surface, shell,
    phase, comp, roles?}]. `surface` is a canonical view name or null.
    NULL-SURFACE RULE: skipped, never invented, and always REPORTED (one
    `skip:` line each + a count in the summary). `surface` is the shared
    naming SSOT across producers; deriving a name here would mint a surface
    no other producer knows.
  - per entry with surface != null: pick the role that can actually see it
    (entry.roles[0], else comp-prefix Studio->leo / Admin->erika, else felix
    — the rule scripts/seed/sweep_htmx_routes.mjs already encodes), GET
    /?role=<role>&screen=<id>, settle ~1500ms, and fail on any console/page
    error. A role that cannot see a screen is bounced to the Phase-E
    placeholder, which renders a perfectly valid page — so the placeholder
    marker and the data-screen-label are both asserted, never assumed.
  - extract the SCREEN CONTENT only: the .phone-screen subtree with every
    design/exclusions.json `selectors` match stripped (the shared exclusions
    SSOT, same file emit_playground reads).
  - compose a standalone doc: fonts/tokens/app/hda CSS inlined as <style>,
    every /assets/... URL rewritten to ../assets/... so it resolves
    from new-htmx/surfaces/, and a timestamp-free GENERATED banner naming the
    source screen. Written on diff only.
"""
import argparse
import functools
import http.server
import importlib.util
import json
import os
import re
import shutil
import socket
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from urllib.parse import quote

TOOL = Path(__file__).resolve()
FIXTURE_APP = TOOL.parent / "fixtures" / "app"
CLOCK = TOOL.parent / "frozen_clock.mjs"
REPO = TOOL.parents[3]  # tools/vendor/emit_htmx/emit_htmx.py → repo root

# Mobile viewport is config-driven (R3: config/appbox.config.json viewports.mobile),
# not the 390×844 literal. Fallback only if config is absent/unreadable.
def _cfg_viewport():
    try:
        d = json.loads((REPO / "config" / "appbox.config.json").read_text())
        v = d["viewports"]["mobile"]
        return int(v["width"]), int(v["height"])
    except Exception:
        return 390, 844
VW, VH = _cfg_viewport()

# The screen-content root inside the htmx stage's iPhone frame: everything
# outside it (stage, toolbar, phone hardware, brand strip) is chrome by
# construction; chrome INSIDE it (dynamic island, status bar, home indicator)
# is stripped via the shared exclusions.json selectors.
CONTENT_ROOT = ".phone-screen"

# stage_viewmodel renders the Phase-E placeholder when the requested role
# cannot see the surface. It returns 200 with a clean console and its own
# data-screen-label, so only this copy distinguishes it from a real surface
# (scripts/seed/sweep_htmx_routes.mjs, trap 2).
PLACEHOLDER_MARK = "Phase E surface —"

# CSS the tree links from ui/common/base.html, in that order.
CSS_FILES = ("fonts.css", "tokens.css", "app.css", "hda.css")

# How the emitted surface reaches the producer's assets from new-htmx/surfaces/.
# surfaces/ lives INSIDE the producer folder (2026-07-25 reorg), so assets/ is
# exactly one level up. The pre-reorg rule (../new-htmx/assets/) resolved to
# design/new-htmx/new-htmx/assets/ and 404'd every font and video — which the
# freeze render gate reports as a console error, so the whole producer failed
# intake. Same defect, same fix, as emit_playground (../new/assets/ -> ../assets/);
# it was fixed there and never propagated here.
ASSET_PREFIX = "../assets/"

DOC = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="icon" href="data:,">
__BANNER__
<title>__SURFACE__</title>
<style>
__CSS__
</style>
</head>
<body>
__CONTENT__
</body>
</html>
"""

EXTRACT_JS = """(args) => {
  const root = document.querySelector(args.root);
  if (!root) return { ok: false, error: 'screen-content root not found: ' + args.root };
  const label = root.getAttribute('data-screen-label');
  const placeholder = root.innerHTML.includes(args.placeholderMark);
  const clone = root.cloneNode(true);
  for (const sel of args.selectors) {
    let hits;
    try { hits = clone.querySelectorAll(sel); }
    catch (e) { return { ok: false, error: 'bad exclusion selector ' + JSON.stringify(sel) }; }
    hits.forEach(n => n.remove());
  }
  return { ok: true, html: clone.outerHTML, label: label, placeholder: placeholder };
}"""


def banner(screen_id, role):
    return ("<!-- GENERATED by stacked_kit/tools/emit_htmx — do not hand-edit. "
            f"Source: design/new-htmx/ screen '{screen_id}' (role '{role}'). -->")


def strip_css_comments(css):
    return re.sub(r"/\*.*?\*/", "", css, flags=re.S)


def rewrite_assets(text):
    """Repoint every absolute /assets/... URL at the producer tree.

    The htmx tree serves assets from an absolute root (`/assets/...`), so an
    emitted surface opened from new-htmx/surfaces/ would resolve them against the
    filesystem root. Rewriting is per URL context rather than a blanket string
    replace so prose that merely contains the characters `/assets/` is never
    silently altered; `assert_assets_rewritten` then proves nothing was
    missed."""
    # attribute values: src="/assets/…", href='/assets/…', poster=, srcset=, …
    text = re.sub(r'(?P<a>(?:src|href|poster|srcset|data-src|content)=")/assets/',
                  lambda m: m.group("a") + ASSET_PREFIX, text)
    text = re.sub(r"(?P<a>(?:src|href|poster|srcset|data-src|content)=')/assets/",
                  lambda m: m.group("a") + ASSET_PREFIX, text)
    # CSS url() in stylesheets and inline style attributes, quoted or bare
    text = re.sub(r'url\((?P<q>["\']?)/assets/',
                  lambda m: "url(" + m.group("q") + ASSET_PREFIX, text)
    # srcset lists carry further ", /assets/… 2x" entries after the first
    text = re.sub(r'(?P<sep>,\s*)/assets/', lambda m: m.group("sep") + ASSET_PREFIX, text)
    return text


def assert_assets_rewritten(where, text, failures, surfaces_dir=None):
    """Fail loudly on any /assets/ URL the rewrite did not reach, AND on any
    rewritten URL that does not resolve on disk.

    A missed URL is a silently broken surface (a 404 image, an unstyled font),
    which is exactly the class of defect a freeze gate exists to catch — so it
    is a hard failure, never a warning.

    The second half is not redundant. Checking only for LEFTOVERS is vacuous
    against the failure that actually happened: ASSET_PREFIX pointed at
    ../new-htmx/assets/, every URL was dutifully rewritten, and every one of
    them 404'd. The string moved; the file was never there. So resolve them.
    """
    leftovers = sorted(set(re.findall(r'[("\'=]\s*/assets/[^)"\'\s>]*', text)))
    if leftovers:
        failures.append(f"{where}: {len(leftovers)} un-rewritten /assets/ URL(s): "
                        + ", ".join(x.strip() for x in leftovers[:4]))
    if not surfaces_dir:
        return
    missing = []
    for url in sorted(set(re.findall(r'[("\'=]\s*(\.\./assets/[^)"\'\s>]*)', text))):
        path = os.path.normpath(os.path.join(surfaces_dir, url.split("?", 1)[0].split("#", 1)[0]))
        if not os.path.exists(path):
            missing.append(url)
    if missing:
        failures.append(f"{where}: {len(missing)} rewritten asset URL(s) do not resolve "
                        f"(relative to {surfaces_dir}): " + ", ".join(missing[:4]))


def role_for(entry):
    """Which persona actually sees this surface.

    Mirrors scripts/seed/sweep_htmx_routes.mjs's roleFor — the htmx tree has
    no window.P2.roles table to consult, the role is derived from the registry
    entry itself."""
    roles = entry.get("roles")
    if isinstance(roles, list) and roles:
        return roles[0]
    comp = str(entry.get("comp") or "")
    if comp.startswith("Studio"):
        return "leo"
    if comp.startswith("Admin"):
        return "erika"
    return "felix"


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class ServerBootError(Exception):
    """The producer server could not be started — an environment fault."""


def boot_server(htmx_dir, port, extra_env=None):
    """Start the htmx producer on `port` and wait for its ready line.

    Readiness is the server's OWN stdout announcement, not a TCP poll: a poll
    cannot tell "not listening yet" from "died on import", and the common
    failure here IS death on import (new-htmx/node_modules is gitignored, so a
    fresh checkout has no nunjucks). Waiting on stdout lets a dead process be
    reported with its real stderr."""
    if not shutil.which("node"):
        raise ServerBootError("no `node` on PATH — the htmx producer is a node server")
    env = dict(os.environ, PORT=str(port))
    if extra_env:
        env.update(extra_env)
    proc = subprocess.Popen(
        ["node", "--import", CLOCK.as_uri(), "server.js"],
        cwd=str(htmx_dir), env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    out_lines, err_lines = [], []

    def pump(stream, sink):
        for line in stream:
            sink.append(line)

    threading.Thread(target=pump, args=(proc.stdout, out_lines), daemon=True).start()
    threading.Thread(target=pump, args=(proc.stderr, err_lines), daemon=True).start()

    deadline = time.time() + 30
    while time.time() < deadline:
        if any("http://localhost:" in ln for ln in out_lines):
            return proc
        if proc.poll() is not None:
            stop_server(proc)
            tail = "".join(err_lines[-12:]).strip() or "".join(out_lines[-12:]).strip()
            raise ServerBootError(
                f"server.js exited with code {proc.returncode} before becoming ready.\n"
                f"  cwd: {htmx_dir}\n"
                f"  stderr:\n{tail or '(no output)'}\n"
                "  (new-htmx/node_modules is gitignored — try `npm install` there)")
        time.sleep(0.1)
    stop_server(proc)
    raise ServerBootError(f"server.js did not print a ready line within 30s (cwd: {htmx_dir})")


def stop_server(proc):
    """Always tear the server down — success, failure, or exception."""
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)


def emit(app, check=False, server_env=None):
    """Boot the producer, render every registry surface, write on diff.

    Runs under whatever interpreter has playwright (see the --worker cascade).
    check=True renders everything but WRITES NOTHING — each rendered result is
    compared against the on-disk surface (the pre-gate drift guard).
    Returns 0/1/2."""
    design = app / "design"
    htmx = design / "new-htmx"
    registry_path = htmx / "models" / "screens_model" / "registry.json"
    required = [htmx / "server.js", registry_path, htmx / "exclusions.json"]
    required += [htmx / "assets" / "css" / name for name in CSS_FILES]
    for req in required:
        if not req.is_file():
            print(f"FAIL: missing {req.relative_to(app)} — the htmx producer "
                  "(new-htmx/server.js + models/screens_model/registry.json + "
                  "assets/css/*.css) and design/exclusions.json must exist",
                  file=sys.stderr)
            return 1
    try:
        selectors = json.loads((htmx / "exclusions.json").read_text()).get("selectors", [])
        if not isinstance(selectors, list):
            raise ValueError('"selectors" must be a list')
    except Exception as e:
        print(f"FAIL: design/exclusions.json does not parse: {e}", file=sys.stderr)
        return 1
    try:
        registry = json.loads(registry_path.read_text())
        if not isinstance(registry, list) or not registry:
            raise ValueError("registry.json must be a non-empty array")
    except Exception as e:
        print(f"FAIL: {registry_path.relative_to(app)} does not parse: {e}", file=sys.stderr)
        return 1

    failures = []
    css_parts = []
    for name in CSS_FILES:
        raw = strip_css_comments((htmx / "assets" / "css" / name).read_text())
        css_parts.append(rewrite_assets(raw))
    css = "\n".join(css_parts)
    assert_assets_rewritten("inlined CSS", css, failures)

    # Emitted surfaces live inside their own producer folder (2026-07-25
    # reorg): design/new-htmx/surfaces/, not a sibling design/new-htmx/surfaces/.
    outdir = htmx / "surfaces"
    from playwright.sync_api import sync_playwright

    proc = None
    rendered = 0
    skipped = []
    drifted = []
    try:
        port = free_port()
        try:
            proc = boot_server(htmx, port, extra_env=server_env)
        except ServerBootError as e:
            print(f"emit: ERROR (exit 2) — could not boot the htmx producer: {e}", file=sys.stderr)
            return 2
        base = f"http://127.0.0.1:{port}/"
        with sync_playwright() as pw:
            browser = pw.chromium.launch()

            def fresh_page():
                pg = browser.new_page(viewport={"width": VW, "height": VH})
                msgs = []
                pg.on("console", lambda m: msgs.append(m.text) if m.type == "error" else None)
                pg.on("pageerror", lambda e: msgs.append(str(e)))
                return pg, msgs

            seen = {}
            for entry in registry:
                if not isinstance(entry, dict):
                    continue
                sid = entry.get("id")
                surface = entry.get("surface")
                if not surface:
                    # NULL-SURFACE RULE: reported, never invented, never silent.
                    skipped.append(sid)
                    print(f"skip: screen '{sid}' — registry surface is null "
                          "(no canonical surface name to emit under)")
                    continue
                if surface in seen:
                    failures.append(f"surface collision: '{surface}' claimed by both "
                                    f"'{seen[surface]}' and '{sid}'")
                    continue
                seen[surface] = sid
                role = role_for(entry)
                pg, msgs = fresh_page()
                pg.goto(f"{base}?role={quote(str(role))}&screen={quote(str(sid))}")
                pg.wait_for_timeout(1500)
                res = pg.evaluate(EXTRACT_JS, {"root": CONTENT_ROOT,
                                               "selectors": selectors,
                                               "placeholderMark": PLACEHOLDER_MARK})
                pg.close()
                for m in msgs:
                    failures.append(f"{surface}: console/page error — {m}")
                if not res.get("ok"):
                    failures.append(f"{surface}: {res.get('error')}")
                    continue
                if res.get("placeholder"):
                    failures.append(f"{surface}: role '{role}' got the Phase-E placeholder, "
                                    f"not the real surface for screen '{sid}'")
                    continue
                want_label = f"{role} · {sid}"
                if res.get("label") != want_label:
                    failures.append(f"{surface}: data-screen-label is "
                                    f"{res.get('label')!r}, expected {want_label!r} — "
                                    "the surface template did not render")
                    continue
                content = rewrite_assets(res["html"])
                assert_assets_rewritten(surface, content, failures, surfaces_dir=str(outdir))
                doc = (DOC.replace("__BANNER__", banner(sid, role))
                          .replace("__SURFACE__", str(surface))
                          .replace("__CSS__", css)
                          .replace("__CONTENT__", content))
                out = outdir / f"{surface}.html"
                rel = f"design/new-htmx/surfaces/{surface}.html"
                if check:
                    if not out.exists():
                        drifted.append(f"{surface}.html")
                        print(f"DRIFT {rel} (not on disk — run emit)")
                    elif out.read_text() != doc:
                        drifted.append(f"{surface}.html")
                        print(f"DRIFT {rel} (producer changed — re-run emit)")
                    else:
                        print(f"in-sync {rel}")
                else:
                    outdir.mkdir(parents=True, exist_ok=True)
                    if out.exists() and out.read_text() == doc:
                        print(f"unchanged {rel} (write-on-diff: content identical)")
                    else:
                        out.write_text(doc)
                        print(f"wrote {rel}  (screen '{sid}', role '{role}')")
                rendered += 1
            browser.close()
    finally:
        stop_server(proc)

    if check and outdir.is_dir():
        # Files under new-htmx/surfaces/ matching no registry surface are orphans:
        # informational, never failures (sibling parity — a legacy frozen
        # surface legitimately outliving its registry entry is a human call).
        for p in sorted(outdir.glob("*.html")):
            if p.stem not in seen:
                print(f"note: orphan {p.relative_to(app)} (no registry surface claims it)")

    tail = f" ({len(skipped)} registry-null screen(s) skipped: {', '.join(skipped)})" if skipped else ""
    if failures:
        print(f"emit: FAIL — {len(failures)} problem(s):", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1
    if check:
        if drifted:
            print(f"emit --check: FAIL — {len(drifted)} surface(s) drifted: "
                  f"{', '.join(drifted)}", file=sys.stderr)
            return 1
        print(f"emit --check: PASS — {rendered} surface(s) in-sync with "
              f"design/new-htmx/surfaces/{tail}")
        return 0
    print(f"emit: PASS — {rendered} surface(s) emitted to design/new-htmx/surfaces/{tail}")
    return 0


def run_with_backend(app, check=False, server_env=None):
    """Render-backend cascade — mirrors emit_playground/freeze_design.sh."""
    extra = ["--check"] if check else []
    if shutil.which("uv"):
        return subprocess.call(["uv", "run", "--with", "playwright", "python",
                                str(TOOL), "--worker", "--app", str(app)] + extra,
                               env=dict(os.environ, **(server_env or {})))
    if importlib.util.find_spec("playwright"):
        return emit(app, check=check, server_env=server_env)
    print("emit: ERROR (exit 2) — no render backend. Install one of:", file=sys.stderr)
    print("  uv run --with playwright", file=sys.stderr)
    print("  pip install playwright && python3 -m playwright install chromium", file=sys.stderr)
    return 2


def self_test():
    """Hermetic calibration against fixtures/ — offline, no npm install.

    The fixture producer is dependency-free node, so this exercises the REAL
    boot path (node --import frozen_clock.mjs server.js on $PORT, wait for the
    ready line) rather than a bypass."""
    failed = []

    def chk(cond, label):
        print(("  ok   " if cond else "  FAIL ") + label)
        if not cond:
            failed.append(label)

    def run(app, extra=(), env=None):
        e = dict(os.environ)
        e.pop("EMIT_RENDER", None)
        if env:
            e.update(env)
        return subprocess.run([sys.executable, str(TOOL), "--app", str(app)] + list(extra),
                              capture_output=True, text=True, env=e)

    print("emit_htmx self-test (fixtures/app)")

    with tempfile.TemporaryDirectory() as td:
        app = Path(td) / "app"
        shutil.copytree(FIXTURE_APP, app)
        surf = app / "design" / "new-htmx" / "surfaces"

        # -- no app root / skip mode: environment discipline before rendering
        e = dict(os.environ)
        e.pop("APPBOX_APP", None)
        e.pop("EMIT_RENDER", None)
        r = subprocess.run([sys.executable, str(TOOL)], capture_output=True, text=True, env=e)
        chk(r.returncode == 2, "no --app and no $APPBOX_APP → exit 2 (environment)")

        r = subprocess.run([sys.executable, str(TOOL), "--app", str(app)],
                           capture_output=True, text=True,
                           env=dict(os.environ, EMIT_RENDER="skip"))
        chk(r.returncode == 0 and "SKIPPED" in r.stdout, "EMIT_RENDER=skip → exit 0, writes nothing")
        chk(not surf.exists(), "EMIT_RENDER=skip wrote no surfaces")

        # -- the emit itself
        r = run(app)
        if r.returncode != 0:
            print(r.stdout)
            print(r.stderr, file=sys.stderr)
        chk(r.returncode == 0, "emit over the fixture producer → exit 0")
        chk("emit: PASS — 2 surface(s) emitted to design/new-htmx/surfaces/" in r.stdout,
            "summary names the count and the destination")
        chk("fixture.hidden" in r.stdout and "registry surface is null" in r.stdout,
            "null-surface screen is REPORTED, not silently dropped")
        chk("1 registry-null screen(s) skipped" in r.stdout,
            "summary carries the skipped count")

        out = surf / "fixture_shell_home_view.html"
        chk(out.is_file(), "surface written under design/new-htmx/surfaces/")
        chk(not (app / "design" / "new" / "surfaces").exists(),
            "design/surfaces/ (the React producer's output) is never created")
        h = out.read_text() if out.is_file() else ""
        chk("GENERATED by stacked_kit/tools/emit_htmx" in h and "fixture.one" in h,
            "generated banner names the source screen, timestamp-free")
        chk("--fixture-ink" in h, "tokens.css inlined")
        chk(".fx-content" in h, "hda.css inlined")
        chk("FixtureSans" in h, "fonts.css inlined")
        chk("tweak" not in h, "CSS comments stripped (no chrome signatures leak)")
        chk("Fixture Home" in h, "screen DOM present")
        chk("statusbar" not in h and "dyn-island" not in h and "home-ind" not in h,
            "chrome stripped via exclusions.json selectors")
        chk("toolbar" not in h, "stage chrome outside .phone-screen never enters the surface")
        chk('src="../assets/icon.svg"' in h, "attribute asset URL rewritten")
        chk("url(../assets/icon.svg)" in h, "inline-style url() asset rewritten")
        chk("url(../assets/fonts/fixture-400.woff2)" in h, "CSS url() asset rewritten")
        chk('="/assets/' not in h and "url(/assets/" not in h,
            "no un-rewritten /assets/ URL survives anywhere")

        # -- write-on-diff: the second run must be a no-op. This also
        # calibrates frozen_clock.mjs — the fixture prints Date.now() into the
        # surface, so an unfrozen clock fails here.
        r2 = run(app)
        chk(r2.returncode == 0 and "unchanged" in r2.stdout and "wrote" not in r2.stdout,
            "second consecutive run is a write-on-diff no-op (frozen clock holds)")

        # -- --check drift guard
        rc = run(app, extra=["--check"])
        chk(rc.returncode == 0 and "in-sync" in rc.stdout, "--check on a clean tree → in-sync, exit 0")
        chk("wrote" not in rc.stdout and "unchanged" not in rc.stdout, "--check writes nothing")

        (surf / "legacy_orphan_view.html").write_text("<html>legacy frozen surface</html>")
        rc2 = run(app, extra=["--check"])
        chk(rc2.returncode == 0 and "orphan" in rc2.stdout,
            "orphan surface is informational, not a failure")
        (surf / "legacy_orphan_view.html").unlink()

        out.write_text(h + "<!-- hand edit -->")
        rc3 = run(app, extra=["--check"])
        chk(rc3.returncode == 1 and "DRIFT" in rc3.stdout, "--check on a drifted surface → exit 1")
        run(app)  # restore

        # -- the placeholder trap: a screen the role cannot see renders a
        # valid 200 page; freezing it would be a silent lie.
        rp = run(app, env={"FIXTURE_PLACEHOLDER": "1"})
        chk(rp.returncode == 1 and "placeholder" in (rp.stdout + rp.stderr),
            "Phase-E placeholder is a FAILURE, never frozen as a real surface")

    # -- a producer that cannot boot is an environment fault, not a gate FAIL
    with tempfile.TemporaryDirectory() as td:
        app = Path(td) / "app"
        shutil.copytree(FIXTURE_APP, app)
        (app / "design" / "new-htmx" / "server.js").write_text(
            "import 'node:definitely-not-a-real-module';\n")
        r = run(app)
        chk(r.returncode == 2 and "could not boot" in r.stderr,
            "server that dies on import → exit 2 with its stderr surfaced")

    print()
    if failed:
        print(f"SELF-TEST FAILED ({len(failed)} check(s)):")
        for f in failed:
            print(f"  - {f}")
        sys.exit(1)
    print("ALL GREEN")


def main(argv):
    ap = argparse.ArgumentParser(
        description="emit chrome-stripped static surfaces from the design/new-htmx producer")
    ap.add_argument("--app", help="app root (default: $APPBOX_APP)")
    ap.add_argument("--check", action="store_true",
                    help="drift guard: render + compare against on-disk surfaces, write nothing")
    ap.add_argument("--self-test", action="store_true", help="hermetic calibration against fixtures/")
    ap.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)  # cascade re-exec target
    args = ap.parse_args(argv)

    if args.self_test:
        self_test()
        return

    app = args.app or os.environ.get("APPBOX_APP")
    if not app:
        print("emit: ERROR (exit 2) — no app root: pass --app <app-root> or set $APPBOX_APP",
              file=sys.stderr)
        sys.exit(2)
    app = Path(app).resolve()
    if not app.is_dir():
        print(f"emit: ERROR (exit 2) — app root not found: {app}", file=sys.stderr)
        sys.exit(2)

    if os.environ.get("EMIT_RENDER") == "skip":
        print("  (emit SKIPPED — EMIT_RENDER=skip; no surfaces written — hermetic/CI runs only)")
        sys.exit(0)

    if args.worker:
        sys.exit(emit(app, check=args.check))
    sys.exit(run_with_backend(app, check=args.check))


if __name__ == "__main__":
    main(sys.argv[1:])
