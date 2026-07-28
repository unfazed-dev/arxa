#!/usr/bin/env python3
"""Shared web eval-transport: one `ev(expr) -> value` bridge over every web
engine probe-runner can reach, plus a single resolver both `web_anim` and
`web_eval` call so they target identical transports (kept in sync by construction).

A transport is an `_Eval` with two methods: `ev(expr)` runs a self-contained JS
*expression* returning a JSON-serialisable value, and `close()` tears down. The
two concrete transports cover every engine:

  - `_CDPEval`  — Chrome DevTools Protocol `Runtime.evaluate` over a persistent
                  inspector WebSocket. Host Chrome, Android-emulator Chrome /
                  debuggable WebView (adb-forwarded port), and any pre-forwarded
                  CDP endpoint.
  - `_WDEval`   — WebDriver `execute_script`. Host Safari and Mobile Safari on a
                  booted iOS simulator. selenium marshals return values to native
                  Python the same shape CDP `returnByValue` gives, so probe
                  payloads round-trip unchanged across both.

`resolve_web_eval(args)` reads the standard transport flags off an argparse
namespace (`browser`, `url`, `android`, `ios`, `cdp_port`, `serial`) and returns
`(engine, ev, device)`. `navigate(ev, engine, url)` loads a URL (mandatory for
the fresh WebDriver sessions, which start blank).
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import time
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die
from _web import cdp_session, cdp_target, ensure_browser, safari_driver
from _settle import adaptive_settle


DEFAULT_MAX_WAIT = 10.0  # settle cap (s). Cartier-class 26s hydrate: pass --max-wait 30.

# Engine-agnostic settle read: node count + readyState + a network-activity proxy
# from Resource Timing. inflight = resources not yet finished (responseEnd === 0);
# since_start_ms = ms since the most recent resource STARTED (a lone long-lived
# stream stops bumping this, so quiet still opens -> RSC-safe). Works identically
# over CDP returnByValue and WebDriver execute_script (both marshal the object).
_SETTLE_JS = (
    "(function(){"
    "var rs=performance.getEntriesByType('resource');"
    "var inflight=0,lastStart=0;"
    "for(var i=0;i<rs.length;i++){var e=rs[i];"
    "if(e.responseEnd===0)inflight++;"
    "if(e.startTime>lastStart)lastStart=e.startTime;}"
    "return{n:document.getElementsByTagName('*').length,"
    "ready:document.readyState==='complete',"
    "inflight:inflight,"
    "since_start_ms:performance.now()-lastStart};"
    "})()"
)


# ---------------- eval transport (CDP or WebDriver) ----------------
# Every in-page interaction goes through one method, `ev(expr) -> value`, so the
# caller's logic is identical whether the JS runs over Chrome DevTools Protocol
# (host/Android) or WebDriver execute_script (Safari/iOS). Each expr is a
# self-contained expression returning a JSON-serialisable value.

class _Eval:
    def ev(self, expr):  # pragma: no cover - interface
        raise NotImplementedError

    def close(self):  # pragma: no cover - interface
        pass


class _CDPEval(_Eval):
    """CDP Runtime.evaluate over a persistent inspector WebSocket."""

    def __init__(self, ws_url, suppress_origin=False):
        # Default 20s WS read timeout; heavy pages whose DOMSnapshot.captureSnapshot
        # exceeds it (e.g. very tall lazy-loaded sites) can raise it via
        # PROBE_RUNNER_CDP_TIMEOUT without a code change.
        try:
            _to = float(os.environ.get("PROBE_RUNNER_CDP_TIMEOUT", "20") or "20")
        except ValueError:
            _to = 20.0
        self.sess = cdp_session(ws_url, timeout=_to, suppress_origin=suppress_origin)

    def ev(self, expr):
        r = self.sess.send("Runtime.evaluate", {
            "expression": expr, "returnByValue": True, "awaitPromise": False,
        })
        if "exceptionDetails" in r:
            die("in-page error: " + json.dumps(r["exceptionDetails"])[:300])
        return r.get("result", {}).get("value")

    def close(self):
        self.sess.close()


class _WDEval(_Eval):
    """WebDriver execute_script (Safari host / Mobile Safari on iOS sim).

    selenium marshals JS return values to native Python (dict/list/num/str) the
    same shape CDP returnByValue gives, so the probe payload round-trips
    unchanged. A JS error raises (no exceptionDetails dict), so wrap it to the
    same die() surface as the CDP path."""

    def __init__(self, driver):
        self.driver = driver

    def ev(self, expr):
        try:
            return self.driver.execute_script("return (" + expr + ");")
        except Exception as e:
            die("in-page error: " + str(e)[:300])

    def close(self):
        try:
            self.driver.quit()
        except Exception:
            pass


def _rewrite_ws(ws_url, port):
    """Point a CDP WebSocket URL at the local forwarded port.

    Chrome's /json on an Android device reports `webSocketDebuggerUrl` with the
    *device-side* host:port (typically the original --remote-debugging-port).
    Accessed through `adb forward tcp:<local> localabstract:chrome_devtools_remote`
    the WS must instead hit 127.0.0.1:<local>, else the handshake 404s/refuses."""
    return re.sub(r"^ws://[^/]+/", "ws://127.0.0.1:%d/" % port, ws_url)


def _adb_forward(port, serial):
    cmd = ["adb"] + (["-s", serial] if serial else []) + \
        ["forward", "tcp:%d" % port, "localabstract:chrome_devtools_remote"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        die("adb forward failed: %s. Is an emulator running with a debuggable "
            "Chrome/WebView open? (check `adb devices`; for WebView the app must "
            "call WebView.setWebContentsDebuggingEnabled(true))"
            % (r.stderr.strip() or r.stdout.strip() or "no output"))


def _remote_cdp_eval(port, focus_url):
    """Build a CDP eval against a pre-forwarded port (Android / generic remote)."""
    os.environ["PROBE_RUNNER_CHROME_CDP_PORT"] = str(port)
    try:
        tgt = cdp_target(focus_url)
    except Exception as e:
        die(str(e))
    return _CDPEval(_rewrite_ws(tgt["webSocketDebuggerUrl"], port),
                    suppress_origin=True), tgt


def _ios_safari_driver():
    """Mobile Safari on the booted iOS simulator (mirrors ios_safari.py caps)."""
    try:
        from selenium import webdriver  # type: ignore
        from selenium.webdriver.safari.options import Options  # type: ignore
    except ImportError:
        die("missing selenium. pip3 install selenium")
    opts = Options()
    opts.set_capability("platformName", "iOS")
    opts.set_capability("safari:useSimulator", True)
    try:
        return webdriver.Safari(options=opts)
    except Exception as e:
        die("safaridriver(iOS) init failed: %s. Boot a sim (`xcrun simctl boot`), "
            "run `safaridriver --enable`, and ensure Xcode's iOS platform is "
            "installed." % e)


def add_transport_args(p):
    """Register the standard transport flags shared by web_anim and web_eval.

    Keeping the flag definitions in one place means the two verbs cannot drift
    apart in name, default, or help. Callers add their own probe-specific args."""
    p.add_argument("--browser", default="auto", choices=["chrome", "safari", "auto"],
                   help="host engine when no device flag is given (default auto→chrome)")
    p.add_argument("--url", help="navigate here first (required for --ios / --browser safari)")
    p.add_argument("--android", action="store_true",
                   help="target Chrome/WebView in a running Android emulator via adb forward")
    p.add_argument("--ios", action="store_true",
                   help="target Mobile Safari on the booted iOS simulator (WebDriver)")
    p.add_argument("--cdp-port", type=int, dest="cdp_port",
                   help="use a pre-forwarded CDP port (default 9223 with --android)")
    p.add_argument("--serial", help="adb device serial for --android (multi-device)")


def resolve_web_eval(args):
    """Resolve the transport flags on `args` to `(engine, ev, device)`.

    The single point where web_anim and web_eval choose a transport, so both
    reach the identical engine for a given flag set. `engine` in {chrome, safari}
    (chrome ⇒ CDP, safari ⇒ WebDriver); `device` is a human label."""
    if getattr(args, "ios", False):
        if not args.url:
            die("--ios needs --url (fresh Mobile Safari session has no page loaded)")
        return "safari", _WDEval(_ios_safari_driver()), "ios-sim"
    if getattr(args, "android", False):
        port = args.cdp_port or 9223
        _adb_forward(port, getattr(args, "serial", None))
        ev, _tgt = _remote_cdp_eval(port, args.url)
        return "chrome", ev, "android-emu"
    if getattr(args, "cdp_port", None):
        ev, _tgt = _remote_cdp_eval(args.cdp_port, args.url)
        return "chrome", ev, "remote-cdp"
    if args.browser == "safari":
        if not args.url:
            die("--browser safari needs --url (fresh WebDriver session has no page loaded)")
        try:
            return "safari", _WDEval(safari_driver()), "host"
        except Exception as e:
            die(str(e))
    try:
        engine, handle = ensure_browser(args.browser)
    except Exception as e:
        die(str(e))
    ev = _CDPEval(handle["webSocketDebuggerUrl"]) if engine == "chrome" else _WDEval(handle)
    return engine, ev, "host"


def navigate(ev, engine, url, max_wait=DEFAULT_MAX_WAIT):
    """Load `url` (mandatory for the fresh WebDriver sessions, which start blank),
    then adaptively settle. Returns settle provenance
    {settled, capped, waited_ms, n_nodes}; callers may ignore it (they did before
    this gained a return value). Content-blind: the read carries only counts/flags.
    See `_settle.adaptive_settle` for the settle definition + the honest ceiling."""
    if engine == "safari":
        ev.driver.get(url)
    else:
        ev.ev("location.assign(%s)" % json.dumps(url))
    return adaptive_settle(lambda: ev.ev(_SETTLE_JS), time.sleep, time.monotonic,
                           max_wait=max_wait)
