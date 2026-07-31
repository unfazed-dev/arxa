#!/usr/bin/env python3
"""Shared adb helpers."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from typing import Optional


def adb_bin() -> str:
    p = shutil.which("adb")
    if not p:
        raise RuntimeError("adb not installed. brew install android-platform-tools")
    return p


def serial() -> Optional[str]:
    return os.environ.get("PROBE_RUNNER_ADB_SERIAL")


def _remedy(msg: str) -> str:
    """Map a failed adb verb's stderr to the next concrete action, so the death
    message says what to run instead of only that something failed."""
    m = msg.lower()
    if "no devices" in m or "no emulators" in m:
        return "no device/emulator is up — boot one: adb_boot.py boot <avd> (list targets: adb devices)"
    if "more than one device" in m:
        return "multiple devices — pick one: PROBE_RUNNER_ADB_SERIAL=<serial> (list: adb devices)"
    if "device offline" in m:
        return "device offline — re-attach: adb reconnect (or re-run adb_boot.py)"
    if "device" in m and "not found" in m:
        return "device not found — list targets: adb devices; set PROBE_RUNNER_ADB_SERIAL=<serial>"
    return "device/emulator up? (boot: adb_boot.py boot <avd>; list: adb devices)"


def adb_cmd(args: list[str], *, check: bool = True, capture: bool = False, input_: Optional[bytes] = None,
            stdout=None, stderr=None) -> subprocess.CompletedProcess:
    s = serial()
    base = [adb_bin()]
    if s:
        base += ["-s", s]
    r = subprocess.run(
        base + args,
        check=False,
        capture_output=capture and stdout is None and stderr is None,
        text=False if input_ is not None else None,
        input=input_,
        stdout=stdout,
        stderr=stderr,
    )
    if check and r.returncode != 0:
        msg = ""
        if isinstance(r.stderr, (bytes, bytearray)):
            msg = r.stderr.decode("utf-8", errors="replace").strip()
        elif r.stderr:
            msg = str(r.stderr).strip()
        if not msg:
            msg = f"adb {' '.join(args)} failed rc={r.returncode}"
        print(f"probe-runner: {msg} — {_remedy(msg)}", file=sys.stderr)
        sys.exit(r.returncode or 2)
    return r


def adb_shell(cmd: str, *, capture: bool = True) -> str:
    s = serial()
    base = [adb_bin()]
    if s:
        base += ["-s", s]
    r = subprocess.run(base + ["shell", cmd], check=False, capture_output=capture, text=True)
    if r.returncode != 0:
        msg = (r.stderr or "").strip() or f"adb shell '{cmd}' failed rc={r.returncode}"
        print(f"probe-runner: {msg} — {_remedy(msg)}", file=sys.stderr)
        sys.exit(r.returncode or 2)
    return r.stdout if capture else ""
