#!/usr/bin/env python3
"""Host gate: web_skeleton --themes captures per-node resolved style deltas under
prefers-color-scheme:dark / forced-colors:active / prefers-contrast:more, and the
pipeline redacts them content-free. PROVES JOIN CORRECTNESS: a node whose color
changes under dark gets the RIGHT dark delta; a node with NO theme rule gets NO
delta. Deterministic, offline (local server). Runs on host CDP.
bundle_writer.write_bundle runs the firewall audit and RAISES on leak."""
from __future__ import annotations
import json
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))
from web_tokens import parse_color  # noqa: E402  (format-robust rgb compare)

# #known: distinct base bg rgb(200,200,200); restyles under dark + contrast.
# #static: no @media rule -> MUST get no theme delta.
_PAGE = """<!doctype html><meta charset=utf-8><title>theme-gate</title>
<style>
 #known { width:120px; height:60px; color: rgb(10,20,30);
          background-color: rgb(200,200,200); }
 #static { width:80px; height:40px; color: rgb(50,60,70);
           background-color: rgb(123,124,125); }
 @media (prefers-color-scheme: dark) {
   #known { color: rgb(240,240,240); background-color: rgb(17,17,17); }
 }
 @media (prefers-contrast: more) {
   #known { color: rgb(0,0,0); }
 }
</style>
<div id=known>k</div><div id=static>s</div>"""


# ---------------------------------------------------------------------------
# Local server helper (ThreadingHTTPServer on a random port), mirroring
# fixtures/css_style/run_css_style.py's offline-server pattern.
# ---------------------------------------------------------------------------


def _serve(page_bytes):
    """Start a ThreadingHTTPServer on a random port; return (base_url, srv).
    Closure-based handler so page_bytes is available without a global."""
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(page_bytes)))
            self.end_headers()
            self.wfile.write(page_bytes)

    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return f"http://127.0.0.1:{port}/", srv


# ---------------------------------------------------------------------------
# Node-by-background helper
# ---------------------------------------------------------------------------
# background-color is stored in the _node_colors sidecar (stripped before the
# bundle's skeleton.json is written) and is NOT present in node["style"] for
# regular (non-pseudo) elements.  token_ref.bg resolves to a palette role name,
# which requires a non-empty palette — unavailable here (we use {"palette":{}}).
#
# Instead we identify nodes by their rendered bbox dimensions, which are fixed
# by the page CSS and fully deterministic.  The mapping from the expected base
# bg rgb tuple to (w, h) dimensions is:
#   rgb(200,200,200) -> #known  -> 120 x 60  px
#   rgb(123,124,125) -> #static ->  80 x 40  px
#
# parse_color is imported for the theme-delta assertions in _check (it remains
# the format-robust color comparison as in run_css_style.py).

_RGB_TO_SIZE = {
    (200, 200, 200): (120.0, 60.0),
    (123, 124, 125): (80.0, 40.0),
}

_SIZE_TOL = 2.0  # px; DPR rounding tolerance


def _node_by_bg(nodes, rgb, sk):  # noqa: sk unused (skeleton dict, kept for API compat)
    """Find the emitted node whose base CSS dimensions match the known bg rgb.

    run_css_style.py's MARK_RGB approach: match by a color present in the
    rendered style.  Here background-color is absent from node['style']
    (regular nodes; only pseudo-elements carry it inline).  We therefore key
    on rendered bbox size, which is equally deterministic for this fixture.
    Returns the node or None."""
    target = _RGB_TO_SIZE.get(rgb)
    if target is None:
        return None
    tw, th = target
    for n in nodes:
        b = n.get("bbox") or {}
        w = b.get("w", -1)
        h = b.get("h", -1)
        if abs(w - tw) <= _SIZE_TOL and abs(h - th) <= _SIZE_TOL:
            return n
    return None


