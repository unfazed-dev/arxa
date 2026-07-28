#!/usr/bin/env python3
"""Tests for _platform.py — host detection + capability layer.

Hermetic: mocks platform.system(), sw_vers, and PATH lookups so detection is
testable without actually changing OS. Confirms macOS routes through, and
Linux/Windows desktop capture/input raise a clear NotImplementedError (not a
raw ImportError crash).
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pytest

import _platform as P


@pytest.fixture(autouse=True)
def _reset_caches():
    """Each test gets fresh lru_cache state (detection is cached per-call)."""
    P.os_name.cache_clear()
    P.macos_version.cache_clear()
    yield
    P.os_name.cache_clear()
    P.macos_version.cache_clear()


# ─── os_name ──────────────────────────────────────────────────────────────────

def test_os_name_macos(monkeypatch):
    monkeypatch.setattr("platform.system", lambda: "Darwin")
    assert P.os_name() == "macos"


def test_os_name_windows(monkeypatch):
    monkeypatch.setattr("platform.system", lambda: "Windows")
    assert P.os_name() == "windows"


def test_os_name_linux(monkeypatch):
    monkeypatch.setattr("platform.system", lambda: "Linux")
    assert P.os_name() == "linux"


def test_os_name_cached(monkeypatch):
    monkeypatch.setattr("platform.system", lambda: "Darwin")
    assert P.os_name() == "macos"
    # change the underlying value — cache holds
    monkeypatch.setattr("platform.system", lambda: "Linux")
    assert P.os_name() == "macos"
    P.os_name.cache_clear()
    assert P.os_name() == "linux"


# ─── macos_version ────────────────────────────────────────────────────────────

def test_macos_version_parses(monkeypatch):
    monkeypatch.setattr("platform.system", lambda: "Darwin")
    monkeypatch.setattr("subprocess.run",
                        lambda *a, **k: _fake_stdout("14.5\n"))
    assert P.macos_version() == (14, 5)


def test_macos_version_major_only(monkeypatch):
    monkeypatch.setattr("platform.system", lambda: "Darwin")
    monkeypatch.setattr("subprocess.run",
                        lambda *a, **k: _fake_stdout("15\n"))
    assert P.macos_version() == (15, 0)


def test_macos_version_none_off_mac(monkeypatch):
    monkeypatch.setattr("platform.system", lambda: "Linux")
    assert P.macos_version() is None


def test_macos_version_garbage(monkeypatch):
    monkeypatch.setattr("platform.system", lambda: "Darwin")
    monkeypatch.setattr("subprocess.run",
                        lambda *a, **k: _fake_stdout("garbage\n"))
    assert P.macos_version() is None


# ─── has_screencapturekit ─────────────────────────────────────────────────────

def test_sck_unavailable_below_12_3(monkeypatch):
    # macOS 12.2 < 12.3 → the version gate (checked before any import attempt)
    # fails. Run the REAL function; do NOT monkeypatch it (that would make the
    # assertion tautological). The gate at _platform.py:72 short-circuits False.
    monkeypatch.setattr("platform.system", lambda: "Darwin")
    P.macos_version.cache_clear()
    monkeypatch.setattr("subprocess.run", lambda *a, **k: _fake_stdout("12.2\n"))
    assert P.has_screencapturekit() is False


def test_sck_available_on_12_3_with_binding(monkeypatch):
    monkeypatch.setattr("platform.system", lambda: "Darwin")
    monkeypatch.setattr("subprocess.run", lambda *a, **k: _fake_stdout("14.0\n"))
    # stub the import check to True (the real binding may be absent in CI)
    import builtins
    real_import = builtins.__import__

    def fake_import(name, *a, **k):
        if name == "ScreenCaptureKit":
            class _Stub:
                pass
            return _Stub()
        return real_import(name, *a, **k)
    monkeypatch.setattr(builtins, "__import__", fake_import)
    assert P.has_screencapturekit() is True


def test_sck_unavailable_without_binding(monkeypatch):
    monkeypatch.setattr("platform.system", lambda: "Darwin")
    monkeypatch.setattr("subprocess.run", lambda *a, **k: _fake_stdout("14.0\n"))
    import builtins
    real_import = builtins.__import__

    def fake_import(name, *a, **k):
        if name == "ScreenCaptureKit":
            raise ImportError("no binding")
        return real_import(name, *a, **k)
    monkeypatch.setattr(builtins, "__import__", fake_import)
    assert P.has_screencapturekit() is False


def test_sck_unavailable_off_mac(monkeypatch):
    monkeypatch.setattr("platform.system", lambda: "Linux")
    assert P.has_screencapturekit() is False


# ─── has_cliclick (the only PATH probe probe-runner gates on) ────────────────

def test_has_cliclick(monkeypatch):
    monkeypatch.setattr("shutil.which", lambda b: "/usr/local/bin/cliclick" if b == "cliclick" else None)
    assert P.has_cliclick() is True
    monkeypatch.setattr("shutil.which", lambda b: None)
    assert P.has_cliclick() is False


# ─── assert_desktop_capture / assert_desktop_input ───────────────────────────

def test_assert_desktop_capture_ok_on_mac(monkeypatch):
    monkeypatch.setattr("platform.system", lambda: "Darwin")
    P.os_name.cache_clear()
    P.assert_desktop_capture("shot")  # must not raise


def test_assert_desktop_capture_raises_on_linux(monkeypatch):
    monkeypatch.setattr("platform.system", lambda: "Linux")
    P.os_name.cache_clear()
    with pytest.raises(NotImplementedError) as ei:
        P.assert_desktop_capture("shot")
    assert "macOS-only" in str(ei.value)
    assert "PipeWire" in str(ei.value) or "xdg-desktop-portal" in str(ei.value)


def test_assert_desktop_capture_raises_on_windows(monkeypatch):
    monkeypatch.setattr("platform.system", lambda: "Windows")
    P.os_name.cache_clear()
    with pytest.raises(NotImplementedError) as ei:
        P.assert_desktop_capture("shot")
    assert "dxcam" in str(ei.value) or "mss" in str(ei.value)


def test_assert_desktop_input_ok_on_mac_with_cliclick(monkeypatch):
    monkeypatch.setattr("platform.system", lambda: "Darwin")
    monkeypatch.setattr("shutil.which", lambda b: "/usr/local/bin/cliclick" if b == "cliclick" else None)
    P.os_name.cache_clear()
    P.assert_desktop_input("click")  # must not raise


def test_assert_desktop_input_raises_on_linux(monkeypatch):
    monkeypatch.setattr("platform.system", lambda: "Linux")
    P.os_name.cache_clear()
    with pytest.raises(NotImplementedError) as ei:
        P.assert_desktop_input("click")
    assert "pynput" in str(ei.value) or "xdotool" in str(ei.value)


# ─── helper ───────────────────────────────────────────────────────────────────

class _Fake:
    def __init__(self, stdout=""):
        self.stdout = stdout
        self.returncode = 0
        self.stderr = ""


def _fake_stdout(s):
    return _Fake(stdout=s)
