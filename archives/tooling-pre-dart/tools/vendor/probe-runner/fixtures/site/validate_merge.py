#!/usr/bin/env python3
"""Content-free real-site validation harness for G3b cross-route token merge. Captures
a real multi-route site with site_capture (host CDP) into a tempdir, runs site_merge,
asserts the firewall backstop is CLEAN, and prints content-free merge stats (per-role
core/exact/clustered COUNTS, per-scalar core/distinct COUNTS). NEVER echoes token
values, page content, or subprocess stderr. NOT in the unit suite (needs a browser).

    python3 fixtures/site/validate_merge.py --urls "https://www.python.org/,https://www.python.org/about/" --cdp-port 9222
"""
import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"


def _run(cmd):
    # Content-free: return rc only; never surface subprocess stderr.
    return subprocess.run(cmd, cwd=str(SCRIPTS), capture_output=True, text=True).returncode


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--urls", help="comma-separated route URLs")
    ap.add_argument("--urls-file")
    ap.add_argument("--cdp-port", dest="cdp_port", type=int, default=9222)
    ap.add_argument("--cluster-tol", dest="cluster_tol", type=int, default=8)
    args = ap.parse_args()

    tmp = Path(tempfile.mkdtemp(prefix="g3b_merge_"))
    try:
        cap = [sys.executable, str(SCRIPTS / "site_capture.py"),
               "--out", str(tmp / "site"), "--cdp-port", str(args.cdp_port)]
        if args.urls_file:
            cap += ["--urls-file", args.urls_file]
        elif args.urls:
            cap += ["--urls", args.urls]
        else:
            print("FAIL: need --urls or --urls-file"); return 1
        rc = _run(cap)
        print("site_capture rc:", rc)
        if rc != 0:
            print("FAIL: capture failed"); return 1

        site_dir = tmp / "site"
        rc = _run([sys.executable, str(SCRIPTS / "site_merge.py"),
                   "--site", str(site_dir), "--cluster-tol", str(args.cluster_tol)])
        print("site_merge rc:", rc)
        if rc != 0:
            print("FAIL: merge failed (rc %d)" % rc); return 1

        ds = json.loads((site_dir / "design_system.json").read_text())
        print("hosts:", ds["hosts"], " merged_route_count:", ds["merged_route_count"])
        for role in ds["palette"]:
            ex, cl = ds["palette"][role]["exact"], ds["palette"][role]["clustered"]
            print("  palette.%-11s exact=%d (core %d) | clustered=%d (core %d)" % (
                role, len(ex), sum(e["core"] for e in ex),
                len(cl), sum(e["core"] for e in cl)))
        for cat, entries in ds["scalars"].items():
            print("  scalar.%-12s distinct=%d (core %d)" % (
                cat, len(entries), sum(e["core"] for e in entries)))

        # consistency: clustered distinct <= exact distinct per role
        for role in ds["palette"]:
            assert len(ds["palette"][role]["clustered"]) <= len(ds["palette"][role]["exact"]), role

        sys.path.insert(0, str(SCRIPTS))
        import importlib
        cf = importlib.import_module("content_firewall")
        viol = cf.audit_bundle(site_dir)
        print("site-root firewall audit:", "CLEAN" if not viol else "DIRTY (%d)" % len(viol))
        ok = not viol
        print("GATE PASS" if ok else "GATE FAIL")
        return 0 if ok else 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
