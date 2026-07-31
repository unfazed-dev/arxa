#!/usr/bin/env python3
"""Sample CPU stacks of a target process.

Usage:
  sample.py <owner> <seconds>
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import emit_path, out_path, resolve_window


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner")
    p.add_argument("seconds", type=int)
    args = p.parse_args()

    win = resolve_window(args.owner)
    out = out_path(args.owner, "txt", kind="sample")
    with open(out, "w") as f:
        subprocess.run(["sample", str(win["pid"]), str(args.seconds)], stdout=f, check=True)
    emit_path(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
