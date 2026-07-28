#!/usr/bin/env python3
"""Compare two images and emit a diff score + optional diff image.

Three metrics, all normalised so **0 = identical** and larger = more different
(so `above_threshold = score > T` reads the same for each):

  --engine mean   (back-compat) mean per-channel RGB difference / 255. Fast but
                  the most flaky under anti-aliasing / sub-pixel font rendering.
  --engine ssim   (DEFAULT)     windowed Structural Similarity (1 - meanSSIM).
                  Materially more robust to anti-aliasing / font-rendering
                  shifts because it compares local structure, not raw pixels.
  --engine odiff  SIMD-fast Rust binary (shell-out). Built-in anti-aliasing
                  detection (--odiff-antialiasing). Strictly OPT-IN: it is a
                  3rd-party binary not installed by default, and auto-detecting
                  it would make the same command give different scores across
                  machines (odiff's algorithm differs numerically from ssim/
                  mean). Fails fast with an install hint if odiff is missing.

Every output carries an `engine` + `metric` field so a run is never ambiguous
about which engine produced it (the reproducibility invariant: the same
`pixdiff a b --threshold X` must give the same pass/fail on every machine).

Usage:
  pixdiff.py A.png B.png [--out DIFF.png] [--threshold 0.01]
  pixdiff.py A.png B.png --engine mean|ssim|odiff [--odiff-antialiasing]
  pixdiff.py A.png B.png --region X,Y,W,H
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
from _metrics import mean_score, ssim_score, odiff_run


def _load_pair(a_path: str, b_path: str, region=None):
    """Open both images as RGB; optionally crop both to region. Returns (a, b)."""
    try:
        from PIL import Image  # type: ignore
    except ImportError:
        die("missing Pillow. install: pip3 install Pillow")
        return None, None  # unreachable
    a = Image.open(a_path).convert("RGB")
    b = Image.open(b_path).convert("RGB")
    if region:
        x, y, w, h = region
        box = (x, y, x + w, y + h)
        for label, img in (("a", a), ("b", b)):
            if x + w > img.width or y + h > img.height:
                die(f"--region {x},{y},{w},{h} exceeds {label} bounds {img.size}")
        a = a.crop(box)
        b = b.crop(box)
    return a, b


def _parse_region(spec: str):
    if not spec:
        return None
    try:
        x, y, w, h = (int(v) for v in spec.split(","))
    except ValueError:
        die(f"--region expects X,Y,W,H ints (got {spec!r})")
        return None  # unreachable
    if w <= 0 or h <= 0:
        die(f"--region W and H must be positive (got {w}x{h})")
        return None  # unreachable
    return (x, y, w, h)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("a")
    p.add_argument("b")
    p.add_argument("--out")
    p.add_argument("--threshold", type=float, default=0.0,
                   help="score above this -> above_threshold=true (0=identical for all engines)")
    p.add_argument("--engine", choices=["mean", "ssim", "odiff"], default="ssim",
                   help="diff metric (default: ssim — robust to anti-aliasing; "
                        "mean = back-compat raw RGB; odiff = SIMD-fast Rust binary, opt-in)")
    p.add_argument("--odiff-antialiasing", action="store_true",
                   help="(odiff only) enable odiff's built-in anti-aliasing detection")
    p.add_argument("--region", type=str, default=None,
                   help="crop both inputs to X,Y,W,H (comma-separated pixels, "
                        "top-left origin) before differencing")
    args = p.parse_args()

    region = _parse_region(args.region)

    # odiff operates on file paths (it decodes internally), so it cannot share
    # the in-memory crop path. Region + odiff is unsupported (clear message);
    # mean/ssim use the PIL load+crop.
    if args.engine == "odiff":
        if region is not None:
            die("--region is not supported with --engine odiff (odiff reads files); "
                "pre-crop with region.py or use --engine ssim/mean")
        try:
            res = odiff_run(args.a, args.b, threshold=args.threshold,
                            antialiasing=args.odiff_antialiasing, out_diff=args.out)
        except FileNotFoundError as e:
            die(str(e))
            return 2  # unreachable
        emit_json({
            "engine": "odiff", "metric": "odiff",
            "score": res["score"], "above_threshold": res["score"] > args.threshold,
            "match": res.get("match"), "diff_count": res.get("diff_count"),
            "diff_percentage": res.get("diff_percentage"), "reason": res.get("reason"),
            "odiff_rc": res.get("rc"), "odiff_antialiasing": args.odiff_antialiasing,
            "threshold": args.threshold,
            "diff_image": args.out,
        })
        return 0

    # mean / ssim: load + crop in memory
    a, b = _load_pair(args.a, args.b, region=region)
    if a is None:
        return 2
    if a.size != b.size:
        die(f"size mismatch: {a.size} vs {b.size}")

    if args.engine == "mean":
        score, mean_rgb = mean_score(a, b)
        metric = "mean-rgb"
    else:  # ssim
        score = ssim_score(a, b)
        mean_rgb = None
        metric = "ssim"

    if args.out:
        from PIL import ImageChops  # type: ignore
        ImageChops.difference(a, b).save(args.out)

    emit_json({
        "engine": args.engine, "metric": metric,
        "score": score, "above_threshold": score > args.threshold,
        "mean_rgb": mean_rgb, "diff_image": args.out, "size": a.size,
        "region": {"x": region[0], "y": region[1], "w": region[2], "h": region[3]} if region else None,
        "threshold": args.threshold,
    })
    return 0


if __name__ == "__main__":
    sys.exit(main())
