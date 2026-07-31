#!/usr/bin/env python3
"""Host CDP gate for ARIA landmark-role enrichment. Serves a synthetic landmark page
(own markup, content-free) and runs the FULL site_capture pipeline on it
(web_skeleton -> web_tokens -> bundle_writer -> redact_node -> routes/<id>/skeleton.json)
-- the exact composed per-route artifact a future G3c consumer reads, NOT web_skeleton in
isolation. Asserts:
  - aria_role lands on the landmark elements (nav->navigation, header->banner,
    footer->contentinfo, main->main) IN THE BUNDLED skeleton (proves redact_node + the
    bundle pipeline preserve the additive key through the composed path),
  - the captured site tree audits CLEAN (content_firewall),
  - capture is deterministic (two runs -> identical aria_role set).
Runs on host Bash (CDP :9222), dangerouslyDisableSandbox=true. Prints PASS/FAIL +
content-free counts only; NEVER subprocess stderr or page bytes.
NOTE: <section> exposes role=region only when accessibly named -> the fixture names it
with aria-label (OUR fixture markup, never captured; only the role is read; aria_label is
itself a CONTENT_KEYS entry stripped by redact_node).
"""
import argparse
import http.server
import json
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]   # fixtures/aria -> fixtures -> repo root
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

_PAGE = (
    "<!doctype html><html><head><meta charset=utf-8>"
    "<style>body{margin:0}nav,header,footer,main,section{display:block;padding:8px}</style>"
    "</head><body>"
    "<header>alpha</header>"
    "<nav>one two three</nav>"
    "<main><section aria-label='r'>body copy here</section></main>"
    "<footer>four five</footer>"
    "</body></html>"
)


def _serve():
    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            b = _PAGE.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(b)))
            self.end_headers()
            self.wfile.write(b)

        def log_message(self, *a):
            pass

    httpd = socketserver.TCPServer(("127.0.0.1", 0), H)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd, "http://127.0.0.1:%d/" % httpd.server_address[1]


def _site_capture(url, out, port):
    """Run the gated site_capture orchestrator on a 1-route list -> returncode ONLY
    (never stderr -- a leak message can embed a content sample)."""
    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "site_capture.py"),
         "--urls", url, "--out", str(out), "--cdp-port", str(port)],
        cwd=str(SCRIPTS), capture_output=True, text=True)
    return r.returncode


def _route_nodes(out):
    """Nodes of the first ok route's BUNDLED, redacted skeleton.json under a site_capture
    --out dir (the artifact a G3c consumer reads). None if no ok route OR if site.json /
    skeleton.json is missing/unparseable (site_capture exited 0 but partial-wrote) -- a
    missing artifact must yield a clean GATE FAIL, not a traceback."""
    try:
        site = json.loads((out / "site.json").read_text())
        for row in site.get("routes", []):
            if row.get("ok"):
                sk = out / "routes" / row["route_id"] / "skeleton.json"
                return json.loads(sk.read_text()).get("nodes") or []
    except (OSError, ValueError, KeyError):
        return None
    return None


def _aria_set(nodes):
    return {n["aria_role"] for n in nodes if n.get("aria_role")}


def _run_once(url, port):
    """One full site_capture run -> (bundled route nodes | None, audit_clean bool).
    Cleans its own dir."""
    import content_firewall as cf
    out = Path(tempfile.mkdtemp(prefix="aria_gate_"))
    try:
        rc = _site_capture(url, out, port)
        if rc != 0:
            print("  site_capture rc=%d" % rc)
            return None, False
        clean = not cf.audit_bundle(out)
        return _route_nodes(out), clean
    finally:
        shutil.rmtree(out, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cdp-port", type=int, default=9222)
    args = ap.parse_args()

    httpd, url = _serve()
    try:
        nodes, clean = _run_once(url, args.cdp_port)
        if nodes is None:
            print("GATE FAIL — capture failed")
            return 1
        got = _aria_set(nodes)
        want = {"navigation", "banner", "contentinfo", "main"}
        print("  bundled route nodes=%d ; with aria_role=%d ; roles seen=%s"
              % (len(nodes), sum(1 for n in nodes if n.get("aria_role")), sorted(got)))
        nodes2, _ = _run_once(url, args.cdp_port)
        if nodes2 is None:
            print("  run2 capture failed")
        det = nodes2 is not None and _aria_set(nodes2) == got
        print("  audit CLEAN=%s ; determinism=%s" % (clean, det))
        ok = want.issubset(got) and clean and det
        print("GATE %s" % ("PASS" if ok else "FAIL"))
        return 0 if ok else 1
    finally:
        httpd.shutdown()


if __name__ == "__main__":
    raise SystemExit(main())
