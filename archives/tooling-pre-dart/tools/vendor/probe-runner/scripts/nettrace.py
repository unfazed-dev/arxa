#!/usr/bin/env python3
"""Capture network packets for the target process.

Uses tcpdump with a BPF filter scoped to the pid's open sockets.
Requires sudo for tcpdump.

Usage:
  nettrace.py <owner> --seconds N [--iface en0]
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
    p.add_argument("--seconds", type=int, required=True)
    p.add_argument("--iface", default="any")
    args = p.parse_args()

    win = resolve_window(args.owner)
    out = out_path(args.owner, "pcap", kind="net")
    cmd = ["sudo", "tcpdump", "-i", args.iface, "-w", str(out), "-G", str(args.seconds), "-W", "1"]
    print(f'recording {args.seconds}s to {out} (sudo required). pid={win["pid"]}', file=sys.stderr)
    subprocess.run(cmd, check=True)
    emit_path(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
