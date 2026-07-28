"""CLI units for cross-route token merge (G3b). No CDP."""
import json
import sys
from pathlib import Path

import pytest


def _write_capture(root, routes):
    """routes: {route_id: tokens_dict_or_None}. None -> ok route with NO tokens.json
    (unreadable). Writes site.json + routes/<id>/tokens.json."""
    rows = []
    for rid, toks in routes.items():
        rdir = root / "routes" / rid
        rdir.mkdir(parents=True, exist_ok=True)
        if toks is not None:
            (rdir / "tokens.json").write_text(json.dumps(toks))
        rows.append({"route_id": rid, "url": "https://e.com/%s" % rid,
                     "bundle": "routes/%s" % rid, "ok": True})
    site = {"schema": "probe-runner/site-manifest@1", "hosts": ["e.com"],
            "route_count": len(rows), "ok_count": len(rows), "routes": rows}
    (root / "site.json").write_text(json.dumps(site))


def _run(monkeypatch, argv):
    import site_merge
    monkeypatch.setattr(sys, "argv", ["site_merge.py"] + argv)
    return site_merge.main()


def test_site_merge_writes_artifact(tmp_path, monkeypatch):
    _write_capture(tmp_path, {
        "r00": {"palette": {"background": "#fff", "accent": "#3b82f6"},
                "type_scale": [16, 24]},
        "r01": {"palette": {"background": "#fff", "accent": "#ef4444"},
                "type_scale": [16]},
    })
    rc = _run(monkeypatch, ["--site", str(tmp_path)])
    assert rc == 0
    ds = json.loads((tmp_path / "design_system.json").read_text())
    assert ds["schema"] == "probe-runner/design-system@1"
    assert ds["merged_route_count"] == 2
    bg = ds["palette"]["background"]["exact"]
    assert bg[0]["value"] == "#fff" and bg[0]["core"] is True


def test_site_merge_skips_unreadable_route(tmp_path, monkeypatch):
    _write_capture(tmp_path, {
        "r00": {"palette": {"accent": "#3b82f6"}},
        "r01": None,   # ok row but missing tokens.json -> skipped, not fatal
    })
    rc = _run(monkeypatch, ["--site", str(tmp_path)])
    assert rc == 0
    ds = json.loads((tmp_path / "design_system.json").read_text())
    assert ds["merged_route_count"] == 1 and ds["route_ids"] == ["r00"]


def test_site_merge_zero_mergeable_exits_2(tmp_path, monkeypatch):
    rows = [{"route_id": "r00", "url": "https://e.com/", "bundle": "routes/r00",
             "ok": False, "error_kind": "skeleton_failed"}]
    site = {"schema": "probe-runner/site-manifest@1", "hosts": ["e.com"],
            "route_count": 1, "ok_count": 0, "routes": rows}
    (tmp_path / "site.json").write_text(json.dumps(site))
    with pytest.raises(SystemExit) as ei:
        _run(monkeypatch, ["--site", str(tmp_path)])
    assert ei.value.code == 2


def test_site_merge_canary_palette_prose_trips_firewall(tmp_path, monkeypatch, capsys):
    # prose injected into a PALETTE value flows into design_system.json under a "value"
    # key (NOT firewall-exempt) -> the UNCHANGED content_firewall trips -> exit 3, no
    # sample printed. Written to an ISOLATED empty --out dir so the trip is attributable
    # to design_system.json itself, proving the NEW persistence surface is scanned.
    # (Families is deliberately NOT used here: it sits under the exempt "family" key.)
    prose = "The quick brown fox jumps over the lazy dog repeatedly in this paragraph."
    _write_capture(tmp_path, {"r00": {"palette": {"accent": prose}}})
    iso = tmp_path / "iso"
    iso.mkdir()
    out = iso / "design_system.json"
    rc = _run(monkeypatch, ["--site", str(tmp_path), "--out", str(out)])
    assert rc == 3
    captured = capsys.readouterr().out
    assert "content_audit_failed" in captured
    assert prose not in captured and "sample" not in captured


def test_site_merge_families_long_stack_clean(tmp_path, monkeypatch):
    # Regression: a long keyword-less font stack (>24 chars, no sans-serif/serif/etc.)
    # passes tokens.json audit under the exempt "families" key. In design_system.json it
    # must ALSO pass -- the merge emits it under the exempt "family" key. Without that
    # fix this stack would false-positive exit 3.
    stack = "Helvetica Neue, Arial, Liberation Sans"
    _write_capture(tmp_path, {"r00": {"families": [stack]}})
    iso = tmp_path / "iso"
    iso.mkdir()
    out = iso / "design_system.json"
    rc = _run(monkeypatch, ["--site", str(tmp_path), "--out", str(out)])
    assert rc == 0
    ds = json.loads(out.read_text())
    assert ds["scalars"]["families"][0]["family"] == stack


def test_site_merge_missing_site_json_exits_2(tmp_path, monkeypatch):
    # _load_routes dies (exit 2) when site.json is absent/unreadable.
    with pytest.raises(SystemExit) as ei:
        _run(monkeypatch, ["--site", str(tmp_path)])   # tmp_path has no site.json
    assert ei.value.code == 2


def test_site_merge_removes_artifact_on_audit_failure(tmp_path, monkeypatch):
    # On a firewall trip the flagged artifact must NOT be left on disk.
    prose = "The quick brown fox jumps over the lazy dog repeatedly in this paragraph."
    _write_capture(tmp_path, {"r00": {"palette": {"accent": prose}}})
    iso = tmp_path / "iso"
    iso.mkdir()
    out = iso / "design_system.json"
    rc = _run(monkeypatch, ["--site", str(tmp_path), "--out", str(out)])
    assert rc == 3
    assert not out.exists()
