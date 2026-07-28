import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import probe_g3c_richness_gated as P

LM = {"navigation", "main", "banner", "contentinfo", "complementary", "region", "form"}


def node(nid, role, parent, aria=None, styled=False):
    """Minimal skeleton node. styled -> flex layout + a bg token_ref (passes C._is_styled)."""
    return {
        "id": nid, "role": role, "parent": parent, "aria_role": aria,
        "layout": {"mode": "flex" if styled else "block", "direction": "row",
                   "gap": 0.0, "pad": [0, 0, 0, 0], "justify": "normal", "align": "normal",
                   "grid_cols": None, "grid_rows": None},
        "sizing": {"w": "fixed", "h": "fixed", "confidence": "high"},
        "token_ref": {"bg": "surface" if styled else None, "fg": None, "border": None},
    }


def test_node_token_level0_is_role_only_level1_adds_layout_and_aria_anchor():
    plain = node(1, "box", 0, styled=True)
    assert P._node_token(plain, 0) == "box"
    assert "flex" in P._node_token(plain, 1)
    landmark = node(2, "box", 0, aria="navigation", styled=True)
    assert P._node_token(landmark, 1).startswith("navigation@")


def test_route_sigs_anchor_on_landmark_aria_roots_only():
    # nav landmark (id1) with 2 styled children; a non-landmark styled box (id4) is NOT a root.
    nodes = [
        node(0, "unknown_box", None),
        node(1, "box", 0, aria="navigation", styled=True),
        node(2, "link", 1, styled=True), node(3, "link", 1, styled=True),
        node(4, "box", 0, styled=True),  # styled but no aria -> not a landmark root
    ]
    sigs, by_parent = P._route_sigs_with_meta(nodes, 1, LM)
    assert len(sigs) == 1                       # only the navigation root
    only = next(iter(sigs))
    assert only.startswith("navigation@")
    assert P._route_sig_set(nodes, 1, LM) == set(sigs)


def _rich_routes():
    """4 identical routes with 3 recurring landmark structures -> core=3, jac=1.0."""
    def one():
        return [node(0, "unknown_box", None),
                node(1, "box", 0, aria="navigation", styled=True),
                node(2, "link", 1, styled=True), node(3, "button", 1, styled=True),
                node(4, "box", 0, aria="region", styled=True),
                node(5, "button", 4, styled=True), node(6, "text", 4, styled=True),
                node(7, "box", 0, aria="form", styled=True),
                node(8, "textbox", 7, styled=True), node(9, "button", 7, styled=True)]
    return [one() for _ in range(4)]


def _divergent_routes():
    """One shared region card (recurs) + a navigation whose child ROLE differs per route
    (vary role, NOT count -- collapse policy collapses count). core=1 (region only), jac~0.33."""
    uniq = ["button", "text", "link", "image"]
    def one(r):
        return [node(0, "unknown_box", None),
                node(1, "box", 0, aria="region", styled=True),
                node(2, "button", 1, styled=True), node(3, "text", 1, styled=True),
                node(4, "box", 0, aria="navigation", styled=True),
                node(5, uniq[r], 4, styled=True), node(6, "image", 4, styled=True)]
    return [one(r) for r in range(4)]


def test_gate_passes_when_landmark_structures_recur_across_routes():
    gated, best = P.gate(_rich_routes(), LM)
    assert gated is True
    assert best["core"] >= P.GATE_CORE and best["jac"] >= P.GATE_JAC


def test_gate_fails_when_landmark_compositions_diverge_across_routes():
    gated, best = P.gate(_divergent_routes(), LM)
    assert gated is False
    assert (best["core"] < P.GATE_CORE) or (best["jac"] < P.GATE_JAC)


