#!/usr/bin/env python3
"""Cross-route shared-chrome dedup (G3d). Read a G3a capture (site.json + routes/<id>/skeleton.json
across N routes) and emit a content-free, losslessly-reconstructable deduped-chrome artifact
(chrome_dedup.json, schema probe-runner/chrome-dedup@1).

Content-free: stores only structural mechanism + positional ids/bbox + token_ref/text_len deltas,
the same fields the firewalled skeletons already carry. The output's parent dir is re-audited
through content_firewall.audit_bundle and never persisted on a violation.

Lossless: reconstruct(dedup(skeletons)) is byte-identical to the input; the CLI fails closed if not.

Usage: python3 scripts/site_chrome.py --site site_out [--out chrome_dedup.json]
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
import content_firewall as cf
import _chrome_dedup as D


def _load_routes(site_dir):
    try:
        site = json.loads((site_dir / "site.json").read_text())
    except (OSError, ValueError):
        die("cannot read site.json under %s" % site_dir)  # clean die (exit 2), not a traceback
    routes = {}
    for r in site.get("routes", []):
        if not r.get("ok"):
            continue
        sk = site_dir / "routes" / r["route_id"] / "skeleton.json"
        if not sk.exists():
            continue
        try:
            doc = json.loads(sk.read_text())
        except Exception:
            continue                                  # per-route isolation, mirrors G3a
        nodes = doc.get("nodes", doc) if isinstance(doc, dict) else doc
        if isinstance(nodes, list):
            routes[r["route_id"]] = nodes
    return routes


def _node_sets_equal(a, b):
    by = lambda ns: {n["id"]: n for n in ns}
    return by(a) == by(b)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--site", required=True)
    ap.add_argument("--out")
    args = ap.parse_args()
    site_dir = Path(args.site)
    out = Path(args.out) if args.out else site_dir / "chrome_dedup.json"

    routes = _load_routes(site_dir)
    if len(routes) < 2:
        die("need >=2 ok routes with skeletons to dedup chrome")

    art = D.dedup_chrome(routes)

    # Losslessness gate (absolute): reconstruct must be byte-identical, else fail closed.
    rebuilt = D.reconstruct(art)
    roundtrip_ok = all(rid in rebuilt and _node_sets_equal(rebuilt[rid], routes[rid])
                       for rid in routes)
    if not roundtrip_ok:
        die("round-trip not byte-identical — dedup would be lossy; refusing to write")

    doc = {"schema": "probe-runner/chrome-dedup@1", "route_count": len(routes), **_jsonable(art)}
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(doc, indent=2, ensure_ascii=False))

    viol = cf.audit_bundle(out.parent)
    if viol:
        out.unlink(missing_ok=True)
        emit_json({"ok": False, "error": "content_firewall", "out": str(out),
                   "violations": len(viol)})
        return 3                                       # nonzero exit (mirrors site_merge) on flag
    emit_json({"ok": True, "out": str(out), "roundtrip_ok": True,
               "route_count": len(routes), "template_count": len(art["templates"])})
    return 0


def _jsonable(art):
    """JSON-safe view of the artifact. Structural keys are STRINGS, so `templates` persists as a
    {key: nodes} dict that reconstruct() consumes DIRECTLY (the on-disk file is exactly what
    reconstruct reads). Only two non-JSON values exist: each vdelta `flags` set -> sorted list
    (informational; reconstruct reads `values`, never `flags`). `exceptions` keys are already str.
    The G3d `drop` map ({str(i): [field,...]}, template-only fields deleted on rebuild) is JSON-native
    and carried through explicitly so reconstruct() of the on-disk file stays lossless even if this
    serializer is later rewritten field-by-field (dict(ref) already copies it; the explicit set is a
    by-construction guard, not a transform)."""
    routes = {}
    for rid, route in art["routes"].items():
        refs = []
        for ref in route["refs"]:
            r = dict(ref)
            r["nodes"] = [{"bbox": pn.get("bbox"),
                           "vdelta": {"flags": sorted(pn["vdelta"]["flags"]),
                                      "values": pn["vdelta"]["values"]}} for pn in ref["nodes"]]
            r["drop"] = ref.get("drop", {})            # template-only fields deleted on rebuild
            refs.append(r)
        routes[rid] = {"refs": refs, "donor_keys": route["donor_keys"], "rest": route["rest"]}
    return {"templates": art["templates"], "routes": routes}


if __name__ == "__main__":
    raise SystemExit(main())
