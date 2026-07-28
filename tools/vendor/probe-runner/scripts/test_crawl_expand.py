import json
from pathlib import Path

import site_capture as SC
import _crawl as cw
import content_firewall as cf


def _content(n_items, item_role="listitem"):
    """A raw node-list: one `main` landmark + n_items identical content children.
    content_fingerprint counts main + all children (main is a non-chrome landmark)."""
    nodes = [{"id": 0, "parent": None, "role": "region", "aria_role": "main"}]
    for i in range(n_items):
        nodes.append({"id": i + 1, "parent": 0, "role": item_role,
                      "aria_role": None, "text_len": 5})
    return nodes


def test_crawl_expand_keeps_only_novel_deduped(tmp_path):
    routes = tmp_path / "routes"
    routes.mkdir()
    seed_nodes = _content(25, "listitem")               # seed template
    seed_fp = cw.content_fingerprint(seed_nodes)
    novel_nodes = _content(25, "article")               # different role -> novel
    frontier = [
        ("ex.com/same", "https://ex.com/same", 0),      # == seed -> not_novel
        ("ex.com/n1", "https://ex.com/n1", 0),          # novel -> kept r01
        ("ex.com/n2", "https://ex.com/n2", 1),          # dup of n1
        ("ex.com/tiny", "https://ex.com/tiny", 0),      # 6 nodes -> subfloor
    ]
    fake_nodes = {
        "https://ex.com/same": seed_nodes,
        "https://ex.com/n1": novel_nodes,
        "https://ex.com/n2": novel_nodes,
        "https://ex.com/tiny": _content(5, "listitem"),
    }

    def fake_skel(href, transport):
        return fake_nodes[href]

    def fake_capture(href, route_dir):
        route_dir = Path(route_dir)
        route_dir.mkdir(parents=True, exist_ok=True)
        (route_dir / "skeleton.json").write_text(json.dumps({"nodes": fake_nodes[href]}))
        return True, len(fake_nodes[href]), fake_nodes[href]

    rows, raw_by_rid, norm_by_rid, ledger, nxt = SC.crawl_expand(
        frontier, [seed_fp], routes, start_idx=1, transport=[],
        T=0.5, floor=20, robots_allow=lambda h: True,
        skeleton_nodes=fake_skel, capture_page=fake_capture,
        sleep=lambda s: None, delay=0.0)

    assert [r["route_id"] for r in rows] == ["r01"]
    assert rows[0]["discovered"] is True and "url" not in rows[0]
    assert rows[0]["via"] == "r00"
    assert rows[0]["bundle"] == "routes/r01" and rows[0]["ok"] is True
    assert ledger == {"subfloor": 1, "not_novel": 1, "dup": 1,
                      "robots_blocked": 0, "failed": 0}
    assert nxt == 2
    assert norm_by_rid == {"r01": "ex.com/n1"} and "r01" in raw_by_rid


def test_crawl_expand_robots_blocked_counts(tmp_path):
    routes = tmp_path / "routes"
    routes.mkdir()
    seed_fp = cw.content_fingerprint(_content(25))
    frontier = [("ex.com/x", "https://ex.com/x", 0)]
    rows, _r, _n, ledger, nxt = SC.crawl_expand(
        frontier, [seed_fp], routes, 1, [], T=0.5, floor=20,
        robots_allow=lambda h: False,
        skeleton_nodes=lambda h, t: _content(25),
        capture_page=lambda h, d: (True, 26, _content(25)),
        sleep=lambda s: None, delay=0.0)
    assert rows == [] and ledger["robots_blocked"] == 1 and nxt == 1


def test_crawl_expand_zero_yield_is_graceful_noop(tmp_path):
    routes = tmp_path / "routes"
    routes.mkdir()
    seed_nodes = _content(25)
    seed_fp = cw.content_fingerprint(seed_nodes)
    frontier = [("ex.com/same", "https://ex.com/same", 0)]
    rows, _r, _n, ledger, nxt = SC.crawl_expand(
        frontier, [seed_fp], routes, 1, [], T=0.5, floor=20,
        robots_allow=lambda h: True,
        skeleton_nodes=lambda h, t: seed_nodes,
        capture_page=lambda h, d: (True, 26, seed_nodes),
        sleep=lambda s: None, delay=0.0)
    assert rows == [] and ledger["not_novel"] == 1 and nxt == 1


def test_crawl_expand_capture_failure_counts_failed(tmp_path):
    routes = tmp_path / "routes"
    routes.mkdir()
    seed_fp = cw.content_fingerprint(_content(25))
    frontier = [("ex.com/n1", "https://ex.com/n1", 0)]
    rows, _r, _n, ledger, nxt = SC.crawl_expand(
        frontier, [seed_fp], routes, 1, [], T=0.5, floor=20,
        robots_allow=lambda h: True,
        skeleton_nodes=lambda h, t: _content(25, "article"),   # novel -> accepted...
        capture_page=lambda h, d: (False, None, []),           # ...but full capture fails
        sleep=lambda s: None, delay=0.0)
    assert rows == [] and ledger["failed"] == 1 and nxt == 1


def test_capture_route_failure_returns_five_tuple(tmp_path, monkeypatch):
    class _R:
        returncode = 1
    monkeypatch.setattr(SC, "_run", lambda cmd: _R())
    res = SC.capture_route("https://x.com/", tmp_path / "r00", transport=[])
    assert res == (False, None, "skeleton_failed", [], [])


