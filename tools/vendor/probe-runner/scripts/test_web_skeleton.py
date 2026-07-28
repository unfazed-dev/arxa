# test_web_skeleton.py
import web_skeleton as ws

# Extended whitelist: spec §4 base styles PLUS sizing-behavior inputs.
WANT = ws.WANT_STYLES

def _idx(strings, val):
    return strings.index(val)

def _snap():
    # strings table; -1 means "no string"
    S = ["", "DIV", "IMG", "H1", "Hello world", "16px", "700", "24px",
         "normal", "sans-serif", "left", "rgb(0,0,0)", "rgba(0,0,0,0)",
         "none", "0px", "static", "auto", "block", "visible", "flex",
         "row", "1", "0", "stretch", "center", "space-between", "border-box"]
    nodes = {"nodeName": [1, 3, 2], "nodeValue": [-1, -1, -1],
             "parentIndex": [-1, 0, 0]}
    # one style row helper keyed by the WANT_STYLES order
    def row(**kw):
        defaults = {k: _idx(S, "none") if k in ("background-image",) else _idx(S, "0px")
                    for k in WANT}
        # sane neutral defaults
        for k in WANT:
            if k in ("display",): defaults[k] = _idx(S, "block")
            elif k in ("visibility",): defaults[k] = _idx(S, "visible")
            elif k in ("position",): defaults[k] = _idx(S, "static")
            elif k in ("color", "background-color"): defaults[k] = _idx(S, "rgb(0,0,0)")
            elif k in ("text-align",): defaults[k] = _idx(S, "left")
            elif k in ("font-family",): defaults[k] = _idx(S, "sans-serif")
            elif k in ("box-sizing",): defaults[k] = _idx(S, "border-box")
            elif k in ("flex-direction",): defaults[k] = _idx(S, "row")
            elif k in ("flex-grow", "flex-shrink"): defaults[k] = _idx(S, "0")
            elif k in ("width", "height", "flex-basis", "min-width", "max-width"):
                defaults[k] = _idx(S, "auto")
            elif k in ("align-self", "align-items", "justify-content"):
                defaults[k] = _idx(S, "normal") if k == "align-self" else _idx(S, "stretch")
            elif k in ("gap",): defaults[k] = _idx(S, "0px")
            elif k in ("grid-template-columns", "grid-template-rows"):
                defaults[k] = _idx(S, "none")
            else:
                defaults[k] = _idx(S, "0px")
        for k, v in kw.items():
            defaults[k] = _idx(S, v)
        return [defaults[k] for k in WANT]
    layout = {
        "nodeIndex": [0, 1, 2],
        "bounds": [[0, 0, 1440, 35137], [120, 1774, 600, 96], [120, 1900, 480, 320]],
        "paintOrders": [0, 12, 8],
        "text": [-1, _idx(S, "Hello world"), -1],
        "styles": [
            row(display="flex", **{"font-size": "16px", "font-weight": "700"}),
            row(**{"font-size": "16px", "font-weight": "700", "color": "rgb(0,0,0)"}),
            row(**{"font-size": "16px", "font-weight": "700"}),
        ],
    }
    return {"strings": S, "documents": [{"nodes": nodes, "layout": layout}]}

def test_parse_flattens_nodes_with_bbox_text_style():
    recs = ws.parse_snapshot(_snap(), WANT)
    assert len(recs) == 3
    h1 = recs[1]
    assert h1["tag"] == "H1"
    assert h1["bbox"] == {"x": 120.0, "y": 1774.0, "w": 600.0, "h": 96.0}
    assert h1["z"] == 12
    assert h1["text"] == "Hello world"
    assert h1["style"]["font-size"] == "16px"
    assert h1["style"]["font-weight"] == "700"
    img = recs[2]
    assert img["tag"] == "IMG"
    assert img["text"] is None
    assert h1["dom_index"] == 1

def test_parse_divides_bounds_by_dpr_to_css_px():
    # DOMSnapshot.captureSnapshot returns bounds in DEVICE px; the rest of the
    # bundle (page/viewport/web_anim anchors) is CSS px. parse_snapshot must
    # normalize bounds to CSS px by dividing by dpr so match_motion can join
    # motion anchors (CSS) to skeleton nodes (now CSS). Regression: on a retina
    # (dpr=2) capture the raw device-px bbox was 2x the CSS anchor, so motion
    # bound to the wrong node (or none).
    recs = ws.parse_snapshot(_snap(), WANT, dpr=2.0)
    h1 = recs[1]  # device bounds [120, 1774, 600, 96] -> CSS /2
    assert h1["bbox"] == {"x": 60.0, "y": 887.0, "w": 300.0, "h": 48.0}

def test_parse_dpr_defaults_to_one_noop():
    # dpr=1 (or omitted) leaves bounds unchanged (non-retina / already-CSS path).
    recs_default = ws.parse_snapshot(_snap(), WANT)
    recs_one = ws.parse_snapshot(_snap(), WANT, dpr=1.0)
    assert recs_default[1]["bbox"] == {"x": 120.0, "y": 1774.0, "w": 600.0, "h": 96.0}
    assert recs_one[1]["bbox"] == recs_default[1]["bbox"]

def test_parse_tolerates_empty_style_rows():
    # Real DOMSnapshot emits variable-length style rows: rendered nodes carry one
    # string-index per WANT_STYLES, but document/non-rendered nodes carry an empty
    # row. parse_snapshot must not index past a short row — it yields None instead.
    S = ["", "HTML", "16px"]
    full = [-1] * len(WANT)
    full[0] = _idx(S, "16px")  # font-size on the rendered row
    snap = {"strings": S, "documents": [{
        "nodes": {"nodeName": [1, 1], "nodeValue": [-1, -1], "parentIndex": [-1, 0]},
        "layout": {"nodeIndex": [0, 1], "bounds": [[0, 0, 10, 10], [0, 0, 5, 5]],
                   "paintOrders": [0, 1], "text": [-1, -1],
                   "styles": [[], full]},  # first row empty, second full
    }]}
    recs = ws.parse_snapshot(snap, WANT)
    assert len(recs) == 2
    # empty row -> every style value is None (no IndexError)
    assert all(v is None for v in recs[0]["style"].values())
    # full row still parses normally
    assert recs[1]["style"]["font-size"] == "16px"

def test_want_styles_includes_sizing_inputs():
    for k in ["flex-direction", "flex-grow", "flex-shrink", "flex-basis",
              "align-self", "align-items", "justify-content", "gap",
              "padding-top", "padding-right", "padding-bottom", "padding-left",
              "grid-template-columns", "grid-template-rows",
              "width", "height", "min-width", "max-width", "box-sizing"]:
        assert k in ws.WANT_STYLES

def test_classify_roles_and_unknown_fallback():
    # image by tag, image by bg-image, text, box (border), unknown_box, svg, skip zero-area
    def rec(tag, w=10, h=10, text=None, bgimg="none", border="0px", bg="rgba(0,0,0,0)"):
        return {"tag": tag, "bbox": {"x": 0, "y": 0, "w": w, "h": h}, "text": text,
                "style": {"background-image": bgimg, "border-top-width": border,
                          "background-color": bg}}
    assert ws.classify(rec("IMG"), in_svg=False) == "image"
    assert ws.classify(rec("DIV", bgimg='url("a.png")'), in_svg=False) == "image"
    assert ws.classify(rec("P", text="hi"), in_svg=False) == "text"
    assert ws.classify(rec("DIV", border="2px"), in_svg=False) == "box"
    # opaque background-color, no border, no text -> box (direct coverage)
    assert ws.classify(rec("DIV", bg="rgb(255,0,0)"), in_svg=False) == "box"
    assert ws.classify(rec("DIV"), in_svg=False) == "unknown_box"
    assert ws.classify(rec("PATH"), in_svg=True) == "svg"
    assert ws.classify(rec("DIV", w=0, h=0), in_svg=False) is None

def test_svg_descendants_marks_subtree():
    # nodes: 0 DIV (root), 1 SVG (child of 0), 2 PATH (child of 1)
    snap = {"strings": ["", "DIV", "svg", "path"],
            "documents": [{"nodes": {"nodeName": [1, 2, 3], "parentIndex": [-1, 0, 1]},
                           "layout": {"nodeIndex": [], "bounds": [], "styles": [],
                                      "text": [], "paintOrders": []}}]}
    sset = ws.svg_descendants(snap["documents"][0], snap["strings"])
    assert 1 in sset and 2 in sset and 0 not in sset

def test_svg_descendants_ignores_negative_nodename_sentinel():
    # real DOMSnapshot text/doc nodes carry nodeName index -1. With the LAST
    # string being "svg", an unguarded strings[-1] lookup would falsely mark
    # the node as svg. The -1 sentinel must be treated as "no name".
    snap = {"strings": ["DIV", "svg"],
            "documents": [{"nodes": {"nodeName": [-1], "parentIndex": [-1]},
                           "layout": {"nodeIndex": [], "bounds": [], "styles": [],
                                      "text": [], "paintOrders": []}}]}
    sset = ws.svg_descendants(snap["documents"][0], snap["strings"])
    assert 0 not in sset

def test_derive_sizing_fill_hug_fixed():
    def st(**kw):
        base = {"width": "auto", "height": "auto", "flex-grow": "0",
                "flex-shrink": "1", "align-self": "auto", "position": "static",
                "display": "block"}
        base.update(kw)
        return base
    # width:100% -> fill
    assert ws.derive_sizing(st(width="100%"), axis="w") == ("fill", "high")
    # flex-grow > 0 -> fill
    assert ws.derive_sizing(st(**{"flex-grow": "1"}), axis="w") == ("fill", "high")
    # align-self:stretch -> fill (cross axis grow)
    assert ws.derive_sizing(st(**{"align-self": "stretch"}), axis="h") == ("fill", "high")
    # width:auto + shrinks to content -> hug
    assert ws.derive_sizing(st(width="auto"), axis="w") == ("hug", "high")
    # explicit px -> fixed
    assert ws.derive_sizing(st(width="240px"), axis="w") == ("fixed", "high")
    # explicit rem -> fixed
    assert ws.derive_sizing(st(width="20rem"), axis="w") == ("fixed", "high")
    # height analogous: explicit px fixed, auto hug
    assert ws.derive_sizing(st(height="120px"), axis="h") == ("fixed", "high")
    assert ws.derive_sizing(st(height="auto"), axis="h") == ("hug", "high")


