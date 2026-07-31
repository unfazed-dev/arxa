"""Unit tests for the pure _crawl ship core (§C9-R-CRAWL-BUILD)."""
from collections import Counter
import _crawl as cw


def _node(nid, parent=None, aria_role=None, role="generic", href=None, text_len=0):
    n = {"id": nid, "parent": parent, "role": role, "text_len": text_len}
    if aria_role is not None:
        n["aria_role"] = aria_role
    if href is not None:
        n["href"] = href
    return n


# --- cap_frontier ---
def test_cap_frontier_under_cap_unchanged():
    f = [("a", "ha", 0), ("b", "hb", 0)]
    capped, n_over = cw.cap_frontier(f, 5)
    assert capped == f and n_over == 0


def test_cap_frontier_over_cap_truncates_and_counts():
    f = [("a", "1", 0), ("b", "2", 0), ("c", "3", 1)]
    capped, n_over = cw.cap_frontier(f, 2)
    assert capped == [("a", "1", 0), ("b", "2", 0)] and n_over == 1


def test_cap_frontier_empty():
    assert cw.cap_frontier([], 10) == ([], 0)


# --- reject_reason / accept ---
def test_reject_reason_subfloor():
    assert cw.reject_reason(Counter({"k": 5}), [], [], 0.5, 20) == "subfloor"


def test_reject_reason_not_novel_when_matches_seed():
    seed = Counter({"a": 20})
    assert cw.reject_reason(Counter({"a": 20}), [seed], [], 0.5, 20) == "not_novel"


def test_reject_reason_dup_of_kept():
    seed = Counter({"a": 20})
    kept = Counter({"z": 20})
    assert cw.reject_reason(Counter({"z": 20}), [seed], [kept], 0.5, 20) == "dup"


def test_reject_reason_none_means_capture():
    seed = Counter({"a": 20})
    kept = Counter({"z": 20})
    assert cw.reject_reason(Counter({"q": 21}), [seed], [kept], 0.5, 20) is None


def test_accept_wraps_reject_reason():
    seed = Counter({"a": 20})
    assert cw.accept(Counter({"q": 21}), [seed], [], 0.5, 20) is True
    assert cw.accept(Counter({"a": 20}), [seed], [], 0.5, 20) is False


def test_accept_no_seeds_is_vacuously_novel():
    assert cw.accept(Counter({"q": 20}), [], [], 0.5, 20) is True


def test_accept_kept_set_statefulness():
    seed = [Counter({"a": 20})]
    fp = Counter({"z": 20})
    kept = []
    assert cw.accept(fp, seed, kept, 0.5, 20) is True
    kept.append(fp)
    assert cw.accept(fp, seed, kept, 0.5, 20) is False


# --- frontier_targets provenance ---
def test_frontier_targets_records_src_idx():
    seed_urls = ["https://ex.com/", "https://ex.com/docs"]
    route0 = [_node(0, aria_role="main"),
              _node(1, parent=0, role="link", href="https://ex.com/blog/x")]   # from seed 0
    route1 = [_node(0, aria_role="main"),
              _node(1, parent=0, role="link", href="https://ex.com/guide")]    # from seed 1
    targets, n_cross = cw.frontier_targets([route0, route1], seed_urls)
    by_norm = {norm: src for norm, _href, src in targets}
    assert by_norm["ex.com/blog/x"] == 0
    assert by_norm["ex.com/guide"] == 1
    assert n_cross == 0


def test_frontier_targets_first_seed_wins_on_collision():
    seed_urls = ["https://ex.com/", "https://ex.com/docs"]
    link = "https://ex.com/shared"
    route0 = [_node(0, aria_role="main"), _node(1, parent=0, role="link", href=link)]
    route1 = [_node(0, aria_role="main"), _node(1, parent=0, role="link", href=link)]
    targets, _ = cw.frontier_targets([route0, route1], seed_urls)
    src = {norm: s for norm, _h, s in targets}["ex.com/shared"]
    assert src == 0


def test_frontier_targets_drops_cross_origin_and_chrome():
    seed_urls = ["https://ex.com/"]
    nodes = [
        _node(0, aria_role="navigation"),
        _node(1, parent=0, role="link", href="https://ex.com/chrome-link"),    # chrome -> drop
        _node(2, aria_role="main"),
        _node(3, parent=2, role="link", href="https://other.com/x"),           # cross-origin -> drop+count
        _node(4, parent=2, role="link", href="https://ex.com/keep"),           # content same-origin -> keep
    ]
    targets, n_cross = cw.frontier_targets([nodes], seed_urls)
    norms = {n for n, _h, _s in targets}
    assert norms == {"ex.com/keep"} and n_cross == 1


def test_frontier_urls_wrapper_matches_legacy_shape():
    seed_urls = ["https://ex.com/"]
    nodes = [_node(0, aria_role="main"), _node(1, parent=0, role="link", href="https://ex.com/p")]
    targets, n_cross = cw.frontier_urls([nodes], seed_urls)
    assert targets == [("ex.com/p", "https://ex.com/p")] and n_cross == 0


def test_reject_reason_t_boundary_is_not_novel():
    # bag_jaccard exactly == T must be treated as "same template" (>= T), not novel.
    from collections import Counter
    seed = Counter({"x": 1, "y": 1})
    fp = Counter({"x": 1, "y": 1, "z": 1, "w": 1})   # Sum min=2 / Sum max=4 = 0.5 == T
    assert cw.bag_jaccard(fp, seed) == 0.5
    assert cw.reject_reason(fp, [seed], [], T=0.5, floor=0) == "not_novel"


def test_frontier_targets_empty_seed_preserves_index():
    # seed 0 captured nothing (empty list); seed 1 has the link -> src_idx must be 1.
    seed_urls = ["https://ex.com/", "https://ex.com/docs"]
    route0 = []
    route1 = [_node(0, aria_role="main"),
              _node(1, parent=0, role="link", href="https://ex.com/found")]
    targets, n_cross = cw.frontier_targets([route0, route1], seed_urls)
    src = {norm: s for norm, _h, s in targets}["ex.com/found"]
    assert src == 1
