#!/usr/bin/env python3
"""Boot / kill an Android emulator AVD.

Usage:
  adb_boot.py list
  adb_boot.py boot <avd-name> [--wipe]
  adb_boot.py kill                  # current device
"""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _adb import adb_cmd
from _common import die, emit_json


def emulator_bin() -> str:
    p = shutil.which("emulator")
    if not p:
        # try $ANDROID_HOME/emulator/emulator
        ah = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
        if ah and Path(ah, "emulator", "emulator").exists():
            return str(Path(ah, "emulator", "emulator"))
        die("emulator binary not found. install Android SDK, then add $ANDROID_HOME/emulator to PATH")
    return p


def avd_abi(avd_name: str) -> str | None:
    cfg = Path.home() / ".android" / "avd" / f"{avd_name}.avd" / "config.ini"
    if not cfg.exists():
        return None
    try:
        for line in cfg.read_text(errors="replace").splitlines():
            if line.startswith("abi.type="):
                return line.split("=", 1)[1].strip()
    except OSError:
        pass
    return None


def warn_incompatible_abi(avd_name: str) -> None:
    """Apple Silicon (arm64) cannot run arm32 AVDs under QEMU2."""
    abi = avd_abi(avd_name)
    if not abi:
        return
    if platform.machine() == "arm64" and abi == "arm":
        print(
            f"probe-runner: WARNING: AVD '{avd_name}' is abi.type={abi} (32-bit ARM); "
            f"host is arm64 — emulator will FATAL. Use an arm64-v8a AVD.",
            file=sys.stderr,
        )


def main() -> int:
    p = argparse.ArgumentParser(description="Boot / kill an Android emulator AVD.")
    p.add_argument("action", choices=["list", "boot", "kill"])
    p.add_argument("avd", nargs="?")
    p.add_argument("--wipe", action="store_true")
    args = p.parse_args()

    if args.action == "list":
        r = subprocess.run([emulator_bin(), "-list-avds"], check=True, capture_output=True, text=True)
        sys.stdout.write(r.stdout)
        return 0

    if args.action == "kill":
        adb_cmd(["emu", "kill"], check=False)
        emit_json({"killed": True})
        return 0

    if not args.avd:
        die("avd name required for boot")
    warn_incompatible_abi(args.avd)
    cmd = [emulator_bin(), "-avd", args.avd]
    if args.wipe:
        cmd.append("-wipe-data")
    log_path = Path("/tmp") / f"probe-runner-emu-{args.avd}.log"
    log_fh = log_path.open("wb")
    proc = subprocess.Popen(cmd, stdout=log_fh, stderr=subprocess.STDOUT)
    # Most fatal config errors (wrong ABI, missing system image) abort within ~2s.
    time.sleep(3)
    rc = proc.poll()
    if rc is not None:
        log_fh.close()
        tail = ""
        try:
            tail = "\n".join(log_path.read_text(errors="replace").splitlines()[-10:])
        except OSError:
            pass
        print(
            f"probe-runner: emulator '{args.avd}' exited rc={rc} within 3s. log: {log_path}\n{tail}",
            file=sys.stderr,
        )
        return 1
    emit_json({"booting": args.avd, "pid": proc.pid, "log": str(log_path)})
    return 0


if __name__ == "__main__":
    sys.exit(main())
