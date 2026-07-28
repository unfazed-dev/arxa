#!/usr/bin/env python3
"""OCR two images and diff the recognized text.

Usage:
  text_diff.py A.png B.png
"""

from __future__ import annotations

import argparse
import difflib
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import emit_json


def _ocr_text(image: str) -> str:
    script = Path(__file__).with_name("ocr.py")
    r = subprocess.run(
        ["python3", str(script), "--image", image],
        check=True, capture_output=True, text=True,
    )
    data = json.loads(r.stdout)
    return "\n".join(l["text"] for l in data["lines"])


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("a")
    p.add_argument("b")
    args = p.parse_args()

    ta, tb = _ocr_text(args.a), _ocr_text(args.b)
    ratio = difflib.SequenceMatcher(None, ta, tb).ratio()
    diff = list(difflib.unified_diff(ta.splitlines(), tb.splitlines(), lineterm=""))
    emit_json({"ratio": ratio, "diff": diff})
    return 0


if __name__ == "__main__":
    sys.exit(main())
