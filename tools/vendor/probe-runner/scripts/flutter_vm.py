#!/usr/bin/env python3
"""Generic JSON-RPC client against the Dart VM service.

Usage:
  flutter_vm.py <method> [--params '{"k":"v"}'] [--isolate ID]

Examples:
  flutter_vm.py getVM
  flutter_vm.py getIsolate --isolate <id>
  flutter_vm.py ext.flutter.inspector.show
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
from _flutter import rpc


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("method")
    p.add_argument("--params")
    p.add_argument("--isolate")
    args = p.parse_args()

    params = json.loads(args.params) if args.params else None
    try:
        emit_json(rpc(args.method, params, isolate=args.isolate))
    except Exception as e:
        die(str(e))
    return 0


if __name__ == "__main__":
    sys.exit(main())
