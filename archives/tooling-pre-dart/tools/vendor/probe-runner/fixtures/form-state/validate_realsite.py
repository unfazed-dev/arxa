#!/usr/bin/env python3
"""One-off real-site validation for form-state (:checked/:disabled) computed-style delta capture
(NOT in the committed suite — nondeterministic). Drives the full pipeline
(web_skeleton --form-states -> bundle_writer) against a public --url and prints ONLY content-free
signal about the captured form_state sidecars.

CONTENT-FREE INVARIANT: nothing printed here is a CSS value, selector, class/id, or full URL.
Only counts, property NAMES, state labels, and the host netloc. bundle_writer.write_bundle RAISES
on any leak (non-zero exit = caught content leak / firewall audit fired) — the harness reports
that as FAIL but still prints summary counts. Failure paths print the returncode ONLY, never the
subprocess stderr (a ContentLeak message can embed a content sample).

PRECISION HEURISTIC (differs from reduced-motion): UA disabled styling greys ~every form control
(probe FS2: disabled color -> rgb(84,84,84) with no author rule), so a HIGH :disabled node count
is EXPECTED, not over-capture. The smear signal to watch is deltas on nodes that are neither
state-eligible nor combinator-reachable — which the querySelectorAll targeting prevents at source.

Host Bash (CDP):
    python3 fixtures/form-state/validate_realsite.py --url https://github.com
    python3 fixtures/form-state/validate_realsite.py --url https://stripe.com
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

        # Step 1: capture skeleton with form-state sidecar.
        r = subprocess.run(
            [sys.executable, str(SCRIPTS / "web_skeleton.py"),
             "--url", args.url, "--form-states", "--out", str(sk)],
            cwd=str(SCRIPTS), capture_output=True, text=True, timeout=180,
        )
        if r.returncode != 0:
            print(f"web_skeleton FAILED (rc={r.returncode})")
            return 1

        # Step 2: bundle_writer — a non-zero exit means the content firewall audit fired
        # (a caught content leak). We still read what landed on disk if any.
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
        sidecar_leaked = "_node_form_state" in disk or "_node_backend" in disk
        backend_in_node = any("backend" in n for n in nodes)
        if not sidecar_leaked and not backend_in_node:
            gate_line = "on-disk gate: CLEAN (_node_form_state/_node_backend absent; no node.backend)"
        else:
            parts = []
            if sidecar_leaked:
                parts.append("_node_form_state/_node_backend LEAKED into skeleton.json")
            if backend_in_node:
                parts.append("node has 'backend' key")
            gate_line = "on-disk gate: ▲ " + "; ".join(parts)

        # --- form-state aggregates (content-free counts/names only) ---
        nodes_with_fs = [n for n in nodes if n.get("form_state")]
        total_nodes = len(nodes)
        fs_node_count = len(nodes_with_fs)

        # Per-state node counts; changed-prop NAMES seen under each state label (never values).
        # n["form_state"] is {state_label: {prop-name: redacted-value}}; collect labels + keys only.
        per_state_node_count: Counter = Counter()
        prop_freq_by_state = {"checked": Counter(), "disabled": Counter()}
        prop_name_set: set[str] = set()
        delta_size_dist: Counter = Counter()  # total changed props per node (across states)

        for n in nodes_with_fs:
            fs = n["form_state"] or {}
            total_props = 0
            for label, delta in fs.items():
                delta = delta or {}
                per_state_node_count[label] += 1
                total_props += len(delta)
                for prop_name in delta.keys():
                    prop_name_set.add(prop_name)
                    if label in prop_freq_by_state:
                        prop_freq_by_state[label][prop_name] += 1
            delta_size_dist[total_props] += 1

        # --- print content-free report ---
        print(f"host: {host}")
        print(f"nodes: {total_nodes}  nodes-with-form_state: {fs_node_count}")
        print(f"per-state node counts: "
              f"checked={per_state_node_count.get('checked', 0)}  "
              f"disabled={per_state_node_count.get('disabled', 0)}")
        print(f"changed form-state-prop names (sorted): {sorted(prop_name_set)}")
        for label in ("checked", "disabled"):
            freq = prop_freq_by_state[label]
            print(f"per-prop change frequency [:{label}] (counts only):")
            for p in sorted(freq, key=lambda k: -freq[k]):
                print(f"    {p}: {freq[p]}")
        print(f"delta-size distribution (total changed-props-per-node -> count of nodes):")
        for ds in sorted(delta_size_dist):
            print(f"    {ds} props: {delta_size_dist[ds]} node(s)")
        print(gate_line)
        print(f"bundle audit: {'CLEAN (write_bundle did not raise)' if audit_ok else 'FAILED (caught content leak — firewall audit fired)'}")

        if not audit_ok:
            # content-free: never echo bundle_writer stderr — the ContentLeak message can embed a
            # sample of the leaked content. The returncode is enough signal.
            print(f"bundle_writer returncode: {r_bw.returncode}")

    return 0 if audit_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
