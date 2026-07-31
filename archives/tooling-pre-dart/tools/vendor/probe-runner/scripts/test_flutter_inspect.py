#!/usr/bin/env python3
"""Unit tests for flutter_inspect.py's delegation error propagation.

Runnable: python3 test_flutter_inspect.py
No framework — assert-based, mirrors test_color_assert.py's style. Offline:
subprocess.run is stubbed; no devices, no VM.

Covers the swallowed-stderr bug class: a failing delegated child
(ios_shot/adb_shot/pixdiff) must surface its stderr in the JSON payload
(`screenshot_error` / pixdiff {"error": ...}) instead of a bare null.
"""
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import flutter_inspect as fi  # noqa: E402


def _cp(rc, stdout="", stderr=""):
    return subprocess.CompletedProcess(args=["fake"], returncode=rc, stdout=stdout, stderr=stderr)


def _stub_run(fn):
    """Swap subprocess.run for fn; return a restore closure."""
    orig = subprocess.run
    subprocess.run = fn
    return lambda: setattr(subprocess, "run", orig)


# ─── _shot: stderr propagation on failure ─────────────────────────────────────

def test_shot_success_returns_path_and_no_error():
    restore = _stub_run(lambda *a, **k: _cp(0, stdout="", stderr='{"shot": "/tmp/x/shot-1.png"}'))
    try:
        path, err = fi._shot("ios", "/tmp")
    finally:
        restore()
    assert path == "/tmp/x/shot-1.png", f"path: {path}"
    assert err is None, f"err: {err}"


def test_shot_failure_propagates_child_stderr():
    """The bug: rc!=0 used to return bare None → `screenshot: null`, no reason."""
    restore = _stub_run(lambda *a, **k: _cp(1, stdout="", stderr="probe-runner: no booted simulator"))
    try:
        path, err = fi._shot("ios", "/tmp")
    finally:
        restore()
    assert path is None
    assert err is not None and "no booted simulator" in err, f"stderr swallowed: {err!r}"
    assert "rc=1" in err, f"rc missing: {err!r}"


def test_shot_failure_falls_back_to_stdout_when_stderr_empty():
    restore = _stub_run(lambda *a, **k: _cp(1, stdout="idb: target not found", stderr=""))
    try:
        path, err = fi._shot("ios", "/tmp")
    finally:
        restore()
    assert path is None
    assert "target not found" in err, f"stdout fallback missing: {err!r}"


def test_shot_spawn_failure_reports_exception():
    def boom(*a, **k):
        raise subprocess.TimeoutExpired(cmd="ios_shot.py", timeout=30)
    restore = _stub_run(boom)
    try:
        path, err = fi._shot("ios", "/tmp")
    finally:
        restore()
    assert path is None
    assert err is not None and "timed out" in err, f"timeout swallowed: {err!r}"


def test_shot_rc0_without_png_path_is_an_error_not_silent_none():
    restore = _stub_run(lambda *a, **k: _cp(0, stdout="everything is fine", stderr=""))
    try:
        path, err = fi._shot("adb", "/tmp")
    finally:
        restore()
    assert path is None
    assert err is not None and "no .png path" in err, f"err: {err!r}"


# ─── _pixdiff: error dict on failure ──────────────────────────────────────────

def test_pixdiff_failure_propagates_stderr():
    restore = _stub_run(lambda *a, **k: _cp(2, stdout="", stderr="cannot open golden.png"))
    try:
        out = fi._pixdiff("a.png", "b.png")
    finally:
        restore()
    assert out == {"error": "cannot open golden.png"}, f"out: {out}"


def test_pixdiff_failure_without_stderr_mentions_rc():
    restore = _stub_run(lambda *a, **k: _cp(2, stdout="", stderr=""))
    try:
        out = fi._pixdiff("a.png", "b.png")
    finally:
        restore()
    assert "rc=2" in out["error"], f"out: {out}"


def test_pixdiff_timeout_is_an_error_not_none():
    """A pixdiff timeout used to surface as a silent `pixdiff: null`."""
    def boom(*a, **k):
        raise subprocess.TimeoutExpired(cmd="pixdiff.py", timeout=60)
    restore = _stub_run(boom)
    try:
        out = fi._pixdiff("a.png", "b.png")
    finally:
        restore()
    assert out is not None and "timed out" in out["error"], f"out: {out}"


def test_pixdiff_success_parses_json():
    restore = _stub_run(lambda *a, **k: _cp(0, stdout='{"ssim": 0.99}', stderr=""))
    try:
        out = fi._pixdiff("a.png", "b.png")
    finally:
        restore()
    assert out == {"ssim": 0.99}, f"out: {out}"


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
