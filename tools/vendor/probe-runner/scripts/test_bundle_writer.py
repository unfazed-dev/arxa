"""Tests for bundle_writer — Phase D of the probe-runner capture engine.
TDD: tests appended per task (D1–D4); implementation in bundle_writer.py."""
import pytest
import bundle_writer as bw

# ---------------------------------------------------------------------------
# Synthetic motion fixture (generic — the engine reads motion from an external
# capture, never a baked literal). Two scroll rows + one time row, enough to
# exercise field-shape, nearest-in-band matching, and class/source variety.
# ---------------------------------------------------------------------------
SYN_MOTION = [
    {"name": "hero_bg_parallax", "anchor": 1774, "easing": "ease-out",
     "cubic_bezier": [0, 0, 0.58, 1], "amplitude": -218.5, "axis": "ty",
     "window": [0, 1219], "klass": "scroll", "source": "web_anim", "rms": 0.016},
    {"name": "intro_lede", "anchor": 2183, "easing": "easeOutCubic",
     "cubic_bezier": [0.33, 1, 0.68, 1], "amplitude": 24, "axis": "ty",
     "window": [871, 1161], "klass": "scroll", "source": "web_anim", "rms": 0.033},
    {"name": "menu_marquee", "anchor": 21829, "easing": "linear",
     "cubic_bezier": [0, 0, 1, 1], "amplitude": 1100, "axis": "tx",
     "window": [0, 0], "klass": "time", "source": "flipbook", "rms": 0.0},
]


# ---------------------------------------------------------------------------
# D1 tests — module header + match_motion
# ---------------------------------------------------------------------------

def test_motion_fixture_has_required_fields():
    for row in SYN_MOTION:
        for k in ("name", "anchor", "easing", "cubic_bezier", "amplitude",
                  "axis", "window", "klass", "source", "rms"):
            assert k in row, f"{row.get('name')} missing {k}"
        assert isinstance(row["cubic_bezier"], list) and len(row["cubic_bezier"]) == 4
        assert row["klass"] in ("scroll", "time")
        assert row["source"] in ("web_anim", "flipbook")


def test_match_motion_assigns_nearest_in_band():
    nodes = [
        {"id": 0, "role": "image", "bbox": {"x": 0, "y": 1774, "w": 600, "h": 96}, "anim_ref": None},
        {"id": 1, "role": "text", "bbox": {"x": 0, "y": 2183, "w": 600, "h": 96}, "anim_ref": None},
        {"id": 2, "role": "box", "bbox": {"x": 0, "y": 9000, "w": 10, "h": 10}, "anim_ref": None},
    ]
    rows = bw.match_motion(nodes, SYN_MOTION, band=400.0)
    by_id = {r["node_id"]: r for r in rows}
    assert 0 in by_id            # hero image (y=1774) matched
    assert 2 not in by_id        # no in-band anchor near y=9000
    assert nodes[0]["anim_ref"] is not None
    assert nodes[2]["anim_ref"] is None


# Two co-located movers (same y, different x) — the kasane mirror-hero case.
# Each h1 sits at y=365; only center-x distinguishes them. Opposite-sign tx amps.
CO_LOCATED_MOTION = [
    {"name": "h1#0#tx", "anchor": 365, "anchor_x": 395, "easing": "ease-out",
     "cubic_bezier": [0, 0, 0.58, 1], "amplitude": -648, "axis": "x",
     "window": [165, 1088], "klass": "scroll", "source": "web_anim", "rms": 0.018},
    {"name": "h1#1#tx", "anchor": 365, "anchor_x": 1053, "easing": "ease-out",
     "cubic_bezier": [0, 0, 0.58, 1], "amplitude": 648, "axis": "x",
     "window": [165, 1088], "klass": "scroll", "source": "web_anim", "rms": 0.018},
]


def test_match_motion_2d_binds_co_located_to_distinct_nodes():
    # Two word-nodes at the SAME y=365, different x. y-only binding would collapse
    # both onto one node; center-x must split them to their correct distinct nodes.
    nodes = [
        {"id": 80, "role": "text", "bbox": {"x": 189, "y": 365, "w": 414, "h": 78}, "anim_ref": None},
        {"id": 84, "role": "text", "bbox": {"x": 854, "y": 365, "w": 397, "h": 78}, "anim_ref": None},
    ]
    rows = bw.match_motion(nodes, CO_LOCATED_MOTION, band=400.0)
    by_name = {r["name"]: r for r in rows}
    # left mover (anchor_x 395) -> node 80 (center 396); right (1053) -> node 84 (center 1052)
    assert by_name["h1#0#tx"]["node_id"] == 80
    assert by_name["h1#1#tx"]["node_id"] == 84
    # the SPECIFIC assignment: left node carries the negative (leftward) amp,
    # right node the positive — the mirror is preserved end-to-end.
    assert by_name["h1#0#tx"]["amplitude"] < 0 < by_name["h1#1#tx"]["amplitude"]


