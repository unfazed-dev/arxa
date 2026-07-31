#!/usr/bin/env python3
# pipeline/prototype/serve.py -- appbox prototype runtime (plan 09).
#
# Serves a frozen design's static tree over loopback HTTP and prints one
# machine-readable ready line a UI spawns against. Host and port come from
# config/appbox.config.json (prototypeServer), never literals -- port 0 asks
# the OS for a free one, the same spawn contract as the designer's serve CLI.
#
# Buildable subset of plan 09: static serving + correct MIME + relative asset
# paths (step 9.5), the spawn contract (config-driven host/port, OS-assigned
# port, ready line) and clean shutdown (step 9.7). It does NOT execute the
# design's viewmodels, so rendered pages and POST mutations are not served
# here -- that needs the embedded engine (steps 9.1-9.4), which lives in the
# desktop app and is fenced for this build. The ready-line JSON shape matches
# the designer's serve CLI so a caller integrates against one contract.
import argparse
import json
import mimetypes
import os
import posixpath
import signal
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent  # pipeline/prototype/ -> pipeline/ -> repo root
CONFIG = ROOT / "config" / "appbox.config.json"
DESIGNS = ROOT / "designs"

READY_TAG = "appbox-prototype-ready"


def die(msg, code=1):
    # Errors go to stderr as plain text even under --json: a caller parsing
    # stdout must never mistake a failure for a ready record.
    print(msg, file=sys.stderr)
    sys.exit(code)


def load_server_defaults():
    host, port = "127.0.0.1", 0
    try:
        cfg = json.loads(CONFIG.read_text())
    except FileNotFoundError:
        return host, port  # config is canonical but the loopback/port-0 defaults are safe
    except json.JSONDecodeError as e:
        die(f"config is not valid JSON: {e}", 78)
    ps = cfg.get("prototypeServer", {}) or {}
    if ps.get("host"):
        host = ps["host"]
    if ps.get("port") is not None:
        port = ps["port"]
    return host, int(port)


def resolve_design(target):
    # A path wins; otherwise treat the target as a design name under designs/.
    # The artifact marker is app.routes.js (the routing contract) -- the same
    # rule the designer uses, so both servers agree on what "a design" is.
    candidates = [Path(target).resolve(), (DESIGNS / target).resolve()]
    for c in candidates:
        if (c / "app.routes.js").is_file():
            return c
    tried = "\n".join(f"  {c}" for c in dict.fromkeys(candidates))
    die(
        f'no design at "{target}" -- every candidate lacked app.routes.js:\n{tried}',
        66,
    )


def register_mime():
    mimetypes.add_type("text/css", ".css")
    mimetypes.add_type("text/javascript", ".js")
    mimetypes.add_type("application/json", ".json")
    mimetypes.add_type("image/svg+xml", ".svg")
    mimetypes.add_type("image/png", ".png")
    mimetypes.add_type("image/webp", ".webp")
    mimetypes.add_type("font/woff2", ".woff2")
    mimetypes.add_type("font/woff", ".woff")
    mimetypes.add_type("text/html", ".html")
    mimetypes.add_type("text/plain", ".txt")


class Handler(BaseHTTPRequestHandler):
    root = None  # injected per run (the resolved design dir)

    server_version = "appbox-prototype/1.0"

    def translate_path(self, path):
        # Strip query/fragment, drop any '..' segment, and confine the result to
        # the design root. A prototype is unreleased client work -- traversal
        # out of the root is rejected, not merely unexpected.
        path = path.split("?", 1)[0].split("#", 1)[0]
        parts = [p for p in posixpath.normpath(path).split("/") if p and p != ".."]
        full = self.root.joinpath(*parts).resolve()
        try:
            full.relative_to(self.root.resolve())
        except ValueError:
            return None
        return full

    def _serve(self, head_only):
        full = self.translate_path(self.path)
        if full is None or not full.is_file():
            self.send_error(404, "not found")
            return
        ctype = mimetypes.guess_type(full.name)[0] or "application/octet-stream"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(full.stat().st_size))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if not head_only:
            self.wfile.write(full.read_bytes())

    def do_GET(self):
        self._serve(head_only=False)

    def do_HEAD(self):
        self._serve(head_only=True)

    def log_message(self, fmt, *args):
        # Access log to stderr so stdout stays the single ready-line channel.
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


def main():
    ap = argparse.ArgumentParser(
        prog="serve.py",
        description="Serve a frozen design over loopback HTTP (appbox prototype runtime).",
    )
    ap.add_argument("design", help="design name (e.g. appbox-app) or path to a design dir")
    ap.add_argument("--host", help="bind host (default: config prototypeServer.host)")
    ap.add_argument(
        "--port",
        type=int,
        help="bind port; 0 = OS-assigned (default: config prototypeServer.port)",
    )
    ap.add_argument(
        "--json",
        action="store_true",
        help="print one JSON ready line once listening, then keep serving",
    )
    args = ap.parse_args()

    cfg_host, cfg_port = load_server_defaults()
    host = args.host or cfg_host
    port = args.port if args.port is not None else cfg_port
    if not isinstance(port, int) or not (0 <= port <= 65535):
        die(f"not a port: {port}", 64)

    design_dir = resolve_design(args.design)
    register_mime()

    Handler.root = design_dir
    ThreadingHTTPServer.allow_reuse_address = True
    ThreadingHTTPServer.daemon_threads = True
    try:
        httpd = ThreadingHTTPServer((host, port), Handler)
    except OSError as e:
        # A port clash or permission denial surfaces as a non-zero exit with a
        # named cause -- never a silent exit 0 that a UI mistakes for success.
        die(f"cannot bind {host}:{port} -- {e.strerror or e}", 70)

    bound = httpd.server_address[1]  # the real port (truth when --port 0)
    shown = "localhost" if host in ("0.0.0.0", "::") else host
    url = f"http://{shown}:{bound}/"

    if args.json:
        # Compact JSON (separators) matches the Node JSON.stringify contract
        # the designer emits, so a parent greps one tight line for both servers.
        print(
            json.dumps(
                {
                    "tag": READY_TAG,
                    "url": url,
                    "port": bound,
                    "host": host,
                    "pid": os.getpid(),
                    "design": args.design,
                    "artifact": str(design_dir),
                },
                separators=(",", ":"),
            ),
            flush=True,
        )
    else:
        print(f"appbox prototype serving {design_dir}", flush=True)
        print(f"-> {url}", flush=True)

    def _stop(signum, frame):
        # serve_forever runs in the main thread; shutdown() must come from
        # another thread or it deadlocks waiting on itself.
        threading.Thread(target=httpd.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    try:
        httpd.serve_forever()
    finally:
        httpd.server_close()  # release the port


if __name__ == "__main__":
    main()
