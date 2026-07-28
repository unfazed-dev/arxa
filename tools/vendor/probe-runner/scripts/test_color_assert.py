#!/usr/bin/env python3
"""Unit tests for color_assert.py (ΔE math + sample/assert flow).

Runnable: python3 scripts/test_color_assert.py
No framework — assert-based, mirrors the repo's existing test style
(test_pixdiff_metrics.py). Covers:
  - CIEDE2000 against the Sharma reference test vector (the gold-standard check)
  - the perceptual contract: identical→0, near-colour→small, different→large
  - hex parsing + the full _mean_rgb → ΔE → pass pipeline on a synthetic image
"""
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import color_assert as ca  # noqa: E402


def _approx(a, b, tol=0.01):
    return abs(a - b) <= tol


def test_sharma_reference_vector():
    """The Sharma et al. CIEDE2000 reference test pair must yield 2.0425.
    This is THE correctness anchor — if this passes, the ΔE implementation is right."""
    de = ca._delta_e_2000((50, 2.6772, -79.7751), (50, 0, -82.7485))
    assert _approx(de, 2.0425, 0.01), f"Sharma vector: expected 2.0425, got {de:.4f}"


def test_identical_is_zero():
    de = ca._delta_e_2000(ca._rgb_to_lab(0xD2, 0x52, 0x2B), ca._rgb_to_lab(0xD2, 0x52, 0x2B))
    assert _approx(de, 0.0, 0.001), f"identical colours must be ΔE≈0, got {de:.4f}"


def test_near_colour_small():
    """A small RGB perturbation must read as 'same colour' (ΔE < 5)."""
    de = ca._delta_e_2000(ca._rgb_to_lab(0xD2, 0x52, 0x2B), ca._rgb_to_lab(0xD4, 0x55, 0x30))
    assert de < 5.0, f"near-accent should be ΔE<5, got {de:.2f}"


def test_distinct_colour_large():
    """Accent vs bone-3 must read as 'clearly different' (ΔE > 20)."""
    de = ca._delta_e_2000(ca._rgb_to_lab(0xD2, 0x52, 0x2B), ca._rgb_to_lab(0xDD, 0xD3, 0xC0))
    assert de > 20.0, f"accent vs bone3 should be ΔE>20, got {de:.2f}"


def test_hex_parse():
    assert ca._hex_to_rgb("D2522B") == (0xD2, 0x52, 0x2B)
    assert ca._hex_to_rgb("#D2522B") == (0xD2, 0x52, 0x2B)
    assert ca._hex_to_rgb("#abc") == (0xAA, 0xBB, 0xCC)  # 3-digit form


def test_mean_rgb_flat_fill():
    """_mean_rgb over a flat-colour PNG returns that colour (the centroid of a flat
    fill IS the token colour — this is the invariant the whole probe relies on)."""
    try:
        from PIL import Image  # noqa: F401
    except ImportError:
        return  # skip gracefully if Pillow not installed
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
        path = f.name
    try:
        Image.new("RGB", (100, 40), (0xD2, 0x52, 0x2B)).save(path)
        mr, mg, mb = ca._mean_rgb(path, (0, 0, 100, 40))
        assert (mr, mg, mb) == (0xD2, 0x52, 0x2B), f"flat fill centroid: got ({mr},{mg},{mb})"
    finally:
        os.unlink(path)


def test_mean_rgb_with_inset():
    """Inset dodges a border ring — the interior mean is the fill, not the border."""
    try:
        from PIL import Image  # noqa: F401
    except ImportError:
        return
    # 100x40 accent fill with a 4px black border
    img = Image.new("RGB", (100, 40), (0xD2, 0x52, 0x2B))
    from PIL import ImageDraw
    ImageDraw.Draw(img).rectangle([0, 0, 99, 39], outline=(0, 0, 0), width=4)
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
        path = f.name
    try:
        img.save(path)
        # without inset: the border drags the mean toward black
        mr0, _, _ = ca._mean_rgb(path, (0, 0, 100, 40), inset=0)
        # with inset 6: the border is excluded → pure accent
        mr6, mg6, mb6 = ca._mean_rgb(path, (0, 0, 100, 40), inset=6)
        assert mr6 > mr0, "inset should exclude the dark border, raising the R mean"
        assert (mr6, mg6, mb6) == (0xD2, 0x52, 0x2B), \
            f"inset mean should be pure accent, got ({mr6},{mg6},{mb6})"
    finally:
        os.unlink(path)


def _run():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    passed = 0
    for t in tests:
        try:
            t()
            print(f"PASS {t.__name__}")
            passed += 1
        except AssertionError as e:
            print(f"FAIL {t.__name__}: {e}")
            return 1
    print(f"\nALL GREEN ({passed}/{len(tests)} checks)")
    return 0


if __name__ == "__main__":
    sys.exit(_run())
