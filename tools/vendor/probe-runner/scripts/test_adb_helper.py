#!/usr/bin/env python3
"""Unit tests for _adb.py's failure-path remediation.

Runnable: python3 test_adb_helper.py
No framework — assert-based, mirrors test_color_assert.py's style. Offline:
subprocess.run and adb_bin are stubbed; no emulator needed.

_covers the 'unactionable death message' bug class: when an adb verb fails,
the printed message must name the next concrete action (adb_boot.py /
PROBE_RUNNER_ADB_SERIAL / adb reconnect), not just '(device/emulator booted?)'.
"""
import contextlib
import io
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _adb  # noqa: E402


def _cp(rc, stdout=b"", stderr=b""):
    return subprocess.CompletedProcess(args=["fake"], returncode=rc, stdout=stdout, stderr=stderr)


def _stub(run_fn):
    """Swap subprocess.run + adb_bin; return a restore closure."""
    orig_run, orig_bin = subprocess.run, _adb.adb_bin
    subprocess.run = run_fn
    _adb.adb_bin = lambda: "/fake/adb"
    def restore():
        subprocess.run = orig_run
        _adb.adb_bin = orig_bin
    return restore


# ─── _remedy mapping ──────────────────────────────────────────────────────────

def test_remedy_no_devices_points_at_adb_boot():
    r = _adb._remedy("error: no devices/emulators found")
    assert "adb_boot.py" in r, f"remedy: {r!r}"


def test_remedy_multiple_devices_points_at_serial_env():
    r = _adb._remedy("error: more than one device/emulator")
    assert "PROBE_RUNNER_ADB_SERIAL" in r, f"remedy: {r!r}"


def test_remedy_offline_points_at_reconnect():
    r = _adb._remedy("error: device offline")
    assert "adb reconnect" in r, f"remedy: {r!r}"


def test_remedy_device_not_found_points_at_devices_list():
    r = _adb._remedy("error: device 'emulator-5554' not found")
    assert "adb devices" in r, f"remedy: {r!r}"


def test_remedy_fallback_is_actionable():
    r = _adb._remedy("adb shell 'input tap 1 2' failed rc=1")
    assert "adb_boot.py" in r and "adb devices" in r, f"remedy: {r!r}"


# ─── adb_cmd failure path: adb stderr + remedy both printed ──────────────────

def test_adb_cmd_failure_prints_stderr_and_remedy():
    restore = _stub(lambda *a, **k: _cp(1, stderr=b"error: no devices/emulators found\n"))
    buf = io.StringIO()
    code = None
    try:
        with contextlib.redirect_stderr(buf):
            try:
                _adb.adb_cmd(["shell", "true"], capture=True)
            except SystemExit as e:
                code = e.code
    finally:
        restore()
    msg = buf.getvalue()
    assert code == 1, f"exit code: {code}"
    assert "no devices/emulators found" in msg, f"adb stderr lost: {msg!r}"
    assert "adb_boot.py" in msg, f"remedy missing: {msg!r}"


def test_adb_cmd_failure_multidevice_names_serial_env():
    restore = _stub(lambda *a, **k: _cp(1, stderr=b"error: more than one device/emulator\n"))
    buf = io.StringIO()
    try:
        with contextlib.redirect_stderr(buf):
            try:
                _adb.adb_cmd(["shell", "true"], capture=True)
            except SystemExit:
                pass
    finally:
        restore()
    assert "PROBE_RUNNER_ADB_SERIAL" in buf.getvalue(), f"msg: {buf.getvalue()!r}"


def test_adb_cmd_success_returns_completed_process():
    restore = _stub(lambda *a, **k: _cp(0, stdout=b"ok"))
    try:
        r = _adb.adb_cmd(["shell", "true"], capture=True)
    finally:
        restore()
    assert r.returncode == 0 and r.stdout == b"ok"


# ─── adb_shell failure path ───────────────────────────────────────────────────

def test_adb_shell_failure_prints_remedy():
    restore = _stub(lambda *a, **k: subprocess.CompletedProcess(
        args=["fake"], returncode=1, stdout="", stderr="error: device offline"))
    buf = io.StringIO()
    code = None
    try:
        with contextlib.redirect_stderr(buf):
            try:
                _adb.adb_shell("input tap 1 2")
            except SystemExit as e:
                code = e.code
    finally:
        restore()
    msg = buf.getvalue()
    assert code == 1, f"exit code: {code}"
    assert "device offline" in msg and "adb reconnect" in msg, f"msg: {msg!r}"


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
