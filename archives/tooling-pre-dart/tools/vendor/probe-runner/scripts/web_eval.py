#!/usr/bin/env python3
"""Evaluate JS in the active web target and print the result as JSON.

Shares one transport resolver with `web_anim` (`_web_eval.resolve_web_eval`), so
eval reaches the *same* engine web_anim measures for any given flag set — host
Chrome (CDP), host/iOS-sim Safari (WebDriver), Android-emulator Chrome
(adb-forwarded CDP), or any pre-forwarded CDP port.

Usage:
  web_eval.py "document.title"
  web_eval.py "fetch('/api').then(r=>r.text())" --await        # host Chrome
  web_eval.py "getComputedStyle(document.querySelector('.menu')).transition" \
      --ios   --url https://site                               # Mobile Safari (sim)
  web_eval.py "innerHeight"  --android --url https://site      # emulator Chrome
  web_eval.py "location.href" --browser safari --url https://x # host Safari

Note: --await (awaitPromise) applies to the CDP transports (Chrome / Android /
forwarded port). WebDriver (Safari / iOS) evaluates synchronously, mirroring the
prior behaviour. --ios and --browser safari need --url (fresh WebDriver session
starts blank).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
from _web_eval import resolve_web_eval, navigate, add_transport_args


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("js")
    p.add_argument("--await", dest="await_promise", action="store_true",
                   help="awaitPromise (CDP transports only: Chrome/Android/forwarded port)")
    add_transport_args(p)  # --browser/--url/--android/--ios/--cdp-port/--serial (shared)
    args = p.parse_args()

    engine, ev, device = resolve_web_eval(args)
    try:
        if args.url:
            navigate(ev, engine, args.url)

        if engine == "chrome" and args.await_promise:
            # reach into the persistent CDP session for awaitPromise; the shared
            # _CDPEval.ev forces awaitPromise=False (the common, sync case).
            r = ev.sess.send("Runtime.evaluate", {
                "expression": args.js, "awaitPromise": True, "returnByValue": True,
            })
            if "exceptionDetails" in r:
                die("in-page error: " + json.dumps(r["exceptionDetails"])[:300])
            value = r.get("result", {}).get("value")
        else:
            value = ev.ev(args.js)

        emit_json({"engine": engine, "device": device, "value": value})
    finally:
        ev.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
