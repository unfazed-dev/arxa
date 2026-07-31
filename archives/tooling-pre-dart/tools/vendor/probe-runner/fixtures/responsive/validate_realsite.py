#!/usr/bin/env python3
"""One-off real-site validation for Regime-3c responsive breakpoint capture (NOT in the
committed suite — nondeterministic). Drives the full pipeline (web_skeleton
--breakpoints -> bundle_writer) against a public --url and prints ONLY content-free
signal: per non-base viewport width (768 / 390 when using defaults), the count of nodes
carrying a delta and the changed-prop occurrences (CSS prop NAMES from the fixed
RESPONSIVE_PROPS vocabulary — never a resolved value, color, selector, or url).

COVERAGE SANITY (advisor watch-item): the base viewport (widest width) is captured
first; each narrower width is diffed against it. Nodes with no responsive change carry
no delta. This harness prints the total node count and each label's volume %, so a
suspiciously-low ratio surfaces genuine absence vs. a capture bug. NO page content,
NO resolved values, NO full URL is printed or persisted (host only) — IP firewall +
content-free invariant. bundle_writer.write_bundle RAISES on any leak, so a clean exit
proves the firewall passed on real data. Host Bash (CDP):
    python3 fixtures/responsive/validate_realsite.py --url https://github.com
    python3 fixtures/responsive/validate_realsite.py --url https://github.com --widths 1440,768,390"""
import argparse
import json
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
DEFAULT_WIDTHS = "1440,768,390"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--widths", default=DEFAULT_WIDTHS,
                    help="comma-separated viewport widths; widest is base (default: 1440,768,390)")
    args = ap.parse_args()
    host = args.url.split("/")[2] if "//" in args.url else args.url
    widths = [int(w) for w in args.widths.split(",") if w.strip()]
    # LABELS = all widths except the max (the base); narrower widths only
    base_width = max(widths)
    labels = [str(w) for w in widths if w != base_width]
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        sk, tok, bundle = td / "sk.json", td / "tokens.json", td / "bundle"
        tok.write_text(json.dumps({"palette": {}}))
        r = subprocess.run([sys.executable, str(SCRIPTS / "web_skeleton.py"),
                            "--url", args.url, "--breakpoints", args.widths,
                            "--out", str(sk)],
                           cwd=str(SCRIPTS), capture_output=True, text=True, timeout=180)
        if r.returncode != 0:
            print(f"web_skeleton FAILED (rc={r.returncode})")
            return 1
        r = subprocess.run([sys.executable, str(SCRIPTS / "bundle_writer.py"),
                            "--skeleton", str(sk), "--tokens", str(tok), "--out", str(bundle)],
                           cwd=str(SCRIPTS), capture_output=True, text=True, timeout=180)
        audit_ok = r.returncode == 0
        disk = json.loads((bundle / "skeleton.json").read_text()) if audit_ok else {}
        nodes = disk.get("nodes") or []
        total = len(nodes)
        # per-label aggregates: nodes-with-delta + changed-prop occurrences (NAMES only,
        # from the fixed RESPONSIVE_PROPS vocabulary — never a resolved value).
        nodes_with = Counter()
        prop_occ = {label: Counter() for label in labels}
        for n in nodes:
            resp = n.get("responsive") or {}
            for label in labels:
                delta = resp.get(label)
                if delta:
                    nodes_with[label] += 1
                    for p in delta:
                        prop_occ[label][p] += 1
        print(f"host: {host}")
        print(f"nodes: {total}  with-any-responsive: {sum(1 for n in nodes if n.get('responsive'))}")
        print(f"bundle audit: {'CLEAN (write_bundle did not raise)' if audit_ok else 'FAILED'}")
        for label in labels:
            nw = nodes_with[label]
            props = prop_occ[label]
            tot_props = sum(props.values())
            vol = (100.0 * nw / total) if total else 0.0
            print(f"[{label}px] nodes-with-delta: {nw}/{total} ({vol:.1f}%)  "
                  f"changed-prop occurrences: {tot_props}  distinct-props: {len(props)}")
            for p in sorted(props, key=lambda k: -props[k]):
                print(f"    {p}: {props[p]}")
        print("coverage sanity: low nodes-with-delta vs total is EXPECTED (most elements "
              "have no @media rule); a near-ZERO ratio across ALL widths would instead "
              "suggest a capture bug or a site with no responsive CSS — distinguish by eye.")
        if not audit_ok:
            # content-free: never echo bundle_writer stderr — the ContentLeak message can
            # embed a sample of the leaked content. The returncode is enough signal.
            print(f"bundle_writer returncode: {r.returncode}")
    return 0 if audit_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
