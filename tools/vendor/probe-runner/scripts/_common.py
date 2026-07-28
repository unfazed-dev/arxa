#!/usr/bin/env python3
"""Shared helpers for probe-runner scripts.

Every other script imports from this module. Keeps window discovery,
output-path resolution, and TCC permission checks in one place.
"""

from __future__ import annotations

import datetime as _dt
import fcntl as _fcntl
import json
import os
import select as _select
import shutil
import subprocess
import sys
import time as _time
from pathlib import Path
from typing import Any, Iterator, Optional

OUTDIR = Path(os.environ.get("PROBE_RUNNER_OUTDIR", "/tmp/probe-runner"))
OUTDIR.mkdir(parents=True, exist_ok=True)


def iter_lines_until(
    proc: "subprocess.Popen[Any]",
    *,
    deadline: Optional[float] = None,
    poll_interval: float = 0.2,
) -> Iterator[str]:
    """Yield text lines from proc.stdout, honoring an optional monotonic deadline.

    Unlike a bare `proc.stdout.readline()` loop, this uses select() on the
    underlying pipe so the deadline is enforced even when the child writes
    nothing. When the deadline passes, the proc is terminated and the
    generator returns. Each yielded line ends with '\\n' (except possibly
    the final line if no trailing newline was written).
    """
    if proc.stdout is None:
        return
    fd = proc.stdout.fileno()
    try:
        flags = _fcntl.fcntl(fd, _fcntl.F_GETFL)
        _fcntl.fcntl(fd, _fcntl.F_SETFL, flags | os.O_NONBLOCK)
    except OSError:
        pass

    buf = b""
    while True:
        if deadline is not None:
            remaining = deadline - _time.monotonic()
            if remaining <= 0:
                proc.terminate()
                return
            wait = min(poll_interval, max(0.0, remaining))
        else:
            wait = poll_interval

        r, _w, _e = _select.select([fd], [], [], wait)
        if not r:
            if proc.poll() is not None and not buf:
                return
            continue
        try:
            chunk = os.read(fd, 4096)
        except BlockingIOError:
            continue
        if not chunk:
            if buf:
                yield buf.decode("utf-8", errors="replace")
            return
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            yield line.decode("utf-8", errors="replace") + "\n"


def ts() -> str:
    # microsecond-resolution so back-to-back captures don't collide
    return _dt.datetime.now().strftime("%Y%m%d-%H%M%S-%f")


def out_path(target: str, ext: str, kind: Optional[str] = None) -> Path:
    safe = "".join(c if c.isalnum() or c in "-_." else "_" for c in target)
    suffix = f"-{kind}" if kind else ""
    return OUTDIR / f"{safe}-{ts()}{suffix}.{ext.lstrip('.')}"


def die(msg: str, code: int = 2) -> None:
    print(f"probe-runner: {msg}", file=sys.stderr)
    sys.exit(code)


def which_or_die(binary: str, install_hint: str) -> str:
    p = shutil.which(binary)
    if not p:
        die(f"missing dependency '{binary}'. install: {install_hint}")
    return p


def run(cmd: list[str], *, check: bool = True, capture: bool = False,
        timeout: Optional[float] = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        check=check,
        capture_output=capture,
        text=True,
        timeout=timeout,
    )


