#!/usr/bin/env python3
"""Run a probe-runner command while screen sleep / dimming is inhibited.

Usage:
  headless.py -- <verb> <args...>     # runs `caffeinate -dimsu python3 .../scripts/<verb>.py args`
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) >= 2 and sys.argv[1] in ("-h", "--help"):
        print(__doc__.strip())
        print()
        print("usage: headless.py -- <verb> <args...>")
        return 0
    if "--" not in sys.argv:
        print("usage: headless.py -- <verb> <args...>", file=sys.stderr)
        return 2
    idx = sys.argv.index("--")
    rest = sys.argv[idx + 1:]
    if not rest:
        print("missing verb after --", file=sys.stderr)
        return 2
    verb, *args = rest
    script = Path(__file__).with_name(f"{verb}.py")
    if not script.exists():
        print(f"no such verb: {verb}", file=sys.stderr)
        return 2
    cmd = ["caffeinate", "-dimsu", sys.executable, str(script), *args]
    os.execvp(cmd[0], cmd)


if __name__ == "__main__":
    sys.exit(main())
