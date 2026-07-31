#!/usr/bin/env python3
"""Host gate: web_skeleton captures Regime-1 visual CSS into _node_style, and the
full pipeline (web_skeleton -> bundle_writer) redacts external url() while keeping
filter/clip mechanism, producing a content-free `style` on disk that audits clean.

Deterministic, offline: ONE local server serves both the page AND the "external"
image (http://127.0.0.1:port/ext.png), so the external-url redaction path is
exercised without leaving the host. The page's marker node carries filter,
backdrop-filter, clip-path:url(#c) (with an inline <svg><clipPath id=c>), a
linear-gradient background, a full dashed border + per-corner radius, and a known
bg color; a SECOND node carries background-image:url(/ext.png) (the redaction
exerciser). Asserts the bundle's on-disk node style: filter/gradient/clip #ref kept,
the external bg redacted to url("<asset>"). bundle_writer.write_bundle runs the
firewall audit and RAISES on any leak, so a redaction regression fails the gate.
Also exercises Regime-2 pseudo-elements: a ::before (string content -> "<text>"), an ::after (url() content -> url("<asset>")), and a custom li::marker color, attached to their originating nodes."""
from __future__ import annotations
import json
import re
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))
from web_tokens import parse_color  # noqa: E402

MARK_RGB = (18, 52, 86)  # marker node bg; matched via parse_color (format-robust)

# A 1x1 transparent PNG (real magic bytes) served as the "external" asset.
_PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4"
    "890000000a49444154789c6360000002000154a24f9f0000000049454e44ae426082")

_PAGE = """<!doctype html><meta charset=utf-8><title>css-style-gate</title>
<style>
  body { margin: 0; }
  #mark { width: 320px; height: 180px; margin: 40px;
          background: linear-gradient(135deg, rgb(18,52,86) 0%, rgb(240,240,240) 100%);
          filter: blur(0.5px); backdrop-filter: blur(8px);
          -webkit-backdrop-filter: blur(8px); mix-blend-mode: multiply;
          clip-path: url(#c);
          border-top: 4px dashed rgb(10,20,30); border-right: 4px dashed rgb(10,20,30);
          border-bottom: 4px dashed rgb(10,20,30); border-left: 4px dashed rgb(10,20,30);
          border-radius: 8px 12px 16px 20px; }
  #ext { width: 100px; height: 100px; background-image: url(/ext.png); }
  #cut2 { width: 120px; height: 120px;
          outline: 3px solid rgb(7,8,9); outline-offset: 2px;
          text-shadow: rgb(0,0,0) 2px 2px 4px;
          background-image: linear-gradient(90deg, rgb(1,1,1), rgb(2,2,2));
          background-repeat: no-repeat; background-position: 10px 20px;
          overflow: hidden; transform-style: preserve-3d; perspective: 600px;
          writing-mode: vertical-rl; }
  #img2 { width: 80px; height: 80px; object-fit: cover; object-position: 25% 75%; }
  #plain { width: 50px; height: 50px; }
  #pb { width: 60px; height: 20px; }
  #pb::before { content: "Handcrafted urushi lacquer keyboard"; color: rgb(200,10,10);
                display: block; width: 12px; height: 12px; }
  #pa { width: 60px; height: 20px; }
  #pa::after { content: url(/ext.png); display: inline-block; width: 10px; height: 10px; }
  ol li::marker { color: rgb(0,128,0); }
</style>
<svg width=0 height=0><defs><clipPath id=c><circle cx=50 cy=50 r=50/></clipPath></defs></svg>
<div id=mark></div>
<div id=ext></div>
<div id=cut2></div>
<img id=img2 src="/ext.png">
<div id=plain></div>
<div id=pb></div>
<div id=pa></div>
<ol><li>item</li></ol>"""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path.endswith("/ext.png"):
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(_PNG)))
            self.end_headers()
            self.wfile.write(_PNG)
            return
        body = _PAGE.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def _run(url):
    sk = ROOT / "fixtures" / "css_style" / "_sk.json"
    tok = ROOT / "fixtures" / "css_style" / "_tokens.json"
    bundle = ROOT / "fixtures" / "css_style" / "_bundle"
    tok.write_text(json.dumps({"palette": {}}))
    r = subprocess.run([sys.executable, str(SCRIPTS / "web_skeleton.py"),
                        "--url", url, "--out", str(sk)],
                       cwd=str(SCRIPTS), capture_output=True, text=True, timeout=90)
    if r.returncode != 0:
        print("web_skeleton FAILED:\n", r.stdout, r.stderr)
        return None
    r = subprocess.run([sys.executable, str(SCRIPTS / "bundle_writer.py"),
                        "--skeleton", str(sk), "--tokens", str(tok), "--out", str(bundle)],
                       cwd=str(SCRIPTS), capture_output=True, text=True, timeout=90)
    if r.returncode != 0:
        print("bundle_writer FAILED (content leak?):\n", r.stdout, r.stderr)
        return None
    return json.loads((bundle / "skeleton.json").read_text())