def test_match_motion_anim_ref_is_list_appends_multiple_channels():
    # one node animated on two channels -> anim_ref is a LIST of both names,
    # never an overwriting scalar.
    nodes = [{"id": 5, "role": "text", "bbox": {"x": 100, "y": 365, "w": 200, "h": 50}, "anim_ref": None}]
    motion = [
        {"name": "h1#0#tx", "anchor": 365, "anchor_x": 200, "easing": "ease-out",
         "cubic_bezier": [0, 0, 0.58, 1], "amplitude": -648, "axis": "x",
         "window": [165, 1088], "klass": "scroll", "source": "web_anim", "rms": 0.018},
        {"name": "h1#0#op", "anchor": 365, "anchor_x": 200, "easing": "ease-out",
         "cubic_bezier": [0, 0, 0.58, 1], "amplitude": -0.75, "axis": "opacity",
         "window": [165, 1088], "klass": "scroll", "source": "web_anim", "rms": 0.018},
    ]
    bw.match_motion(nodes, motion, band=400.0)
    assert nodes[0]["anim_ref"] == ["h1#0#tx", "h1#0#op"]


def test_match_motion_passes_anchor_x_through():
    nodes = [{"id": 80, "role": "text", "bbox": {"x": 189, "y": 365, "w": 414, "h": 78}, "anim_ref": None}]
    rows = bw.match_motion(nodes, [CO_LOCATED_MOTION[0]], band=400.0)
    assert rows[0]["anchor_x"] == 395


# ---------------------------------------------------------------------------
# D2 tests — derive_slots
# ---------------------------------------------------------------------------

def test_derive_slots_per_role():
    nodes = [
        {"id": 0, "role": "image", "bbox": {"x": 0, "y": 0, "w": 200, "h": 100},
         "sizing": {"w": "fill", "h": "fixed", "confidence": "high"}},
        {"id": 1, "role": "text", "bbox": {"x": 0, "y": 0, "w": 100, "h": 20},
         "sizing": {"w": "hug", "h": "hug", "confidence": "high"},
         "font": {"size": 16.0, "weight": 400}, "text_len": 18},
        {"id": 2, "role": "svg", "bbox": {"x": 0, "y": 0, "w": 50, "h": 50},
         "sizing": {"w": "fixed", "h": "fixed", "confidence": "high"}},
        {"id": 3, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
         "sizing": {"w": "fill", "h": "hug", "confidence": "high"}},
    ]
    slots = bw.derive_slots(nodes)
    by_id = {s["node_id"]: s for s in slots}
    assert set(by_id) == {0, 1, 2}              # box (id 3) structural, no slot
    assert by_id[0]["kind"] == "image"
    assert by_id[0]["aspect"] == 2.0            # 200/100
    assert by_id[0]["sizing"] == nodes[0]["sizing"]
    assert by_id[1]["kind"] == "text"
    assert by_id[1]["font"]["size"] == 16.0
    assert by_id[1]["suggested_max_glyphs"] == 27   # text_len 18 * 1.5
    assert by_id[2]["kind"] == "svg"
    assert by_id[2]["aspect"] == 1.0
    assert by_id[2]["vec_ref"] is None


# ---------------------------------------------------------------------------
# D3 tests — apply_token_refs
# ---------------------------------------------------------------------------

def test_apply_token_refs_maps_nearest_role():
    palette = {"background": "#0b0b0c", "surface": "#15151a",
               "fg-primary": "#f5f5f0", "fg-muted": "#9a9a93",
               "accent": "#c8552a", "border": "#2a2a30"}
    nodes = [{"id": 0, "role": "text",
              "token_ref": {"bg": None, "fg": None, "border": None}}]
    node_colors = {0: {"bg": "rgb(21,21,26)", "fg": "rgb(245,245,240)",
                       "border": "rgb(42,42,48)"}}
    bw.apply_token_refs(nodes, palette, node_colors)
    tr = nodes[0]["token_ref"]
    assert tr["bg"] == "surface"       # #15151a
    assert tr["fg"] == "fg-primary"    # #f5f5f0
    assert tr["border"] == "border"    # #2a2a30


def test_apply_token_refs_leaves_none_for_transparent():
    palette = {"background": "#0b0b0c"}
    nodes = [{"id": 0, "role": "box", "token_ref": {"bg": None, "fg": None, "border": None}}]
    node_colors = {0: {"bg": "rgba(0,0,0,0)", "fg": None, "border": None}}
    bw.apply_token_refs(nodes, palette, node_colors)
    assert nodes[0]["token_ref"]["bg"] is None


