#!/usr/bin/env python3
"""derisk_flutter_skeleton — LIVE validation recipe for flutter_skeleton.py.

NOT collected by pytest (derisk_* convention). flutter_skeleton's pure logic
(classify, build_skeleton, _parse_walk) is unit-tested in
test_flutter_skeleton.py; this script is the manual live-VM harness that proves
the Dart VM walk works end-to-end against a real Flutter app. Run it by hand
when changing _WALK_EXPR or targeting a new Flutter version.

RECIPE:
  1. flutter run -d <device> --disable-service-auth-codes   (debug build)
  2. flutter_attach.py --url http://127.0.0.1:<PORT>/        (from run output)
  3. python3 derisk_flutter_skeleton.py                      (this script)

It runs flutter_skeleton._capture() (one VM eval round-trip) and asserts the
returned probe-skeleton/2 payload is well-formed: non-empty nodes, every node
has a non-zero bbox, the schema is probe-skeleton/2, and a self-diff through
skeleton_diff passes. The VM-walk expression is Flutter-version-sensitive (it
walks WidgetsBinding.instance.rootElement with visitChildren and reads
localToGlobal + size on every RenderBox); if it fails on another version the
failing expression is printed.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import emit_json
import flutter_skeleton as fs
import skeleton_diff as sd


def main() -> int:
    sk = fs._capture()  # live VM walk; raises/die()s on VM failure

    nodes = sk["nodes"]
    assert sk["schema"] == "probe-skeleton/2", sk["schema"]
    assert nodes, "no RenderBoxes recovered"
    for n in nodes:
        assert n["bbox"]["w"] > 0 and n["bbox"]["h"] > 0, ("zero-area node", n)

    # self-diff must pass (identical geometry)
    self_diff = sd.diff(sk, sk, sd.DEFAULT_GATES)

    emit_json({
        "derisk": "flutter_skeleton",
        "engine": sk["engine"],
        "node_count": len(nodes),
        "role_counts": {r: sum(1 for n in nodes if n["role"] == r)
                        for r in set(n["role"] for n in nodes)},
        "viewport": sk["viewport"],
        "self_diff_pass": self_diff["pass"],
        "ok": bool(nodes and self_diff["pass"]),
    })
    return 0 if nodes and self_diff["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
