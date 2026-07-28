#!/usr/bin/env python3
"""Unit tests for flutter_tap.py — failure-visibility paths, fully offline.

Runnable: python3 scripts/test_flutter_tap.py
No framework — assert-based, mirrors the repo's existing test style
(test_color_assert.py). No VM service, simulator, or device required:
`subprocess.run` (the flutter_find / ios_tap / adb_tap delegations) and
`_rect_via_vm` (the VM tree-walk) are stubbed out.

Covers the two confirmed failure-visibility bugs:
  1. Delegated tap failure was invisible: ios_tap.py/adb_tap.py stderr was
     captured but never emitted. The JSON must now carry `tap_stderr`, plus a
     `tap_error` remediation line naming the underlying script when rc != 0.
     Exit code stays 3.
  2. Bare `die("no match")`: flutter_find count==0 must die with a message
     naming the tried selector(s), the native platform-view caveat (a
     KitNativeButton-style label is not a Text widget in the Flutter element
     tree, so --text can never match it), and runnable fallback commands.
"""
import contextlib
import io
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import flutter_tap as ft  # noqa: E402


_MATCH = {"count": 1, "matches": [{"description": "Account",
                                   "widgetRuntimeType": "Text"}]}
_RECT = (10.0, 20.0, 100.0, 40.0)


def _cp(cmd, rc, out="", err=""):
    return subprocess.CompletedProcess(cmd, rc, stdout=out, stderr=err)


def _drive(argv, find_payload, tap=None, rect=_RECT):
    """Run ft.main() with every external boundary stubbed.

    `tap` is (rc, stdout, stderr) for the delegated ios_tap/adb_tap call, or
    None to make that call blow up if reached. Returns
    (rc, system_exit_or_none, captured_stdout, captured_stderr).
    """
    real_run, real_rect, real_argv = subprocess.run, ft._rect_via_vm, sys.argv

    def fake_run(cmd, **_kw):
        name = Path(cmd[1]).name
        if name == "flutter_find.py":
            return _cp(cmd, 0, out=json.dumps(find_payload))
        if name in ("ios_tap.py", "adb_tap.py") and tap is not None:
            return _cp(cmd, tap[0], tap[1], tap[2])
        raise AssertionError(f"unexpected subprocess call: {cmd}")

    out, err = io.StringIO(), io.StringIO()
    rc, exc = None, None
    subprocess.run = fake_run
    ft._rect_via_vm = lambda *_a: rect
    sys.argv = argv
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                rc = ft.main()
            except SystemExit as e:
                exc = e
    finally:
        subprocess.run, ft._rect_via_vm, sys.argv = real_run, real_rect, real_argv
    return rc, exc, out.getvalue(), err.getvalue()


def test_delegated_tap_failure_carries_stderr_and_exits_3():
    """The original bug: ios_tap died (idb not connected) and the operator saw
    only {"tap_rc": 1, "tap_stdout": null}. tap_stderr + tap_error must ship."""
    rc, exc, out, _ = _drive(
        ["flutter_tap.py", "--target", "ios", "--text", "Account"],
        find_payload=_MATCH,
        tap=(1, "", "error: idb companion not connected for the booted simulator"))
    assert exc is None, exc
    assert rc == 3, f"delegated tap failure must exit 3, got {rc}"
    payload = json.loads(out)
    assert payload["tap_rc"] == 1, payload
    assert "idb companion not connected" in payload["tap_stderr"], payload
    assert "ios_tap.py" in payload["tap_error"], payload


def test_delegated_tap_success_exits_0_with_null_stderr():
    """Happy path: rc=0, tap_stderr key present but null, no tap_error key."""
    rc, exc, out, _ = _drive(
        ["flutter_tap.py", "--target", "adb", "--key", "login"],
        find_payload=_MATCH,
        tap=(0, '{"tapped": [60, 40]}', ""))
    assert exc is None and rc == 0, (exc, rc)
    payload = json.loads(out)
    assert payload["tap_rc"] == 0, payload
    assert payload["tap_stdout"] == '{"tapped": [60, 40]}', payload
    assert payload["tap_stderr"] is None, payload
    assert "tap_error" not in payload, payload


def test_no_match_death_names_selector_and_fallback():
    """The original bug: a bare `no match`. The death message must name the
    tried selector, explain the platform-view invisibility, and list runnable
    fallback commands."""
    rc, exc, _, err = _drive(
        ["flutter_tap.py", "--target", "ios", "--text", "Continue with Google"],
        find_payload={"count": 0, "matches": []})
    assert rc is None and isinstance(exc, SystemExit), (rc, exc)
    assert exc.code == 2, f"die() default exit code unchanged, got {exc.code}"
    assert "Continue with Google" in err, err          # the tried selector
    assert "platform view" in err, err                 # why --text can never match
    assert "flutter_tree.py" in err, err               # enumerate candidates
    assert "flutter_shot.py" in err, err               # screenshot path
    assert "ios_tap.py <x> <y>" in err, err            # tap-by-coordinates path


def test_no_match_adb_fallback_names_adb_tap():
    """The fallback sequence is target-aware: adb gets adb_tap.py, not ios_tap.py."""
    rc, exc, _, err = _drive(
        ["flutter_tap.py", "--target", "adb", "--text", "Account"],
        find_payload={"count": 0, "matches": []})
    assert isinstance(exc, SystemExit), (rc, exc)
    assert "adb_tap.py <x> <y>" in err, err
    assert "ios_tap.py" not in err, err


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
