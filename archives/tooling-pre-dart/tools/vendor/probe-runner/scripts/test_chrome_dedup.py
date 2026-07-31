# scripts/test_chrome_dedup.py
import _chrome_dedup as D


def _node(nid, parent=None, role=None, tag="div", **extra):
    n = {"id": nid, "parent": parent, "tag": tag, "z": 0, "confidence": 1.0}
    if role is not None:
        n["aria_role"] = role
    n.update(extra)
    return n


def test_children_and_roots():
    nodes = [_node(1), _node(2, parent=1), _node(3, parent=1), _node(4)]
    bp = D._children(nodes)
    assert [c["id"] for c in bp[1]] == [2, 3]
    assert [r["id"] for r in D._roots(nodes)] == [1, 4]


def test_structural_key_ignores_positional_and_volatile():
    # same structure, different id/parent/bbox/z and different token_ref/text_len -> same key
    a = _node(10, parent=1, role="navigation", token_ref={"bg": "a", "fg": "b", "border": "c"},
              text_len=5, bbox={"x": 0, "y": 0, "w": 10, "h": 10})
    b = _node(99, parent=7, role="navigation", token_ref={"bg": "X", "fg": "Y", "border": "Z"},
              text_len=999, bbox={"x": 5, "y": 5, "w": 20, "h": 20})
    assert D._node_key(a) == D._node_key(b)


def test_structural_key_separates_real_structure():
    # tag is NOT a keyed field; a keyed field (aria_role) must drive the distinction
    a = _node(1, role="navigation")
    b = _node(2, role="banner")
    assert D._node_key(a) != D._node_key(b)


def test_field_vals_reads_nested_and_normalizes_pseudo():
    # direct coverage: _field_vals is reused by later-task code, so pin its contract
    n = _node(1, role="navigation", layout={"mode": "flex"}, sizing={"w": 100},
              font={"family": "x"}, pseudo="::before")
    v = D._field_vals(n)
    assert v["aria_role"] == "navigation" and v["layout.mode"] == "flex"
    assert v["sizing.w"] == 100 and v["font.family"] == "x"
    assert v["pseudo"] == 1                       # truthy pseudo normalizes to 1
    assert D._field_vals(_node(2))["pseudo"] == 0  # absent pseudo -> 0


def test_subtree_key_is_structural_and_recursive():
    nodes = [_node(1, role="navigation"), _node(2, parent=1, tag="a"), _node(3, parent=1, tag="a")]
    bp = D._children(nodes)
    k1 = D._subtree(nodes[0], bp)
    # identical structure under a different banner reuses the same subtree key
    nodes2 = [_node(50, role="navigation"), _node(51, parent=50, tag="a"), _node(52, parent=50, tag="a")]
    bp2 = D._children(nodes2)
    assert D._subtree(nodes2[0], bp2) == k1


def test_volatile_delta_roundtrip():
    tmpl = _node(1, token_ref={"bg": "a", "fg": "b", "border": "c"}, text_len=5)
    inst = _node(2, token_ref={"bg": "a", "fg": "Z", "border": "c"}, text_len=5)  # only fg differs
    delta = D._encode_volatile(tmpl, inst)
    assert delta["flags"] == {"token_ref.fg"}        # exactly the differing leaf is flagged
    assert delta["values"] == {"token_ref.fg": "Z"}  # only the differing value is stored
    rebuilt = _node(2, token_ref={"bg": "a", "fg": "b", "border": "c"}, text_len=5)  # = template vols
    D._apply_volatile(rebuilt, tmpl, delta)
    assert rebuilt["token_ref"] == {"bg": "a", "fg": "Z", "border": "c"} and rebuilt["text_len"] == 5


def test_subtree_key_separates_different_shape():
    # the discriminating direction dedup grouping relies on: a different child count must NOT collide
    two = [_node(1, role="navigation"), _node(2, parent=1, tag="a"), _node(3, parent=1, tag="a")]
    one = [_node(1, role="navigation"), _node(2, parent=1, tag="a")]
    assert D._subtree(two[0], D._children(two)) != D._subtree(one[0], D._children(one))


def _nav_route(base, bg):
    # a 3-node nav landmark (root + 2 links) starting at id `base`, with a per-route bg color
    return [
        _node(base, parent=None, role="navigation", token_ref={"bg": bg, "fg": "f", "border": "b"}),
        _node(base + 1, parent=base, tag="a", text_len=4),
        _node(base + 2, parent=base, tag="a", text_len=4),
    ]


