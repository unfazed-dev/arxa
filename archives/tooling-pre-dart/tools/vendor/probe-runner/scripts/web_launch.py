#!/usr/bin/env python3
"""Launch a CDP-enabled Chrome (or report Safari fallback availability).

Usage:
  web_launch.py                          # spawn Chrome with --remote-debugging-port
  web_launch.py --url about:blank        # spawn + navigate the active tab
  web_launch.py --browser=safari         # ensure safaridriver is enabled
  web_launch.py --status                 # report chrome state
  web_launch.py --browser=safari --status # report safaridriver/Safari state
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
from _web import (
    cdp_send, cdp_target, chrome_binary, chrome_launch, chrome_running,
    ensure_browser,
)


def _safari_status() -> dict:
    safaridriver = shutil.which("safaridriver") or "/System/Cryptexes/App/usr/bin/safaridriver"
    if not Path(safaridriver).exists():
        safaridriver = None  # type: ignore[assignment]
    # Probe whether the Allow-Remote-Automation toggle is on by starting and
    # immediately quitting safaridriver in --diagnose mode is too invasive;
    # operators must verify the Safari UI toggle themselves. Surface what we
    # can detect cheaply.
    safari_running = False
    try:
        r = subprocess.run(["pgrep", "-x", "Safari"], capture_output=True, text=True, check=False)
        safari_running = r.returncode == 0 and bool(r.stdout.strip())
    except Exception:
        pass
    return {
        "engine": "safari",
        "safaridriver": safaridriver,
        "safari_running": safari_running,
        "remote_automation_hint": (
            "if session creation later fails, enable Safari → Settings → "
            "Advanced → Show Develop menu → Develop → Allow Remote Automation"
        ),
    }


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--browser", default="chrome", choices=["chrome", "safari", "auto"])
    p.add_argument("--status", action="store_true")
    p.add_argument("--url", help="after launch, navigate the active tab here (Chrome only)")
    args = p.parse_args()

    if args.status:
        if args.browser == "safari":
            emit_json(_safari_status())
            return 0
        emit_json({
            "engine": "chrome",
            "chrome_binary": chrome_binary(),
            "chrome_running": chrome_running(),
        })
        return 0

    if args.browser == "safari":
        try:
            engine, _h = ensure_browser("safari")
        except Exception as e:
            die(str(e))
        emit_json({"engine": engine})
        return 0

    if not chrome_running():
        try:
            chrome_launch()
        except Exception as e:
            die(str(e))

    navigated = None
    if args.url:
        try:
            ws_url = cdp_target()["webSocketDebuggerUrl"]
            cdp_send(ws_url, "Page.navigate", {"url": args.url})
            navigated = args.url
        except Exception as e:
            die(f"navigate failed after launch: {e}")

    emit_json({"engine": "chrome", "running": chrome_running(), "navigated": navigated})
    return 0


if __name__ == "__main__":
    sys.exit(main())
