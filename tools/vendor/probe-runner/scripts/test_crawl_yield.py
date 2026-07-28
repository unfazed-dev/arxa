from collections import Counter
import _crawl_yield as cy


def test_bag_jaccard_identical_is_one():
    a = Counter({"x": 2, "y": 1})
    assert cy.bag_jaccard(a, Counter({"x": 2, "y": 1})) == 1.0


def test_bag_jaccard_disjoint_is_zero():
    assert cy.bag_jaccard(Counter({"x": 1}), Counter({"y": 1})) == 0.0


def test_bag_jaccard_partial_overlap():
    # min: x->1, y->0, z->0 => 1 ; max: x->2, y->1, z->1 => 4 ; 1/4
    a = Counter({"x": 1, "y": 1})
    b = Counter({"x": 2, "z": 1})
    assert cy.bag_jaccard(a, b) == 0.25


def test_bag_jaccard_both_empty_is_one():
    assert cy.bag_jaccard(Counter(), Counter()) == 1.0


def test_bag_jaccard_one_empty_is_zero():
    assert cy.bag_jaccard(Counter({"x": 1}), Counter()) == 0.0


def _node(nid, parent=None, aria_role=None, role="generic", href=None, text_len=0):
    n = {"id": nid, "parent": parent, "role": role, "text_len": text_len}
    if aria_role is not None:
        n["aria_role"] = aria_role
    if href is not None:
        n["href"] = href
    return n


def test_content_fingerprint_excludes_chrome():
    # node 1 lives under a navigation landmark (chrome) -> excluded;
    # node 3 lives under main (content) -> included.
    nodes = [
        _node(0, aria_role="navigation"),
        _node(1, parent=0, role="link"),          # chrome -> excluded
        _node(2, aria_role="main"),
        _node(3, parent=2, role="link"),          # content -> included
    ]
    fp = cy.content_fingerprint(nodes)
    # only node 2 (main landmark) and node 3 are content; node 2 itself is a landmark
    # but NOT a chrome landmark, so it is included too.
    assert sum(fp.values()) == 2


def test_content_fingerprint_counts_multiset():
    # two structurally identical content nodes -> one key with count 2
    nodes = [
        _node(0, aria_role="main"),
        _node(1, parent=0, role="listitem", text_len=5),
        _node(2, parent=0, role="listitem", text_len=5),
    ]
    fp = cy.content_fingerprint(nodes)
    listitem_keys = [k for k, c in fp.items() if c == 2]
    assert len(listitem_keys) == 1


def test_frontier_urls_keeps_content_links_to_unenumerated_pages():
    seed_urls = ["https://ex.com/", "https://ex.com/about"]
    # one seed route's nodes:
    nodes = [
        _node(0, aria_role="navigation"),
        _node(1, parent=0, role="link", href="https://ex.com/about"),   # chrome -> dropped
        _node(2, aria_role="main"),
        _node(3, parent=2, role="link", href="https://ex.com/blog/x"),  # content, NOT seed -> KEEP
        _node(4, parent=2, role="link", href="https://ex.com/about"),   # content but IS seed -> drop
        _node(5, parent=2, role="link", href="https://other.com/z"),    # different origin but still resolves; kept only if not seed
        _node(6, parent=2, role="link", href="mailto:a@b.c"),           # non-http -> drop
        _node(7, parent=2, role="link", href="https://ex.com/blog/x#h"),# dup of node 3 after normalize -> collapse
    ]
    targets, n_cross = cy.frontier_urls([nodes], seed_urls)
    norms = {n for n, _ in targets}
    assert "ex.com/blog/x" in norms
    assert "other.com/z" not in norms          # cross-origin now DROPPED by same-origin gate
    assert n_cross >= 1                         # the other.com link counted as cross-origin
    assert "ex.com/about" not in norms          # seed route excluded
    assert all(not k.startswith("mailto") for k in norms)
    # blog/x appears once despite the #fragment duplicate
    assert sum(1 for n, _ in targets if n == "ex.com/blog/x") == 1


def test_count_novel_templates_basic():
    seed = [Counter({"a": 3}), Counter({"b": 3})]
    frontier = [
        Counter({"a": 3}),         # identical to a seed -> NOT novel
        Counter({"z": 5}),         # far from all seeds -> novel
        Counter({"z": 5}),         # identical to the prior novel -> collapses, +0
        Counter({"q": 1, "w": 1}), # novel, distinct from {z} -> +1
    ]
    assert cy.count_novel_templates(frontier, seed, T=0.5) == 2


def test_count_novel_templates_threshold_boundary():
    # bag_jaccard = 0.5 exactly is NOT < T, so the page is "same template", not novel.
    seed = [Counter({"x": 1, "y": 1})]
    frontier = [Counter({"x": 1, "z": 1})]   # jaccard = 1/3 < 0.5 -> novel
    assert cy.count_novel_templates(frontier, seed, T=0.5) == 1
    frontier_same = [Counter({"x": 1, "y": 1, "z": 1})]  # 2/3 >= 0.5 -> not novel
    assert cy.count_novel_templates(frontier_same, seed, T=0.5) == 0


def test_discrimination_matrix_diagonal_is_one():
    seed = [Counter({"a": 1}), Counter({"b": 1})]
    m = cy.discrimination_matrix(seed)
    assert m[0][0] == 1.0 and m[1][1] == 1.0
    assert m[0][1] == 0.0    # different templates -> low


def test_frontier_urls_rejects_lookalike_host():
    seed_urls = ["https://ex.com/"]
    nodes = [
        _node(0, aria_role="main"),
        _node(1, parent=0, role="link", href="https://ex.com.evil.com/x"),  # lookalike -> cross-origin
        _node(2, parent=0, role="link", href="https://ex.com/real"),        # true same-origin -> keep
    ]
    targets, n_cross = cy.frontier_urls([nodes], seed_urls)
    norms = {n for n, _ in targets}
    assert "ex.com/real" in norms
    assert all("evil" not in n for n in norms)
    assert n_cross >= 1


def test_passes_floor():
    assert cy.passes_floor(Counter({"a": 20}), 20) is True        # exactly the floor
    assert cy.passes_floor(Counter({"a": 19}), 20) is False
    assert cy.passes_floor(Counter({"a": 10, "b": 11}), 20) is True   # 21 total
    assert cy.passes_floor(Counter(), 20) is False
