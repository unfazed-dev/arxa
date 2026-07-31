#!/usr/bin/env python3
"""Tests for pr-decide.py (the routing resolver) and verbs.json (the manifest).

No framework — assert-based, mirrors the repo's existing test style
(test_color_assert.py). Also collected by pytest (every check is a test_* fn).

Covers:
  - manifest structural validity (declared intents/targets match routes)
  - every route has the four required keys
  - every non-null script EXISTS on disk (the drift check — the top risk both
    advisors flagged: manifest rot when a script is renamed/removed)
  - resolver: single-route, all-targets, --list, bare matrix
  - resolver: unknown intent / unknown target -> die (rc=2)
  - resolver: --self-test passes
"""
from __future__ import annotations

import importlib.util
import io
import json
import sys
from contextlib import redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

# pr-decide.py uses a hyphen (not importable as a module name) — load by path.
_spec = importlib.util.spec_from_file_location("pr_decide", HERE / "pr-decide.py")
assert _spec is not None and _spec.loader is not None
pd = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pd)  # noqa: E402

SCRIPTS = HERE
MANIFEST = HERE / "verbs.json"


# ─── manifest validity ───────────────────────────────────────────────────────

def test_manifest_loads_and_is_valid_json() -> None:
    m = pd._load()
    assert isinstance(m, dict)
    assert m["schema_version"] == 1


def test_declared_intents_match_routes() -> None:
    m = pd._load()
    assert set(m["routes"].keys()) == set(m["intents"])


def test_every_intent_covers_all_targets() -> None:
    m = pd._load()
    for intent, by_target in m["routes"].items():
        assert set(by_target.keys()) == set(m["targets"]), f"{intent} missing targets"


def test_every_route_has_required_keys() -> None:
    m = pd._load()
    for intent, by_target in m["routes"].items():
        for tgt, r in by_target.items():
            for key in ("script", "args", "fallback", "notes"):
                assert key in r, f"{intent}/{tgt} missing '{key}'"
            if r["script"] is not None:
                assert isinstance(r["args"], list), f"{intent}/{tgt} args not a list"


# ─── drift check (the top risk) ──────────────────────────────────────────────

def test_every_referenced_script_exists_on_disk() -> None:
    """If a script is renamed/removed without updating verbs.json, this fails loud."""
    m = pd._load()
    missing = []
    for intent, by_target in m["routes"].items():
        for tgt, r in by_target.items():
            if r["script"] is None:
                continue
            if not (SCRIPTS / r["script"]).exists():
                missing.append(f"{intent}/{tgt} -> {r['script']}")
    assert not missing, "manifest references scripts that do not exist:\n  " + "\n  ".join(missing)


def test_at_least_one_target_supports_each_intent() -> None:
    """Each intent must have >=1 non-null script (else it shouldn't be an intent)."""
    m = pd._load()
    for intent, by_target in m["routes"].items():
        scripts = [r["script"] for r in by_target.values() if r["script"] is not None]
        assert scripts, f"intent '{intent}' has no script on ANY target"


# ─── resolver behavior ───────────────────────────────────────────────────────

def _run(argv: list[str]) -> tuple[int, str, str]:
    """Invoke pr_decide.main() with a fake argv, capture stdout, return (rc, out, err)."""
    old = sys.argv
    sys.argv = [pd.__file__] + argv
    out_buf, err_buf = io.StringIO(), io.StringIO()
    rc = -1
    try:
        with redirect_stdout(out_buf):
            try:
                rc = pd.main()
            except SystemExit as e:  # die() raises SystemExit(code)
                rc = e.code if isinstance(e.code, int) else 2
    finally:
        sys.argv = old
    return rc, out_buf.getvalue(), err_buf.getvalue()


def test_single_route_returns_json_with_command() -> None:
    rc, out, _ = _run(["tap", "--target", "ios"])
    assert rc == 0, out
    d = json.loads(out)
    assert d["intent"] == "tap"
    assert d["target"] == "ios"
    assert d["script"] == "ios_tap.py"
    assert d["command"] == "python3 scripts/ios_tap.py <x> <y>"
    assert d["args"] == ["<x>", "<y>"]
    assert d["fallback"]
    assert d["notes"]


def test_null_script_route_emits_command_null_with_notes() -> None:
    """Honest-gap targets (eval on native ios) answer command:null + a pointer."""
    rc, out, _ = _run(["eval", "--target", "ios"])
    assert rc == 0, out
    d = json.loads(out)
    assert d["command"] is None
    assert d["script"] is None
    assert "NO JS/Dart eval" in d["notes"]


def test_all_targets_for_intent() -> None:
    rc, out, _ = _run(["tap"])
    assert rc == 0, out
    d = json.loads(out)
    assert d["intent"] == "tap"
    assert d["targets"] == pd._load()["targets"]
    assert len(d["routes"]) == 6


def test_list_runs_clean() -> None:
    rc, out, _ = _run(["--list"])
    assert rc == 0, out
    for intent in ("tap", "type", "screenshot", "uitree", "eval", "find",
                   "scroll", "record", "animate", "launch", "quit", "wait"):
        assert intent in out


def test_bare_invocation_prints_matrix() -> None:
    rc, out, _ = _run([])
    assert rc == 0, out
    assert "intent" in out and "ios" in out
    # every intent should head a row
    for intent in pd._load()["intents"]:
        assert intent in out


def test_unknown_intent_dies_rc2() -> None:
    rc, _out, _err = _run(["frobnicate"])
    assert rc == 2


def test_unknown_target_dies_rc2() -> None:
    rc, _out, _err = _run(["tap", "--target", "qnx"])
    assert rc == 2


def test_self_test_passes() -> None:
    rc, out, _ = _run(["--self-test"])
    assert rc == 0, out
    assert json.loads(out)["self_test"] == "pass"


# ─── self-runner (test_color_assert.py style) ────────────────────────────────

def _run_all() -> int:
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    passed = 0
    for t in tests:
        try:
            t()
            print(f"PASS {t.__name__}")
            passed += 1
        except AssertionError as e:
            print(f"FAIL {t.__name__}: {e}")
            return 1
        except Exception as e:  # noqa: BLE001
            print(f"ERROR {t.__name__}: {type(e).__name__}: {e}")
            return 1
    print(f"\nALL GREEN ({passed}/{len(tests)} checks)")
    return 0


if __name__ == "__main__":
    sys.exit(_run_all())
