#!/usr/bin/env python3
"""Unit tests for color_assert.py's _shot delegation + the main() die path.

Runnable: python3 test_color_assert_delegate.py
No framework — assert-based, mirrors test_color_assert.py's style. Offline:
subprocess.run / ca._shot are stubbed; no devices, no VM.

Covers the swallowed-stderr bug class: a failing delegated shot child must
reach the operator via die()'s message instead of a bare 'could not capture'.
"""
import contextlib
import io
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import color_assert as ca  # noqa: E402


def _cp(rc, stdout="", stderr=""):
    return subprocess.CompletedProcess(args=["fake"], returncode=rc, stdout=stdout, stderr=stderr)


def _stub_run(fn):
    orig = subprocess.run
    subprocess.run = fn
    return lambda: setattr(subprocess, "run", orig)


# ─── _shot: stderr propagation on failure ─────────────────────────────────────

def test_shot_success_returns_path_and_no_error():
    restore = _stub_run(lambda *a, **k: _cp(0, stdout="/tmp/probe-runner/s.png\n", stderr=""))
    try:
        path, err = ca._shot("adb", "/tmp")
    finally:
        restore()
    assert path == "/tmp/probe-runner/s.png", f"path: {path}"
    assert err is None, f"err: {err}"


def test_shot_failure_propagates_child_stderr():
    """The bug: rc!=0 used to return bare None → die('could not capture…'), no reason."""
    restore = _stub_run(lambda *a, **k: _cp(1, stdout="", stderr="error: no devices/emulators found"))
    try:
        path, err = ca._shot("adb", "/tmp")
    finally:
        restore()
    assert path is None
    assert err is not None and "no devices/emulators found" in err, f"stderr swallowed: {err!r}"
    assert "rc=1" in err, f"rc missing: {err!r}"


def test_shot_spawn_failure_reports_exception():
    def boom(*a, **k):
        raise subprocess.TimeoutExpired(cmd="adb_shot.py", timeout=30)
    restore = _stub_run(boom)
    try:
        path, err = ca._shot("adb", "/tmp")
    finally:
        restore()
    assert path is None
    assert err is not None and "timed out" in err, f"timeout swallowed: {err!r}"


# ─── main(): the die message carries the child's reason ───────────────────────

def test_main_die_message_contains_shot_error():
    """--target with a failing shot must die(2) naming the child's stderr."""
    orig_shot, orig_argv = ca._shot, sys.argv
    ca._shot = lambda target, outdir: (None, "adb_shot.py rc=1: error: no devices/emulators found")
    sys.argv = ["color_assert.py", "--target", "adb", "--hex", "D2522B"]
    buf = io.StringIO()
    code = None
    try:
        with contextlib.redirect_stderr(buf):
            try:
                ca.main()
            except SystemExit as e:
                code = e.code
    finally:
        ca._shot, sys.argv = orig_shot, orig_argv
    assert code == 2, f"expected die() exit 2, got {code}"
    msg = buf.getvalue()
    assert "no devices/emulators found" in msg, f"child stderr missing from die: {msg!r}"
    assert "could not capture" in msg, f"lost the framing: {msg!r}"


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