def resolve_window(owner: str, *, index: int = 0, all_: bool = False) -> Any:
    """Return window info for an owner name via Quartz.

    Returns either a single dict (when `all_` is False) or a list of dicts.
    Each dict has: window_id, owner, title, bounds {x,y,w,h}, pid, layer.
    Largest-bounds window wins for the default selection.

    macOS-only (Quartz / pyobjc). On Linux/Windows, die() with a clear message
    routing to the platform-agnostic verbs instead of a raw ImportError.
    """
    try:
        import Quartz  # type: ignore
    except ImportError:
        from _platform import os_name
        if os_name() == "macos":
            die(
                "missing 'Quartz' (pyobjc). macOS system Python should have it; "
                "if not: pip3 install pyobjc-framework-Quartz"
            )
        else:
            die(
                "window discovery is macOS-only (Quartz). On " + os_name() +
                " the web/ios/adb/flutter verbs are the path (CDP/VM/idb/adb "
                "are platform-agnostic); desktop-window targeting is not supported. "
                "See SKILL.md → Platform support."
            )
        return  # unreachable

    opts = Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements  # type: ignore
    wins = Quartz.CGWindowListCopyWindowInfo(opts, Quartz.kCGNullWindowID)  # type: ignore
    matches = []
    for w in wins:
        if w.get("kCGWindowOwnerName", "") != owner:
            continue
        b = w.get("kCGWindowBounds", {}) or {}
        matches.append({
            "window_id": int(w.get("kCGWindowNumber", 0)),
            "owner": w.get("kCGWindowOwnerName", ""),
            "title": w.get("kCGWindowName", "") or "",
            "bounds": {
                "x": int(b.get("X", 0)),
                "y": int(b.get("Y", 0)),
                "w": int(b.get("Width", 0)),
                "h": int(b.get("Height", 0)),
            },
            "pid": int(w.get("kCGWindowOwnerPID", 0)),
            "layer": int(w.get("kCGWindowLayer", 0)),
        })

    if all_:
        return matches
    if not matches:
        die(f"no window found for owner '{owner}'. is the app running?")
    # Largest by area wins (best heuristic for "the main window").
    matches.sort(key=lambda m: m["bounds"]["w"] * m["bounds"]["h"], reverse=True)
    if index >= len(matches):
        die(f"index {index} out of range; {len(matches)} window(s) found")
    return matches[index]


def secure_input_active() -> bool:
    try:
        out = subprocess.run(
            ["ioreg", "-l"], check=False, capture_output=True, text=True, timeout=3
        ).stdout
    except Exception:
        return False
    return "kIOHIDStateSecureInput" in out


# Public TCC scope identifiers accepted by tcc_check().
TCC_SCOPES = ("screen_recording", "accessibility")

_TCC_GRANT_HINTS = {
    "screen_recording": (
        "System Settings → Privacy & Security → Screen Recording → enable the "
        "terminal/IDE that ran probe-runner, then relaunch it. Required for "
        "shot/region/record/multishot."
    ),
    "accessibility": (
        "System Settings → Privacy & Security → Accessibility → enable the "
        "terminal/IDE that ran probe-runner (and 'cliclick' if listed), then "
        "relaunch it. Required for click/drag/scroll/type_text/ax_*."
    ),
}


def tcc_status(scope: str) -> Optional[bool]:
    """Return True/False for granted/denied; None if the OS API is unavailable.

    Uses preflight APIs that do NOT trigger the system prompt:
      - screen_recording: CGPreflightScreenCaptureAccess (macOS 10.15+)
      - accessibility:    AXIsProcessTrusted             (macOS 10.9+)

    Returning None means we couldn't query the state (pyobjc framework
    missing); callers should fall through to the native error path.
    """
    if scope == "screen_recording":
        try:
            from Quartz import CGPreflightScreenCaptureAccess  # type: ignore
        except ImportError:
            return None
        return bool(CGPreflightScreenCaptureAccess())
    if scope == "accessibility":
        try:
            from ApplicationServices import AXIsProcessTrusted  # type: ignore
        except ImportError:
            return None
        return bool(AXIsProcessTrusted())
    raise ValueError(f"unknown tcc scope '{scope}'; expected one of {TCC_SCOPES}")


def tcc_check(scope: str, *, soft: bool = False) -> bool:
    """Preflight a TCC permission; die with a grant hint if denied.

    `soft=True` returns the boolean instead of exiting — for use inside
    composite scripts that already handle the error path.

    A None result from tcc_status (preflight API unavailable on this host)
    is treated as 'pass through' — the wrapping script's native call will
    surface the real error if permission is missing.
    """
    state = tcc_status(scope)
    if state is None or state is True:
        return True
    hint = _TCC_GRANT_HINTS.get(scope, "")
    msg = f"TCC '{scope}' not granted to this process. {hint}"
    if soft:
        print(f"probe-runner: {msg}", file=sys.stderr)
        return False
    die(msg, code=3)
    return False  # unreachable


def emit_json(payload: Any) -> None:
    print(json.dumps(payload, indent=2, ensure_ascii=False))


def emit_path(p: Path) -> None:
    print(str(p))