# ---------------------------------------------------------------------------
# D4 tests — assemble + write_bundle
# ---------------------------------------------------------------------------

def test_assemble_builds_core_bundle_keys():
    skeleton = {"schema": "probe-skeleton/2", "url": "u",
                "viewport": {"w": 1440, "h": 887, "dpr": 2},
                "page": {"w": 1440, "h": 35137},
                "nodes": [
                    {"id": 0, "role": "image", "bbox": {"x": 0, "y": 1774, "w": 600, "h": 96},
                     "sizing": {"w": "fill", "h": "fixed", "confidence": "high"},
                     "token_ref": {"bg": None, "fg": None, "border": None}, "anim_ref": None},
                ]}
    tokens = {"palette": {"background": "#0b0b0c"}, "type_scale": [16, 64]}
    node_colors = {0: {"bg": "rgb(11,11,12)", "fg": None, "border": None}}
    bundle = bw.assemble(skeleton, tokens, node_colors, SYN_MOTION,
                         meta_extra={"timestamp": "2026-05-28T00:00:00Z"})
    assert set(bundle.keys()) == {"meta", "skeleton", "tokens", "motion", "manifest", "substrate"}
    assert bundle["meta"]["url"] == "u"
    assert bundle["meta"]["viewport"] == {"w": 1440, "h": 887, "dpr": 2}
    assert bundle["meta"]["page"] == {"w": 1440, "h": 35137}
    # motion: hero image (y=1774) matched the hero_bg_parallax row
    assert any(r["node_id"] == 0 for r in bundle["motion"])
    assert bundle["skeleton"]["nodes"][0]["anim_ref"] == ["hero_bg_parallax"]
    # token_ref resolved
    assert bundle["skeleton"]["nodes"][0]["token_ref"]["bg"] == "background"
    # manifest slot for the image (build_slots schema: id/type, + index)
    assert any(s["id"] == 0 and s["type"] == "image" for s in bundle["manifest"]["slots"])
    assert bundle["manifest"]["index"] == [0]   # build_slots adds the id index


def test_write_bundle_creates_files(tmp_path):
    skeleton = {"schema": "probe-skeleton/2", "url": "u",
                "viewport": {"w": 1, "h": 1, "dpr": 1}, "page": {"w": 1, "h": 1},
                "nodes": []}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={})
    bw.write_bundle(bundle, str(tmp_path))
    import os
    for f in ["meta.json", "skeleton.json", "tokens.json", "motion.json"]:
        assert os.path.exists(os.path.join(str(tmp_path), f))
    assert os.path.exists(os.path.join(str(tmp_path), "assets", "manifest.json"))


def test_write_bundle_fails_on_content_leak(tmp_path):
    # a skeleton node carrying planted prose must not survive into a written
    # bundle: write_bundle audits and raises.
    skeleton = {"url": "x", "schema": 1,
                "viewport": {"w": 1280, "h": 800, "dpr": 2}, "page": {"h": 1000},
                "nodes": [{"id": 1, "role": "text",
                           "bbox": {"x": 0, "y": 0, "w": 50, "h": 20},
                           "leaked_prose": "Handcrafted with urushi lacquer here"}]}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={})
    # force the leak past redaction to prove the audit is the backstop:
    bundle["skeleton"]["nodes"][0]["leaked_prose"] = \
        "Handcrafted with urushi lacquer applied by hand"
    with pytest.raises(bw.ContentLeak):
        bw.write_bundle(bundle, str(tmp_path))


def test_write_bundle_clean_passes(tmp_path):
    skeleton = {"url": "x", "schema": 1,
                "viewport": {"w": 1280, "h": 800, "dpr": 2}, "page": {"h": 1000},
                "nodes": [{"id": 1, "role": "box",
                           "bbox": {"x": 0, "y": 0, "w": 50, "h": 20}}]}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={})
    bw.write_bundle(bundle, str(tmp_path))   # no raise
    import os
    assert os.path.exists(os.path.join(str(tmp_path), "skeleton.json"))
    assert os.path.exists(os.path.join(str(tmp_path), "assets", "manifest.json"))


def test_write_bundle_fails_on_nonascii_leak(tmp_path):
    # inject Japanese AFTER assemble (past R3 redaction) so ONLY the audit can
    # catch it — exercises the non-ASCII detector in the write path.
    skeleton = {"url": "x", "schema": 1,
                "viewport": {"w": 1280, "h": 800, "dpr": 2}, "page": {"h": 1000},
                "nodes": [{"id": 1, "role": "box",
                           "bbox": {"x": 0, "y": 0, "w": 50, "h": 20}}]}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={})
    bundle["skeleton"]["nodes"][0]["leaked_jp"] = \
        "手作りの漆塗りキーボード。本物の製品です。"
    with pytest.raises(bw.ContentLeak):
        bw.write_bundle(bundle, str(tmp_path))


