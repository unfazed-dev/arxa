#!/usr/bin/env python3
"""DEPRECATED shim — forwards to adb_intent.py.

adb_push.py was historically used for `am broadcast`, which collides with
adb's `adb push` (file copy). It now forwards all arguments to adb_intent.py
and prints a deprecation notice to stderr. For file push/pull see adb_files.py.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

print(
    "probe-runner: adb_push.py is deprecated — use adb_intent.py "
    "(am broadcast). For file push/pull use adb_files.py.",
    file=sys.stderr,
)
os.execv(sys.executable, [sys.executable, str(HERE / "adb_intent.py"), *sys.argv[1:]])