def _card_route():
    """A recurring 'card': region landmark > styled box with a styled accent button + styled
    text (>=2 styled children, 2 distinct roles, not subset of {text}). PLUS a generic
    box>text repeat and a single-child wrapper that MUST be excluded."""
    nodes = [node(0, "unknown_box", None)]
    # the card (novel): region root -> box -> (button, text)
    nodes += [node(1, "box", 0, aria="region", styled=True),
              node(2, "box", 1, styled=True),
              node(3, "button", 2, styled=True), node(4, "text", 2, styled=True)]
    # generic wrapper (must be EXCLUDED): main -> box -> text only
    nodes += [node(5, "box", 0, aria="main", styled=True),
              node(6, "box", 5, styled=True), node(7, "text", 6, styled=True)]
    # single-child styled wrapper (EXCLUDED: <2 styled children): form -> box -> box
    nodes += [node(8, "box", 0, aria="form", styled=True),
              node(9, "box", 8, styled=True)]
    return nodes


def test_composition_novel_includes_real_card_excludes_generic_and_single_child():
    routes = [_card_route() for _ in range(4)]   # all three structures recur on all routes
    novel = P.composition_novel_components(routes, 1, LM)
    # exactly one novel component: the region card. main(box>text) and form(box) excluded.
    assert len(novel) == 1
    assert novel[0].startswith("region@")


def test_composition_novel_requires_two_distinct_child_roles():
    # region > box > (button, button): 2 styled children but only ONE role -> excluded.
    def two_same(_):
        return [node(0, "unknown_box", None),
                node(1, "box", 0, aria="region", styled=True),
                node(2, "box", 1, styled=True),
                node(3, "button", 2, styled=True), node(4, "button", 2, styled=True)]
    assert P.composition_novel_components([two_same(i) for i in range(4)], 1, LM) == []


def test_coverage_excludes_chrome_and_counts_styled_main_under_novel_only():
    nodes = _card_route()                      # region card (novel) + generic main + form
    routes = [_card_route() for _ in range(4)]
    novel = P.composition_novel_components(routes, 1, LM)   # the region card sig
    cov = P.coverage(nodes, novel, 1, LM)
    # styled main-content (not under banner/nav/contentinfo/complementary):
    #   region card subtree {1,2,3,4}=4, generic-main subtree {5,6,7}=3, form subtree {8,9}=2,
    #   root id0 is unknown_box NOT styled. Total styled main = 4+3+2 = 9.
    # covered = region card subtree styled nodes {1,2,3,4} = 4. 4/9 = 0.444.
    assert cov == 0.444


def test_coverage_zero_when_no_novel_components():
    nodes = _card_route()
    assert P.coverage(nodes, [], 1, LM) == 0.0


def test_coverage_drops_chrome_landmark_subtrees():
    # a navigation (chrome) card identical to a region (main) card; only the region one counts.
    def mixed(_):
        return [node(0, "unknown_box", None),
                node(1, "box", 0, aria="region", styled=True),
                node(2, "button", 1, styled=True), node(3, "text", 1, styled=True),
                node(4, "box", 0, aria="navigation", styled=True),
                node(5, "button", 4, styled=True), node(6, "text", 4, styled=True)]
    routes = [mixed(i) for i in range(4)]
    novel = P.composition_novel_components(routes, 1, LM)
    # both region@ and navigation@ are novel; coverage counts only the region (main) subtree.
    cov = P.coverage(mixed(0), novel, 1, LM)
    # styled main = region subtree {1,2,3}=3 (nav subtree {4,5,6} is chrome-excluded). covered=3. 3/3=1.0
    assert cov == 1.0


def _res(netloc, gated, novel, cov):
    return {"netloc": netloc, "gated_in": gated, "novel": novel, "coverage": cov}


def test_verdict_build_when_controls_clean_and_three_rich_clear():
    controls = [_res("python.org", True, 2, 0.05), _res("w3.org", True, 1, 0.10)] + \
               [_res(n, False, 0, 0.0) for n in ("iana.org", "django", "gnu", "apache")]
    rich = [_res("mui.com", True, 7, 0.30), _res("ant.design", True, 6, 0.22),
            _res("getbootstrap.com", True, 5, 0.18), _res("primer.style", True, 3, 0.10)]
    v, _why = P.verdict(controls, rich)
    assert v == "BUILD"


