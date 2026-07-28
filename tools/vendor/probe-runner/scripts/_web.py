#!/usr/bin/env python3
"""Shared web-automation helpers: CDP client + safaridriver fallback."""

from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import sys
import time
import urllib.request
from typing import Any, Optional


CHROME_PATHS = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Arc.app/Contents/MacOS/Arc",
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
]


def _port() -> int:
    return int(os.environ.get("PROBE_RUNNER_CHROME_CDP_PORT", "9222"))


def _user_data_dir() -> str:
    return os.environ.get("PROBE_RUNNER_CHROME_USER_DATA_DIR", "/tmp/probe-runner-chrome")


def chrome_binary() -> Optional[str]:
    p = shutil.which("google-chrome") or shutil.which("chromium") or shutil.which("chrome")
    if p:
        return p
    for path in CHROME_PATHS:
        if os.path.exists(path):
            return path
    return None


def chrome_running() -> bool:
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{_port()}/json/version", timeout=0.5) as r:
            return r.status == 200
    except Exception:
        return False


def chrome_launch(extra_args: Optional[list[str]] = None) -> None:
    bin_ = chrome_binary()
    if not bin_:
        raise RuntimeError("Chrome not installed. brew install --cask google-chrome")
    args = [
        bin_,
        f"--remote-debugging-port={_port()}",
        f"--user-data-dir={_user_data_dir()}",
        "--remote-allow-origins=*",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-features=ChromeWhatsNewUI",
        # web_anim sets scrollY statically and reads f(scrollY). When the window is
        # backgrounded/occluded Chrome throttles the renderer: setTimeout-built late
        # pages stall AND programmatic window.scrollTo stops dispatching 'scroll', so
        # scroll-event-driven transforms read identity -> false "no movers". Disable
        # that throttling so static-scroll measurement is reliable regardless of
        # window focus (headless-equivalent timing without going headless).
        "--disable-renderer-backgrounding",
        "--disable-backgrounding-occluded-windows",
        "--disable-background-timer-throttling",
    ]
    if extra_args:
        args.extend(extra_args)
    subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(40):
        if chrome_running():
            return
        time.sleep(0.25)
    raise RuntimeError("Chrome failed to expose CDP within 10s")


def cdp_targets() -> list[dict]:
    with urllib.request.urlopen(f"http://127.0.0.1:{_port()}/json", timeout=2) as r:
        return json.loads(r.read())


def cdp_target(focus_url: Optional[str] = None) -> dict:
    targets = [t for t in cdp_targets() if t.get("type") == "page"]
    if not targets:
        raise RuntimeError("no Chrome page targets; open a tab first or pass --url to web_open")
    if focus_url:
        for t in targets:
            if focus_url in t.get("url", ""):
                return t
    return targets[0]


def cdp_send(ws_url: str, method: str, params: Optional[dict] = None,
             *, _id: int = 1, timeout: float = 10.0) -> dict:
    try:
        from websocket import create_connection  # type: ignore
    except ImportError:
        print("probe-runner: missing websocket-client. pip3 install websocket-client",
              file=sys.stderr)
        sys.exit(2)
    ws = create_connection(ws_url, timeout=timeout)
    try:
        ws.send(json.dumps({"id": _id, "method": method, "params": params or {}}))
        while True:
            msg = json.loads(ws.recv())
            if msg.get("id") == _id:
                if "error" in msg:
                    raise RuntimeError(json.dumps(msg["error"]))
                return msg.get("result", {})
    finally:
        ws.close()


class CDPSession:
    """Persistent CDP WebSocket. Required for DOM nodeId chains.

    DOM.getDocument-returned nodeIds are valid only within a single inspector
    session. Reusing one ws keeps them alive across querySelector/getBoxModel/
    Accessibility.getPartialAXTree.
    """

    def __init__(self, ws_url: str, timeout: float = 10.0, suppress_origin: bool = False):
        try:
            from websocket import create_connection  # type: ignore
        except ImportError:
            print("probe-runner: missing websocket-client. pip3 install websocket-client",
                  file=sys.stderr)
            sys.exit(2)
        # suppress_origin: Android Chrome (and any device-side Chrome reached over
        # `adb forward`) rejects the CDP WS handshake with 403 when an Origin
        # header is present — it can't be launched with --remote-allow-origins=*.
        # Omitting Origin is the supported path for forwarded endpoints.
        self._ws = create_connection(ws_url, timeout=timeout, suppress_origin=suppress_origin)
        self._id = 0

    def send(self, method: str, params: Optional[dict] = None) -> dict:
        self._id += 1
        mid = self._id
        self._ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
        while True:
            msg = json.loads(self._ws.recv())
            if msg.get("id") == mid:
                if "error" in msg:
                    raise RuntimeError(json.dumps(msg["error"]))
                return msg.get("result", {})

    def close(self) -> None:
        try:
            self._ws.close()
        except Exception:
            pass

    def __enter__(self) -> "CDPSession":
        return self

    def __exit__(self, *exc: Any) -> None:
        self.close()


def cdp_session(ws_url: str, timeout: float = 10.0,
                suppress_origin: bool = False) -> CDPSession:
    return CDPSession(ws_url, timeout=timeout, suppress_origin=suppress_origin)


def use_chrome_by_default() -> bool:
    return os.environ.get("PROBE_RUNNER_BROWSER", "chrome").lower() == "chrome"


# ---------------- Safari fallback (selenium + safaridriver) ----------------


def safari_driver() -> Any:
    try:
        from selenium import webdriver  # type: ignore
        from selenium.webdriver.safari.options import Options  # type: ignore
    except ImportError:
        raise RuntimeError("missing selenium: pip3 install selenium")

    opts = Options()
    return webdriver.Safari(options=opts)


def ensure_browser(preferred: str = "auto") -> tuple[str, Any]:
    """Return (engine, handle) where engine in {chrome, safari}.

    chrome -> handle is a dict from cdp_target()
    safari -> handle is a selenium WebDriver instance

    On Safari failure (driver init, missing safaridriver, "Allow Remote
    Automation" toggle off, SessionNotCreatedException), raise a
    RuntimeError carrying the install/enable hint so every caller's
    `die(str(e))` emits the same `probe-runner: <hint>` line and exits
    with rc=2.
    """
    preferred = preferred.lower()
    if preferred == "safari":
        try:
            return ("safari", safari_driver())
        except Exception as e:
            raise RuntimeError(
                f"safari session failed: {e}. enable safaridriver "
                f"(`safaridriver --enable`) and toggle Safari → Settings → "
                f"Advanced → Show Develop menu → Develop → "
                f"Allow Remote Automation."
            )
    if preferred in ("chrome", "auto") and chrome_binary():
        if not chrome_running():
            chrome_launch()
        return ("chrome", cdp_target())
    # fall back
    try:
        return ("safari", safari_driver())
    except Exception as e:
        raise RuntimeError(
            f"no browser available. install Chrome (brew install --cask google-chrome) "
            f"or enable safaridriver (`safaridriver --enable`). last error: {e}"
        )
