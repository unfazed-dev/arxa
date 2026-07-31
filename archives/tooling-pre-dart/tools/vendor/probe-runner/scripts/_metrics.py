#!/usr/bin/env python3
"""Image-difference metrics for probe-runner (pure numpy + Pillow).

Shared by `pixdiff.py`.
Three metrics, all normalised so that **0 = identical** and larger = more
different (so `above_threshold = score > T` means the same thing for each):

  - `mean`:  mean per-channel RGB difference / 255 (the original pixdiff score).
             Fast, intuitive, but the MOST flaky under anti-aliasing / sub-pixel
             font rendering (a 1px sub-pixel shift flips many pixels).
  - `ssim`:  windowed Structural Similarity Index. SSIM is 1 = identical, so we
             return `1 - mean_ssim` (0 = identical) to keep the contract above.
             Materially more robust to anti-aliasing / font-rendering shifts
             because it compares local structure, not raw pixels.
  - `odiff`: shelled out to the `odiff` binary in pixdiff.py (NOT here — this
             module is the pure-Python path). Listed for symmetry.

SSIM reference (the canonical algorithm): Wang et al. 2004. The numpy impl here
follows the public-domain windowed form documented at
https://cvnote.ddlee.cc/2019/09/12/PSNR-SSIM-Python.html and
https://github.com/mubeta06/python — no scipy/scikit-image dependency (numpy
only, which probe-runner already pulls in via _flipbook).
"""
from __future__ import annotations

from typing import Any, Optional, Tuple

import numpy as np
from PIL import Image

# The default SSIM window: 11x11 Gaussian (Wang et al. sigma=1.5), per the
# canonical reference. A uniform 7x7/11x11 window is the common simplification;
# we use Gaussian for fidelity to the paper but keep it small (no scipy needed).
_SSIM_WIN = 11
_SSIM_SIGMA = 1.5
# SSIM stabiliser constants. C1=(K1*L)^2, C2=(K2*L)^2 with L=255 (8-bit), K1=0.01,
# K2=0.03 — the standard values from the paper. These prevent division-by-zero
# on flat regions and set the numerical scale.
_C1 = (0.01 * 255) ** 2
_C2 = (0.03 * 255) ** 2


def _gaussian_window(size: int = _SSIM_WIN, sigma: float = _SSIM_SIGMA) -> np.ndarray:
    """A 2D Gaussian window (normalised to sum=1), no scipy."""
    ax = np.arange(size) - (size - 1) / 2.0
    g1 = np.exp(-(ax ** 2) / (2.0 * sigma ** 2))
    g1 /= g1.sum()
    w = np.outer(g1, g1)
    return w / w.sum()


def _to_luma(arr_rgb: np.ndarray) -> np.ndarray:
    """RGB (H,W,3) float -> luma (H,W) float via Rec.601 weights."""
    return (0.299 * arr_rgb[..., 0] + 0.587 * arr_rgb[..., 1] + 0.114 * arr_rgb[..., 2])


def _conv2d_same(img: np.ndarray, kernel: np.ndarray) -> np.ndarray:
    """2D 'same'-size convolution via zero-padded numpy sliding-window sum.

    No scipy. Uses stride tricks for a single efficient pass; falls back to a
    simple pad+loop if stride tricks are unavailable. `img` is 2D float."""
    kh, kw = kernel.shape
    ph, pw = kh // 2, kw // 2
    padded = np.pad(img, ((ph, ph), (pw, pw)), mode="edge")
    try:
        from numpy.lib.stride_tricks import sliding_window_view
        windows = sliding_window_view(padded, (kh, kw))
        return (windows * kernel).sum(axis=(-2, -1))
    except (ImportError, AttributeError):
        out = np.zeros_like(img, dtype=np.float64)
        for i in range(kh):
            for j in range(kw):
                out += kernel[i, j] * padded[i:i + img.shape[0], j:j + img.shape[1]]
        return out