def test_derive_layout_flex_grid_block():
    def st(**kw):
        base = {"display": "block", "flex-direction": "row", "gap": "0px",
                "justify-content": "normal", "align-items": "normal",
                "padding-top": "0px", "padding-right": "0px",
                "padding-bottom": "0px", "padding-left": "0px",
                "grid-template-columns": "none", "grid-template-rows": "none"}
        base.update(kw)
        return base
    flex = ws.derive_layout(st(display="flex", **{"flex-direction": "row", "gap": "24px",
            "justify-content": "space-between", "align-items": "center",
            "padding-top": "16px", "padding-right": "24px",
            "padding-bottom": "16px", "padding-left": "24px"}))
    assert flex["mode"] == "flex"
    assert flex["direction"] == "row"
    assert flex["gap"] == 24.0
    assert flex["pad"] == [16.0, 24.0, 16.0, 24.0]
    assert flex["justify"] == "space-between"
    assert flex["align"] == "center"
    assert flex["grid_cols"] is None and flex["grid_rows"] is None

    grid = ws.derive_layout(st(display="grid",
            **{"grid-template-columns": "1fr 1fr 1fr", "grid-template-rows": "auto"}))
    assert grid["mode"] == "grid"
    assert grid["grid_cols"] == "1fr 1fr 1fr"
    assert grid["grid_rows"] == "auto"

    block = ws.derive_layout(st(display="block"))
    assert block["mode"] == "block"

    none_ = ws.derive_layout(st(display="none"))
    assert none_["mode"] == "none"


def test_build_parent_map_nearest_emitted_ancestor():
    # dom tree: 0 (root, emitted id=0) -> 1 (skipped) -> 2 (emitted id=1)
    # parentIndex by dom index: [-1, 0, 1]
    parent_index = [-1, 0, 1]
    # emitted nodes carry their source dom_index; id is their position
    emitted = [{"id": 0, "dom_index": 0}, {"id": 1, "dom_index": 2}]
    pm = ws.build_parent_map(emitted, parent_index)
    assert pm[0] is None          # root -> no parent
    assert pm[1] == 0             # dom 2's nearest emitted ancestor is dom 0 (id 0)


def test_to_skeleton_locks_full_schema():
    recs = ws.parse_snapshot(_snap(), WANT)
    svg_set = set()
    # dom parentIndex from _snap(): [-1, 0, 0]
    sk, node_colors, _, _, _ = ws.to_skeleton(recs, svg_set, parent_index=[-1, 0, 0],
                        url="https://x/y",
                        viewport={"w": 1440, "h": 887, "dpr": 2},
                        page={"w": 1440, "h": 35137})
    # node_colors sidecar keyed by emitted node id, with bg/fg/border per node
    assert set(node_colors.keys()) == {n["id"] for n in sk["nodes"]}
    for cols in node_colors.values():
        assert set(cols.keys()) == {"bg", "fg", "border"}
    assert sk["schema"] == "probe-skeleton/2"
    assert sk["viewport"] == {"w": 1440, "h": 887, "dpr": 2}
    assert sk["page"] == {"w": 1440, "h": 35137}
    n = sk["nodes"]
    roles = [x["role"] for x in n]
    assert "text" in roles and "image" in roles
    # every node has the locked structural fields
    for node in n:
        assert set(["id", "role", "confidence", "bbox", "z", "parent",
                    "sizing", "layout", "token_ref", "anim_ref"]).issubset(node.keys())
        assert set(node["sizing"].keys()) == {"w", "h", "confidence"}
        assert set(node["layout"].keys()) == {"mode", "direction", "gap", "pad",
                                              "justify", "align", "grid_cols", "grid_rows"}
        assert set(node["token_ref"].keys()) == {"bg", "fg", "border"}
        assert node["anim_ref"] is None
    t = next(x for x in n if x["role"] == "text")
    assert t["font"]["size"] == 16.0          # parsed "16px" -> number
    assert t["font"]["weight"] == 700
    assert t["text_len"] == len("Hello world")  # length only, NOT the content
    assert "text" not in t                       # raw string dropped
    # parent edges: root (id 0) has parent None; children point at it
    root = next(x for x in n if x["parent"] is None)
    assert root["id"] == 0


def test_to_skeleton_drops_content():
    recs = ws.parse_snapshot(_snap(), WANT)
    sk, _, _, _, _ = ws.to_skeleton(recs, set(), parent_index=[-1, 0, 0], url="u",
                              viewport={"w": 1, "h": 1, "dpr": 1}, page={"w": 1, "h": 1})
    blob = repr(sk)
    assert "Hello world" not in blob   # no raw text leaks into the skeleton


def test_infer_sizing_from_breakpoints():
    obs = {
        "A": [{"vw": 390, "w": 390, "h": 100}, {"vw": 1440, "w": 1440, "h": 100}],
        "B": [{"vw": 390, "w": 200, "h": 50}, {"vw": 1440, "w": 200, "h": 50}],
    }
    a = ws.infer_sizing_from_breakpoints(obs["A"])
    b = ws.infer_sizing_from_breakpoints(obs["B"])
    assert a == {"w": "fill", "h": "fixed", "confidence": "low"}
    assert b == {"w": "fixed", "h": "fixed", "confidence": "low"}


class _FakeSess:
    def __init__(self, metrics):
        self._m = metrics
        self.calls = []
    def send(self, method, params=None):
        self.calls.append(method)
        # tolerant: getLayoutMetrics returns the canned metrics; any other CDP call
        # (if the helper ever adds one) returns {} instead of breaking the fake.
        return self._m if method == "Page.getLayoutMetrics" else {}

class _FakeEv:
    def __init__(self, metrics):
        self.sess = _FakeSess(metrics)


def test_backing_scale_reads_layout_metrics_not_js_dpr():
    # #56 (T10): under an Emulation deviceScaleFactor:1 override on a HEADED retina
    # display, JS devicePixelRatio collapses to 1 while DOMSnapshot bounds AND
    # Page.getLayoutMetrics keep the real backing scale (proven live 2026-05-29:
    # layoutViewport.clientWidth=2560, cssLayoutViewport.clientWidth=1280 under the
    # override). _backing_scale must read the metrics ratio (2.0), NOT trust js dpr
    # (1) — trusting js dpr is exactly the bug that left coords 2x too large.
    ev = _FakeEv({"layoutViewport": {"clientWidth": 2560},
                  "cssLayoutViewport": {"clientWidth": 1280}})
    assert ws._backing_scale(ev) == 2.0

def test_backing_scale_unit_on_non_retina():
    # headless / non-retina: device == css -> 1.0 (the previously-working path;
    # the fix must not regress it).
    ev = _FakeEv({"layoutViewport": {"clientWidth": 1280},
                  "cssLayoutViewport": {"clientWidth": 1280}})
    assert ws._backing_scale(ev) == 1.0

def test_backing_scale_snaps_near_integer_scale():
    # sub-pixel clientWidth rounding -> ratio slightly off 2.0; snap to the nearest
    # real display scale as a noise guard.
    ev = _FakeEv({"layoutViewport": {"clientWidth": 2561},
                  "cssLayoutViewport": {"clientWidth": 1280}})
    assert ws._backing_scale(ev) == 2.0


def _substrate_snap():
    # canvas, video, captured-iframe (#so/#xo), uncaptured-iframe (#xs), plain img.
    S = ["", "CANVAS", "VIDEO", "IFRAME", "IMG", "rgba(0,0,0,0)", "none",
         "0px", "block", "visible", "static", "rgb(0,0,0)", "left",
         "sans-serif", "border-box", "row", "0", "auto", "normal", "stretch"]
    names = [_idx(S, t) for t in ("CANVAS", "VIDEO", "IFRAME", "IFRAME", "IMG")]
    nodes = {"nodeName": names, "nodeValue": [-1] * 5, "parentIndex": [-1, 0, 0, 0, 0],
             # node 2 (first IFRAME) HAS a captured doc; node 3 (second IFRAME) does NOT.
             "contentDocumentIndex": {"index": [2], "value": [1]}}

    def row():
        d = {}
        for k in ws.WANT_STYLES:
            if k == "display": d[k] = _idx(S, "block")
            elif k == "visibility": d[k] = _idx(S, "visible")
            elif k == "position": d[k] = _idx(S, "static")
            elif k in ("color", "background-color"): d[k] = _idx(S, "rgba(0,0,0,0)")
            elif k == "text-align": d[k] = _idx(S, "left")
            elif k == "font-family": d[k] = _idx(S, "sans-serif")
            elif k == "box-sizing": d[k] = _idx(S, "border-box")
            elif k == "flex-direction": d[k] = _idx(S, "row")
            elif k in ("flex-grow", "flex-shrink"): d[k] = _idx(S, "0")
            elif k in ("width", "height", "flex-basis", "min-width", "max-width"):
                d[k] = _idx(S, "auto")
            elif k == "align-items" or k == "justify-content": d[k] = _idx(S, "stretch")
            elif k == "align-self": d[k] = _idx(S, "normal")
            elif k in ("grid-template-columns", "grid-template-rows"): d[k] = _idx(S, "none")
            elif k == "background-image": d[k] = _idx(S, "none")
            else: d[k] = _idx(S, "0px")
        return [d[k] for k in ws.WANT_STYLES]

    layout = {
        "nodeIndex": [0, 1, 2, 3, 4],
        "bounds": [[0, 0, 200, 120], [0, 130, 200, 120], [0, 260, 200, 120],
                   [0, 390, 200, 120], [0, 520, 200, 120]],
        "paintOrders": [1, 2, 3, 4, 5],
        "text": [-1, -1, -1, -1, -1],
        "styles": [row(), row(), row(), row(), row()],
    }
    return {"strings": S, "documents": [{"nodes": nodes, "layout": layout}]}