def test_crawl_expand_multiple_keeps_advance_index(tmp_path):
    # Two mutually-distinct novel pages -> both kept, rid + via + maps advance correctly.
    routes = tmp_path / "routes"
    routes.mkdir()
    seed_fp = cw.content_fingerprint(_content(25, "listitem"))
    a = _content(25, "article")        # novel template A
    b = _content(25, "heading")        # novel template B, distinct from A
    frontier = [
        ("ex.com/a", "https://ex.com/a", 0),
        ("ex.com/b", "https://ex.com/b", 1),
    ]
    fake_nodes = {"https://ex.com/a": a, "https://ex.com/b": b}

    def fake_skel(href, transport):
        return fake_nodes[href]

    def fake_capture(href, route_dir):
        Path(route_dir).mkdir(parents=True, exist_ok=True)
        return True, len(fake_nodes[href]), fake_nodes[href]

    rows, raw_by_rid, norm_by_rid, ledger, nxt = SC.crawl_expand(
        frontier, [seed_fp], routes, start_idx=1, transport=[],
        T=0.5, floor=20, robots_allow=lambda h: True,
        skeleton_nodes=fake_skel, capture_page=fake_capture,
        sleep=lambda s: None, delay=0.0)

    assert [r["route_id"] for r in rows] == ["r01", "r02"]
    assert [r["via"] for r in rows] == ["r00", "r01"]
    assert nxt == 3
    assert set(raw_by_rid) == {"r01", "r02"}
    assert norm_by_rid == {"r01": "ex.com/a", "r02": "ex.com/b"}
    assert ledger == {"subfloor": 0, "not_novel": 0, "dup": 0,
                      "robots_blocked": 0, "failed": 0}


def test_resolve_combined_edges_links_seed_and_discovered():
    urls = ["https://ex.com/", "https://ex.com/docs"]
    seed0 = [{"id": 0, "parent": None, "role": "region", "aria_role": "main"},
             {"id": 1, "parent": 0, "role": "link", "aria_role": None,
              "href": "https://ex.com/blog"}]               # seed -> discovered
    seed1 = [{"id": 0, "parent": None, "role": "region", "aria_role": "main"}]
    disc = [{"id": 0, "parent": None, "role": "region", "aria_role": "main"},
            {"id": 1, "parent": 0, "role": "link", "aria_role": None,
             "href": "https://ex.com/docs"}]                # discovered -> seed
    routes_raw = {0: seed0, 1: seed1, 2: disc}
    norm_by_rid = {"r02": "ex.com/blog"}
    edges = SC._resolve_combined_edges(routes_raw, urls, norm_by_rid)
    assert {"src": "r00", "dst": "r02", "src_node": 1, "chrome": False} in edges
    assert {"src": "r02", "dst": "r01", "src_node": 1, "chrome": False} in edges


def test_capture_site_crawl_branch_offline(tmp_path, monkeypatch):
    """End-to-end crawl branch with capture stubbed: a seed links to one novel discovered
    page; assert the discovered row has no url, carries via, nav_edges connect them, and the
    firewall backstop is clean. Injectables are passed via the `crawl` dict (no reliance on
    default-arg binding); seed captures go through a monkeypatched capture_route."""

    def _redacted(nodes):
        # mimic bundle_writer: hrefs are stripped before skeleton.json is written to disk
        return [{k: v for k, v in n.items() if k != "href"} for n in nodes]

    seed_nodes = [{"id": 0, "parent": None, "role": "region", "aria_role": "main"},
                  {"id": 1, "parent": 0, "role": "link", "aria_role": None,
                   "href": "https://ex.com/blog"}] + \
                 [{"id": i + 2, "parent": 0, "role": "listitem", "aria_role": None,
                   "text_len": 5} for i in range(22)]
    disc_nodes = [{"id": 0, "parent": None, "role": "region", "aria_role": "main"}] + \
                 [{"id": i + 1, "parent": 0, "role": "article", "aria_role": None,
                   "text_len": 9} for i in range(24)]
    by_url = {"https://ex.com/": seed_nodes, "https://ex.com/blog": disc_nodes}

    def _write_bundle(route_dir, nodes):
        route_dir = Path(route_dir)
        route_dir.mkdir(parents=True, exist_ok=True)
        (route_dir / "skeleton.json").write_text(json.dumps({"nodes": _redacted(nodes)}))
        (route_dir / "tokens.json").write_text(
            json.dumps({"palette": {}, "type_scale": [], "spacing": []}))

    def fake_capture_route(url, route_dir, transport, sweep=None, route_map=None, src_id=None):
        nodes = by_url[url]
        _write_bundle(route_dir, nodes)
        return (True, len(nodes), None, [], nodes)       # raw nodes (href intact) in-memory

    def fake_capture_page(href, route_dir):
        nodes = by_url[href]
        _write_bundle(route_dir, nodes)
        return (True, len(nodes), nodes)

    monkeypatch.setattr(SC, "capture_route", fake_capture_route)   # seed captures

    out = tmp_path / "site_out"
    crawl = {"T": 0.5, "floor": 20, "max": 40, "delay": 0.0, "ua": "probe-runner/1.0",
             "sleep": (lambda s: None), "robots_allow": (lambda h: True),
             "skeleton_nodes": (lambda href, transport: by_url[href]),
             "capture_page": fake_capture_page}
    manifest = SC.capture_site(["https://ex.com/"], str(out), transport=[], crawl=crawl)

    discovered = [r for r in manifest["routes"] if r.get("discovered")]
    assert len(discovered) == 1
    assert "url" not in discovered[0] and discovered[0]["via"] == "r00"
    assert any(e["src"] == "r00" and e["dst"] == "r01" for e in manifest["nav_edges"])
    assert manifest["crawl"]["kept"] == 1 and manifest["crawl"]["cross_origin_dropped"] == 0
    site_text = (out / "site.json").read_text()
    assert "blog" not in site_text                       # discovered href never persisted
    assert cf.audit_bundle(out) == []                    # firewall backstop clean
