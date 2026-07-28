#!/usr/bin/env python3
"""Memory snapshot of a target process.

Usage:
  mem.py <owner> [--leaks|--vmmap]   # default: leaks
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
    p.add_argument("--leaks", action="store_true")
    p.add_argument("--vmmap", action="store_true")
    args = p.parse_args()

    win = resolve_window(args.owner)
    tool = "vmmap" if args.vmmap else "leaks"
    out = out_path(args.owner, "txt", kind=tool)
    with open(out, "w") as f:
        subprocess.run([tool, str(win["pid"])], stdout=f, check=False)
    emit_path(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