def test_dedup_builds_one_template_for_recurring_chrome():
    routes = {"r0": _nav_route(0, "red"), "r1": _nav_route(100, "blue"), "r2": _nav_route(200, "red")}
    art = D.dedup_chrome(routes)
    assert len(art["templates"]) == 1                 # one structural key recurs across 3 routes
    tk = next(iter(art["templates"]))
    refs = [r for route in art["routes"].values() for r in route["refs"] if r["template"] == tk]
    assert len(refs) == 2                              # 3 instances -> 1 template + 2 refs
    # bbox-only: a ref stores bbox + volatile delta + id_base, NOT parent/z/confidence per node
    sample = refs[0]
    assert "id_base" in sample and "nodes" in sample
    assert set(sample["nodes"][0]) <= {"bbox", "vdelta"}  # per-node payload is bbox + volatile only


def test_singletons_are_not_deduped():
    routes = {"r0": _nav_route(0, "red"),
              "r1": [_node(100, role="banner")]}        # banner appears once -> no template
    art = D.dedup_chrome(routes)
    assert art["templates"] == {} or all(
        len(v) >= 2 for v in _instances_per_key(art).values())


def _instances_per_key(art):
    counts = {}
    for route in art["routes"].values():
        for r in route["refs"]:
            counts.setdefault(r["template"], 0)
            counts[r["template"]] += 1
    return counts


def test_dedup_captures_volatile_delta_and_clean_case_has_no_exceptions():
    routes = {"r0": _nav_route(0, "red"), "r1": _nav_route(100, "blue")}
    art = D.dedup_chrome(routes)
    ref = art["routes"]["r1"]["refs"][0]
    # the per-route bg ("blue") differs from the template ("red") -> captured as a lossless delta
    assert ref["nodes"][0]["vdelta"]["values"] == {"token_ref.bg": "blue"}
    assert ref["nodes"][0]["vdelta"]["flags"] == {"token_ref.bg"}
    # contiguous ids + matching z/confidence -> no positional exceptions, and no leftover rest
    assert ref["exceptions"] == {}
    assert art["routes"]["r1"]["rest"] == []


def test_dedup_charges_exception_when_positional_differs():
    r0 = _nav_route(0, "red")
    r1 = _nav_route(100, "red")
    r1[0]["z"] = 9                                   # template z=0, instance z=9 -> charged exception
    art = D.dedup_chrome({"r0": r0, "r1": r1})
    ref = art["routes"]["r1"]["refs"][0]
    assert ref["exceptions"]["0"] == {"z": 9}


def test_dedup_keeps_non_chrome_nodes_in_rest():
    routes = {"r0": _nav_route(0, "red") + [_node(9, tag="main")],
              "r1": _nav_route(100, "red") + [_node(109, tag="main")]}
    art = D.dedup_chrome(routes)
    assert [n["id"] for n in art["routes"]["r1"]["rest"]] == [109]


def _by_id(nodes):
    return {n["id"]: n for n in nodes}


def test_roundtrip_byte_identical_simple():
    routes = {"r0": _nav_route(0, "red"), "r1": _nav_route(100, "blue"), "r2": _nav_route(200, "red")}
    art = D.dedup_chrome(routes)
    rebuilt = D.reconstruct(art)
    for rid, original in routes.items():
        assert _by_id(rebuilt[rid]) == _by_id(original), rid   # exact node-set equality per route


def test_roundtrip_lossless_when_z_varies_per_instance():
    # z differs across instances -> bbox-only assumption breaks -> must be stored as an exception,
    # and reconstruction must STILL be byte-identical (losslessness is absolute).
    r0 = _nav_route(0, "red")
    r1 = _nav_route(100, "red")
    r1[0]["z"] = 9                                   # template z=0, this instance z=9
    art = D.dedup_chrome({"r0": r0, "r1": r1})
    ref = art["routes"]["r1"]["refs"][0]
    assert ref["exceptions"].get("0", {}).get("z") == 9   # charged (str key), not dropped
    rebuilt = D.reconstruct(art)
    assert _by_id(rebuilt["r1"]) == _by_id(r1)


def test_reconstruct_preserves_non_chrome_rest_nodes():
    routes = {"r0": _nav_route(0, "red") + [_node(9, tag="main")],
              "r1": _nav_route(100, "blue") + [_node(109, tag="main")]}
    art = D.dedup_chrome(routes)
    rebuilt = D.reconstruct(art)
    assert _by_id(rebuilt["r0"]) == _by_id(routes["r0"])
    assert _by_id(rebuilt["r1"]) == _by_id(routes["r1"])


