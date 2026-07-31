#!/usr/bin/env python3
"""Drive Mobile Safari on the booted iOS sim via safaridriver.

Usage:
  ios_safari.py --url <url> [--eval "<js>"] [--shot OUT.png]
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json, out_path  # noqa


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--url")
    p.add_argument("--eval")
    p.add_argument("--shot")
    args = p.parse_args()

    try:
        from selenium import webdriver  # type: ignore
        from selenium.webdriver.safari.options import Options  # type: ignore
    except ImportError:
        die("missing selenium. pip3 install selenium")

    opts = Options()
    opts.set_capability("platformName", "iOS")
    opts.set_capability("safari:useSimulator", True)
    try:
        driver = webdriver.Safari(options=opts)
    except Exception as e:
        die(f"safaridriver init failed: {e}. did you run `safaridriver --enable`?")

    out: dict[str, object] = {}
    try:
        if args.url:
            driver.get(args.url)
            time.sleep(1.0)
            out["title"] = driver.title
        if args.eval:
            out["eval"] = driver.execute_script(f"return ({args.eval})")
        if args.shot:
            o = out_path("ios-safari", "png") if args.shot == "auto" else Path(args.shot)
            o.write_bytes(driver.get_screenshot_as_png())
            out["shot"] = str(o)
    finally:
        driver.quit()
    emit_json(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