def test_parse_attaches_substrate_marker():
    recs = ws.parse_snapshot(_substrate_snap(), ws.WANT_STYLES)
    by_tag_idx = {0: "canvas", 1: "video", 2: None, 3: "iframe_uncaptured", 4: None}
    for i, expected in by_tag_idx.items():
        assert recs[i].get("substrate") == expected, (i, recs[i].get("substrate"))


def test_to_skeleton_copies_substrate_onto_nodes():
    snap = _substrate_snap()
    recs = ws.parse_snapshot(snap, ws.WANT_STYLES)
    sk, _, _, _, _ = ws.to_skeleton(recs, svg_set=set(),
                              parent_index=snap["documents"][0]["nodes"]["parentIndex"],
                              url="http://x/", viewport={"w": 200, "h": 120, "dpr": 1.0},
                              page={"w": 200, "h": 640})
    subs = {n["id"]: n.get("substrate") for n in sk["nodes"]}
    kinds = sorted(v for v in subs.values() if v)
    assert kinds == ["canvas", "iframe_uncaptured", "video"]
    # a captured iframe and a plain img carry NO substrate key.
    assert any("substrate" not in n for n in sk["nodes"])


def test_style_props_subset_of_want_styles():
    # Every prop _collect_style reads MUST be requested via captureSnapshot, else it
    # is silently never captured (st.get() -> None). Guards the two-list duplication.
    missing = set(ws.STYLE_PROPS) - set(ws.WANT_STYLES)
    assert not missing, f"STYLE_PROPS not in WANT_STYLES (never captured): {sorted(missing)}"


def test_existing_snap_without_content_doc_index_has_no_substrate():
    # the legacy _snap() has no contentDocumentIndex -> parse must default cleanly
    # (no KeyError) and emit no substrate markers (DIV/H1/IMG are not substrate).
    recs = ws.parse_snapshot(_snap(), ws.WANT_STYLES)
    assert all(r.get("substrate") is None for r in recs)

def test_backing_scale_falls_back_to_raw_for_exotic_ratio():
    # a ratio in a gap between standard scales (1440/1280 = 1.125, >=0.06 from both
    # 1.0 and 1.25) -> use the measured ratio rather than mis-snapping. Still correct;
    # never trusts js dpr.
    ev = _FakeEv({"layoutViewport": {"clientWidth": 1440},
                  "cssLayoutViewport": {"clientWidth": 1280}})
    assert ws._backing_scale(ev) == 1.125

def test_backing_scale_snaps_standard_fractional_scales():
    # Windows 125%/175% and Android 2.5 land on the widened snap grid (sub-pixel
    # rounding nudges the integer clientWidths slightly off the exact ratio).
    def ev(dev, css):
        return _FakeEv({"layoutViewport": {"clientWidth": dev},
                        "cssLayoutViewport": {"clientWidth": css}})
    assert ws._backing_scale(ev(1601, 1280)) == 1.25   # ~1.2508 -> 1.25
    assert ws._backing_scale(ev(2241, 1280)) == 1.75   # ~1.7508 -> 1.75
    assert ws._backing_scale(ev(3201, 1280)) == 2.5    # ~2.5008 -> 2.5
    # a genuine non-standard 2.4 stays raw (0.1 from 2.5 > 0.06 band)
    assert ws._backing_scale(ev(3072, 1280)) == 2.4

def test_backing_scale_fallback_unit_on_missing_metrics():
    # degenerate metrics (empty / zero) -> safe 1.0 no-op, never crash.
    assert ws._backing_scale(_FakeEv({})) == 1.0
    assert ws._backing_scale(_FakeEv({"layoutViewport": {"clientWidth": 0},
                                      "cssLayoutViewport": {"clientWidth": 1280}})) == 1.0

def test_backing_scale_non_cdp_ev_is_unit_noop():
    # an ev without a CDP .sess (non-CDP transport) -> 1.0 no-op via the narrow
    # AttributeError catch. A REAL CDP/transport error must NOT be swallowed (it
    # would silently re-arm the 2x bug) — so only AttributeError is caught.
    class _NoSess:
        pass
    assert ws._backing_scale(_NoSess()) == 1.0
    # a transport that raises a real error on send propagates, not silently 1.0:
    class _BoomSess:
        def send(self, *a, **k):
            raise RuntimeError("transport closed")
    class _BoomEv:
        sess = _BoomSess()
    import pytest
    with pytest.raises(RuntimeError):
        ws._backing_scale(_BoomEv())


