#!/usr/bin/env python3
"""Cross-route token merge (G3b). Read a G3a capture (site.json + routes/<id>/
tokens.json across N routes) and emit a content-free unified design system
(design_system.json, schema probe-runner/design-system@1).

A SEPARATE pass over an existing capture — site_capture is unchanged, and the content
firewall is unchanged: the artifact is the same token surface tokens.json already
persists (hex values, numeric scales, role/category names, counts, positional route
ids), re-audited through content_firewall.audit_bundle as a backstop. Failure paths
print only error kind / violation count — never a content sample, never subprocess stderr.

    python3 scripts/site_merge.py --site site_out [--out design_system.json] [--cluster-tol 8]
"""
import argparse
import json
from pathlib import Path

import content_firewall as cf
import _merge
from _common import die, emit_json


def _load_routes(site_dir):
    """Return (per_route, hosts). per_route = [(route_id, tokens_dict)] for ok routes
    with a readable tokens.json, IN site.json order (positional, deterministic). An
    unreadable route is skipped, not fatal (mirrors G3a per-route isolation)."""
    try:
        site = json.loads((site_dir / "site.json").read_text())
    except (OSError, ValueError):
        die("cannot read site.json under %s" % site_dir)
    hosts = site.get("hosts") or []
    per_route = []
    for r in site.get("routes", []):
        if not r.get("ok"):
            continue
        tok = site_dir / "routes" / r["route_id"] / "tokens.json"
        try:
            per_route.append((r["route_id"], json.loads(tok.read_text())))
        except (OSError, ValueError):
            continue
    return per_route, hosts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--site", required=True, help="G3a capture dir (contains site.json)")
    ap.add_argument("--out", help="output path (default <site>/design_system.json). The "
                    "firewall backstop audits the OUTPUT'S PARENT dir, so point --out at "
                    "the capture dir or an isolated/empty path -- a populated unrelated "
                    "dir would be over-scanned and could false-positive exit 3.")
    ap.add_argument("--cluster-tol", dest="cluster_tol", type=int, default=8,
                    help="Chebyshev delta-RGB tolerance for the clustered palette view")
    args = ap.parse_args()

    site_dir = Path(args.site)
    out = Path(args.out) if args.out else site_dir / "design_system.json"

    per_route, hosts = _load_routes(site_dir)
    if not per_route:
        die("no mergeable routes")

    ds = _merge.build_design_system(per_route, hosts, args.cluster_tol)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(ds, indent=2, ensure_ascii=False))

    # Backstop: re-audit through the UNCHANGED firewall. audit_bundle rglobs the dir
    # containing the artifact (and, when out is in the capture dir, the route bundles).
    viol = cf.audit_bundle(out.parent)
    if viol:
        out.unlink(missing_ok=True)  # never persist a flagged artifact (content-free posture)
        emit_json({"ok": False, "error": "content_audit_failed",
                   "out": str(out), "violations": len(viol)})
        return 3
    emit_json({"ok": True, "out": str(out),
               "merged_route_count": ds["merged_route_count"]})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
