#!/usr/bin/env python3
"""One-off real-site validation for Regime-1 CSS cut-2 + Regime-2 pseudo-elements (NOT
in the committed suite — nondeterministic). Drives the full pipeline (web_skeleton ->
bundle_writer) against a public --url and prints ONLY content-free signal: which cut-2
props populated (NAMES + occurrence COUNTS), which pseudo selectors populated
(::before/::after/::marker NAMES + occurrence COUNTS — never a content value, resolved
string, or url), node counts, and the bundle audit verdict. NO page content, NO resolved
values, NO full URL is printed or persisted (host only) — IP firewall + content-free
invariant. bundle_writer.write_bundle RAISES on any leak, so a clean exit proves the
firewall passed on real data. Host Bash (CDP):
    python3 fixtures/css_style/validate_realsite.py --url https://example.com"""
import argparse
import json
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
CUT2 = [
    "background-size", "background-position", "background-repeat", "background-clip",
    "background-origin", "background-attachment", "background-blend-mode",
    "outline-style", "outline-width", "outline-color", "outline-offset",
    "text-shadow", "overflow-x", "overflow-y", "aspect-ratio",
    "object-fit", "object-position",
    "text-transform", "text-decoration-line", "font-variant", "writing-mode", "direction",
    "perspective", "transform-style", "rotate", "scale", "translate",
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    args = ap.parse_args()
    host = args.url.split("/")[2] if "//" in args.url else args.url
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        sk, tok, bundle = td / "sk.json", td / "tokens.json", td / "bundle"
        tok.write_text(json.dumps({"palette": {}}))
        r = subprocess.run([sys.executable, str(SCRIPTS / "web_skeleton.py"),
                            "--url", args.url, "--out", str(sk)],
                           cwd=str(SCRIPTS), capture_output=True, text=True, timeout=150)
        if r.returncode != 0:
            print("web_skeleton FAILED:", r.stderr[-300:])
            return 1
        r = subprocess.run([sys.executable, str(SCRIPTS / "bundle_writer.py"),
                            "--skeleton", str(sk), "--tokens", str(tok), "--out", str(bundle)],
                           cwd=str(SCRIPTS), capture_output=True, text=True, timeout=150)
        audit_ok = r.returncode == 0
        disk = json.loads((bundle / "skeleton.json").read_text()) if audit_ok else {}
        nodes = disk.get("nodes") or []
        cnt = Counter()
        pcnt = Counter()      # Regime-2: pseudo-selector occurrence counts (NAMES only)
        for n in nodes:
            for p in (n.get("style") or {}):
                if p in CUT2:
                    cnt[p] += 1
            for sel in (n.get("pseudo") or {}):   # sel in {"::before","::after","::marker"}
                pcnt[sel] += 1
        print(f"host: {host}")
        print(f"nodes: {len(nodes)}  styled: {sum(1 for n in nodes if n.get('style'))}"
              f"  with-pseudo: {sum(1 for n in nodes if n.get('pseudo'))}")
        print(f"bundle audit: {'CLEAN (write_bundle did not raise)' if audit_ok else 'FAILED'}")
        print("cut-2 props populated (name: node-count):")
        for p in CUT2:
            if cnt[p]:
                print(f"  {p}: {cnt[p]}")
        print("pseudo selectors populated (selector: node-count):")
        for sel in sorted(pcnt):
            print(f"  {sel}: {pcnt[sel]}")
        if not audit_ok:
            print("bundle_writer stderr tail:", r.stderr[-300:])
    return 0 if audit_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