def ssim_map(a_rgb: np.ndarray, b_rgb: np.ndarray) -> np.ndarray:
    """Per-pixel SSIM index (1 = identical) between two RGB uint8/float arrays.

    Computes the SSIM structural-similarity map on the luma channel, per Wang
    et al. Returns an HxW float array in [−1, 1] (1 = identical structure).
    Both inputs must be the same shape."""
    a = _to_luma(a_rgb.astype(np.float64))
    b = _to_luma(b_rgb.astype(np.float64))
    w = _gaussian_window()
    mu_a = _conv2d_same(a, w)
    mu_b = _conv2d_same(b, w)
    mu_a2, mu_b2, mu_ab = mu_a * mu_a, mu_b * mu_b, mu_a * mu_b
    sig_a2 = _conv2d_same(a * a, w) - mu_a2
    sig_b2 = _conv2d_same(b * b, w) - mu_b2
    sig_ab = _conv2d_same(a * b, w) - mu_ab
    num = (2 * mu_ab + _C1) * (2 * sig_ab + _C2)
    den = (mu_a2 + mu_b2 + _C1) * (sig_a2 + sig_b2 + _C2)
    return num / den


def ssim_score(a: Image.Image, b: Image.Image) -> float:
    """Mean structural dissimilarity score in [0, 2]: **0 = identical**.

    Returns `1 - mean(SSIM)` (SSIM's 1=identical inverted to the probe-runner
    convention where 0=identical, larger=more different), so this composes with
    `above_threshold = score > T` exactly like the mean-RGB metric."""
    a3 = np.asarray(a.convert("RGB"))
    b3 = np.asarray(b.convert("RGB"))
    if a3.shape != b3.shape:
        raise ValueError(f"size mismatch: {a3.shape} vs {b3.shape}")
    m = ssim_map(a3, b3)
    # clip the theoretical −1 floor so the score stays non-negative for the
    # common (identical-ish) case; rare anti-correlated noise can push past 1.
    return float(max(0.0, 1.0 - float(m.mean())))


def mean_score(a: Image.Image, b: Image.Image) -> Tuple[float, list[float]]:
    """Mean per-channel RGB difference / 255 in [0, 1]: **0 = identical**.

    The original pixdiff score, preserved verbatim for back-compat. Returns
    (score, mean_rgb) where mean_rgb is the per-channel mean diff list."""
    from PIL import ImageChops, ImageStat
    if a.size != b.size:
        raise ValueError(f"size mismatch: {a.size} vs {b.size}")
    diff = ImageChops.difference(a.convert("RGB"), b.convert("RGB"))
    stat = ImageStat.Stat(diff)
    mean = sum(stat.mean) / len(stat.mean)
    return (mean / 255.0, list(stat.mean))


# ─── odiff shell-out (called by pixdiff.py, kept here for locality of docs) ───

def odiff_available() -> Optional[str]:
    """Return the odiff binary path if on PATH, else None. Pure detection."""
    import shutil
    return shutil.which("odiff")


def odiff_run(a_path: str, b_path: str, *, threshold: float = 0.0,
              antialiasing: bool = False,
              out_diff: Optional[str] = None) -> dict[str, Any]:
    """Run the odiff binary on two image files, parse its JSON, return a score
    dict. Raises FileNotFoundError if odiff is not on PATH.

    odiff's `--threshold` is a 0..1 fraction of pixels allowed to differ; we
    surface `diffPercentage`/100 as the score (0 = identical). The `match`
    boolean and diff pixel count are passed through for auditability. When
    `out_diff` is given, it is passed as odiff's 3rd positional so odiff writes
    the diff image itself."""
    import json
    import subprocess
    bin_path = odiff_available()
    if not bin_path:
        raise FileNotFoundError(
            "odiff binary not found on PATH. Install: `npm i -g odiff-bin` "
            "(prebuilt) or download a release binary from "
            "https://github.com/dmtrKovalenko/odiff")
    cmd = [bin_path, a_path, b_path]
    if out_diff:
        cmd.append(str(out_diff))
    if antialiasing:
        cmd.append("--antialiasing")
    # odiff emits JSON when its stderr/stdout is parsed; the modern binary
    # prints `{"match":...,"reason":...,"diffCount":...,"diffPercentage":...}`.
    r = subprocess.run(cmd, capture_output=True, text=True)
    out = (r.stdout or "").strip()
    # odiff's JSON may be the trailing JSON object on stdout; parse defensively.
    try:
        start = out.rfind("{")
        parsed = json.loads(out[start:]) if start >= 0 else {}
    except json.JSONDecodeError:
        parsed = {}
    diff_pct = parsed.get("diffPercentage")
    score = float(diff_pct) / 100.0 if diff_pct is not None else (0.0 if parsed.get("match") else 1.0)
    return {
        "score": score,
        "match": parsed.get("match"),
        "diff_count": parsed.get("diffCount"),
        "diff_percentage": diff_pct,
        "reason": parsed.get("reason"),
        "rc": r.returncode,
    }
