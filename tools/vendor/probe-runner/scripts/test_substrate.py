import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _substrate import classify_substrate


def test_canvas_is_substrate():
    assert classify_substrate("CANVAS") == "canvas"
    assert classify_substrate("canvas") == "canvas"  # case-insensitive


def test_video_is_substrate():
    assert classify_substrate("VIDEO") == "video"


def test_captured_iframe_is_not_flagged():
    # document captured (same-origin OR same-site cross-origin) -> reproducible.
    assert classify_substrate("IFRAME", captured=True) is None
    assert classify_substrate("FRAME", captured=True) is None


def test_uncaptured_iframe_is_flagged():
    # cross-SITE OOPIF: document NOT in the snapshot -> opaque.
    assert classify_substrate("IFRAME", captured=False) == "iframe_uncaptured"
    assert classify_substrate("FRAME", captured=False) == "iframe_uncaptured"


def test_iframe_without_capture_signal_is_not_flagged():
    # default/None (no signal) errs toward reproducible — never over-flag.
    assert classify_substrate("IFRAME") is None
    assert classify_substrate("IFRAME", captured=None) is None


def test_plain_image_tags_are_never_substrate():
    # IMG/PICTURE/SOURCE/SVG are swappable slots, reproducible — not substrate.
    for t in ("IMG", "PICTURE", "SOURCE", "SVG", "DIV", "H1", ""):
        assert classify_substrate(t) is None
        assert classify_substrate(t, captured=False) is None


from _substrate import collect_substrate


def _node(nid, role, kind=None, x=0, y=0, w=10, h=10, z=0):
    n = {"id": nid, "role": role, "bbox": {"x": x, "y": y, "w": w, "h": h}, "z": z}
    if kind is not None:
        n["substrate"] = kind
    return n


def test_collect_builds_regions_and_kind_counts():
    nodes = [
        _node(0, "box"),                              # no substrate -> skipped
        _node(1, "image", kind="canvas", z=3),
        _node(2, "image", kind="video"),
        _node(3, "unknown_box", kind="iframe_uncaptured"),
        _node(4, "image"),                            # plain image -> skipped
    ]
    m = collect_substrate(nodes, url="http://x/")
    assert m["schema"] == "probe-substrate/1"
    assert m["url"] == "http://x/"
    assert m["n_regions"] == 3
    assert m["kinds"] == {"canvas": 1, "video": 1, "iframe_uncaptured": 1}
    canvas = next(r for r in m["regions"] if r["kind"] == "canvas")
    assert canvas == {"node_id": 1, "kind": "canvas",
                      "role": "image", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10}, "z": 3}


def test_collect_is_content_free():
    # a region descriptor must carry ONLY geometry/mechanism keys, never content.
    m = collect_substrate([_node(0, "image", kind="canvas")])
    assert set(m["regions"][0].keys()) == {"node_id", "kind", "role", "bbox", "z"}


def test_collect_empty_when_no_substrate():
    m = collect_substrate([_node(0, "box"), _node(1, "text")])
    assert m["n_regions"] == 0 and m["regions"] == [] and m["kinds"] == {}


def test_collect_skips_empty_string_substrate():
    # an empty-string marker is falsy -> skipped (no region with kind="").
    # pins the `if not kind:` contract against a future tightening to `is None`.
    nodes = [_node(0, "image"), _node(1, "image")]
    nodes[1]["substrate"] = ""
    m = collect_substrate(nodes)
    assert m["n_regions"] == 0 and m["regions"] == []


def test_collect_handles_none_nodes():
    # a None nodes list must yield an empty, well-formed manifest, not crash.
    m = collect_substrate(None)
    assert m["schema"] == "probe-substrate/1"
    assert m["n_regions"] == 0 and m["regions"] == [] and m["kinds"] == {}