def _check(disk) -> bool:
    nodes = disk.get("nodes") or []
    styled = [n for n in nodes if n.get("style")]
    print("nodes:", len(nodes), "styled:", len(styled))
    # marker node: a linear-gradient bg whose FIRST captured rgb() stop equals MARK_RGB
    # (load-bearing: a gradient-color regression must fail this, not pass on presence alone)
    mark = None
    for n in styled:
        bi = n["style"].get("background-image") or ""
        m = re.search(r"rgb\([^)]*\)", bi)
        if "linear-gradient" in bi and m and parse_color(m.group(0)) == MARK_RGB:
            mark = n
            break
    if mark is None:
        print("GATE FAIL: no node carried the gradient marker style with the expected color")
        return False
    s = mark["style"]
    # filter AND backdrop-filter each independently carry blur (concat would mask a drop);
    # clip-path keeps the same-doc #c ref; blend/dashed-border/8px corner radius kept.
    ok = ("blur" in (s.get("filter") or "")
          and "blur" in (s.get("backdrop-filter") or "")
          and s.get("clip-path", "").find("#c") >= 0
          and s.get("mix-blend-mode") == "multiply"
          and any(k.endswith("-style") and s[k] == "dashed" for k in s)
          and s.get("border-top-left-radius") == "8px")
    if not ok:
        print("GATE FAIL: marker style incomplete:", json.dumps(s))
        return False
    # the external-bg node: background-image redacted to the asset marker
    ext = [n for n in styled if (n["style"].get("background-image") or "").strip() == 'url("<asset>")']
    if not ext:
        print("GATE FAIL: external background-image not redacted to url(\"<asset>\");",
              json.dumps([n["style"].get("background-image") for n in styled]))
        return False
    print("style ok: filter+backdrop blur / clip(#c) / blend / dashed border / radius=8px kept; external bg redacted")
    # cut-2: the #cut2 node (outline-style:solid is its fingerprint) carries the new props
    c2 = next((n for n in styled if n["style"].get("outline-style") == "solid"), None)
    if c2 is None:
        print("GATE FAIL: no cut-2 node carried outline-style:solid")
        return False
    s2 = c2["style"]
    ok2 = (s2.get("outline-width") == "3px"
           and "rgb" in (s2.get("outline-color") or "")
           and s2.get("outline-offset") == "2px"
           and "rgb" in (s2.get("text-shadow") or "")
           and s2.get("background-repeat") == "no-repeat"
           and s2.get("background-position") == "10px 20px"
           and s2.get("overflow-x") == "hidden" and s2.get("overflow-y") == "hidden"
           and s2.get("transform-style") == "preserve-3d"
           and s2.get("perspective") == "600px"
           and s2.get("writing-mode") == "vertical-rl")
    if not ok2:
        print("GATE FAIL: cut-2 style incomplete:", json.dumps(s2))
        return False
    # object-fit/position on the replaced img
    im = next((n for n in styled if n["style"].get("object-fit") == "cover"), None)
    if im is None or im["style"].get("object-position") != "25% 75%":
        print("GATE FAIL: object-fit/object-position not captured")
        return False
    # default-suppression: NO node may carry a Chrome-default value, and the outline
    # group must never appear without outline-style (proves the gate/map are load-bearing).
    for n in styled:
        sd = n["style"]
        for prop, dval in (("background-repeat", "repeat"), ("writing-mode", "horizontal-tb"),
                           ("transform-style", "flat"), ("overflow-x", "visible"),
                           ("object-fit", "fill"), ("direction", "ltr")):
            if sd.get(prop) == dval:
                print(f"GATE FAIL: default value leaked: {prop}={dval}")
                return False
        if "outline-style" not in sd and ("outline-width" in sd or "outline-color" in sd):
            print("GATE FAIL: outline group present without outline-style:", json.dumps(sd))
            return False
    print("cut-2 ok: outline group + text-shadow + bg longhands + object-fit + 3d kept; defaults suppressed")
    # Regime-2: pseudo-elements attach to their originating node.
    pnodes = [n for n in nodes if n.get("pseudo")]
    print("pseudo nodes:", len(pnodes))
    # ::before string content -> redacted to "<text>"; custom color captured.
    pb = next((n for n in pnodes if (n["pseudo"].get("::before") or {}).get("content") == '"<text>"'), None)
    if pb is None:
        print("GATE FAIL: no ::before with redacted content '\"<text>\"';",
              json.dumps([n.get("pseudo") for n in pnodes]))
        return False
    if "rgb" not in (pb["pseudo"]["::before"].get("color") or ""):
        print("GATE FAIL: ::before color not captured:", json.dumps(pb["pseudo"]["::before"]))
        return False
    # ::after url() content -> redacted to url("<asset>") (url-in-content vector).
    pa = next((n for n in pnodes if (n["pseudo"].get("::after") or {}).get("content") == 'url("<asset>")'), None)
    if pa is None:
        print("GATE FAIL: ::after url() content not redacted to url(\"<asset>\");",
              json.dumps([n["pseudo"].get("::after") for n in pnodes if "::after" in n["pseudo"]]))
        return False
    # custom ::marker color captured (default markers, equal to parent text color, are absent).
    mk = next((n for n in pnodes if "rgb" in ((n["pseudo"].get("::marker") or {}).get("color") or "")), None)
    if mk is None:
        print("GATE FAIL: custom ::marker color not captured")
        return False
    # the raw authored ::before string must NOT appear anywhere on disk.
    if "Handcrafted" in json.dumps(disk):
        print("GATE FAIL: raw pseudo content leaked to disk")
        return False
    print("pseudo ok: ::before content redacted to <text> + color; ::after url() content redacted; custom ::marker color kept")
    return True


def main() -> int:
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    ok = False
    try:
        disk = _run(f"http://127.0.0.1:{port}/")
        ok = bool(disk) and _check(disk)
    finally:
        srv.shutdown()
    if ok:
        print("GATE PASS: Regime-1 + Regime-2 visual CSS captured + redacted; bundle audits clean.")
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
