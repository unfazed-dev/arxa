#!/usr/bin/env python3
"""One-off real-site validation for fixed-width @container capture (NOT in the committed suite —
nondeterministic). Drives the full pipeline (web_skeleton --container-queries -> bundle_writer)
against a public --url and prints ONLY content-free signal about the captured `container`
sidecars.

CONTENT-FREE INVARIANT: nothing printed here is a CSS value, selector, class/id, or full URL.
Only counts, CSS property NAMES (from the fixed CONTAINER_PROPS vocabulary), sweep-width
integers, and the host netloc. bundle_writer.write_bundle RAISES on any leak (non-zero exit =
caught content leak / firewall audit fired) — the harness reports that as FAIL but still prints
summary counts. Failure paths print the returncode ONLY, never the subprocess stderr (a
ContentLeak message can embed a content sample).

COVERAGE NOTE: this rung MUTATES fixed-width inline-size containers and captures the restyle.
A site with no inline-size query containers (or only viewport-tracking ones) legitimately yields
few/zero `container` deltas — that is honest absence, not a bug. The harness prints total node
count and nodes-with-container so a suspiciously-low ratio is visible. The composite label is
"<container_node_id>@<width>"; the container node_id is bundle-internal (content-safe) and the
width is the swept integer — neither is content.

Host Bash (CDP):
    python3 fixtures/container-query/validate_realsite.py --url https://example.com
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
    ap.add_argument("--widths", default=None,
                    help="optional comma container widths (default: web_skeleton's 240,480,720)")
    args = ap.parse_args()

    # Content-free: print host NETLOC only — never the full URL or path/query.
    host = urlparse(args.url).netloc or args.url.split("/")[2]

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        sk = td / "_sk.json"
        tok = td / "_tokens.json"
        bundle = td / "_bundle"
        tok.write_text(json.dumps({"palette": {}}))

        cq_arg = args.widths if args.widths else None
        cmd = [sys.executable, str(SCRIPTS / "web_skeleton.py"),
               "--url", args.url, "--out", str(sk)]
        # bare --container-queries uses the default widths; with --widths pass them through.
        cmd += (["--container-queries", cq_arg] if cq_arg else ["--container-queries"])

        # Step 1: capture skeleton with the container sidecar.
        r = subprocess.run(cmd, cwd=str(SCRIPTS), capture_output=True, text=True, timeout=240)
        if r.returncode != 0:
            print(f"web_skeleton FAILED (rc={r.returncode})")
            return 1

        # Step 2: bundle_writer — a non-zero exit means the content firewall audit fired.
        r_bw = subprocess.run(
            [sys.executable, str(SCRIPTS / "bundle_writer.py"),
             "--skeleton", str(sk), "--tokens", str(tok), "--out", str(bundle)],
            cwd=str(SCRIPTS), capture_output=True, text=True, timeout=240,
        )
        audit_ok = r_bw.returncode == 0

        bundle_sk_path = bundle / "skeleton.json"
        disk = json.loads(bundle_sk_path.read_text()) if (audit_ok and bundle_sk_path.exists()) else {}
        nodes = disk.get("nodes") or []

        # --- on-disk gate checks (mirror the content-free gate) ---
        sidecar_leaked = "_node_container" in disk or "_node_backend" in disk
        backend_in_node = any("backend" in n for n in nodes)
        if not sidecar_leaked and not backend_in_node:
            gate_line = "on-disk gate: CLEAN (_node_container/_node_backend absent; no node.backend)"
        else:
            parts = []
            if sidecar_leaked:
                parts.append("_node_container/_node_backend LEAKED into skeleton.json")
            if backend_in_node:
                parts.append("node has 'backend' key")
            gate_line = "on-disk gate: ▲ " + "; ".join(parts)

        # --- container aggregates (content-free counts/names only) ---
        nodes_with_cq = [n for n in nodes if n.get("container")]
        total_nodes = len(nodes)

        # n["container"] is {"<container_node_id>@<width>": {prop-name: value}}; collect labels,
        # prop NAMES, and per-width counts only — never a value.
        label_count = 0
        prop_name_set = set()
        width_counter: Counter = Counter()           # swept width -> # of (node,label) deltas
        container_ids = set()                         # distinct swept-container node_ids
        prop_freq: Counter = Counter()
        delta_size_dist: Counter = Counter()          # changed-props-per-label -> count

        for n in nodes_with_cq:
            cq = n["container"] or {}
            for label, delta in cq.items():
                delta = delta or {}
                label_count += 1
                # label = "<container_node_id>@<width>"
                if "@" in label:
                    cid, _, w = label.rpartition("@")
                    container_ids.add(cid)
                    if w.isdigit():
                        width_counter[int(w)] += 1
                delta_size_dist[len(delta)] += 1
                for prop_name in delta.keys():
                    prop_name_set.add(prop_name)
                    prop_freq[prop_name] += 1

        # --- print content-free report ---
        print(f"host: {host}")
        print(f"nodes: {total_nodes}  nodes-with-container: {len(nodes_with_cq)}  "
              f"total (node,label) deltas: {label_count}")
        print(f"distinct swept query-containers (by internal node_id): {len(container_ids)}")
        print(f"per-swept-width delta counts: "
              f"{dict(sorted(width_counter.items()))}")
        print(f"changed container-prop names (sorted): {sorted(prop_name_set)}")
        print("per-prop change frequency (counts only):")
        for p in sorted(prop_freq, key=lambda k: -prop_freq[k]):
            print(f"    {p}: {prop_freq[p]}")
        print("delta-size distribution (changed-props-per-(node,label) -> count):")
        for ds in sorted(delta_size_dist):
            print(f"    {ds} props: {delta_size_dist[ds]} delta(s)")
        print(gate_line)
        print(f"bundle audit: {'CLEAN (write_bundle did not raise)' if audit_ok else 'FAILED (caught content leak — firewall audit fired)'}")

        if not audit_ok:
            # content-free: never echo bundle_writer stderr — the ContentLeak message can embed
            # a sample of the leaked content. The returncode is enough signal.
            print(f"bundle_writer returncode: {r_bw.returncode}")

    return 0 if audit_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