def test_assemble_redacts_content_keys_from_output_nodes():
    # R3 wired: content keys stripped from emitted skeleton nodes during
    # assemble; mechanism (text_len, bbox) kept.
    skeleton = {"url": "x", "schema": 1,
                "viewport": {"w": 1280, "h": 800, "dpr": 2}, "page": {"h": 1000},
                "nodes": [{"id": 1, "role": "image",
                           "bbox": {"x": 0, "y": 0, "w": 50, "h": 20},
                           "text": "Handcrafted lacquer keyboard",
                           "src": "https://kasane.example/p.jpg",
                           "alt": "a product photo", "text_len": 28}]}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={})
    n = bundle["skeleton"]["nodes"][0]
    for k in ("text", "src", "alt"):
        assert k not in n          # redacted (R3 in the emit path)
    assert n["text_len"] == 28     # mechanism kept
    assert n["bbox"]["w"] == 50


# ---- G4: optional states.json artifact ----

def test_assemble_omits_states_key_by_default():
    import bundle_writer as bw
    skeleton = {"schema": "probe-skeleton/2", "url": "http://x", "nodes": [],
                "viewport": {"w": 1280, "h": 800, "dpr": 1}, "page": {"w": 1280, "h": 800}}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={})
    # substrate is ALWAYS present (derived free from the skeleton); states is opt-in.
    assert set(bundle.keys()) == {"meta", "skeleton", "tokens", "motion", "manifest", "substrate"}
    assert "states" not in bundle


def test_write_bundle_emits_states_json_and_passes_audit(tmp_path):
    import json, bundle_writer as bw
    skeleton = {"schema": "probe-skeleton/2", "url": "http://x", "nodes": [],
                "viewport": {"w": 1280, "h": 800, "dpr": 1}, "page": {"w": 1280, "h": 800}}
    states = {"schema": "probe-states/1", "url": "http://x", "base_nodes": 0,
              "states": [{"trigger": {"selector": "html > body > button:nth-of-type(1)",
                                       "kind": "menu", "action": "click"},
                          "n_appeared": 2,
                          "appeared": [{"role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10}, "z": 0},
                                       {"role": "box", "bbox": {"x": 0, "y": 20, "w": 10, "h": 10}, "z": 0}]}]}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={}, states=states)
    assert bundle["states"] == states
    bw.write_bundle(bundle, str(tmp_path))      # must NOT raise ContentLeak
    written = json.loads((tmp_path / "states.json").read_text())
    assert written["states"][0]["trigger"]["kind"] == "menu"


def test_write_bundle_emits_substrate_json_and_passes_audit(tmp_path):
    import json
    skeleton = {
        "schema": "probe-skeleton/2", "url": "http://x/",
        "viewport": {"w": 200, "h": 120, "dpr": 1.0}, "page": {"w": 200, "h": 640},
        "nodes": [
            {"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 200, "h": 40},
             "z": 0, "parent": None, "sizing": {"w": "fill", "h": "fixed", "confidence": "high"},
             "layout": {"mode": "block", "direction": "row", "gap": 0.0, "pad": [0, 0, 0, 0],
                        "justify": "normal", "align": "normal", "grid_cols": None, "grid_rows": None},
             "token_ref": {"bg": None, "fg": None, "border": None}, "anim_ref": None},
            {"id": 1, "role": "image", "bbox": {"x": 0, "y": 130, "w": 200, "h": 120},
             "z": 1, "parent": 0, "sizing": {"w": "fixed", "h": "fixed", "confidence": "high"},
             "layout": {"mode": "block", "direction": "row", "gap": 0.0, "pad": [0, 0, 0, 0],
                        "justify": "normal", "align": "normal", "grid_cols": None, "grid_rows": None},
             "token_ref": {"bg": None, "fg": None, "border": None}, "anim_ref": None,
             "substrate": "canvas"},
        ],
    }
    tokens = {"palette": {}, "type": {}, "spacing": [], "radii": [], "shadows": []}
    bundle = bw.assemble(skeleton, tokens, node_colors={}, motion_rows=[], meta_extra={})
    assert bundle["substrate"]["schema"] == "probe-substrate/1"
    assert bundle["substrate"]["n_regions"] == 1
    assert bundle["substrate"]["kinds"] == {"canvas": 1}
    out = tmp_path / "bundle"
    bw.write_bundle(bundle, str(out))   # raises ContentLeak if the firewall finds content
    written = json.loads((out / "substrate.json").read_text())
    assert written["regions"][0]["kind"] == "canvas"
    assert set(written["regions"][0].keys()) == {"node_id", "kind", "role", "bbox", "z"}


