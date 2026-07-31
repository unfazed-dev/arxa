# scripts/test_site_chrome.py
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _write_route(site, rid, nodes):
    rd = site / "routes" / rid
    rd.mkdir(parents=True, exist_ok=True)
    (rd / "skeleton.json").write_text(json.dumps({"nodes": nodes}))


def _nav(base, bg):
    return [
        {"id": base, "parent": None, "tag": "nav", "aria_role": "navigation", "z": 0,
         "confidence": 1.0, "token_ref": {"bg": bg, "fg": "f", "border": "b"}},
        {"id": base + 1, "parent": base, "tag": "a", "z": 0, "confidence": 1.0, "text_len": 4},
    ]


def test_cli_dedups_and_roundtrips(tmp_path):
    site = tmp_path / "site_out"
    (site).mkdir()
    (site / "site.json").write_text(json.dumps({"routes": [
        {"route_id": "r0", "ok": True}, {"route_id": "r1", "ok": True}]}))
    _write_route(site, "r0", _nav(0, "red"))
    _write_route(site, "r1", _nav(100, "blue"))
    out = site / "chrome_dedup.json"
    r = subprocess.run([sys.executable, str(HERE / "site_chrome.py"),
                        "--site", str(site), "--out", str(out)],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr + r.stdout
    payload = json.loads(r.stdout)
    assert payload["ok"] is True and payload["roundtrip_ok"] is True
    assert payload["template_count"] == 1
    assert out.exists()


def test_written_artifact_reloads_and_reconstructs(tmp_path):
    # the ON-DISK file (not in-memory art) must reconstruct byte-identically
    import _chrome_dedup as D
    site = tmp_path / "site_out"
    site.mkdir()
    (site / "site.json").write_text(json.dumps({"routes": [
        {"route_id": "r0", "ok": True}, {"route_id": "r1", "ok": True}]}))
    _write_route(site, "r0", _nav(0, "red"))
    _write_route(site, "r1", _nav(100, "blue"))
    out = site / "chrome_dedup.json"
    subprocess.run([sys.executable, str(HERE / "site_chrome.py"),
                    "--site", str(site), "--out", str(out)],
                   check=True, capture_output=True, text=True)
    loaded = json.loads(out.read_text())
    rebuilt = D.reconstruct(loaded)
    originals = {"r0": _nav(0, "red"), "r1": _nav(100, "blue")}
    for rid, orig in originals.items():
        assert {n["id"]: n for n in rebuilt[rid]} == {n["id"]: n for n in orig}, rid


def test_too_few_routes_exits_nonzero(tmp_path):
    site = tmp_path / "site_out"
    site.mkdir()
    (site / "site.json").write_text(json.dumps({"routes": [{"route_id": "r0", "ok": True}]}))
    _write_route(site, "r0", _nav(0, "red"))
    out = site / "chrome_dedup.json"
    r = subprocess.run([sys.executable, str(HERE / "site_chrome.py"),
                        "--site", str(site), "--out", str(out)], capture_output=True, text=True)
    assert r.returncode != 0          # die: fewer than 2 ok routes -> clean nonzero, no file
    assert not out.exists()


def _nav_with_leak(base):
    n = _nav(base, "red")
    n[0]["href"] = "https://example.com/secret-photo.jpg"   # a content URL the firewall must catch
    return n


def test_firewall_violation_unlinks_and_reports(tmp_path):
    # a leaked content value -> audit_bundle flags -> the artifact is unlinked and a nonzero exit
    # (mirrors site_merge); a flagged artifact must never persist.
    site = tmp_path / "site_out"
    site.mkdir()
    (site / "site.json").write_text(json.dumps({"routes": [
        {"route_id": "r0", "ok": True}, {"route_id": "r1", "ok": True}]}))
    _write_route(site, "r0", _nav_with_leak(0))
    _write_route(site, "r1", _nav_with_leak(100))
    out = site / "chrome_dedup.json"
    r = subprocess.run([sys.executable, str(HERE / "site_chrome.py"),
                        "--site", str(site), "--out", str(out)], capture_output=True, text=True)
    assert r.returncode == 3
    payload = json.loads(r.stdout)
    assert payload["ok"] is False and payload["error"] == "content_firewall"
    assert not out.exists()           # flagged artifact never persists


def test_on_disk_roundtrip_preserves_unkeyed_style(tmp_path):
    # the WRITTEN artifact (post _jsonable) must reconstruct an unkeyed-style difference losslessly,
    # i.e. drop/exceptions survive serialization. Guards _jsonable dropping the new `drop` map.
    import _chrome_dedup as D
    site = tmp_path / "site_out"
    site.mkdir()
    (site / "site.json").write_text(json.dumps({"routes": [
        {"route_id": "r0", "ok": True}, {"route_id": "r1", "ok": True}]}))
    def styled(base, grad):
        return [
            {"id": base, "parent": None, "tag": "nav", "aria_role": "navigation", "z": 0,
             "confidence": 1.0, "token_ref": {"bg": "b", "fg": "f", "border": "b"},
             "style": {"background-image": grad}},
            {"id": base + 1, "parent": base, "tag": "a", "z": 0, "confidence": 1.0, "text_len": 4}]
    _write_route(site, "r0", styled(0, "grad-a"))
    _write_route(site, "r1", styled(100, "grad-b"))
    out = site / "chrome_dedup.json"
    r = subprocess.run([sys.executable, str(HERE / "site_chrome.py"),
                        "--site", str(site), "--out", str(out)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr + r.stdout
    loaded = json.loads(out.read_text())
    rebuilt = D.reconstruct(loaded)
    originals = {"r0": styled(0, "grad-a"), "r1": styled(100, "grad-b")}
    for rid, orig in originals.items():
        assert {n["id"]: n for n in rebuilt[rid]} == {n["id"]: n for n in orig}, rid


def test_on_disk_roundtrip_preserves_drop_map(tmp_path):
    # drop-specific on-disk guard: r0 (donor) carries `style`; r1 has NONE -> reconstruct must DROP
    # the template's style for r1. This exercises the `drop` map's survival through _jsonable
    # (the styled-pair test above only charges `exceptions`, never populating `drop`).
    import _chrome_dedup as D
    site = tmp_path / "site_out"
    site.mkdir()
    (site / "site.json").write_text(json.dumps({"routes": [
        {"route_id": "r0", "ok": True}, {"route_id": "r1", "ok": True}]}))
    def styled(base, grad):
        return [
            {"id": base, "parent": None, "tag": "nav", "aria_role": "navigation", "z": 0,
             "confidence": 1.0, "token_ref": {"bg": "b", "fg": "f", "border": "b"},
             "style": {"background-image": grad}},
            {"id": base + 1, "parent": base, "tag": "a", "z": 0, "confidence": 1.0, "text_len": 4}]
    def plain(base):
        return [
            {"id": base, "parent": None, "tag": "nav", "aria_role": "navigation", "z": 0,
             "confidence": 1.0, "token_ref": {"bg": "b", "fg": "f", "border": "b"}},
            {"id": base + 1, "parent": base, "tag": "a", "z": 0, "confidence": 1.0, "text_len": 4}]
    _write_route(site, "r0", styled(0, "grad-a"))
    _write_route(site, "r1", plain(100))                     # same struct key, NO style at all
    out = site / "chrome_dedup.json"
    r = subprocess.run([sys.executable, str(HERE / "site_chrome.py"),
                        "--site", str(site), "--out", str(out)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr + r.stdout
    loaded = json.loads(out.read_text())
    # directly assert the on-disk JSON carries the drop map (proves _jsonable kept it)
    drop_for_r1 = loaded["routes"]["r1"]["refs"][0]["drop"]
    assert "style" in drop_for_r1.get("0", []), drop_for_r1
    rebuilt = D.reconstruct(loaded)
    originals = {"r0": styled(0, "grad-a"), "r1": plain(100)}
    for rid, orig in originals.items():
        assert {n["id"]: n for n in rebuilt[rid]} == {n["id"]: n for n in orig}, rid
