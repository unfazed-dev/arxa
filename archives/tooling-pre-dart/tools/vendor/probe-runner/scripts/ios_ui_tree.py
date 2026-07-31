#!/usr/bin/env python3
"""Dump iOS UI hierarchy via idb.

Usage:
  ios_ui_tree.py            # idb ui describe-all on booted sim
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _ios import idb_run
from _common import die, which_or_die  # noqa


def main() -> int:
    argparse.ArgumentParser(description="Dump iOS UI hierarchy via idb.").parse_args()
    r = idb_run(["ui", "describe-all"], capture=True)
    sys.stdout.write(r.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
