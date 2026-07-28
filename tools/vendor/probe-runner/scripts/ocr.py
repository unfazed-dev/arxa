#!/usr/bin/env python3
"""OCR an image (or fresh screenshot of a window/region) via macOS Vision.

Usage:
  ocr.py --image PATH
  ocr.py <owner>                          # shot first, then OCR
  ocr.py --rect X,Y,W,H                   # screenshot region first
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json, out_path, resolve_window


def _vision_text(image_path: str) -> list[dict]:
    try:
        import Vision  # type: ignore
        import Quartz  # type: ignore
        from Cocoa import NSURL  # type: ignore
    except ImportError:
        die("missing pyobjc-framework-Vision. pip3 install pyobjc-framework-Vision pyobjc-framework-Cocoa")
        return []

    url = NSURL.fileURLWithPath_(image_path)
    img = Quartz.CIImage.imageWithContentsOfURL_(url)
    if img is None:
        die(f"could not load image: {image_path}")
        return []
    req = Vision.VNRecognizeTextRequest.alloc().init()
    req.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelAccurate)
    handler = Vision.VNImageRequestHandler.alloc().initWithCIImage_options_(img, {})
    handler.performRequests_error_([req], None)
    out = []
    for obs in (req.results() or []):
        cand = obs.topCandidates_(1)
        if not cand:
            continue
        text = cand[0].string()
        bb = obs.boundingBox()
        out.append({"text": str(text), "bbox": [bb.origin.x, bb.origin.y, bb.size.width, bb.size.height]})
    return out


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner", nargs="?")
    p.add_argument("--image")
    p.add_argument("--rect")
    args = p.parse_args()

    img_path = args.image
    if not img_path:
        if not args.owner:
            die("pass --image or <owner>")
        if args.rect:
            cmd_path = Path(__file__).with_name("region.py")
            r = subprocess.run(
                ["python3", str(cmd_path), args.owner, "--rect", args.rect],
                check=False, capture_output=True, text=True,
            )
        else:
            cmd_path = Path(__file__).with_name("shot.py")
            r = subprocess.run(
                ["python3", str(cmd_path), args.owner],
                check=False, capture_output=True, text=True,
            )
        if r.returncode != 0:
            die(f"capture step failed: {r.stderr.strip() or r.stdout.strip()}",
                code=r.returncode or 2)
        img_path = r.stdout.strip().splitlines()[-1]

    res = _vision_text(img_path)
    emit_json({"image": img_path, "lines": res, "count": len(res)})
    return 0


if __name__ == "__main__":
    sys.exit(main())
