import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import _nav


def test_normalize_url_canonicalizes_host_path_and_drops_query_fragment():
    assert _nav.normalize_url("https://www.Example.com/About/") == "example.com/about"
    assert _nav.normalize_url("http://example.com/about") == "example.com/about"
    assert _nav.normalize_url("https://example.com/") == "example.com/"
    assert _nav.normalize_url("https://example.com/x/?q=1#frag") == "example.com/x"
    assert _nav.normalize_url("mailto:a@b.com") is None
    assert _nav.normalize_url("javascript:void(0)") is None
    assert _nav.normalize_url("") is None


def test_build_route_map_first_wins():
    urls = ["https://x.com/", "https://x.com/a/", "https://www.x.com/a"]  # last collides with [1]
    rm = _nav.build_route_map(urls)
    assert rm == {"x.com/": 0, "x.com/a": 1}


def test_resolve_edges_keeps_other_route_drops_self_external_unresolved():
    rm = {"x.com/": 0, "x.com/a": 1, "x.com/b": 2}
    anchors = [
        {"node": 10, "href": "https://x.com/a", "chrome": True},    # -> route 1 (other)
        {"node": 11, "href": "https://x.com/",  "chrome": True},    # -> route 0 == src -> self, drop
        {"node": 12, "href": "https://other.com/z", "chrome": False},  # external, drop
        {"node": 13, "href": "mailto:a@b.com", "chrome": False},    # non-http, drop
        {"node": 14, "href": "https://x.com/b", "chrome": False},   # -> route 2 (content edge)
    ]
    edges = _nav.resolve_edges(anchors, rm, src_id=0)
    assert edges == [
        {"src": 0, "dst": 1, "src_node": 10, "chrome": True},
        {"src": 0, "dst": 2, "src_node": 14, "chrome": False},
    ]


def _sk(nodes):
    # nodes: list of {"id","parent","aria_role"}; returns by_id + by helper
    return {n["id"]: n for n in nodes}


def test_classify_chrome_true_under_navigation_false_under_main():
    nodes = [
        {"id": 0, "parent": None, "aria_role": None},
        {"id": 1, "parent": 0, "aria_role": "navigation"},
        {"id": 2, "parent": 1, "aria_role": None},        # anchor under navigation -> chrome
        {"id": 3, "parent": 0, "aria_role": "main"},
        {"id": 4, "parent": 3, "aria_role": None},        # anchor under main -> not chrome
    ]
    by_id = _sk(nodes)
    assert _nav.classify_chrome(2, by_id) is True
    assert _nav.classify_chrome(4, by_id) is False
    # a banner ancestor higher up also counts (nearest landmark wins; here only one on the path)
    assert _nav.classify_chrome(0, by_id) is False       # root, no landmark ancestor
