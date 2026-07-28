#!/usr/bin/env python3
"""Platform detection + capability layer for probe-runner.

probe-runner's CORE surface (web/ios/adb/flutter verbs — CDP, VM service, idb,
adb) is platform-agnostic: those targets run regardless of host OS. Only the
**desktop** surface is host-OS-coupled: window discovery (Quartz), still/video
capture (screencapture / ScreenCaptureKit), input synthesis (cliclick), and TCC
permissions. This module centralises detection of those host capabilities so:

  - on macOS, the best available backend is used (ScreenCaptureKit on 12.3+,
    legacy screencapture otherwise; Quartz for windows; cliclick for input);
  - on Linux/Windows, desktop capture/input is NOT YET IMPLEMENTED — the verbs
    raise NotImplementedError with the researched native path printed, instead
    of crashing on a raw ImportError. The web/ios/adb/flutter verbs still run.

Detection is pure (no I/O beyond a single `sw_vers`/PATH check) and cached, so
callers can branch on `has_screencapturekit()` etc. without repeat cost.

Researched Linux/Windows paths (NOT wired this pass; documented for the next):
  Linux capture : DBus → xdg-desktop-portal (PipeWire); consent prompts fight
                  unattended automation (https://stackoverflow.com/questions/79885735)
  Linux input   : xdotool (subprocess) or pynput (Win32/X11 backend)
  Windows capt. : dxcam (DXGI Desktop Duplication) or mss (pure-python, no DXGI)
  Windows input : pynput (Win32 backend)
  Cross-platform capture lib: xcap (Rust; Mac/Win/Linux+Wayland) — lib.rs/crates/xcap
"""
from __future__ import annotations

import functools
import platform
import shutil
import subprocess
from typing import Optional, Tuple


@functools.lru_cache(maxsize=1)
def os_name() -> str:
    """'macos' | 'windows' | 'linux' (fallback). Uses platform.system() — the
    canonical host check (https://discuss.python.org/t/clarify-usage-of-platform-system/70900)."""
    s = platform.system()
    if s == "Darwin":
        return "macos"
    if s == "Windows":
        return "windows"
    return "linux"  # Linux + anything else


@functools.lru_cache(maxsize=1)
def macos_version() -> Optional[Tuple[int, int]]:
    """(major, minor) on macOS, else None. Parsed from `sw_vers -productVersion`
    (the authoritative source; platform.mac_ver() can lag on newer releases)."""
    if os_name() != "macos":
        return None
    try:
        r = subprocess.run(["sw_vers", "-productVersion"], capture_output=True,
                           text=True, timeout=3)
        parts = r.stdout.strip().split(".")
        if len(parts) >= 2:
            return (int(parts[0]), int(parts[1]))
        if parts and parts[0].isdigit():
            return (int(parts[0]), 0)
    except (ValueError, subprocess.SubprocessError, FileNotFoundError):
        pass
    return None


def has_screencapturekit() -> bool:
    """True iff ScreenCaptureKit is available: macOS 12.3+ AND the
    pyobjc-framework-ScreenCaptureKit binding is importable. Apple introduced
    ScreenCaptureKit in 12.3 (https://developer.apple.com/documentation/screencapturekit/)."""
    v = macos_version()
    if not v or v < (12, 3):
        return False
    try:
        import ScreenCaptureKit  # type: ignore  # noqa: F401
        return True
    except ImportError:
        return False


def has_cliclick() -> bool:
    """True iff the `cliclick` binary is on PATH (macOS input synthesis).
    The only PATH probe probe-runner gates on (assert_desktop_input)."""
    return shutil.which("cliclick") is not None


def assert_desktop_capture(verb: str) -> None:
    """Raise a clear NotImplementedError if desktop capture is unsupported on
    this host (Linux/Windows today). Callers in shot/region/record/multishot
    use this instead of crashing on a missing macOS binary."""
    if os_name() == "macos":
        return  # supported (ScreenCaptureKit or legacy screencapture)
    raise NotImplementedError(
        f"{verb}: desktop capture is macOS-only in this build of probe-runner. "
        f"On {os_name()}, the researched native path is: "
        + ("Linux: DBus → xdg-desktop-portal (PipeWire) capture "
           "(https://stackoverflow.com/questions/79885735); note portal consent "
           "prompts complicate unattended automation."
           if os_name() == "linux" else
           "Windows: dxcam (DXGI Desktop Duplication) or mss (pure-python).")
        + " The web/ios/adb/flutter verbs run on every OS — only desktop "
          "capture/input is macOS-gated. See SKILL.md → Platform support.")


def assert_desktop_input(verb: str) -> None:
    """Raise a clear NotImplementedError if desktop input synthesis is unsupported
    (non-macOS, or macOS without cliclick). Callers in click/drag/scroll/etc. use this."""
    if os_name() == "macos" and has_cliclick():
        return
    if os_name() != "macos":
        raise NotImplementedError(
            f"{verb}: desktop input synthesis is macOS-only (cliclick) in this build. "
            f"On {os_name()}, the researched path is pynput "
            "(Win32/X11 backends, cross-platform) or xdotool (Linux). "
            "See SKILL.md → Platform support.")
    # macOS without cliclick — point at the install hint (the verb will also fail)
    raise NotImplementedError(
        f"{verb}: desktop input needs 'cliclick' on PATH. Install: brew install cliclick.")
