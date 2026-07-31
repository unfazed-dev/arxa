#!/usr/bin/env python3
"""One-off real-site validation for reduced-motion (P13) computed-style delta capture (NOT in
the committed suite — nondeterministic). Drives the full pipeline
(web_skeleton --reduced-motion -> bundle_writer) against a public --url and prints ONLY
content-free signal about the captured reduced_motion sidecars.

CONTENT-FREE INVARIANT: nothing printed here is a CSS value, selector, class/id, or full URL.
Only counts, property NAMES, and the host netloc. bundle_writer.write_bundle RAISES on any leak
(non-zero exit = caught content leak / firewall audit fired) — the harness reports that as FAIL
but still prints summary counts.

Host Bash (CDP):
    python3 fixtures/reduced-motion/validate_realsite.py --url https://github.com
    python3 fixtures/reduced-motion/validate_realsite.py --url https://stripe.com
"""
import argparse
import json
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True,
                    help="Public URL to capture (CDP required at runtime).")
    args = ap.parse_args()

    # Content-free: print host NETLOC only — never the full URL or path/query.
    host = urlparse(args.url).netloc or args.url.split("/")[2]

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        sk = td / "_sk.json"
        tok = td / "_tokens.json"
        bundle = td / "_bundle"

        # Reuse a palette-only tokens file — same as the gate.
        tok.write_text(json.dumps({"palette": {}}))

        # Step 1: capture skeleton with reduced-motion sidecar.
        r = subprocess.run(
            [sys.executable, str(SCRIPTS / "web_skeleton.py"),
             "--url", args.url, "--reduced-motion", "--out", str(sk)],
            cwd=str(SCRIPTS), capture_output=True, text=True, timeout=180,
        )
        if r.returncode != 0:
            print(f"web_skeleton FAILED (rc={r.returncode})")
            return 1

        # Step 2: bundle_writer — a non-zero exit means the content firewall audit
        # fired (a caught content leak).  We still read what landed on disk if any.
        # NOTE: bundle_writer raising (non-zero exit) = a caught content leak; the
        # harness treats this as FAIL and surfaces it, but does not suppress counts.
        r_bw = subprocess.run(
            [sys.executable, str(SCRIPTS / "bundle_writer.py"),
             "--skeleton", str(sk), "--tokens", str(tok), "--out", str(bundle)],
            cwd=str(SCRIPTS), capture_output=True, text=True, timeout=180,
        )
        audit_ok = r_bw.returncode == 0

        bundle_sk_path = bundle / "skeleton.json"
        disk = json.loads(bundle_sk_path.read_text()) if (audit_ok and bundle_sk_path.exists()) else {}
        nodes = disk.get("nodes") or []

        # --- on-disk gate checks (mirror the content-free gate) ---
        # Assert _node_reduced_motion and _node_backend are NOT in the on-disk skeleton,
        # and no node has a 'backend' key.
        sidecar_leaked = "_node_reduced_motion" in disk or "_node_backend" in disk
        backend_in_node = any("backend" in n for n in nodes)
        if not sidecar_leaked and not backend_in_node:
            gate_line = "on-disk gate: CLEAN (_node_reduced_motion/_node_backend absent; no node.backend)"
        else:
            parts = []
            if sidecar_leaked:
                parts.append("_node_reduced_motion/_node_backend LEAKED into skeleton.json")
            if backend_in_node:
                parts.append("node has 'backend' key")
            gate_line = "on-disk gate: ▲ " + "; ".join(parts)

        # --- reduced-motion aggregates (content-free counts/names only) ---
        nodes_with_rm = [n for n in nodes if n.get("reduced_motion")]
        total_nodes = len(nodes)
        rm_node_count = len(nodes_with_rm)

        # Changed-prop NAMES seen under the "reduce" label (never values).
        # n["reduced_motion"]["reduce"] is {prop-name: redacted-value}; collect keys only.
        prop_name_set: set[str] = set()
        prop_freq: Counter = Counter()
        delta_size_dist: Counter = Counter()  # how many nodes changed N props

        for n in nodes_with_rm:
            reduce_delta = (n["reduced_motion"] or {}).get("reduce") or {}
            delta_size_dist[len(reduce_delta)] += 1
            for prop_name in reduce_delta.keys():
                prop_name_set.add(prop_name)
                prop_freq[prop_name] += 1

        # --- print content-free report ---
        print(f"host: {host}")
        print(f"nodes: {total_nodes}  nodes-with-reduced_motion: {rm_node_count}")
        print(f"changed motion-prop names (sorted): {sorted(prop_name_set)}")
        print(f"per-prop change frequency (counts only):")
        for p in sorted(prop_freq, key=lambda k: -prop_freq[k]):
            print(f"    {p}: {prop_freq[p]}")
        print(f"delta-size distribution (changed-props-per-node -> count of nodes):")
        for ds in sorted(delta_size_dist):
            print(f"    {ds} props: {delta_size_dist[ds]} node(s)")
        print(gate_line)
        print(f"bundle audit: {'CLEAN (write_bundle did not raise)' if audit_ok else 'FAILED (caught content leak — firewall audit fired)'}")

        if not audit_ok:
            # content-free: never echo bundle_writer stderr — the ContentLeak message can
            # embed a ~40-char sample of the leaked content. The returncode is enough signal.
            print(f"bundle_writer returncode: {r_bw.returncode}")

    return 0 if audit_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
