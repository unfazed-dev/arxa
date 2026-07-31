#!/usr/bin/env python3
"""One-off real-site validation for multi-route site capture (G3a) — NOT in the
committed unit suite (nondeterministic, needs CDP). Drives the full orchestrator
(site_capture -> per-route web_skeleton/web_tokens/bundle_writer) against an EXPLICIT
list of public routes and prints ONLY content-free signal about the produced site
bundle.

CONTENT-FREE INVARIANT: nothing printed here is page content, a CSS value, a selector,
a class/id, or a full URL. Only host netlocs, integer counts, positional route ids,
CSS-prop-free aggregates, and categorical error kinds. site_capture itself re-audits
the whole site tree through content_firewall before declaring clean; this harness
reports the orchestrator's returncode and re-runs the same backstop, but NEVER echoes
subprocess stderr (a ContentLeak message can embed a content sample).

COVERAGE NOTE: G3a is orchestration only — it loops the existing per-route capture and
assembles a content-free manifest. A route that fails (unreachable / content-suspicious)
is recorded with a categorical error_kind and does not abort the run; the per-error_kind
counts below make any failure visible. This harness corroborates the orchestration +
manifest contract on real pages and seeds the later cross-route recurrence probe.

Host Bash (CDP):
    python3 fixtures/site/validate_realsite.py --urls https://a.example/,https://a.example/about --cdp-port 9222
    python3 fixtures/site/validate_realsite.py --urls-file routes.txt --cdp-port 9222
"""
import argparse
import importlib
import json
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--urls", default=None, help="comma-separated public route URLs")
    ap.add_argument("--urls-file", dest="urls_file", default=None,
                    help="file with one route URL per line (# comments ok)")
    ap.add_argument("--cdp-port", dest="cdp_port", type=int, default=9222)
    args = ap.parse_args()
    if not args.urls and not args.urls_file:
        print("need --urls or --urls-file")
        return 2

    with tempfile.TemporaryDirectory() as td:
        out = Path(td) / "site"
        cmd = [sys.executable, str(SCRIPTS / "site_capture.py"),
               "--out", str(out), "--cdp-port", str(args.cdp_port)]
        if args.urls:
            cmd += ["--urls", args.urls]
        if args.urls_file:
            cmd += ["--urls-file", args.urls_file]

        # site_capture exits nonzero if its own site-root audit trips; capture_output
        # keeps subprocess stdout/stderr OUT of context.
        r = subprocess.run(cmd, cwd=str(SCRIPTS), capture_output=True, text=True)
        site_path = out / "site.json"
        audit_ok = r.returncode == 0 and site_path.exists()

        if not site_path.exists():
            # content-free: returncode only, never stderr.
            print("site_capture produced no site.json (rc=%d)" % r.returncode)
            return 1

        site = json.loads(site_path.read_text())
        routes = site.get("routes", [])

        # --- content-free aggregates ---
        ok_rows = [x for x in routes if x.get("ok")]
        err_counter = Counter(x.get("error_kind") for x in routes if not x.get("ok"))
        node_counts = sorted(x.get("node_count", 0) for x in ok_rows)

        # --- on-disk gate (mirror the content-free contract) ---
        # No internal join keys / backend ids may surface in any per-route skeleton.
        backend_leak = False
        sidecar_leak = False
        for x in ok_rows:
            sk = out / x["bundle"] / "skeleton.json"
            if not sk.exists():
                continue
            disk = json.loads(sk.read_text())
            if "_node_backend" in disk or "_node_container" in disk:
                sidecar_leak = True
            if any("backend" in n for n in (disk.get("nodes") or [])):
                backend_leak = True
        gate_clean = not backend_leak and not sidecar_leak

        # --- re-run the firewall backstop on the whole site tree ---
        sys.path.insert(0, str(SCRIPTS))
        cf = importlib.import_module("content_firewall")
        viol = cf.audit_bundle(out)

        # --- print content-free report ---
        print("hosts: %s" % site.get("hosts"))
        print("route_count: %d  ok_count: %d" % (site.get("route_count", 0),
                                                  site.get("ok_count", 0)))
        print("per-error_kind counts: %s" % dict(err_counter))
        print("ok-route node_count distribution (sorted): %s" % node_counts)
        print("on-disk gate: %s" % ("CLEAN (no _node_backend/_node_container; no node.backend)"
                                    if gate_clean else
                                    "LEAK (sidecar=%s backend=%s)" % (sidecar_leak, backend_leak)))
        print("site-root firewall audit: %s" % ("CLEAN" if not viol else
              "FAILED (%d violation(s); kinds=%s)" % (
                  len(viol), sorted({v.get("kind") for v in viol}))))
        print("site_capture rc: %d" % r.returncode)

    return 0 if (audit_ok and gate_clean and not viol) else 1


if __name__ == "__main__":
    raise SystemExit(main())
