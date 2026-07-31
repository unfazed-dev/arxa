# test_slots.py
import slots


def _n(nid, role, **extra):
    n = {"id": nid, "role": role, "bbox": {"x": 0, "y": 0, "w": 120, "h": 60},
         "token_ref": {"bg": "surface", "border": None}, "anim_ref": ["a#tx"]}
    n.update(extra)
    return n


def test_build_slots_one_typed_slot_per_content_node_with_index():
    nodes = [
        _n(1, "image"),
        _n(2, "text", text_len=10,
           font={"size": 32, "weight": 700, "line": 40, "family": "Inter"}),
        _n(3, "svg", bbox={"x": 0, "y": 0, "w": 24, "h": 24}),
        _n(4, "box"),  # mechanism -> no slot
    ]
    out = slots.build_slots(nodes)
    kinds = {s["type"] for s in out["slots"]}
    assert kinds == {"image", "text", "svg"}           # box excluded
    assert out["index"] == [1, 2, 3]                    # node ids, ordered
    img = next(s for s in out["slots"] if s["type"] == "image")
    assert img["box"]["w"] == 120 and img["aspect_ratio"] == 2.0
    assert img["theme_ref"] == {"bg": "surface", "border": None}
    assert img["anim_ref"] == ["a#tx"]
    txt = next(s for s in out["slots"] if s["type"] == "text")
    assert txt["text_class"]["char_len_bucket"] == "short"   # 10 chars
    svg = next(s for s in out["slots"] if s["type"] == "svg")
    assert svg["svg_class"] == "icon" and svg["fill_hint"]


def test_text_len_buckets_vary():
    short = slots._char_bucket(8)
    medium = slots._char_bucket(60)
    long_ = slots._char_bucket(400)
    assert (short, medium, long_) == ("short", "medium", "long")
