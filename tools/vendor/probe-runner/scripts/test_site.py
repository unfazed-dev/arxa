"""Pure-core + orchestrator units for multi-route site capture (G3a). No CDP."""
import json
from pathlib import Path

import pytest


# ---- _site pure core ----

def test_build_site_manifest_shape():
    import _site
    rows = [
        {"route_id": "r00", "url": "https://e.com/", "bundle": "routes/r00",
         "ok": True, "node_count": 10},
        {"route_id": "r01", "url": "https://e.com/p", "bundle": "routes/r01",
         "ok": False, "error_kind": "tokens_failed"},
    ]
    m = _site.build_site_manifest(rows)
    assert m["schema"] == "probe-runner/site-manifest@1"
    assert m["route_count"] == 2
    assert m["ok_count"] == 1
    assert m["hosts"] == ["e.com"]
    assert m["routes"] == rows


def test_build_site_manifest_multi_host_sorted():
    import _site
    rows = [
        {"route_id": "r00", "url": "https://b.com/", "bundle": "routes/r00",
         "ok": True, "node_count": 1},
        {"route_id": "r01", "url": "https://a.com/", "bundle": "routes/r01",
         "ok": True, "node_count": 2},
    ]
    assert _site.build_site_manifest(rows)["hosts"] == ["a.com", "b.com"]


def test_dedupe_preserve_order():
    import _site
    assert _site.dedupe_preserve_order(["a", "b", "a", "c", "b"]) == ["a", "b", "c"]


# ---- firewall canary: site.json is inside the firewall (P14 lesson) ----

def test_site_json_prose_trips_firewall(tmp_path):
    """audit_bundle rglobs every file under a dir, so calling it on the site ROOT
    audits site.json too. Prove unredacted prose in a manifest field trips the
    UNCHANGED firewall — don't assert site.json is content-free, prove it."""
    import content_firewall as cf
    (tmp_path / "site.json").write_text(json.dumps({
        "schema": "probe-runner/site-manifest@1",
        "routes": [{
            "route_id": "r00",
            "url": "https://e.com/",
            "note": "The quick brown fox jumps over the lazy dog repeatedly today.",
        }],
    }))
    viol = cf.audit_bundle(tmp_path)
    assert any(v["kind"] == "prose" for v in viol)


# ---- site_capture orchestrator (subprocess monkeypatched; no CDP) ----

def _fake_run_factory(broken_substr=None, bundle_rc=0, bundle_writes_skeleton=True):
    """Build a subprocess.run replacement that materializes the expected output
    files for the skeleton/tokens/bundle steps. A url containing broken_substr
    makes web_skeleton fail. bundle_writer returns bundle_rc."""
    def fake_run(cmd, **kw):
        class R:
            pass
        r = R()
        r.stdout = ""
        r.stderr = "SECRET-STDERR-MUST-NOT-PERSIST"
        url = cmd[cmd.index("--url") + 1] if "--url" in cmd else ""
        if cmd[1].endswith("web_skeleton.py"):
            if broken_substr and broken_substr in url:
                r.returncode = 2
                return r
            Path(cmd[cmd.index("--out") + 1]).write_text(
                json.dumps({"url": url, "nodes": [1, 2, 3]}))
            r.returncode = 0
        elif cmd[1].endswith("web_tokens.py"):
            Path(cmd[cmd.index("--out") + 1]).write_text(json.dumps({"palette": {}}))
            r.returncode = 0
        elif cmd[1].endswith("bundle_writer.py"):
            if bundle_rc == 0 and bundle_writes_skeleton:
                Path(cmd[cmd.index("--out") + 1], "skeleton.json").write_text(
                    json.dumps({"nodes": [1, 2, 3]}))
            r.returncode = bundle_rc
        else:
            r.returncode = 0
        return r
    return fake_run


def test_transport_argv_forwards_flags():
    import argparse, site_capture
    ns = argparse.Namespace(cdp_port=9222, browser="chrome",
                            android=False, ios=False, serial=None)
    assert site_capture._transport_argv(ns) == ["--cdp-port", "9222",
                                                "--browser", "chrome"]


def test_transport_argv_omits_defaults():
    import argparse, site_capture
    ns = argparse.Namespace(cdp_port=None, browser="auto",
                            android=False, ios=False, serial=None)
    assert site_capture._transport_argv(ns) == []


def test_capture_site_rows_and_manifest(tmp_path, monkeypatch):
    import site_capture
    monkeypatch.setattr(site_capture.subprocess, "run", _fake_run_factory())
    monkeypatch.setattr(site_capture.cf, "audit_bundle", lambda d: [])
    m = site_capture.capture_site(
        ["https://e.com/", "https://e.com/p"], str(tmp_path), [])
    assert m["route_count"] == 2 and m["ok_count"] == 2
    assert m["routes"][0]["route_id"] == "r00"
    assert m["routes"][0]["node_count"] == 3
    assert m["routes"][0]["bundle"] == "routes/r00"
    assert m["hosts"] == ["e.com"]
    assert (tmp_path / "site.json").exists()


