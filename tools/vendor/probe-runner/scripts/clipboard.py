#!/usr/bin/env python3
"""Read or write the macOS clipboard.

Usage:
  clipboard.py get
  clipboard.py set "<text>"
  clipboard.py set --stdin           # take text from stdin
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("action", choices=["get", "set"])
    p.add_argument("text", nargs="?")
    p.add_argument("--stdin", action="store_true")
    args = p.parse_args()

    if args.action == "get":
        r = subprocess.run(["pbpaste"], check=True, capture_output=True, text=True)
        sys.stdout.write(r.stdout)
        return 0

    text = args.text
    if args.stdin:
        text = sys.stdin.read()
    if text is None:
        die("text required (or use --stdin)")
    subprocess.run(["pbcopy"], input=text, text=True, check=True)
    print(json.dumps({"set": len(text)}, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
