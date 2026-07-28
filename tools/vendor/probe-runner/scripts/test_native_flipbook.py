#!/usr/bin/env python3
"""TDD for `_native_flipbook.recover_from_video` -- the platform-agnostic core
shared by every native flipbook verb (Flutter/iOS/Android app, no DOM).

The native input is always a screen-recorded VIDEO. This proves the full
video -> frames -> motion-recovery path on synthetic ground truth: a textured
object translating over a noisy background by a KNOWN easeOutCubic, encoded to
a real (lossless) mp4 with ffmpeg, then recovered. No device required.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))


def _ease_out_cubic(p):
    return 1.0 - (1.0 - p) ** 3


def _make_translate_video(out_path, amp=400.0, n=24, fps=25, w=700, h=300,
                          obj=120, x0=50, y0=90):
    """A distinct textured object translating +x by easeOutCubic over a static
    noisy background, encoded losslessly. Returns (video_path, region, truth_amp)."""
    rng = np.random.default_rng(2)
    bg = (rng.random((h, w)) * 0.3 + 0.3).astype(np.float32)
    patch = rng.random((obj, obj)).astype(np.float32)
    d = tempfile.mkdtemp(prefix="natfb-src-")
    for i in range(n + 1):
        off = amp * _ease_out_cubic(i / n)
        px = int(round(x0 + off))
        frame = bg.copy()
        frame[y0:y0 + obj, px:px + obj] = patch
        Image.fromarray((np.clip(frame, 0, 1) * 255).astype(np.uint8)).save(
            os.path.join(d, f"f{i:03d}.png"))
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
           "-framerate", str(fps), "-i", os.path.join(d, "f%03d.png"),
           "-c:v", "libx264", "-crf", "0", "-pix_fmt", "yuv444p", str(out_path)]
    subprocess.run(cmd, check=True)
    shutil.rmtree(d, ignore_errors=True)
    return str(out_path), (x0, y0, obj, obj), amp


@pytest.fixture
def synthetic_video(tmp_path):
    return _make_translate_video(tmp_path / "translate.mp4")


def test_recover_from_video_with_region(synthetic_video):
    """Given the object's frame-0 region, recover_from_video reads the video and
    recovers the easeOutCubic translate (the native-app certification path)."""
    from _native_flipbook import recover_from_video
    video, region, amp = synthetic_video
    res = recover_from_video(video, fps=25, region=region)
    tx = res["channels"]["tx"]
    assert tx["reliable"] is True
    assert tx["easing"] == "easeOutCubic"  # the certified quantity: exact
    # default trim drops the settled tail (frames within settle_frac of the end),
    # so total amplitude under-reads by ~2%; easing/rms are unaffected.
    assert abs(tx["amp"] - amp) < 8.0
    assert tx["rms"] <= 0.05


def test_recover_from_video_auto_localizes(synthetic_video):
    """With no region, recover_from_video auto-locates the mover (coordinate-free)
    and still recovers the curve -- the platform-universal screenshot-only case."""
    from _native_flipbook import recover_from_video
    video, _region, amp = synthetic_video
    res = recover_from_video(video, fps=25, region=None)
    tx = res["channels"]["tx"]
    assert tx["reliable"] is True
    assert tx["easing"] == "easeOutCubic"
    assert abs(tx["amp"] - amp) < 8.0


def test_aligned_fit_rejects_degenerate_plateau():
    """A capture that undersamples the motion (e.g. a software-GPU emulator
    rendering only ~3 steps) yields a step/plateau trajectory. The aligned fit
    must NOT report a false-confident easing on it -- a constant-y plateau makes
    every easing score rms 0. It must flag the data as degenerate (name=None),
    so a bad capture fails the cert instead of silently passing."""
    from _flipbook import fit_easing_aligned
    # 0 then an 11-frame plateau at 0.787 then end -- the real emulator capture.
    ys = [0.0] + [0.787] * 11 + [1.032] * 5 + [1.0]
    xs = list(range(len(ys)))
    fit = fit_easing_aligned(xs, ys)
    assert fit["name"] is None
    assert fit.get("rms") in (None,) or fit["rms"] is None


def test_aligned_fit_accepts_smooth_curve():
    """A well-sampled smooth easeOutCubic still fits (guard doesn't over-reject)."""
    from _flipbook import fit_easing_aligned, _bez_y_progress
    x1, y1, x2, y2 = 0.33, 1.0, 0.68, 1.0  # css easeOutCubic
    n, t0, D = 24, 0.1, 0.8
    xs = [i / (n - 1) for i in range(n)]
    ys = [_bez_y_progress(min(1.0, max(0.0, (x - t0) / D)), x1, y1, x2, y2) for x in xs]
    fit = fit_easing_aligned(xs, ys)
    assert fit["nearest"] == "easeOutCubic"


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
