"""End-to-end (no browser): the assembled capture_site path ships href-free nav_edges whose
src_node joins a real node in the shipped, redacted skeleton.json. Closes the real-artifact gap
the unit tests leave (per memory validate-real-artifact-not-keys-proxy): the pure helpers were
tested in isolation, but nothing exercised capture_site -> capture_route -> _edges_from_skeleton
-> _site + the real firewall audit together. Monkeypatches _run to stand in for the
web_skeleton/web_tokens/bundle_writer subprocesses, modelling the real redaction (raw _sk.json
carries href; the shipped skeleton.json drops it, exactly as redact_node would)."""
import json
import sys
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent))
import site_capture as SC

# Raw (pre-redaction) per-route skeleton nodes, keyed by the captured URL. Anchors carry href.
_RAW = {
    "https://x.com/": [
        {"id": 0, "parent": None, "role": "unknown_box", "aria_role": None},
        {"id": 1, "parent": 0, "role": "unknown_box", "aria_role": "navigation"},
        {"id": 2, "parent": 1, "role": "unknown_box", "aria_role": None,
         "href": "https://x.com/a"},            # -> route 1, inside navigation -> chrome
    ],
    "https://x.com/a": [
        {"id": 0, "parent": None, "role": "unknown_box", "aria_role": None},
        {"id": 1, "parent": 0, "role": "unknown_box", "aria_role": "main"},
        {"id": 2, "parent": 1, "role": "unknown_box", "aria_role": None,
         "href": "https://x.com/"},             # -> route 0, inside main -> content (not chrome)
    ],
}


def _fake_run(cmd):
    """Stand in for the three real subprocesses, writing the files they would produce."""
    script = next(c for c in cmd if str(c).endswith(".py"))
    out = cmd[cmd.index("--out") + 1]
    if script.endswith("web_skeleton.py"):
        url = cmd[cmd.index("--url") + 1]
        Path(out).write_text(json.dumps({"nodes": _RAW[url]}))
    elif script.endswith("web_tokens.py"):
        Path(out).write_text(json.dumps({"tokens": {}}))
    elif script.endswith("bundle_writer.py"):
        sk = cmd[cmd.index("--skeleton") + 1]
        raw = json.loads(Path(sk).read_text())
        # model redact_node: drop the href CONTENT_KEY, keep structure (id/parent/role/aria_role)
        red = [{k: v for k, v in n.items() if k != "href"} for n in raw["nodes"]]
        Path(out, "skeleton.json").write_text(json.dumps({"nodes": red}))
    return SimpleNamespace(returncode=0)


def test_capture_site_ships_href_free_edges_with_valid_src_node(tmp_path, monkeypatch):
    monkeypatch.setattr(SC, "_run", _fake_run)
    out = tmp_path / "site"
    manifest = SC.capture_site(["https://x.com/", "https://x.com/a"], str(out), transport=[])
    edges = manifest["nav_edges"]

    # 1. populated
    assert edges, "expected non-empty nav_edges"

    # 2. content-free: exact key-set, no href key, no http(s) value anywhere in an edge
    for e in edges:
        assert set(e) == {"src", "dst", "src_node", "chrome"}, e
        assert not any(isinstance(v, str) and "http" in v for v in e.values()), e

    # 3. no shipped skeleton node carries href, AND every edge's src_node joins a real shipped node
    by_route = {}
    for r in manifest["routes"]:
        sk = json.loads((out / r["bundle"] / "skeleton.json").read_text())
        assert all("href" not in n for n in sk["nodes"]), "href leaked into shipped skeleton"
        by_route[r["route_id"]] = {n["id"] for n in sk["nodes"]}
    for e in edges:
        assert e["src_node"] in by_route[e["src"]], ("src_node not in shipped skeleton", e)

    # 4. chrome classification: navigation-anchored edge is chrome; main-anchored is not
    by_pair = {(e["src"], e["dst"]): e for e in edges}
    assert by_pair[("r00", "r01")]["chrome"] is True
    assert by_pair[("r01", "r00")]["chrome"] is False

    # 5. firewall: capture_site ran the real audit_bundle and did not die -> shipped tree is clean
    #    (a raw href value never reaches the audited tree; it lived only in the scratch _sk.json)
    import content_firewall as cf
    assert cf.audit_bundle(out) == []