def _footer_route(base):
    # a 3-node contentinfo landmark (distinct structural key from _nav_route)
    return [
        _node(base, parent=None, role="contentinfo", token_ref={"bg": "g", "fg": "f", "border": "b"}),
        _node(base + 1, parent=base, tag="a", text_len=4),
        _node(base + 2, parent=base, tag="a", text_len=4),
    ]


def test_roundtrip_route_that_is_donor_and_ref():
    # r1 is DONOR for the footer key AND holds a REF for the nav key — the composition most likely
    # to break under future edits. Round-trip must stay node-set identical across all routes.
    routes = {
        "r0": _nav_route(0, "red"),
        "r1": _nav_route(100, "red") + _footer_route(103),
        "r2": _footer_route(200),
    }
    art = D.dedup_chrome(routes)
    r1 = art["routes"]["r1"]
    assert r1["donor_keys"] and r1["refs"]          # both present on the same route
    rebuilt = D.reconstruct(art)
    for rid, original in routes.items():
        assert _by_id(rebuilt[rid]) == _by_id(original), rid


def _styled_nav(base, bg, grad):
    # a nav landmark whose root carries a per-route `style` dict (NOT a keyed field, NOT volatile);
    # `grad` varies per route. Pre-fix: dropped on reconstruct -> lossy.
    n = _nav_route(base, bg)
    n[0]["style"] = {"border-top-width": "1px", "background-image": grad}
    return n


def test_roundtrip_lossless_when_unkeyed_style_varies():
    r0 = _styled_nav(0, "red", "linear-gradient(a)")
    r1 = _styled_nav(100, "red", "linear-gradient(b)")     # same struct key, different style
    art = D.dedup_chrome({"r0": r0, "r1": r1})
    ref = art["routes"]["r1"]["refs"][0]
    assert ref["exceptions"].get("0", {}).get("style", {}).get("background-image") == "linear-gradient(b)"
    rebuilt = D.reconstruct(art)
    assert _by_id(rebuilt["r1"]) == _by_id(r1)
    assert _by_id(rebuilt["r0"]) == _by_id(r0)


def test_roundtrip_lossless_when_instance_lacks_a_template_field():
    # template (donor r0) node carries `style`; instance (r1) has NONE -> reconstruct must DROP it
    r0 = _styled_nav(0, "red", "linear-gradient(a)")
    r1 = _nav_route(100, "red")                            # same struct key, NO style at all
    art = D.dedup_chrome({"r0": r0, "r1": r1})
    ref = art["routes"]["r1"]["refs"][0]
    assert "style" in ref["drop"].get("0", [])
    rebuilt = D.reconstruct(art)
    assert _by_id(rebuilt["r1"]) == _by_id(r1)


def test_roundtrip_lossless_on_real_skeleton_fixture():
    # the REAL python.org chrome pair that exposed the bug (an unkeyed field varies per route).
    # Pre-fix this round-trip was NOT node-set identical; post-fix it must be, for every route.
    import json, pathlib
    data = json.loads((pathlib.Path(__file__).resolve().parent / "fixtures" / "g3d_real_chrome.json").read_text())
    art = D.dedup_chrome(data)
    rebuilt = D.reconstruct(art)
    for rid, original in data.items():
        assert _by_id(rebuilt[rid]) == _by_id(original), rid


def test_key_fields_match_canonical_and_structural_key_matches_with_drop():
    """Drift guard: _chrome_dedup._KEY_FIELDS must equal the canonical in _shape_key.
    Also verifies that _chrome_dedup._node_key(n) (which hard-wires _DROP_STRUCT) produces
    the same string as _shape_key._node_key(n, drop=_chrome_dedup._DROP_STRUCT), so the two
    modules stay in agreement after the re-export swap."""
    import _shape_key
    # 1. field-list identity
    assert D._KEY_FIELDS == _shape_key._KEY_FIELDS, (
        "_chrome_dedup._KEY_FIELDS has drifted from _shape_key._KEY_FIELDS"
    )
    # 2. structural-key equivalence on a representative set of nodes
    samples = [
        _node(1, role="navigation", token_ref={"bg": "red", "fg": "white", "border": "grey"},
              text_len=10, layout={"mode": "flex"}, pseudo="::before"),
        _node(2, parent=1, role="banner", sizing={"w": 100, "h": 50},
              font={"family": "Arial", "weight": "bold"}),
        _node(3),  # all-defaults node
    ]
    for n in samples:
        assert D._node_key(n) == _shape_key._node_key(n, drop=D._DROP_STRUCT), (
            f"structural key mismatch for node {n}"
        )