def _check(bundle_dir):
    sk = json.loads((Path(bundle_dir) / "skeleton.json").read_text())
    nodes = sk.get("nodes") or []

    # Verbatim-critical, on-disk regression lock: backendNodeId is the INTERNAL join
    # key (session-scoped + mild fingerprint) and must NEVER reach disk. It is a bare
    # integer, so it trips NO firewall content-pattern (url/prose/base64/magic) — unlike
    # theme VALUES (guarded by both redact_theme AND the audit), this constraint has no
    # firewall backstop. These two asserts over the real serialized bundle are that
    # backstop: the `_node_backend` sidecar must be discarded by bundle_writer.main, and
    # no per-node `backend` field may survive onto a skeleton node.
    assert "_node_backend" not in sk, \
        "GATE FAIL: internal join-key sidecar _node_backend leaked to disk"
    assert all("backend" not in n for n in nodes), \
        "GATE FAIL: per-node backendNodeId leaked to disk"

    themed = [n for n in nodes if n.get("theme")]
    assert themed, "GATE FAIL: no node carried a theme delta"

    # JOIN CORRECTNESS 1: the #known node's dark delta is the resolved dark color.
    # (match #known by its base bg rgb(200,200,200))
    known = _node_by_bg(nodes, (200, 200, 200), sk)
    assert known is not None and known.get("theme"), "GATE FAIL: #known has no theme"
    dark = known["theme"].get("dark", {})
    assert parse_color(dark.get("color")) == (240, 240, 240), \
        f"GATE FAIL: wrong dark color delta: {dark.get('color')}"
    assert parse_color(dark.get("background-color")) == (17, 17, 17), \
        f"GATE FAIL: wrong dark bg delta: {dark.get('background-color')}"
    # contrast delta on the same node
    contrast = known["theme"].get("contrast", {})
    assert parse_color(contrast.get("color")) == (0, 0, 0), \
        f"GATE FAIL: wrong contrast delta: {contrast.get('color')}"
    # forced-colors produced SOME delta on #known
    assert known["theme"].get("forced-colors"), "GATE FAIL: no forced-colors delta"

    # JOIN CORRECTNESS 2: per-condition isolation. #static has NO author @media
    # rule for dark or contrast, so it must carry NEITHER a `dark` nor a `contrast`
    # delta — proving those deltas land ONLY on the node whose author rule fired
    # (#known), never smeared across the tree. forced-colors:active is a UA-level
    # override that restyles EVERY element (design §9: forced-colors is dense), so
    # #static legitimately carries a forced-colors delta — expected, not a join error.
    static = _node_by_bg(nodes, (123, 124, 125), sk)
    assert static is not None, "GATE FAIL: #static node missing"
    st_theme = static.get("theme") or {}
    assert "dark" not in st_theme, \
        f"GATE FAIL: #static got a spurious dark delta: {st_theme.get('dark')}"
    assert "contrast" not in st_theme, \
        f"GATE FAIL: #static got a spurious contrast delta: {st_theme.get('contrast')}"
    assert st_theme.get("forced-colors"), \
        "GATE FAIL: #static missing the universal forced-colors delta"

    print("GATE PASS: theme join correct (#known carries right dark/contrast/"
          "forced-colors deltas; #static isolated — no dark/contrast, forced-colors "
          "only per universal UA override); bundle audit CLEAN")


def main():
    base_url, _srv = _serve(_PAGE.encode())
    out = ROOT / "fixtures" / "theme" / "_bundle"
    sk_json = ROOT / "fixtures" / "theme" / "_sk.json"
    tok_json = ROOT / "fixtures" / "theme" / "_tokens.json"

    # Pre-write an empty tokens file (mirrors run_css_style.py line 100 exactly;
    # no separate web_tokens subprocess — that also needs CDP and is not required
    # for theme-gate correctness).
    tok_json.write_text(json.dumps({"palette": {}}))

    # 1) capture with themes — same flags as run_css_style.py's web_skeleton call
    #    (only --url + --out; resolve_web_eval auto-starts host Chrome via
    #    ensure_browser("auto") -> _CDPEval, which has .sess, satisfying the
    #    --themes CDP guard at web_skeleton.py:748).  --themes adds the three
    #    emulated-media conditions.
    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "web_skeleton.py"),
         "--url", base_url,
         "--themes", "dark,forced-colors,contrast",
         "--out", str(sk_json)],
        cwd=str(SCRIPTS), capture_output=True, text=True, timeout=90,
    )
    if r.returncode != 0:
        print("web_skeleton FAILED:\n", r.stdout, r.stderr)
        sys.exit(1)

    # 2) bundle (runs firewall audit; raises on leak) — same flags as
    #    run_css_style.py's bundle_writer call.
    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "bundle_writer.py"),
         "--skeleton", str(sk_json),
         "--tokens", str(tok_json),
         "--out", str(out)],
        cwd=str(SCRIPTS), capture_output=True, text=True, timeout=90,
    )
    if r.returncode != 0:
        print("bundle_writer FAILED (content leak?):\n", r.stdout, r.stderr)
        sys.exit(1)

    _check(out)


if __name__ == "__main__":
    main()
