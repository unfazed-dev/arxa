import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import site_capture as SC


def test_edges_from_skeleton_resolves_chrome_and_content():
    # raw _sk.json node-list (REAL post-to_skeleton/enrich_aria shape: `role` + `aria_role` +
    # `parent` + `href`; NO `tag`). Anchors are identified by HREF PRESENCE, not tag/role.
    sk_nodes = [
        {"id": 0, "parent": None, "role": "unknown_box", "aria_role": None},
        {"id": 1, "parent": 0, "role": "unknown_box", "aria_role": "navigation"},
        {"id": 2, "parent": 1, "role": "link", "aria_role": None, "href": "https://x.com/a"},  # chrome -> route1
        {"id": 3, "parent": 0, "role": "unknown_box", "aria_role": "main"},
        {"id": 4, "parent": 3, "role": "link", "aria_role": None, "href": "https://x.com/b"},   # content -> route2
        {"id": 5, "parent": 3, "role": "link", "aria_role": None, "href": "https://x.com/"},    # self -> drop
    ]
    route_map = {"x.com/": 0, "x.com/a": 1, "x.com/b": 2}
    edges = SC._edges_from_skeleton(sk_nodes, route_map, src_id=0)
    assert edges == [
        {"src": 0, "dst": 1, "src_node": 2, "chrome": True},
        {"src": 0, "dst": 2, "src_node": 4, "chrome": False},
    ]