def test_write_bundle_emits_empty_substrate_when_no_substrate_nodes(tmp_path):
    import json
    skeleton = {
        "schema": "probe-skeleton/2", "url": "http://x/",
        "viewport": {"w": 200, "h": 120, "dpr": 1.0}, "page": {"w": 200, "h": 200},
        "nodes": [
            {"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 200, "h": 40},
             "z": 0, "parent": None, "sizing": {"w": "fill", "h": "fixed", "confidence": "high"},
             "layout": {"mode": "block", "direction": "row", "gap": 0.0, "pad": [0, 0, 0, 0],
                        "justify": "normal", "align": "normal", "grid_cols": None, "grid_rows": None},
             "token_ref": {"bg": None, "fg": None, "border": None}, "anim_ref": None},
        ],
    }
    tokens = {"palette": {}, "type": {}, "spacing": [], "radii": [], "shadows": []}
    bundle = bw.assemble(skeleton, tokens, node_colors={}, motion_rows=[], meta_extra={})
    assert bundle["substrate"]["n_regions"] == 0
    assert bundle["substrate"]["regions"] == [] and bundle["substrate"]["kinds"] == {}
    out = tmp_path / "bundle"
    bw.write_bundle(bundle, str(out))   # raises ContentLeak if the firewall finds content
    written = json.loads((out / "substrate.json").read_text())
    assert written["schema"] == "probe-substrate/1" and written["n_regions"] == 0


# ---------------------------------------------------------------------------
# D5 tests — apply_node_style + node_style threading through assemble
# ---------------------------------------------------------------------------

def test_apply_node_style_redacts_and_attaches():
    nodes = [{"id": 0, "role": "box"}, {"id": 1, "role": "box"}]
    node_style = {0: {"filter": "blur(4px)", "background-image": 'url("https://cdn/x.png")',
                      "clip-path": "url(#c)"}}
    bw.apply_node_style(nodes, node_style)
    assert nodes[0]["style"] == {"filter": "blur(4px)",
                                 "background-image": 'url("<asset>")', "clip-path": "url(#c)"}
    assert "style" not in nodes[1]   # no entry -> no field


def test_apply_node_style_none_is_noop():
    nodes = [{"id": 0, "role": "box"}]
    bw.apply_node_style(nodes, None)
    assert "style" not in nodes[0]


def test_assemble_attaches_redacted_style_surviving_redact_node():
    skeleton = {"schema": "probe-skeleton/2", "url": "u",
                "viewport": {"w": 100, "h": 100, "dpr": 1}, "page": {"w": 100, "h": 100},
                "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                           "sizing": {"w": "fixed", "h": "fixed", "confidence": "high"},
                           "token_ref": {"bg": None, "fg": None, "border": None},
                           "anim_ref": None}]}
    node_style = {0: {"filter": "blur(4px)", "background-image": 'url("https://cdn/x.png")'}}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={}, node_style=node_style)
    style = bundle["skeleton"]["nodes"][0]["style"]
    assert style["filter"] == "blur(4px)"
    assert style["background-image"] == 'url("<asset>")'   # redacted, survived redact_node


def test_write_bundle_with_external_url_style_audits_clean(tmp_path):
    # full round-trip: a _node_style with an EXTERNAL url -> redacted on disk -> audit passes
    skeleton = {"schema": "probe-skeleton/2", "url": "u",
                "viewport": {"w": 100, "h": 100, "dpr": 1}, "page": {"w": 100, "h": 100},
                "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                           "token_ref": {"bg": None, "fg": None, "border": None}, "anim_ref": None}],
                "_node_style": {"0": {"background-image": 'url("https://cdn.example.com/x.png")',
                                      "clip-path": "url(#c)", "filter": "blur(2px)"}}}
    raw = skeleton.pop("_node_style")
    node_style = {int(k): v for k, v in raw.items()}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={}, node_style=node_style)
    bw.write_bundle(bundle, tmp_path)   # raises ContentLeak if redaction failed
    import json as _json
    disk = _json.loads((tmp_path / "skeleton.json").read_text())
    assert disk["nodes"][0]["style"]["background-image"] == 'url("<asset>")'
    assert disk["nodes"][0]["style"]["clip-path"] == "url(#c)"


def test_assemble_attaches_cut2_style_surviving_redact_node():
    # Cut-2 props (no url()) survive assemble's redact_node + reach the bundle intact.
    skeleton = {"schema": "probe-skeleton/2", "url": "u",
                "viewport": {"w": 100, "h": 100, "dpr": 1}, "page": {"w": 100, "h": 100},
                "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                           "token_ref": {"bg": None, "fg": None, "border": None},
                           "anim_ref": None}]}
    node_style = {0: {"text-shadow": "rgb(0, 0, 0) 1px 1px 2px", "object-fit": "cover",
                      "outline-style": "solid", "background-repeat": "no-repeat",
                      "transform-style": "preserve-3d"}}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={}, node_style=node_style)
    style = bundle["skeleton"]["nodes"][0]["style"]
    assert style["text-shadow"] == "rgb(0, 0, 0) 1px 1px 2px"
    assert style["object-fit"] == "cover"
    assert style["outline-style"] == "solid"
    assert style["background-repeat"] == "no-repeat"
    assert style["transform-style"] == "preserve-3d"