def test_merge_breakpoints_fills_low_confidence_only():
    ref = {"viewport": {"w": 1440, "h": 887, "dpr": 2}, "page": {"w": 1440, "h": 1000},
           "nodes": [
               {"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 1440, "h": 100},
                "sizing": {"w": "hug", "h": "fixed", "confidence": "low"}},
               {"id": 1, "role": "box", "bbox": {"x": 0, "y": 200, "w": 200, "h": 50},
                "sizing": {"w": "fixed", "h": "fixed", "confidence": "high"}},
           ]}
    narrow = {"viewport": {"w": 390, "h": 887, "dpr": 2},
              "nodes": [
                  {"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 390, "h": 100}},
                  {"id": 1, "role": "box", "bbox": {"x": 0, "y": 200, "w": 200, "h": 50}},
              ]}
    merged = ws.merge_breakpoints(ref, [narrow], radius=40)
    n0 = next(n for n in merged["nodes"] if n["id"] == 0)
    n1 = next(n for n in merged["nodes"] if n["id"] == 1)
    assert n0["sizing"] == {"w": "fill", "h": "fixed", "confidence": "low"}  # overwritten
    assert n1["sizing"] == {"w": "fixed", "h": "fixed", "confidence": "high"}  # preserved


def test_parse_substrate_is_per_document():
    # Two documents, EACH with an iframe at node-index 0. doc[0]'s iframe IS
    # captured (in its contentDocumentIndex); doc[1]'s iframe is NOT. Because the
    # captured-frame set is rebuilt PER DOCUMENT, doc[0]'s iframe must be
    # reproducible (substrate None) and doc[1]'s must be opaque
    # (iframe_uncaptured) — even though both share node-index 0.
    S = ["", "IFRAME"]
    style_cols = len(ws.WANT_STYLES)

    def doc(captured_index):
        nodes = {"nodeName": [1], "nodeValue": [-1], "parentIndex": [-1]}
        if captured_index is not None:
            nodes["contentDocumentIndex"] = {"index": [captured_index], "value": [0]}
        layout = {"nodeIndex": [0], "bounds": [[0, 0, 100, 100]],
                  "paintOrders": [0], "text": [-1], "styles": [[0] * style_cols]}
        return {"nodes": nodes, "layout": layout}

    snap = {"strings": S, "documents": [doc(0), doc(None)]}
    recs = ws.parse_snapshot(snap, ws.WANT_STYLES)
    # recs[0] = doc[0] iframe (captured) ; recs[1] = doc[1] iframe (uncaptured)
    assert recs[0].get("substrate") is None, recs[0].get("substrate")
    assert recs[1].get("substrate") == "iframe_uncaptured", recs[1].get("substrate")


def test_navigate_returns_settle_provenance_chrome():
    import _web_eval as WE

    class FakeEv:
        def __init__(self, signal):
            self.signal = signal
            self.exprs = []
        def ev(self, expr):
            self.exprs.append(expr)
            if "location.assign" in expr:
                return None
            return self.signal       # the _SETTLE_JS read

    quiet = {"n": 42, "ready": True, "inflight": 0, "since_start_ms": 1000}
    ev = FakeEv(quiet)
    r = WE.navigate(ev, "chrome", "http://x.test/", max_wait=5.0)
    assert r["settled"] is True and r["n_nodes"] == 42
    assert any("location.assign" in e for e in ev.exprs)   # it navigated


def test_navigate_returns_settle_provenance_safari():
    import _web_eval as WE

    class FakeDriver:
        def __init__(self):
            self.got = []
        def get(self, url):
            self.got.append(url)

    class FakeEv:
        def __init__(self, signal):
            self.driver = FakeDriver()
            self.signal = signal
        def ev(self, expr):
            return self.signal

    quiet = {"n": 7, "ready": True, "inflight": 1, "since_start_ms": 1000}
    ev = FakeEv(quiet)
    r = WE.navigate(ev, "safari", "http://x.test/", max_wait=5.0)
    assert r["settled"] is True and r["n_nodes"] == 7
    assert ev.driver.got == ["http://x.test/"]               # it navigated


def test_capture_one_attaches_settle_provenance(monkeypatch):
    import web_skeleton as W
    sentinel = {"settled": True, "capped": False, "waited_ms": 700, "n_nodes": 42}
    monkeypatch.setattr(W, "navigate",
                        lambda ev, eng, url, max_wait=10.0: sentinel)
    monkeypatch.setattr(W, "_snapshot_skeleton",
                        lambda ev, url, width=None: (
                            {"schema": "probe-skeleton/2", "url": url, "nodes": []},
                            None, None, {}))
    sk, _, _, _ = W._capture_one(object(), "chrome", "http://x.test/", max_wait=8.0)
    assert sk["settle"] == sentinel


def test_capture_one_forwards_max_wait(monkeypatch):
    import web_skeleton as W
    seen = {}
    def fake_nav(ev, eng, url, max_wait=10.0):
        seen["max_wait"] = max_wait
        return {"settled": True, "capped": False, "waited_ms": 1, "n_nodes": 0}
    monkeypatch.setattr(W, "navigate", fake_nav)
    monkeypatch.setattr(W, "_snapshot_skeleton",
                        lambda ev, url, width=None: ({"nodes": []}, None, None, {}))
    W._capture_one(object(), "chrome", "http://x.test/", max_wait=30.0)
    assert seen["max_wait"] == 30.0


def test_collect_style_sparse_drops_noop_and_zero():
    st = {"filter": "none", "backdrop-filter": "blur(8px)", "clip-path": "none",
          "box-shadow": "none", "mix-blend-mode": "normal",
          "border-top-width": "0px", "border-right-width": "2px",
          "border-top-style": "none", "border-right-style": "dashed",
          "border-right-color": "rgb(1, 2, 3)",
          "border-top-left-radius": "0px", "border-top-right-radius": "8px",
          "transform": "none", "transform-origin": "200px 130px"}
    out = ws._collect_style(st)
    # kept: effective values only
    assert out["backdrop-filter"] == "blur(8px)"
    assert out["border-right-width"] == "2px"
    assert out["border-right-style"] == "dashed"
    assert out["border-right-color"] == "rgb(1, 2, 3)"
    assert out["border-top-right-radius"] == "8px"
    # dropped: none/normal/0/empty + transform-origin (transform is none)
    for k in ("filter", "clip-path", "box-shadow", "mix-blend-mode",
              "border-top-width", "border-top-style", "border-top-left-radius",
              "transform-origin"):
        assert k not in out


def test_collect_style_transform_origin_only_with_transform():
    st = {"transform": "matrix(1, 0, 0, 1, 10, 20)", "transform-origin": "50px 60px"}
    assert ws._collect_style(st)["transform-origin"] == "50px 60px"


def test_collect_style_keeps_raw_url_unredacted():
    # capture is content-BLIND: url() is kept RAW here; redaction is bundle_writer's job.
    st = {"background-image": 'url("https://cdn/x.png")', "clip-path": "url(#c)"}
    out = ws._collect_style(st)
    assert out["background-image"] == 'url("https://cdn/x.png")'
    assert out["clip-path"] == "url(#c)"


def test_want_styles_includes_new_visual_props():
    for k in ("filter", "backdrop-filter", "clip-path",
              "box-shadow", "mix-blend-mode", "transform-origin",
              "border-left-style", "border-bottom-color", "border-bottom-left-radius"):
        assert k in ws.WANT_STYLES


def test_want_styles_parallel_index_stable_after_extension():
    # The WANT_STYLES order is the parse_snapshot contract: style row column k maps
    # to WANT_STYLES[k]. A synthetic row of "v<k>" must decode back by name.
    row = [f"v{k}" for k in range(len(ws.WANT_STYLES))]
    S = [""] + row  # strings table; index 0 = "", row strings at 1..N
    srow = [S.index(v) for v in row]
    snap = {"strings": S, "documents": [{
        "nodes": {"nodeName": [S.index("") if "" in S else 0], "parentIndex": [-1]},
        "layout": {"nodeIndex": [0], "bounds": [[0, 0, 10, 10]], "styles": [srow]}}]}
    recs = ws.parse_snapshot(snap, ws.WANT_STYLES)
    style = recs[0]["style"]
    for k, name in enumerate(ws.WANT_STYLES):
        assert style[name] == f"v{k}"


def test_to_skeleton_emits_node_style_for_styled_node():
    # a styled box node -> node_style entry; capture keeps url() raw.
    recs = [{"dom_index": 0, "tag": "DIV", "bbox": {"x": 0, "y": 0, "w": 100, "h": 40},
             "z": 0, "text": None, "substrate": None,
             "style": {"display": "block", "filter": "blur(4px)",
                       "background-image": 'url("https://cdn/x.png")'}}]
    sk, node_colors, node_style, _, _ = ws.to_skeleton(
        recs, svg_set=set(), parent_index=[-1], url="u",
        viewport={"w": 100, "h": 100, "dpr": 1}, page={"w": 100, "h": 100})
    nid = sk["nodes"][0]["id"]
    assert node_style[nid]["filter"] == "blur(4px)"
    assert node_style[nid]["background-image"] == 'url("https://cdn/x.png")'


def test_collect_style_drops_chrome_defaults():
    # Every cut-2 prop at its Chrome resolved default -> no style emitted (sparse).
    st = {"background-size": "auto", "background-position": "0% 0%",
          "background-repeat": "repeat", "background-clip": "border-box",
          "background-origin": "padding-box", "background-attachment": "scroll",
          "background-blend-mode": "normal", "overflow-x": "visible",
          "overflow-y": "visible", "aspect-ratio": "auto", "object-fit": "fill",
          "object-position": "50% 50%", "text-transform": "none",
          "text-decoration-line": "none", "font-variant": "normal",
          "writing-mode": "horizontal-tb", "direction": "ltr",
          "perspective": "none", "transform-style": "flat", "rotate": "none",
          "scale": "none", "translate": "none", "text-shadow": "none",
          "outline-style": "none", "outline-width": "1.5px",
          "outline-color": "rgb(0, 0, 0)", "outline-offset": "0px"}
    assert ws._collect_style(st) == {}


def test_collect_style_keeps_non_default_cut2():
    st = {"background-repeat": "no-repeat", "overflow-x": "hidden",
          "object-fit": "cover", "object-position": "25% 75%",
          "writing-mode": "vertical-rl", "transform-style": "preserve-3d",
          "text-shadow": "rgb(0, 0, 0) 1px 1px 2px", "perspective": "800px",
          "background-position": "10px 20px"}
    out = ws._collect_style(st)
    assert out["background-repeat"] == "no-repeat"
    assert out["overflow-x"] == "hidden"
    assert out["object-fit"] == "cover"
    assert out["object-position"] == "25% 75%"
    assert out["writing-mode"] == "vertical-rl"
    assert out["transform-style"] == "preserve-3d"
    assert out["text-shadow"] == "rgb(0, 0, 0) 1px 1px 2px"
    assert out["perspective"] == "800px"
    assert out["background-position"] == "10px 20px"


def test_collect_style_outline_group_gated_on_style():
    # Chrome resolves outline-width:1.5px / outline-color:rgb(0,0,0) on EVERY node,
    # so the group must be dropped unless outline-style is set (not zero-dropped).
    st0 = {"outline-style": "none", "outline-width": "1.5px",
           "outline-color": "rgb(0, 0, 0)", "outline-offset": "0px"}
    assert ws._collect_style(st0) == {}
    st1 = {"outline-style": "solid", "outline-width": "2px",
           "outline-color": "rgb(1, 2, 3)", "outline-offset": "3px"}
    out = ws._collect_style(st1)
    assert out["outline-style"] == "solid"
    assert out["outline-width"] == "2px"
    assert out["outline-color"] == "rgb(1, 2, 3)"
    assert out["outline-offset"] == "3px"


def test_want_styles_includes_content_not_in_style_props():
    assert "content" in ws.WANT_STYLES
    assert "content" not in ws.STYLE_PROPS   # real elements resolve content->normal


def test_parse_snapshot_reads_pseudo_type():
    # pseudoType is sparse RareStringData: node index 1 is a ::before; value strings
    # are CDP's bare kinds ("before"/"after"/"marker"), NOT the "::"-prefixed name.
    S = ["", "DIV", "before"]
    full = [-1] * len(WANT)
    snap = {"strings": S, "documents": [{
        "nodes": {"nodeName": [1, 1], "parentIndex": [-1, 0],
                  "pseudoType": {"index": [1], "value": [_idx(S, "before")]}},
        "layout": {"nodeIndex": [0, 1], "bounds": [[0, 0, 10, 10], [0, 0, 5, 5]],
                   "paintOrders": [0, 1], "text": [-1, -1],
                   "styles": [full, full]}}]}
    recs = ws.parse_snapshot(snap, WANT)
    assert recs[0].get("pseudo") is None        # real DIV
    assert recs[1].get("pseudo") == "before"    # the ::before node


def test_parse_snapshot_no_pseudo_type_is_none():
    # legacy/synthetic snapshots without pseudoType -> every record pseudo=None.
    recs = ws.parse_snapshot(_snap(), WANT)
    assert all(r.get("pseudo") is None for r in recs)


def test_want_styles_includes_cut2_props():
    for k in ("background-size", "background-repeat", "background-clip",
              "outline-style", "outline-color", "text-shadow", "overflow-x",
              "aspect-ratio", "object-fit", "object-position", "writing-mode",
              "direction", "transform-style", "translate"):
        assert k in ws.WANT_STYLES


def test_motion_props_curated():
    for p in ("animation-name", "animation-duration", "animation-iteration-count",
              "transition-duration", "transition-property", "scroll-behavior"):
        assert p in ws.MOTION_PROPS
    # animation-play-state excluded (probe PR3: does not move when animation is turned off)
    assert "animation-play-state" not in ws.MOTION_PROPS
    # layout-thrash props excluded
    for p in ("width", "height", "top"):
        assert p not in ws.MOTION_PROPS


def test_capture_with_reduced_motion_diffs_base_vs_reduce(monkeypatch):
    import web_skeleton as W

    sent = []

    class FakeSess:
        def send(self, method, params):
            sent.append((method, params))
            return {}

    class FakeEv:
        def __init__(self): self.sess = FakeSess()
        def ev(self, expr): return None
        def close(self): pass

    ev = FakeEv()
    # distinct backend != node_id so a rekey misplacement surfaces here (not only the gate)
    node_backend = {0: 5, 1: 7}
    monkeypatch.setattr(W, "_capture_one",
        lambda ev, engine, url, width=None, max_wait=None:
            ({"nodes": [{"id": 0}, {"id": 1}]}, None, None, node_backend))

    # _snapshot_recs is called twice: 1st = base (no-preference), 2nd = reduce.
    calls = {"n": 0}
    base_recs = [
        {"backend": 5, "pseudo": None, "style": {"animation-name": "drift",
            "animation-duration": "2s", "animation-iteration-count": "infinite",
            "transition-duration": "0.5s", "transition-property": "opacity",
            "scroll-behavior": "smooth"}},
        {"backend": 7, "pseudo": None, "style": {"animation-name": "none",
            "animation-duration": "0s", "animation-iteration-count": "1",
            "transition-duration": "0s", "transition-property": "all",
            "scroll-behavior": "auto"}}]
    reduce_recs = [
        {"backend": 5, "pseudo": None, "style": {"animation-name": "none",
            "animation-duration": "0s", "animation-iteration-count": "1",
            "transition-duration": "0s", "transition-property": "none",
            "scroll-behavior": "auto"}},
        {"backend": 7, "pseudo": None, "style": {"animation-name": "none",
            "animation-duration": "0s", "animation-iteration-count": "1",
            "transition-duration": "0s", "transition-property": "all",
            "scroll-behavior": "auto"}}]

    def fake_snapshot(ev, props=None):
        calls["n"] += 1
        return base_recs if calls["n"] == 1 else reduce_recs
    monkeypatch.setattr(W, "_snapshot_recs", fake_snapshot)

    sk = W.capture_with_reduced_motion(ev, "chrome", "http://x")

    # node 0 (backend 5) moved on all 6 props; node 1 (backend 7) unchanged -> no entry.
    assert sk["_node_reduced_motion"] == {"0": {"reduce": {
        "animation-name": "none", "animation-duration": "0s",
        "animation-iteration-count": "1", "transition-duration": "0s",
        "transition-property": "none", "scroll-behavior": "auto"}}}
    assert "1" not in sk["_node_reduced_motion"]
    # emulated-media sequence: base no-preference, then reduce, then cleared.
    media = [p["features"] for (m, p) in sent if m == "Emulation.setEmulatedMedia"]
    assert media[0] == [{"name": "prefers-reduced-motion", "value": "no-preference"}]
    assert media[1] == [{"name": "prefers-reduced-motion", "value": "reduce"}]
    assert media[-1] == []          # cleared in finally


def test_capture_with_reduced_motion_clears_emulation_on_error(monkeypatch):
    import web_skeleton as W

    sent = []

    class FakeSess:
        def send(self, method, params):
            sent.append((method, params))
            return {}

    class FakeEv:
        def __init__(self): self.sess = FakeSess()
        def close(self): pass

    ev = FakeEv()

    def boom(ev, engine, url, width=None, max_wait=None):
        raise RuntimeError("capture failed")
    monkeypatch.setattr(W, "_capture_one", boom)

    import pytest
    with pytest.raises(RuntimeError):
        W.capture_with_reduced_motion(ev, "chrome", "http://x")
    # emulation still cleared in finally even when capture raises
    media = [p["features"] for (m, p) in sent if m == "Emulation.setEmulatedMedia"]
    assert media[-1] == []


def test_form_props_and_selectors_curated():
    import web_skeleton as W
    # FORM_PROPS = THEME_PROPS + the three probe-confirmed additions; layout props absent.
    for p in ("opacity", "accent-color", "cursor", "color", "background-color",
              "outline-color"):
        assert p in W.FORM_PROPS
    for p in ("width", "height", "display", "position", "animation-name"):
        assert p not in W.FORM_PROPS
    # eligibility selectors encode state-eligible element types exactly (incl. input type).
    assert W.FORM_STATE_SELECTORS["checked"] == "input[type=checkbox], input[type=radio], option"
    assert W.FORM_STATE_SELECTORS["disabled"] == \
        "input, button, select, textarea, fieldset, optgroup, option"


def test_capture_with_form_states_diffs_per_state(monkeypatch):
    import web_skeleton as W

    sent = []

    class FakeSess:
        def send(self, method, params):
            sent.append((method, params))
            if method == "DOM.getDocument":
                return {"root": {"nodeId": 1}}
            if method == "DOM.querySelectorAll":
                return {"nodeIds": [10, 11]}     # eligible nodes (frontend ids)
            return {}

    class FakeEv:
        def __init__(self): self.sess = FakeSess()
        def ev(self, expr): return None
        def close(self): pass

    ev = FakeEv()
    # distinct backend != node_id so a rekey misplacement surfaces here (not only the gate)
    node_backend = {0: 5, 1: 7}
    monkeypatch.setattr(W, "_capture_one",
        lambda ev, engine, url, width=None, max_wait=None:
            ({"nodes": [{"id": 0}, {"id": 1}]}, None, None, node_backend))

    # _snapshot_recs called 3x: base, then checked cond, then disabled cond.
    base = [
        {"backend": 5, "pseudo": None, "style": {"opacity": "1", "accent-color": "auto",
            "cursor": "default", "color": "rgb(0, 0, 0)", "background-color": "rgba(0, 0, 0, 0)",
            "outline-color": "rgb(0, 0, 0)"}},
        {"backend": 7, "pseudo": None, "style": {"opacity": "1", "accent-color": "auto",
            "cursor": "default", "color": "rgb(0, 0, 0)", "background-color": "rgba(0, 0, 0, 0)",
            "outline-color": "rgb(0, 0, 0)"}}]
    checked = [dict(base[0], style=dict(base[0]["style"], opacity="0.5",
                    **{"accent-color": "rgb(11, 22, 33)"})), base[1]]
    disabled = [dict(base[0], style=dict(base[0]["style"], opacity="0.4", cursor="not-allowed")),
                base[1]]
    seq = {"n": 0, "rows": [base, checked, disabled]}

    def fake_snapshot(ev, props=None):
        r = seq["rows"][seq["n"]]
        seq["n"] += 1
        return r
    monkeypatch.setattr(W, "_snapshot_recs", fake_snapshot)

    sk = W.capture_with_form_states(ev, "chrome", "http://x", ("checked", "disabled"))

    fs = sk["_node_form_state"]
    assert "0" in fs and "1" not in fs                 # node 0 (backend 5) moved; node 1 didn't
    assert fs["0"]["checked"]["opacity"] == "0.5"
    assert fs["0"]["checked"]["accent-color"] == "rgb(11, 22, 33)"
    assert fs["0"]["disabled"]["cursor"] == "not-allowed"
    assert "_node_backend" not in sk                   # internal join key never on the skeleton
    # querySelectorAll used per state with the eligibility selectors
    sels = [p["selector"] for m, p in sent if m == "DOM.querySelectorAll"]
    assert sels == ["input[type=checkbox], input[type=radio], option",
                    "input, button, select, textarea, fieldset, optgroup, option"]
    # every forced node was cleared (forcedPseudoClasses: []) at least as often as it was set
    set_calls = [p for m, p in sent if m == "CSS.forcePseudoState" and p["forcedPseudoClasses"]]
    clr_calls = [p for m, p in sent if m == "CSS.forcePseudoState" and not p["forcedPseudoClasses"]]
    assert len(clr_calls) >= len(set_calls) > 0


def test_capture_with_form_states_clears_forced_on_error(monkeypatch):
    import web_skeleton as W
    import pytest

    sent = []

    class FakeSess:
        def send(self, method, params):
            sent.append((method, params))
            if method == "DOM.getDocument":
                return {"root": {"nodeId": 1}}
            if method == "DOM.querySelectorAll":
                return {"nodeIds": [10]}
            return {}

    class FakeEv:
        def __init__(self): self.sess = FakeSess()
        def ev(self, expr): return None
        def close(self): pass

    ev = FakeEv()
    monkeypatch.setattr(W, "_capture_one",
        lambda ev, engine, url, width=None, max_wait=None:
            ({"nodes": [{"id": 0}]}, None, None, {0: 5}))

    # The BASE snapshot (call 1) happens BEFORE forcing; the exception must land on the COND
    # snapshot (call 2), i.e. AFTER forcePseudoState, so the finally has a forced node to clear.
    calls = {"n": 0}

    def boom(ev, props=None):
        calls["n"] += 1
        if calls["n"] == 1:
            return [{"backend": 5, "pseudo": None, "style": {"opacity": "1"}}]   # base ok
        raise RuntimeError("snapshot failed mid-state")                          # cond -> raises
    monkeypatch.setattr(W, "_snapshot_recs", boom)

    with pytest.raises(RuntimeError):
        W.capture_with_form_states(ev, "chrome", "http://x", ("checked",))
    # node 10 was forced before the cond snapshot raised; finally must clear it.
    assert any(m == "CSS.forcePseudoState" and not p["forcedPseudoClasses"]
               for m, p in sent), "forced pseudo-state must be cleared on error"


def test_collect_style_keeps_meaningful_auto_none_via_default_map():
    # Regression: _STYLE_DEFAULTS is authoritative for its props, so a noop-LOOKING but
    # MEANINGFUL value survives (overflow default is visible, object-fit default is fill).
    assert ws._collect_style({"overflow-x": "auto"}) == {"overflow-x": "auto"}
    assert ws._collect_style({"overflow-y": "auto"}) == {"overflow-y": "auto"}
    assert ws._collect_style({"object-fit": "none"}) == {"object-fit": "none"}
    # their genuine defaults still drop
    assert ws._collect_style({"overflow-x": "visible"}) == {}
    assert ws._collect_style({"object-fit": "fill"}) == {}


def test_collect_pseudo_box_props_via_collect_style():
    st = {"text-shadow": "rgb(0, 0, 0) 1px 1px 2px", "filter": "blur(2px)",
          "color": "rgb(0, 0, 0)", "background-color": "rgba(0, 0, 0, 0)",
          "content": "normal"}
    out = ws._collect_pseudo(st, parent_color="rgb(0, 0, 0)")
    assert out["text-shadow"] == "rgb(0, 0, 0) 1px 1px 2px"
    assert out["filter"] == "blur(2px)"
    assert "color" not in out                   # equals parent -> dropped
    assert "background-color" not in out         # transparent -> dropped
    assert "content" not in out                  # normal -> dropped


def test_collect_pseudo_color_only_when_differs_from_parent():
    # a custom ::marker color on a black-text list -> captured
    assert ws._collect_pseudo({"color": "rgb(255, 0, 0)"}, parent_color="rgb(0, 0, 0)") \
        == {"color": "rgb(255, 0, 0)"}
    # a default marker inherits the parent's color -> dropped (stays sparse)
    assert ws._collect_pseudo({"color": "rgb(0, 0, 0)"}, parent_color="rgb(0, 0, 0)") == {}


def test_collect_pseudo_content_and_bg_kept():
    out = ws._collect_pseudo(
        {"content": '"Read more"', "background-color": "rgb(1, 2, 3)"},
        parent_color="rgb(0, 0, 0)")
    assert out["content"] == '"Read more"'       # RAW (redacted at packaging)
    assert out["background-color"] == "rgb(1, 2, 3)"


def test_collect_pseudo_border_top_color_gated_on_style():
    assert "border-top-color" not in ws._collect_pseudo(
        {"border-top-color": "rgb(9, 9, 9)"}, parent_color=None)
    out = ws._collect_pseudo(
        {"border-top-style": "solid", "border-top-color": "rgb(9, 9, 9)"}, parent_color=None)
    assert out["border-top-style"] == "solid"    # via _collect_style
    assert out["border-top-color"] == "rgb(9, 9, 9)"


def test_collect_pseudo_empty_when_nothing_set():
    assert ws._collect_pseudo({"color": "rgb(0, 0, 0)", "content": "none"},
                              parent_color="rgb(0, 0, 0)") == {}


def test_to_skeleton_attaches_pseudo_to_origin_not_standalone():
    # a DIV (emitted) with a ::before record -> the ::before does NOT become its own
    # node; it attaches to the DIV's node id. Color differs from parent -> captured.
    recs = [
        {"dom_index": 0, "tag": "DIV", "bbox": {"x": 0, "y": 0, "w": 100, "h": 40},
         "z": 0, "text": None, "substrate": None, "pseudo": None,
         "style": {"display": "block", "color": "rgb(0, 0, 0)", "border-top-width": "2px"}},
        {"dom_index": 1, "tag": "::BEFORE", "bbox": {"x": 0, "y": 0, "w": 12, "h": 12},
         "z": 0, "text": None, "substrate": None, "pseudo": "before",
         "style": {"color": "rgb(255, 0, 0)", "content": '"Read more"'}},
    ]
    sk, node_colors, node_style, node_pseudo, _ = ws.to_skeleton(
        recs, svg_set=set(), parent_index=[-1, 0], url="u",
        viewport={"w": 100, "h": 100, "dpr": 1}, page={"w": 100, "h": 100})
    assert len(sk["nodes"]) == 1                    # the ::before is NOT a node
    nid = sk["nodes"][0]["id"]
    assert node_pseudo[nid]["::before"]["color"] == "rgb(255, 0, 0)"
    assert node_pseudo[nid]["::before"]["content"] == '"Read more"'   # RAW


def test_to_skeleton_attaches_pseudo_bbox_when_nondegenerate():
    # Regime-2 GEOMETRY follow-on: a ::after divider bar with its OWN box (1px tall, distinct
    # from the parent's 40px) -> its bbox rides along on the kept sparse style. Geometry is
    # content-free mechanism (floats), non-derivable from the originator's bbox.
    recs = [
        {"dom_index": 0, "tag": "DIV", "bbox": {"x": 0, "y": 0, "w": 200, "h": 40},
         "z": 0, "text": None, "substrate": None, "pseudo": None,
         "style": {"display": "block"}},
        {"dom_index": 1, "tag": "::AFTER", "bbox": {"x": 0, "y": 39, "w": 200, "h": 1},
         "z": 0, "text": None, "substrate": None, "pseudo": "after",
         "style": {"background-color": "rgb(1, 2, 3)", "content": '""'}},
    ]
    _, _, _, node_pseudo, _ = ws.to_skeleton(
        recs, svg_set=set(), parent_index=[-1, 0], url="u",
        viewport={"w": 200, "h": 100, "dpr": 1}, page={"w": 200, "h": 100})
    nid = next(iter(node_pseudo))
    assert node_pseudo[nid]["::after"]["bbox"] == {"x": 0, "y": 39, "w": 200, "h": 1}
    assert node_pseudo[nid]["::after"]["background-color"] == "rgb(1, 2, 3)"


def test_to_skeleton_omits_pseudo_bbox_when_degenerate():
    # a 0x0 ::before (bare content box, no rendered area) -> sparse style kept, NO bbox key
    # (gate is w>0 AND h>0; an invisible box carries no geometry worth shipping).
    recs = [
        {"dom_index": 0, "tag": "DIV", "bbox": {"x": 0, "y": 0, "w": 100, "h": 40},
         "z": 0, "text": None, "substrate": None, "pseudo": None,
         "style": {"display": "block"}},
        {"dom_index": 1, "tag": "::BEFORE", "bbox": {"x": 0, "y": 0, "w": 0, "h": 0},
         "z": 0, "text": None, "substrate": None, "pseudo": "before",
         "style": {"color": "rgb(255, 0, 0)"}},
    ]
    _, _, _, node_pseudo, _ = ws.to_skeleton(
        recs, svg_set=set(), parent_index=[-1, 0], url="u",
        viewport={"w": 100, "h": 100, "dpr": 1}, page={"w": 100, "h": 100})
    nid = next(iter(node_pseudo))
    assert "bbox" not in node_pseudo[nid]["::before"]
    assert node_pseudo[nid]["::before"]["color"] == "rgb(255, 0, 0)"


def test_to_skeleton_drops_orphan_pseudo_with_unemitted_parent():
    # a ::before whose parent (dom 0) is zero-area (classify -> None, not emitted)
    # must be DROPPED, never reattached to an ancestor.
    recs = [
        {"dom_index": 0, "tag": "DIV", "bbox": {"x": 0, "y": 0, "w": 0, "h": 0},
         "z": 0, "text": None, "substrate": None, "pseudo": None, "style": {}},
        {"dom_index": 1, "tag": "::BEFORE", "bbox": {"x": 0, "y": 0, "w": 5, "h": 5},
         "z": 0, "text": None, "substrate": None, "pseudo": "before",
         "style": {"content": '"x"'}},
    ]
    sk, _, _, node_pseudo, _ = ws.to_skeleton(
        recs, svg_set=set(), parent_index=[-1, 0], url="u",
        viewport={"w": 100, "h": 100, "dpr": 1}, page={"w": 100, "h": 100})
    assert sk["nodes"] == []          # parent not emitted
    assert node_pseudo == {}          # orphan pseudo dropped, NOT reattached


def test_parse_extracts_backend_node_id():
    snap = _snap()
    snap["documents"][0]["nodes"]["backendNodeId"] = [101, 102, 103]
    recs = ws.parse_snapshot(snap, WANT)
    assert [r["backend"] for r in recs] == [101, 102, 103]


def test_parse_backend_absent_is_none():
    # legacy/synthetic snaps without backendNodeId -> backend None, no crash
    recs = ws.parse_snapshot(_snap(), WANT)
    assert all(r["backend"] is None for r in recs)


def test_to_skeleton_returns_node_backend_map():
    snap = _snap()
    snap["documents"][0]["nodes"]["backendNodeId"] = [101, 102, 103]
    recs = ws.parse_snapshot(snap, WANT)
    svg_set = ws.svg_descendants(snap["documents"][0], snap["strings"])
    result = ws.to_skeleton(recs, svg_set, parent_index=[-1, 0, 0], url="u",
                            viewport={"w": 1440, "h": 900, "dpr": 1},
                            page={"w": 1440, "h": 35137})
    assert len(result) == 5  # skeleton, node_colors, node_style, node_pseudo, node_backend
    sk, _, _, _, node_backend = result
    for n in sk["nodes"]:
        assert node_backend[n["id"]] in (101, 102, 103)


def test_element_backends_filters_non_elements():
    # forcePseudoState rejects non-elements ("Node is not an Element"), so the force
    # set must keep ELEMENT records only: tag present and not '#…', not a pseudo
    # record, backend present. styles_by_backend keeps text/doc nodes — this does not.
    recs = [
        {"tag": "DIV", "backend": 5, "pseudo": None, "style": {}},
        {"tag": "#text", "backend": 6, "pseudo": None, "style": {}},      # text node
        {"tag": "SPAN", "backend": 7, "pseudo": "::before", "style": {}},  # pseudo record
        {"tag": "BUTTON", "backend": None, "pseudo": None, "style": {}},   # no backend
        {"tag": "A", "backend": 9, "pseudo": None, "style": {}},
        {"tag": "#document", "backend": 1, "pseudo": None, "style": {}},   # document
    ]
    assert ws.element_backends(recs) == [5, 9]


def test_capture_with_pseudo_states_wires_force_diff_clear(monkeypatch):
    import web_skeleton as W

    class FakeSess:
        def __init__(self):
            self.sent = []

        def send(self, method, params):
            self.sent.append((method, params))
            if method == "DOM.pushNodesByBackendIdsToFrontend":
                # backendNodeId -> nodeId (deterministic: nodeId = 100 + backend)
                return {"nodeIds": [100 + b for b in params["backendNodeIds"]]}
            return {}

    class FakeEv:
        def __init__(self):
            self.sess = FakeSess()

        def ev(self, expr):
            return None

        def close(self):
            pass

    ev = FakeEv()
    # base: one element DIV (backend 5) at node id 0.
    base_recs = [{"tag": "DIV", "backend": 5, "pseudo": None,
                  "style": {"color": "rgb(0, 0, 0)"}}]
    node_backend = {0: 5}
    monkeypatch.setattr(W, "_capture_one",
                        lambda ev, engine, url, max_wait=None: ({"nodes": [{"id": 0}]},
                                                                None, None, node_backend))
    monkeypatch.setattr(W, "_snapshot_recs", lambda ev: base_recs)
    # forced recapture: the DIV's color changes under :hover.
    monkeypatch.setattr(W, "_styles_by_backend",
                        lambda ev: {5: {"color": "rgb(1, 1, 1)"}})

    sk = W.capture_with_pseudo_states(ev, "chrome", "http://x", ["hover"])

    # sidecar built with the diffed delta, keyed by node id (string), backend internal.
    assert sk["_node_pseudo_state"] == {"0": {"hover": {"color": "rgb(1, 1, 1)"}}}
    # forced the bare pseudo name on the mapped nodeId (100 + 5), then CLEARED it.
    forces = [p for (m, p) in ev.sess.sent if m == "CSS.forcePseudoState"]
    assert {"nodeId": 105, "forcedPseudoClasses": ["hover"]} in forces
    assert {"nodeId": 105, "forcedPseudoClasses": []} in forces


def test_capture_with_pseudo_states_clears_between_labels(monkeypatch):
    # No-bleed proof: with TWO labels, a clear ([]) must fire BETWEEN the two
    # force-sets (the inner per-label clear), not only in the finally. Deleting the
    # inner clear loop would leave the next label's force stacked on the previous —
    # this test would then fail (no [] between hover-force and focus-force).
    import web_skeleton as W

    class FakeSess:
        def __init__(self):
            self.sent = []

        def send(self, method, params):
            self.sent.append((method, params))
            if method == "DOM.pushNodesByBackendIdsToFrontend":
                return {"nodeIds": [100 + b for b in params["backendNodeIds"]]}
            return {}

    class FakeEv:
        def __init__(self):
            self.sess = FakeSess()

        def ev(self, expr):
            return None

        def close(self):
            pass

    ev = FakeEv()
    base_recs = [{"tag": "DIV", "backend": 5, "pseudo": None,
                  "style": {"color": "rgb(0, 0, 0)"}}]
    node_backend = {0: 5}
    monkeypatch.setattr(W, "_capture_one",
                        lambda ev, engine, url, max_wait=None: ({"nodes": [{"id": 0}]},
                                                                None, None, node_backend))
    monkeypatch.setattr(W, "_snapshot_recs", lambda ev: base_recs)
    monkeypatch.setattr(W, "_styles_by_backend", lambda ev: {5: {"color": "rgb(1, 1, 1)"}})

    W.capture_with_pseudo_states(ev, "chrome", "http://x", ["hover", "focus"])

    fs = [p for (m, p) in ev.sess.sent if m == "CSS.forcePseudoState"]
    i_hover = fs.index({"nodeId": 105, "forcedPseudoClasses": ["hover"]})
    i_focus = fs.index({"nodeId": 105, "forcedPseudoClasses": ["focus"]})
    assert i_hover < i_focus, "labels must be processed in order"
    # a clear must occur BETWEEN the two force-sets (the inner per-label clear).
    assert any(fs[j] == {"nodeId": 105, "forcedPseudoClasses": []}
               for j in range(i_hover + 1, i_focus)), \
        "inter-label clear missing: forced state would bleed from one label to the next"


def test_responsive_props_curated_excludes_continuous_px():
    # The curated discrete-layout set: props that FLIP at author breakpoints, plus
    # font-size (the clamp() fluid curve). Continuous px are deliberately excluded —
    # bbox already carries rendered size and they would delta on nearly every node in
    # fluid layouts (the anti-chimera choice, design §2.1).
    for p in ("display", "flex-direction", "flex-wrap", "grid-template-columns",
              "grid-template-rows", "gap", "column-gap", "row-gap", "position",
              "font-size", "text-align"):
        assert p in ws.RESPONSIVE_PROPS
    for p in ("width", "height", "margin-top", "padding-top", "top", "left", "inset"):
        assert p not in ws.RESPONSIVE_PROPS


def test_snapshot_recs_requests_given_prop_list(monkeypatch):
    # _snapshot_recs(ev, props) must request AND parse exactly `props`; the default is
    # WANT_STYLES (theme/pseudo paths unchanged). Regime-3c passes RESPONSIVE_PROPS
    # (which is NOT a subset of WANT_STYLES), so the parameter must thread through both
    # the captureSnapshot computedStyles AND the parse_snapshot call.
    import web_skeleton as W
    seen = {}

    class FakeSess:
        def send(self, method, params):
            if method == "DOMSnapshot.captureSnapshot":
                seen["props"] = params["computedStyles"]
            return {}

    class FakeEv:
        def __init__(self): self.sess = FakeSess()
        def ev(self, expr): return None

    monkeypatch.setattr(W, "parse_snapshot",
                        lambda snap, props, dpr: ("parsed", list(props)))
    out = W._snapshot_recs(FakeEv(), W.RESPONSIVE_PROPS)
    assert seen["props"] == W.RESPONSIVE_PROPS           # captureSnapshot got the list
    assert out == ("parsed", list(W.RESPONSIVE_PROPS))   # parse_snapshot got the SAME list
    W._snapshot_recs(FakeEv())                           # default
    assert seen["props"] == W.WANT_STYLES


def test_capture_with_breakpoints_wires_override_diff_clear(monkeypatch):
    import web_skeleton as W

    class FakeSess:
        def __init__(self): self.sent = []
        def send(self, method, params):
            self.sent.append((method, params)); return {}

    class FakeEv:
        def __init__(self): self.sess = FakeSess()
        def ev(self, expr): return None
        def close(self): pass

    ev = FakeEv()
    node_backend = {0: 5}
    # base captured at the WIDEST width via _capture_one(width=base_w); it owns that
    # override, so the loop emulates ONLY the narrower widths.
    monkeypatch.setattr(W, "_capture_one",
        lambda ev, engine, url, width=None, max_wait=None:
            ({"nodes": [{"id": 0}]}, None, None, node_backend))
    calls = []

    def fake_recs(ev, props=None):
        calls.append(1)
        # 1st call = base (1440) -> display:flex; 2nd = 768 width -> display:block
        style = {"display": "flex"} if len(calls) == 1 else {"display": "block"}
        return [{"backend": 5, "pseudo": None, "style": style}]

    monkeypatch.setattr(W, "_snapshot_recs", fake_recs)

    sk = W.capture_with_breakpoints(ev, "chrome", "http://x", [1440, 768])

    # sidecar = diffed delta, keyed by node id (string), under the width label; backend internal.
    assert sk["_node_responsive"] == {"0": {"768": {"display": "block"}}}
    overrides = [p for (m, p) in ev.sess.sent
                 if m == "Emulation.setDeviceMetricsOverride"]
    assert any(p["width"] == 768 for p in overrides)           # narrower width emulated
    assert ("Emulation.clearDeviceMetricsOverride", {}) in ev.sess.sent  # cleaned up in finally


def test_capture_with_breakpoints_emulates_each_width_widest_first(monkeypatch):
    import web_skeleton as W

    class FakeSess:
        def __init__(self): self.sent = []
        def send(self, method, params):
            self.sent.append((method, params)); return {}

    class FakeEv:
        def __init__(self): self.sess = FakeSess()
        def ev(self, expr): return None
        def close(self): pass

    ev = FakeEv()
    monkeypatch.setattr(W, "_capture_one",
        lambda ev, engine, url, width=None, max_wait=None:
            ({"nodes": [{"id": 0}]}, None, None, {0: 5}))
    # identical styles at every width -> no delta -> empty sidecar (no crash)
    monkeypatch.setattr(W, "_snapshot_recs",
        lambda ev, props=None: [{"backend": 5, "pseudo": None, "style": {"gap": "0px"}}])

    sk = W.capture_with_breakpoints(ev, "chrome", "http://x", [768, 1440, 390])
    widths = [p["width"] for (m, p) in ev.sess.sent
              if m == "Emulation.setDeviceMetricsOverride"]
    # widest (1440) is the base (via _capture_one, not re-emulated); the loop emulates the
    # narrower widths in descending order.
    assert widths == [768, 390]
    assert sk["_node_responsive"] == {}


def test_animatable_and_candidate_props_curated():
    for p in ("transform", "opacity", "filter", "color", "background-color",
              "border-color", "box-shadow", "translate", "rotate", "scale"):
        assert p in ws.ANIMATABLE_PROPS
    for p in ("width", "height", "margin-top", "top"):
        assert p not in ws.ANIMATABLE_PROPS          # layout-thrash excluded (anti-bloat)
    assert "animation-name" in ws.ANIM_CANDIDATE_PROPS
    for p in ("animation-duration", "animation-timing-function", "animation-iteration-count",
              "animation-direction", "animation-delay", "animation-fill-mode"):
        assert p in ws.ANIM_CANDIDATE_PROPS


def test_capture_with_keyframes_selects_candidates_pushes_parses(monkeypatch):
    import web_skeleton as W

    class FakeSess:
        def __init__(self): self.sent = []
        def send(self, method, params):
            self.sent.append((method, params))
            if method == "DOM.pushNodesByBackendIdsToFrontend":
                # frontend nodeIds positionally aligned to the input backendNodeIds
                return {"nodeIds": [900 + b for b in params["backendNodeIds"]]}
            if method == "CSS.getMatchedStylesForNode":
                # the pushed node for backend 5 (frontend 905) animates 'spin'
                if params["nodeId"] == 905:
                    return {"cssKeyframesRules": [
                        {"animationName": {"text": "spin"},
                         "keyframes": [
                             {"keyText": "0%", "style": {"cssProperties": [
                                 {"name": "transform", "value": "rotate(0deg)"}]}},
                             {"keyText": "100%", "style": {"cssProperties": [
                                 {"name": "transform", "value": "rotate(360deg)"}]}}]}]}
                return {"cssKeyframesRules": []}
            return {}

    class FakeEv:
        def __init__(self): self.sess = FakeSess()
        def ev(self, expr): return None
        def close(self): pass

    ev = FakeEv()
    # node 0 -> backend 5 animates; node 1 -> backend 7 has no animation
    node_backend = {0: 5, 1: 7}
    monkeypatch.setattr(W, "_capture_one",
        lambda ev, engine, url, width=None, max_wait=None:
            ({"nodes": [{"id": 0}, {"id": 1}]}, None, None, node_backend))
    monkeypatch.setattr(W, "_snapshot_recs",
        lambda ev, props=None: [
            {"backend": 5, "pseudo": None, "style": {"animation-name": "spin",
                "animation-duration": "2s", "animation-timing-function": "linear",
                "animation-iteration-count": "infinite", "animation-direction": "normal",
                "animation-delay": "0s", "animation-fill-mode": "none"}},
            {"backend": 7, "pseudo": None, "style": {"animation-name": "none"}}])

    sk = W.capture_with_keyframes(ev, "chrome", "http://x")

    # only the animating node gets a keyframes entry; keyed by node id (string); name dropped.
    assert sk["_node_keyframes"] == {"0": [
        {"timing": {"duration": "2s", "easing": "linear", "iterations": "infinite",
                    "direction": "normal", "delay": "0s", "fill": "none"},
         "frames": [{"offset": 0.0, "props": {"transform": "rotate(0deg)"}},
                    {"offset": 1.0, "props": {"transform": "rotate(360deg)"}}]}]}
    assert "1" not in sk["_node_keyframes"]
    pushed = [p for (m, p) in ev.sess.sent if m == "DOM.pushNodesByBackendIdsToFrontend"]
    assert pushed and pushed[0]["backendNodeIds"] == [5]   # only the candidate pushed (not 7)
    assert "spin" not in str(sk["_node_keyframes"])        # @keyframes name never in output


def test_capture_with_keyframes_no_candidates_empty_sidecar(monkeypatch):
    import web_skeleton as W

    class FakeSess:
        def __init__(self): self.sent = []
        def send(self, method, params): self.sent.append((method, params)); return {}

    class FakeEv:
        def __init__(self): self.sess = FakeSess()
        def ev(self, expr): return None
        def close(self): pass

    ev = FakeEv()
    monkeypatch.setattr(W, "_capture_one",
        lambda ev, engine, url, width=None, max_wait=None:
            ({"nodes": [{"id": 0}]}, None, None, {0: 5}))
    monkeypatch.setattr(W, "_snapshot_recs",
        lambda ev, props=None: [{"backend": 5, "pseudo": None,
                                 "style": {"animation-name": "none"}}])
    sk = W.capture_with_keyframes(ev, "chrome", "http://x")
    assert sk["_node_keyframes"] == {}
    # no candidates -> no push at all
    assert not any(m == "DOM.pushNodesByBackendIdsToFrontend" for (m, p) in ev.sess.sent)


def test_capture_with_keyframes_skips_non_element_node(monkeypatch):
    # real-site robustness: a candidate that pushes to a non-Element node makes CDP raise
    # "Node is not an Element"; capture must DROP it and still return the good node, not abort.
    import web_skeleton as W

    class FakeSess:
        def __init__(self): self.sent = []
        def send(self, method, params):
            self.sent.append((method, params))
            if method == "DOM.pushNodesByBackendIdsToFrontend":
                return {"nodeIds": [900 + b for b in params["backendNodeIds"]]}
            if method == "CSS.getMatchedStylesForNode":
                if params["nodeId"] == 905:   # backend 5 -> good element, animates 'spin'
                    return {"cssKeyframesRules": [
                        {"animationName": {"text": "spin"},
                         "keyframes": [
                             {"keyText": {"text": "0%"}, "style": {"cssProperties": [
                                 {"name": "transform", "value": "translateX(0)"}]}},
                             {"keyText": {"text": "100%"}, "style": {"cssProperties": [
                                 {"name": "transform", "value": "translateX(60px)"}]}}]}]}
                if params["nodeId"] == 907:   # backend 7 -> non-Element: CDP raises
                    raise RuntimeError('{"code": -32000, "message": "Node is not an Element"}')
                return {"cssKeyframesRules": []}

    class FakeEv:
        def __init__(self): self.sess = FakeSess()
        def ev(self, expr): return None
        def close(self): pass

    ev = FakeEv()
    node_backend = {0: 5, 1: 7}
    monkeypatch.setattr(W, "_capture_one",
        lambda ev, engine, url, width=None, max_wait=None:
            ({"nodes": [{"id": 0}, {"id": 1}]}, None, None, node_backend))
    monkeypatch.setattr(W, "_snapshot_recs",
        lambda ev, props=None: [
            {"backend": 5, "pseudo": None, "style": {"animation-name": "spin",
                "animation-duration": "2s", "animation-timing-function": "linear",
                "animation-iteration-count": "infinite"}},
            {"backend": 7, "pseudo": None, "style": {"animation-name": "spin",
                "animation-duration": "2s"}}])

    sk = W.capture_with_keyframes(ev, "chrome", "http://x")   # must NOT raise
    assert "0" in sk["_node_keyframes"]          # good node captured
    assert "1" not in sk["_node_keyframes"]      # raising (non-Element) node dropped


def test_container_props_and_widths_curated():
    import web_skeleton as W
    assert W.CONTAINER_PROPS == W.RESPONSIVE_PROPS         # @container == @media restyle vocab
    assert W.DEFAULT_CONTAINER_WIDTHS == "240,480,720"
    for p in ("width", "height", "margin-top", "padding-left"):
        assert p not in W.CONTAINER_PROPS                  # continuous-px excluded (anti-chimera)
    assert W.CONTAINER_BASE_VIEWPORT == 1440


def test_cq_container_backends_filters_inline_size():
    import web_skeleton as W
    base = {
        5: {"container-type": "inline-size"},
        6: {"container-type": "size"},          # 2D -> ceiling, skipped
        7: {"container-type": "normal"},        # not a container
        8: {},                                  # absent -> not a container
    }
    assert W._cq_container_backends(base) == [5]


def _cq_fake_ev(base_w=320):
    import web_skeleton as W

    class FakeSess:
        def __init__(self): self.sent = []
        def send(self, method, params):
            self.sent.append((method, params))
            if method == "DOM.pushNodesByBackendIdsToFrontend":
                return {"nodeIds": [900 + b for b in params["backendNodeIds"]]}
            if method == "DOM.resolveNode":
                return {"object": {"objectId": "obj-%d" % params["nodeId"]}}
            if method == "Runtime.callFunctionOn":
                fn = params["functionDeclaration"]
                if "getBoundingClientRect" in fn:
                    return {"result": {"value": base_w}}
                if "getPropertyValue" in fn:      # SET width -> returns saved "value|priority"
                    return {"result": {"value": "|"}}
                return {}                          # RESTORE / other
            return {}

    class FakeEv:
        def __init__(self): self.sess = FakeSess()
        def ev(self, expr): return None
        def close(self): pass

    return FakeEv()


def test_capture_with_container_queries_sweeps_keys_and_clamps(monkeypatch):
    import web_skeleton as W
    ev = _cq_fake_ev(base_w=320)
    # node 0 -> backend 5 (the inline-size container); node 1 -> backend 7 (its child)
    node_backend = {0: 5, 1: 7}
    monkeypatch.setattr(W, "_capture_one",
        lambda ev, engine, url, width=None, max_wait=None:
            ({"nodes": [{"id": 0}, {"id": 1}]}, None, None, node_backend))
    # base snapshot, then one cond snapshot per swept width. base_w=320 so only 240 is < 320
    # (480/720 clamped). At 240 the child (backend 7) font-size moves 20 -> 11 (the @container
    # restyle); the container (backend 5) does not change a CONTAINER_PROPS value.
    snaps = iter([
        [  # base
            {"backend": 5, "pseudo": None, "style": {"container-type": "inline-size", "font-size": "16px"}},
            {"backend": 7, "pseudo": None, "style": {"font-size": "20px"}},
        ],
        [  # cond @240
            {"backend": 5, "pseudo": None, "style": {"container-type": "inline-size", "font-size": "16px"}},
            {"backend": 7, "pseudo": None, "style": {"font-size": "11px"}},
        ],
    ])
    monkeypatch.setattr(W, "_snapshot_recs", lambda ev, props=None: next(snaps))

    sk = W.capture_with_container_queries(ev, "chrome", "http://x", [240, 480, 720])

    # composite key "<container_node_id>@<width>" = "0@240"; delta on the child node id "1".
    assert sk["_node_container"] == {"1": {"0@240": {"font-size": "11px"}}}
    # clamp: only 240 was set (480/720 > base_w 320 are no-op widenings).
    set_calls = [p for (m, p) in ev.sess.sent
                 if m == "Runtime.callFunctionOn" and "getPropertyValue" in p["functionDeclaration"]]
    assert len(set_calls) == 1 and set_calls[0]["arguments"] == [{"value": "240px"}]
    # revert uses save/restore (setProperty/removeProperty) — NEVER removeAttribute.
    assert not any("removeAttribute" in p.get("functionDeclaration", "")
                   for (m, p) in ev.sess.sent if m == "Runtime.callFunctionOn")
    restore_calls = [p for (m, p) in ev.sess.sent
                     if m == "Runtime.callFunctionOn" and "indexOf('|')" in p["functionDeclaration"]]
    assert len(restore_calls) == 1                      # the one set width was reverted


def test_capture_with_container_queries_clears_forced_on_error(monkeypatch):
    import web_skeleton as W
    ev = _cq_fake_ev(base_w=320)
    node_backend = {0: 5}
    monkeypatch.setattr(W, "_capture_one",
        lambda ev, engine, url, width=None, max_wait=None:
            ({"nodes": [{"id": 0}]}, None, None, node_backend))
    calls = {"n": 0}
    def boom(ev, props=None):
        calls["n"] += 1
        if calls["n"] == 1:                              # base ok
            return [{"backend": 5, "pseudo": None, "style": {"container-type": "inline-size"}}]
        raise RuntimeError("snapshot boom")              # COND fails AFTER the width is set
    monkeypatch.setattr(W, "_snapshot_recs", boom)

    try:
        W.capture_with_container_queries(ev, "chrome", "http://x", [240])
    except RuntimeError:
        pass
    # finally must restore the forced width (a RESTORE callFunctionOn after the failure).
    restore_calls = [p for (m, p) in ev.sess.sent
                     if m == "Runtime.callFunctionOn" and "indexOf('|')" in p["functionDeclaration"]]
    assert restore_calls, "GATE FAIL: forced inline width not restored on error"


def test_sweep_flag_parses_and_defaults_off():
    import web_skeleton as ws
    p = ws._build_argparser()
    assert p.parse_args(["--url", "x"]).sweep is False
    ns = p.parse_args(["--url", "x", "--sweep", "--sweep-steps", "6"])
    assert ns.sweep is True and ns.sweep_steps == 6


def test_default_capture_has_no_below_fold(monkeypatch):
    import web_skeleton as ws
    ns = ws._build_argparser().parse_args(["--url", "x"])
    assert ns.sweep is False   # branch in main() is guarded on this; below_fold cannot be added
