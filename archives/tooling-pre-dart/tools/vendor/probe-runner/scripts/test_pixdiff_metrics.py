#!/usr/bin/env python3
"""Tests for _metrics.py (SSIM/mean) and pixdiff.py engine routing.

Hermetic: synthetic PIL images, no device/network. odiff is mocked (the binary
is opt-in and not installed in CI). Covers the reproducibility invariant —
every metric emits engine+metric — and the SSIM>mean robustness claim
(anti-aliasing-ish shifts score high under mean but low under SSIM).
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np
from PIL import Image

import _metrics as M


# ─── helpers ──────────────────────────────────────────────────────────────────

def _solid(w, h, rgb):
    return Image.new("RGB", (w, h), rgb)


def _noise(w, h, seed=0):
    rng = np.random.RandomState(seed)
    return Image.fromarray(rng.randint(0, 255, (h, w, 3), dtype=np.uint8))


def _shifted_by_one(img):
    """A 1px horizontal sub-pixel-ish shift: duplicate the leftmost column,
    simulating the anti-aliasing/font-rendering shift that raw-pixel diff flags
    but SSIM tolerates."""
    arr = np.asarray(img)
    shifted = np.empty_like(arr)
    shifted[:, 1:] = arr[:, :-1]
    shifted[:, 0] = arr[:, 0]
    return Image.fromarray(shifted)


# ─── mean_score ───────────────────────────────────────────────────────────────

def test_mean_identical_is_zero():
    a = _solid(32, 32, (100, 150, 200))
    score, mean_rgb = M.mean_score(a, a)
    assert score == 0.0, score
    assert all(m == 0.0 for m in mean_rgb)


def test_mean_uniform_shift_is_proportional():
    a = _solid(32, 32, (0, 0, 0))
    b = _solid(32, 32, (255, 255, 255))   # full swing
    score, _ = M.mean_score(a, b)
    assert abs(score - 1.0) < 1e-9, score


def test_mean_size_mismatch_raises():
    import pytest
    with pytest.raises(ValueError):
        M.mean_score(_solid(10, 10, (0, 0, 0)), _solid(12, 12, (0, 0, 0)))


# ─── ssim_score ───────────────────────────────────────────────────────────────

def test_ssim_identical_is_zero():
    """The contract: 0 = identical (inverted from raw SSIM's 1=identical)."""
    a = _solid(48, 48, (100, 150, 200))
    assert M.ssim_score(a, a) == 0.0, M.ssim_score(a, a)


def test_ssim_large_change_is_high():
    """Completely different images score high (toward 1)."""
    a = _solid(48, 48, (0, 0, 0))
    b = _solid(48, 48, (255, 255, 255))
    score = M.ssim_score(a, b)
    assert score > 0.5, score   # a strong structural difference


def test_ssim_size_mismatch_raises():
    import pytest
    with pytest.raises(ValueError):
        M.ssim_score(_solid(10, 10, (0, 0, 0)), _solid(12, 12, (0, 0, 0)))


def test_ssim_tolerates_structured_shift_better_than_mean():
    """The core robustness claim: a 1px shift of a STRUCTURED image (a gradient
    / solid block edge, the kind of thing anti-aliasing/font-rendering produces)
    flips many raw pixels (mean flags it) but preserves structure (SSIM scores
    it low). Random noise has no structure to preserve, so this uses a gradient."""
    # a horizontal gradient: shifting by 1px moves every pixel's value, but the
    # local structure (the gradient) is preserved — exactly the anti-aliasing case.
    arr = np.tile(np.linspace(0, 255, 128, dtype=np.uint8), (64, 1))
    base = Image.fromarray(np.repeat(arr[..., None], 3, axis=2))
    shifted = _shifted_by_one(base)
    mean_score, _ = M.mean_score(base, shifted)
    ssim = M.ssim_score(base, shifted)
    # mean sees real per-pixel change; ssim is markedly lower (more tolerant)
    assert mean_score > ssim, (mean_score, ssim)
    assert ssim < 0.2, ssim


def test_ssim_noise_scores_moderate():
    """Two different-noise images: both metrics flag it, ssim not at the floor."""
    a = _noise(64, 64, seed=1)
    b = _noise(64, 64, seed=2)
    ssim = M.ssim_score(a, b)
    assert 0.2 < ssim < 1.0, ssim   # clearly different, not a degenerate floor


def test_ssim_window_constants():
    """Sanity: the SSIM stabilisers are the canonical Wang values."""
    assert M._C1 == (0.01 * 255) ** 2
    assert M._C2 == (0.03 * 255) ** 2


def test_gaussian_window_sums_to_one():
    w = M._gaussian_window()
    assert w.shape == (M._SSIM_WIN, M._SSIM_WIN)
    assert abs(float(w.sum()) - 1.0) < 1e-9


# ─── odiff detection / parsing (binary mocked) ────────────────────────────────

def test_odiff_available_returns_none_when_absent(monkeypatch):
    monkeypatch.setattr(M, "odiff_available", lambda: None)
    import pytest
    with pytest.raises(FileNotFoundError):
        M.odiff_run("/a.png", "/b.png")


def test_odiff_run_parses_json(monkeypatch):
    """Mock the subprocess call; confirm diffPercentage->score normalization."""
    class _Fake:
        stdout = '{"match": false, "reason": "pixel diff", "diffCount": 1200, "diffPercentage": 1.07}'
        returncode = 1
    monkeypatch.setattr(M, "odiff_available", lambda: "/usr/local/bin/odiff")
    monkeypatch.setattr("subprocess.run", lambda *a, **k: _Fake())
    res = M.odiff_run("/a.png", "/b.png", antialiasing=True)
    assert abs(res["score"] - 0.0107) < 1e-9, res["score"]   # /100
    assert res["match"] is False
    assert res["diff_count"] == 1200
    assert res["diff_percentage"] == 1.07


def test_odiff_run_match_is_zero(monkeypatch):
    class _Fake:
        stdout = '{"match": true, "reason": "pixels match", "diffCount": 0, "diffPercentage": 0}'
        returncode = 0
    monkeypatch.setattr(M, "odiff_available", lambda: "/usr/local/bin/odiff")
    monkeypatch.setattr("subprocess.run", lambda *a, **k: _Fake())
    res = M.odiff_run("/a.png", "/b.png")
    assert res["score"] == 0.0


# ─── pixdiff.py CLI engine routing (in-process, stdout captured) ──────────────

def _run_pixdiff(tmp_path, engine, a_img, b_img, extra=None):
    """Run pixdiff.main() with argv set, capture its emit_json stdout."""
    import io
    from contextlib import redirect_stdout
    import pixdiff
    a = tmp_path / "a.png"; a_img.save(a)
    b = tmp_path / "b.png"; b_img.save(b)
    argv = ["pixdiff.py", str(a), str(b), "--engine", engine] + (extra or [])
    old = sys.argv
    sys.argv = argv
    buf = io.StringIO()
    try:
        with redirect_stdout(buf):
            rc = pixdiff.main()
    finally:
        sys.argv = old
    return rc, json.loads(buf.getvalue())


def test_pixdiff_default_engine_is_ssim(tmp_path):
    """No --engine -> ssim (the reproducibility-friendly default)."""
    a = _solid(40, 40, (10, 20, 30))
    rc, out = _run_pixdiff(tmp_path, "ssim", a, a)
    assert rc == 0
    assert out["engine"] == "ssim" and out["metric"] == "ssim"
    assert out["score"] == 0.0
    assert out["above_threshold"] is False    # 0.0 > 0.0 is False (strict)


def test_pixdiff_mean_backcompat(tmp_path):
    a = _solid(40, 40, (0, 0, 0))
    b = _solid(40, 40, (255, 255, 255))
    rc, out = _run_pixdiff(tmp_path, "mean", a, b)
    assert out["engine"] == "mean" and out["metric"] == "mean-rgb"
    assert abs(out["score"] - 1.0) < 1e-9
    assert out["mean_rgb"] is not None       # back-compat field preserved


def test_pixdiff_engine_field_always_present(tmp_path):
    """The reproducibility invariant: every run self-reports its engine+metric."""
    a = _solid(20, 20, (50, 50, 50))
    for engine, expect_metric in (("ssim", "ssim"), ("mean", "mean-rgb")):
        rc, out = _run_pixdiff(tmp_path, engine, a, a)
        assert "engine" in out and "metric" in out, out
        assert out["engine"] == engine and out["metric"] == expect_metric


def test_pixdiff_threshold_strict_greater(tmp_path):
    """above_threshold is strict > (score==threshold -> False)."""
    a = _solid(20, 20, (0, 0, 0))
    b = _solid(20, 20, (0, 0, 0))
    # identical -> score 0.0; threshold 0.0 -> 0.0 > 0.0 is False
    rc, out = _run_pixdiff(tmp_path, "ssim", a, b, extra=["--threshold", "0.0"])
    assert out["score"] == 0.0 and out["above_threshold"] is False


def test_pixdiff_region_works_for_ssim(tmp_path):
    a = _solid(60, 60, (0, 0, 0))
    b = _solid(60, 60, (0, 0, 0))
    rc, out = _run_pixdiff(tmp_path, "ssim", a, b, extra=["--region", "10,10,40,40"])
    assert rc == 0 and out["score"] == 0.0
    assert out["region"] == {"x": 10, "y": 10, "w": 40, "h": 40}


def test_pixdiff_region_with_odiff_rejected(monkeypatch, tmp_path):
    """--region + --engine odiff is unsupported (odiff reads files); clear die."""
    import pixdiff
    a = tmp_path / "a.png"; _solid(40, 40, (0, 0, 0)).save(a)
    b = tmp_path / "b.png"; _solid(40, 40, (0, 0, 0)).save(b)
    monkeypatch.setattr(M, "odiff_available", lambda: "/usr/local/bin/odiff")  # so it reaches the region check
    argv = ["pixdiff.py", str(a), str(b), "--engine", "odiff", "--region", "0,0,10,10"]
    old = sys.argv; sys.argv = argv
    try:
        import pytest
        with pytest.raises(SystemExit):
            pixdiff.main()
    finally:
        sys.argv = old


def test_pixdiff_odiff_missing_fails_fast(monkeypatch, tmp_path):
    """odiff requested but not on PATH -> die with install hint (rc=2)."""
    import pixdiff
    monkeypatch.setattr(M, "odiff_available", lambda: None)
    a = tmp_path / "a.png"; _solid(10, 10, (0, 0, 0)).save(a)
    b = tmp_path / "b.png"; _solid(10, 10, (0, 0, 0)).save(b)
    argv = ["pixdiff.py", str(a), str(b), "--engine", "odiff"]
    old = sys.argv; sys.argv = argv
    try:
        import pytest
        with pytest.raises(SystemExit) as ei:
            pixdiff.main()
        assert ei.value.code == 2
    finally:
        sys.argv = old