# ---------------------------------------------------------------------------
# D6 tests — apply_node_pseudo + node_pseudo threading through assemble
# ---------------------------------------------------------------------------

def test_apply_node_pseudo_redacts_and_attaches():
    nodes = [{"id": 0, "role": "box"}, {"id": 1, "role": "box"}]
    node_pseudo = {0: {"::before": {"content": '"Buy now"', "color": "rgb(1, 2, 3)"},
                       "::after": {"background-image": 'url("https://cdn/x.png")'}}}
    bw.apply_node_pseudo(nodes, node_pseudo)
    assert nodes[0]["pseudo"]["::before"]["content"] == '"<text>"'
    assert nodes[0]["pseudo"]["::before"]["color"] == "rgb(1, 2, 3)"
    assert nodes[0]["pseudo"]["::after"]["background-image"] == 'url("<asset>")'
    assert "pseudo" not in nodes[1]              # no entry -> no field


def test_apply_node_pseudo_none_is_noop():
    nodes = [{"id": 0, "role": "box"}]
    bw.apply_node_pseudo(nodes, None)
    assert "pseudo" not in nodes[0]


def test_apply_node_theme_attaches_redacted_delta():
    nodes = [{"id": 0}, {"id": 1}]
    node_theme = {0: {"dark": {"color": "rgb(240, 240, 240)",
                               "background-image": 'url("https://a/b.png")'}}}
    bw.apply_node_theme(nodes, node_theme)
    assert nodes[0]["theme"]["dark"]["color"] == "rgb(240, 240, 240)"
    assert nodes[0]["theme"]["dark"]["background-image"] == 'url("<asset>")'
    assert "theme" not in nodes[1]            # no entry -> no field


def test_apply_node_theme_none_safe():
    nodes = [{"id": 0}]
    bw.apply_node_theme(nodes, None)
    assert "theme" not in nodes[0]


def test_assemble_attaches_pseudo_surviving_redact_node():
    skeleton = {"schema": "probe-skeleton/2", "url": "u",
                "viewport": {"w": 100, "h": 100, "dpr": 1}, "page": {"w": 100, "h": 100},
                "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                           "token_ref": {"bg": None, "fg": None, "border": None},
                           "anim_ref": None}]}
    node_pseudo = {0: {"::before": {"content": '"hi"', "color": "rgb(1, 2, 3)"}}}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={},
                         node_pseudo=node_pseudo)
    ps = bundle["skeleton"]["nodes"][0]["pseudo"]
    assert ps["::before"]["content"] == '"<text>"'    # survived redact_node
    assert ps["::before"]["color"] == "rgb(1, 2, 3)"


def test_write_bundle_with_external_url_pseudo_audits_clean(tmp_path):
    # round-trip: a _node_pseudo with an external url + a long authored string ->
    # redacted on disk -> audit passes; the raw prose is absent.
    skeleton = {"schema": "probe-skeleton/2", "url": "u",
                "viewport": {"w": 100, "h": 100, "dpr": 1}, "page": {"w": 100, "h": 100},
                "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                           "token_ref": {"bg": None, "fg": None, "border": None}, "anim_ref": None}],
                "_node_pseudo": {"0": {"::after": {
                    "background-image": 'url("https://cdn.example.com/x.png")',
                    "content": '"Handcrafted urushi lacquer keyboard by artisans"'}}}}
    raw = skeleton.pop("_node_pseudo")
    node_pseudo = {int(k): v for k, v in raw.items()}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={},
                         node_pseudo=node_pseudo)
    bw.write_bundle(bundle, tmp_path)   # raises ContentLeak if redaction failed
    import json as _json
    text = (tmp_path / "skeleton.json").read_text()
    ps = _json.loads(text)["nodes"][0]["pseudo"]["::after"]
    assert ps["background-image"] == 'url("<asset>")'
    assert ps["content"] == '"<text>"'
    assert "Handcrafted" not in text     # raw prose absent on disk


def test_apply_node_pseudo_state_attaches_redacted_delta():
    nodes = [{"id": 0}, {"id": 1}]
    node_ps = {0: {"hover": {"color": "rgb(0, 128, 0)",
                             "background-image": 'url("https://a/b.png")'}}}
    bw.apply_node_pseudo_state(nodes, node_ps)
    assert nodes[0]["pseudo_state"]["hover"]["color"] == "rgb(0, 128, 0)"
    assert nodes[0]["pseudo_state"]["hover"]["background-image"] == 'url("<asset>")'
    assert "pseudo_state" not in nodes[1]            # no entry -> no field