def test_verdict_defer_when_a_control_clears_the_value_bar():
    controls = [_res("python.org", True, 6, 0.20)] + [_res(n, False, 0, 0.0) for n in "bcdef"]
    rich = [_res("mui.com", True, 7, 0.30), _res("ant.design", True, 6, 0.22),
            _res("getbootstrap.com", True, 5, 0.18), _res("primer.style", True, 5, 0.16)]
    v, _ = P.verdict(controls, rich)
    assert v == "DEFER"


def test_verdict_defer_as_finding_when_fewer_than_four_rich_gate_in():
    controls = [_res(n, False, 0, 0.0) for n in "abcdef"]
    rich = [_res("mui.com", True, 9, 0.40), _res("ant.design", True, 8, 0.35),
            _res("getbootstrap.com", True, 7, 0.30)] + [_res("x", False, 0, 0.0)]
    v, why = P.verdict(controls, rich)
    assert v == "DEFER" and "rich" in why.lower()


def test_richness_predicate_rich_when_enough_landmarks_and_repeated_subtrees():
    nodes = [node(0, "unknown_box", None)]
    # 4 distinct landmark roles
    for j, ar in enumerate(("navigation", "main", "complementary", "form")):
        nodes.append(node(100 + j, "box", 0, aria=ar, styled=True))
        nodes.append(node(200 + j, "text", 100 + j, styled=True))
    # 8 DISTINCT repeated styled subtree shapes, each appearing twice (occ=2). n_repeated counts
    # DISTINCT sigs with occ>=2 -> need 8 different shapes, not one shape x8.
    nid = 300
    for r2 in ("button", "text", "link", "image", "heading", "textbox", "menuitem", "tab"):
        for _ in range(2):
            nodes += [node(nid, "box", 0, styled=True),
                      node(nid + 1, r2, nid, styled=True), node(nid + 2, "text", nid, styled=True)]
            nid += 3
    is_rich, n_lm, n_rep = P.richness_predicate(nodes, LM)
    assert n_lm >= P.RICH_LANDMARKS and n_rep >= P.RICH_SUBTREES and is_rich is True


def test_richness_predicate_sparse_when_few_landmarks():
    nodes = [node(0, "unknown_box", None), node(1, "box", 0, aria="navigation", styled=True),
             node(2, "text", 1, styled=True)]
    is_rich, n_lm, n_rep = P.richness_predicate(nodes, LM)
    assert is_rich is False


def test_site_coverage_is_median_not_mean():
    # one dense route must NOT mask sparse ones: mean 0.175 would clear 0.15; median 0.10 fails.
    assert P._site_coverage([0.10, 0.10, 0.10, 0.40]) == 0.10


def test_site_coverage_odd_even_and_empty():
    assert P._site_coverage([0.1, 0.2, 0.3]) == 0.2
    assert P._site_coverage([0.1, 0.3]) == 0.2
    assert P._site_coverage([]) == 0.0


def test_composition_novelty_ignores_branch_below_signature_depth():
    # The branch (button,text) sits at depth 4 (region>box>box>box>(button,text)); the depth-3
    # signature cannot see it, so it must NOT count as novel -- novelty = f(signature), not of
    # below-window structure. (Unbounded scan would wrongly flag it, route-order-dependently.)
    def deep(_):
        return [node(0, "unknown_box", None),
                node(1, "box", 0, aria="region", styled=True),   # d=3 (root)
                node(2, "box", 1, styled=True),                   # d=2
                node(3, "box", 2, styled=True),                   # d=1
                node(4, "box", 3, styled=True),                   # d=0 -> its children NOT in sig
                node(5, "button", 4, styled=True), node(6, "text", 4, styled=True)]
    assert P.composition_novel_components([deep(i) for i in range(4)], 1, LM) == []