def test_capture_site_isolates_failed_route(tmp_path, monkeypatch):
    import site_capture
    monkeypatch.setattr(site_capture.subprocess, "run",
                        _fake_run_factory(broken_substr="broken"))
    monkeypatch.setattr(site_capture.cf, "audit_bundle", lambda d: [])
    m = site_capture.capture_site(
        ["https://e.com/ok", "https://e.com/broken"], str(tmp_path), [])
    assert m["ok_count"] == 1
    r1 = m["routes"][1]
    assert r1["ok"] is False and r1["error_kind"] == "skeleton_failed"
    assert "node_count" not in r1
    # subprocess stderr must never reach disk
    assert "SECRET-STDERR" not in (tmp_path / "site.json").read_text()


def test_capture_route_maps_exit_3_to_audit(tmp_path, monkeypatch):
    import site_capture
    monkeypatch.setattr(site_capture.subprocess, "run",
                        _fake_run_factory(bundle_rc=3))
    ok, n, err, _edges, _raw = site_capture.capture_route(
        "https://e.com/x", tmp_path / "r00", [])
    assert ok is False and err == "bundle_audit_failed" and n is None


def test_capture_route_maps_generic_bundle_failure(tmp_path, monkeypatch):
    import site_capture
    monkeypatch.setattr(site_capture.subprocess, "run",
                        _fake_run_factory(bundle_rc=1))
    ok, n, err, _edges, _raw = site_capture.capture_route(
        "https://e.com/x", tmp_path / "r00", [])
    assert ok is False and err == "bundle_failed"


def test_capture_site_dies_on_audit_violation(tmp_path, monkeypatch, capsys):
    import site_capture
    monkeypatch.setattr(site_capture.subprocess, "run", _fake_run_factory())
    monkeypatch.setattr(site_capture.cf, "audit_bundle",
                        lambda d: [{"kind": "prose", "file": "site.json",
                                    "sample": "LEAKED"}])
    with pytest.raises(SystemExit) as ei:
        site_capture.capture_site(["https://e.com/"], str(tmp_path), [])
    assert ei.value.code == 3
    # content-free: the violation `sample` must never reach stderr (only kind+file).
    assert "LEAKED" not in capsys.readouterr().err


def test_capture_route_isolates_unreadable_skeleton(tmp_path, monkeypatch):
    import site_capture
    monkeypatch.setattr(site_capture.subprocess, "run",
                        _fake_run_factory(bundle_writes_skeleton=False))
    ok, n, err, _edges, _raw = site_capture.capture_route(
        "https://e.com/x", tmp_path / "r00", [])
    assert ok is False and err == "skeleton_unreadable" and n is None


def test_capture_site_survives_unreadable_skeleton(tmp_path, monkeypatch):
    """rc-0 bundle but no skeleton.json on every route must NOT abort the run:
    the run completes, site.json is written, and each route is isolated."""
    import site_capture
    monkeypatch.setattr(site_capture.subprocess, "run",
                        _fake_run_factory(bundle_writes_skeleton=False))
    monkeypatch.setattr(site_capture.cf, "audit_bundle", lambda d: [])
    m = site_capture.capture_site(
        ["https://e.com/a", "https://e.com/b"], str(tmp_path), [])
    assert m["route_count"] == 2 and m["ok_count"] == 0
    assert all(r["error_kind"] == "skeleton_unreadable" for r in m["routes"])
    assert (tmp_path / "site.json").exists()


def test_capture_site_no_scratch_in_route_dir(tmp_path, monkeypatch):
    """Raw _sk.json/_tok.json must NOT persist inside the per-route bundle dir
    (they are pre-redaction content and would trip the firewall there)."""
    import site_capture
    monkeypatch.setattr(site_capture.subprocess, "run", _fake_run_factory())
    monkeypatch.setattr(site_capture.cf, "audit_bundle", lambda d: [])
    site_capture.capture_site(["https://e.com/"], str(tmp_path), [])
    rd = tmp_path / "routes" / "r00"
    assert not (rd / "_sk.json").exists()
    assert not (rd / "_tok.json").exists()


def test_capture_route_removes_failed_route_dir(tmp_path, monkeypatch):
    """A route whose bundle audit fires must leave NO files on disk (rmtree)."""
    import site_capture
    monkeypatch.setattr(site_capture.subprocess, "run", _fake_run_factory(bundle_rc=3))
    rd = tmp_path / "r00"
    ok, n, err, _edges, _raw = site_capture.capture_route("https://e.com/x", rd, [])
    assert ok is False and err == "bundle_audit_failed"
    assert not rd.exists()


def test_capture_site_survives_bundle_audit_failure(tmp_path, monkeypatch):
    """Every route failing the bundle audit must NOT abort the run: site.json is
    still written, each route isolated, and the failed route dirs are removed."""
    import site_capture
    monkeypatch.setattr(site_capture.subprocess, "run", _fake_run_factory(bundle_rc=3))
    monkeypatch.setattr(site_capture.cf, "audit_bundle", lambda d: [])
    m = site_capture.capture_site(
        ["https://e.com/a", "https://e.com/b"], str(tmp_path), [])
    assert m["route_count"] == 2 and m["ok_count"] == 0
    assert all(r["error_kind"] == "bundle_audit_failed" for r in m["routes"])
    assert (tmp_path / "site.json").exists()
    assert not (tmp_path / "routes" / "r00").exists()