def test_apply_node_pseudo_state_none_safe():
    nodes = [{"id": 0}]
    bw.apply_node_pseudo_state(nodes, None)
    assert "pseudo_state" not in nodes[0]


def test_apply_node_responsive_attaches_redacted_delta():
    nodes = [{"id": 0}, {"id": 1}]
    node_resp = {0: {"768": {"display": "block",
                             "background-image": 'url("https://a/b.png")'}}}
    bw.apply_node_responsive(nodes, node_resp)
    assert nodes[0]["responsive"]["768"]["display"] == "block"
    assert nodes[0]["responsive"]["768"]["background-image"] == 'url("<asset>")'
    assert "responsive" not in nodes[1]            # no entry -> no field


def test_apply_node_responsive_none_safe():
    nodes = [{"id": 0}]
    bw.apply_node_responsive(nodes, None)
    bw.apply_node_responsive(nodes, {})
    assert "responsive" not in nodes[0]


def test_apply_node_keyframes_attaches_redacted_timeline():
    nodes = [{"id": 0}, {"id": 1}]
    node_kf = {0: [{"timing": {"duration": "2s", "easing": "linear",
                               "iterations": "infinite", "direction": "normal",
                               "delay": "0s", "fill": "none"},
                    "frames": [{"offset": 0.0, "props": {"transform": "rotate(0deg)"}},
                               {"offset": 1.0, "props": {"filter": 'url("https://a/b.svg")'}}]}]}
    bw.apply_node_keyframes(nodes, node_kf)
    assert nodes[0]["keyframes"][0]["timing"]["iterations"] == "infinite"
    assert nodes[0]["keyframes"][0]["frames"][0]["props"]["transform"] == "rotate(0deg)"
    assert nodes[0]["keyframes"][0]["frames"][1]["props"]["filter"] == 'url("<asset>")'
    assert "keyframes" not in nodes[1]            # no entry -> no field


def test_apply_node_keyframes_none_safe():
    nodes = [{"id": 0}]
    bw.apply_node_keyframes(nodes, None)
    bw.apply_node_keyframes(nodes, {})
    assert "keyframes" not in nodes[0]


def test_apply_node_reduced_motion_attaches_redacted_delta():
    nodes = [{"id": 0}, {"id": 1}]
    node_rm = {0: {"reduce": {"animation-name": "none", "animation-duration": "0s",
                              "scroll-behavior": "auto"}}}
    bw.apply_node_reduced_motion(nodes, node_rm)
    assert nodes[0]["reduced_motion"]["reduce"]["animation-name"] == "none"
    assert nodes[0]["reduced_motion"]["reduce"]["scroll-behavior"] == "auto"
    assert "reduced_motion" not in nodes[1]        # no entry -> no field


def test_apply_node_reduced_motion_none_safe():
    nodes = [{"id": 0}]
    bw.apply_node_reduced_motion(nodes, None)
    bw.apply_node_reduced_motion(nodes, {})
    assert "reduced_motion" not in nodes[0]


def test_apply_node_form_state_attaches_redacted_delta():
    nodes = [{"id": 0}, {"id": 1}]
    node_fs = {0: {"checked": {"opacity": "0.5", "accent-color": "rgb(11, 22, 33)"},
                   "disabled": {"opacity": "0.4", "cursor": "not-allowed"}}}
    bw.apply_node_form_state(nodes, node_fs)
    assert nodes[0]["form_state"]["checked"]["accent-color"] == "rgb(11, 22, 33)"
    assert nodes[0]["form_state"]["disabled"]["cursor"] == "not-allowed"
    assert "form_state" not in nodes[1]        # no entry -> no field


def test_apply_node_form_state_none_safe():
    nodes = [{"id": 0}]
    bw.apply_node_form_state(nodes, None)
    bw.apply_node_form_state(nodes, {})
    assert "form_state" not in nodes[0]


def test_apply_node_container_attaches_redacted_delta():
    import bundle_writer as bw
    nodes = [{"id": 0}, {"id": 1}]
    node_container = {1: {"7@240": {"font-size": "11px", "display": "flex"}}}
    bw.apply_node_container(nodes, node_container)
    assert "container" not in nodes[0]                       # no entry -> no field
    assert nodes[1]["container"] == {"7@240": {"font-size": "11px", "display": "flex"}}


def test_apply_node_container_none_safe():
    import bundle_writer as bw
    nodes = [{"id": 0}]
    bw.apply_node_container(nodes, None)                     # must not raise
    bw.apply_node_container(nodes, {})                       # empty -> no-op
    assert "container" not in nodes[0]


def test_bundle_writer_main_exits_3_on_content_leak(tmp_path, monkeypatch, capsys):
    """A ContentLeak from write_bundle must exit 3 (distinct audit-fire code), not 1,
    and the printed marker must stay content-free (no `sample`)."""
    import sys, json
    import bundle_writer

    sk = tmp_path / "sk.json"
    tok = tmp_path / "tok.json"
    sk.write_text(json.dumps({"url": "https://e.com", "nodes": []}))
    tok.write_text(json.dumps({"palette": {}}))

    # Isolate the except path: assemble returns a dummy bundle, write_bundle raises.
    monkeypatch.setattr(bundle_writer, "assemble", lambda *a, **k: {"skeleton": {"nodes": []}})

    def boom(bundle, out_dir):
        raise bundle_writer.ContentLeak(
            "content leak in bundle X: 1 violation(s); first 1: "
            "[{'kind': 'prose', 'file': 'skeleton.json'}]")

    monkeypatch.setattr(bundle_writer, "write_bundle", boom)
    monkeypatch.setattr(sys, "argv",
                        ["bundle_writer.py", "--skeleton", str(sk), "--tokens", str(tok),
                         "--out", str(tmp_path / "b")])

    assert bundle_writer.main() == 3
    assert "sample" not in capsys.readouterr().out


def test_content_leak_message_omits_content_sample(tmp_path):
    # The ContentLeak message must NOT echo the prose `sample` (up to 40 chars of leaked
    # content); only kind + file. Guards the stderr/stdout content-free boundary.
    secret = "ZZQQX leaked prose sample marker phrase here now"
    skeleton = {"url": "x", "schema": 1,
                "viewport": {"w": 1280, "h": 800, "dpr": 2}, "page": {"h": 1000},
                "nodes": [{"id": 1, "role": "box",
                           "bbox": {"x": 0, "y": 0, "w": 50, "h": 20}}]}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={})
    # force prose past redaction so only write_bundle's audit catches it
    bundle["skeleton"]["nodes"][0]["leaked_prose"] = secret
    with pytest.raises(bw.ContentLeak) as exc_info:
        bw.write_bundle(bundle, str(tmp_path))
    msg = str(exc_info.value)
    assert secret not in msg, "ContentLeak message leaked the content sample"
    assert "prose" in msg and "skeleton.json" in msg   # kind + file still surfaced


# ---------------------------------------------------------------------------
# Task 3 — below_fold addendum redaction + audit canary
# ---------------------------------------------------------------------------
import json as _json
import content_firewall as cf


def _min_skel_with_below_fold(extra_rec=None):
    shapes = [{"key": "card|...", "role": "card",
               "sizing": {"w": 100, "h": 40, "confidence": "high"},
               "layout": {"mode": "flow"}, "token_ref": {"bg": None, "fg": None, "border": None}}]
    if extra_rec:
        shapes.append(extra_rec)
    return {"schema": "probe-skeleton/2", "url": "x", "viewport": {"dpr": 1}, "page": {},
            "nodes": [], "below_fold": {"schema": "probe-belowfold/1", "step_count": 8,
                                        "new_shapes": len(shapes), "shapes": shapes}}


def test_below_fold_survives_assemble():
    sk = _min_skel_with_below_fold()
    bundle = bw.assemble(sk, {"palette": []}, {}, [], {})
    assert bundle["skeleton"]["below_fold"]["new_shapes"] == 1
    assert bundle["skeleton"]["below_fold"]["shapes"][0]["role"] == "card"


def test_below_fold_url_canary_trips_audit(tmp_path):
    # A url(https://...) in a field NOT in CONTENT_KEYS survives key-strip and
    # must be caught by the file-level audit_bundle backstop (ContentLeak raised).
    # "data_src" is not in CONTENT_KEYS — it is a structural key redact_node keeps.
    leak = {"key": "x", "role": "img", "data_src": "url(https://evil.example/a.png)"}
    sk = _min_skel_with_below_fold(extra_rec=leak)
    bundle = bw.assemble(sk, {"palette": []}, {}, [], {})
    with pytest.raises(bw.ContentLeak) as exc_info:
        bw.write_bundle(bundle, str(tmp_path))
    assert "skeleton.json" in str(exc_info.value)


def test_below_fold_redaction_strips_content_key():
    """Proves the bf["shapes"] redact_node pass in assemble() actually runs.
    background_image IS in CONTENT_KEYS — it must be absent after assemble()."""
    dirty = {"key": "x", "role": "img", "background_image": "url(https://x/y.png)"}
    sk = _min_skel_with_below_fold(extra_rec=dirty)
    bundle = bw.assemble(sk, {"palette": []}, {}, [], {})
    shape = bundle["skeleton"]["below_fold"]["shapes"][1]
    assert "background_image" not in shape, "redact_node did not strip content key from below_fold shape"
