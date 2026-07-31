# scripts/test_url_template.py
import _url_template as ut


def test_query_page_param_same_template_distinct_index():
    a = ut.paginate_key("https://x.test/blog/?page=2")
    b = ut.paginate_key("https://x.test/blog/?page=3")
    assert a is not None and b is not None
    assert a[0] == b[0]          # same template
    assert (a[1], b[1]) == (2, 3)


def test_query_p_param_and_other_params_preserved():
    a = ut.paginate_key("https://x.test/list?p=1&sort=asc")
    b = ut.paginate_key("https://x.test/list?p=2&sort=asc")
    assert a is not None and a[0] == b[0]
    assert "sort=asc" in a[0]    # non-page params kept in the template


def test_path_page_segment():
    a = ut.paginate_key("https://x.test/news/page/4")
    b = ut.paginate_key("https://x.test/news/page/5")
    assert a is not None and a[0] == b[0] and (a[1], b[1]) == (4, 5)


def test_trailing_numeric_segment():
    a = ut.paginate_key("https://x.test/archive/10")
    b = ut.paginate_key("https://x.test/archive/11")
    assert a is not None and a[0] == b[0] and (a[1], b[1]) == (10, 11)


def test_host_canonicalized_www_stripped():
    a = ut.paginate_key("https://www.x.test/b/?page=2")
    b = ut.paginate_key("https://x.test/b/?page=3")
    assert a is not None and a[0] == b[0]


def test_non_paginated_returns_none():
    assert ut.paginate_key("https://x.test/about/") is None
    assert ut.paginate_key("https://x.test/") is None


def test_non_digit_page_param_returns_none():
    # the v.isdigit() guard: ?page=abc is not a pagination signal
    assert ut.paginate_key("https://x.test/blog/?page=abc") is None


def test_mixed_alnum_trailing_segment_not_paginated():
    # only a PURE-digit segment adjacent to '/' is a pagination index; mixed
    # alnum leaf segments (versions, slugs, sku ids) must NOT be grouped as pages
    assert ut.paginate_key("https://x.test/v2") is None
    assert ut.paginate_key("https://x.test/blog/v2") is None
    assert ut.paginate_key("https://x.test/product/abc-123") is None


def test_fragment_stripped_from_template():
    # urlsplit isolates the fragment; the template carries no '#...'
    tmpl, idx = ut.paginate_key("https://x.test/blog/?page=2#section")
    assert idx == 2 and "#" not in tmpl


def test_sibling_key_shared_parent():
    assert ut.sibling_key("https://x.test/blog/foo") == ut.sibling_key("https://x.test/blog/bar")
    assert ut.sibling_key("https://x.test/blog/foo") != ut.sibling_key("https://x.test/news/baz")


def test_group_tier1_pagination_only_when_two_or_more():
    urls = ["https://x.test/b/?page=2", "https://x.test/b/?page=3", "https://x.test/solo/?page=9"]
    g = ut.group_by_template(urls)
    assert len(g["tier1"]) == 1                     # the /b/ template (2 members)
    members = next(iter(g["tier1"].values()))
    assert len(members) == 2
    assert g["tier2"] == {}                         # solo singleton dropped


def test_group_tier2_siblings_exclude_paginated():
    urls = ["https://x.test/blog/foo", "https://x.test/blog/bar",
            "https://x.test/blog/page/2", "https://x.test/blog/page/3"]
    g = ut.group_by_template(urls)
    assert len(g["tier1"]) == 1                     # the /blog/page/{} pagination group
    assert len(g["tier2"]) == 1                     # foo+bar siblings, NOT the paginated ones
    assert all("page/2" not in m and "page/3" not in m
               for m in next(iter(g["tier2"].values())))


def test_group_dedups_identical_urls():
    g = ut.group_by_template(["https://x.test/b/?page=2", "https://x.test/b/?page=2"])
    assert g["tier1"] == {} and g["tier2"] == {}    # one distinct url -> no pair


def test_sibling_key_root_and_single_segment_collapse():
    # root and any single-segment (top-level) page share the root parent key, so top-level
    # pages form one Tier-2 group together (corroborative-only; documents the edge)
    assert ut.sibling_key("https://x.test/") == "https://x.test/"
    assert ut.sibling_key("https://x.test/about") == "https://x.test/"


def test_within_group_pairs_combinations():
    g = ut.group_by_template(["https://x.test/b/?page=2", "https://x.test/b/?page=3",
                              "https://x.test/b/?page=4"])
    pairs = ut.within_group_pairs(g["tier1"])
    assert len(pairs) == 3                          # C(3,2)
    for a, b in pairs:
        assert a != b


def test_across_group_pairs_only_cross_template():
    urls = ["https://x.test/b/?page=2", "https://x.test/b/?page=3",   # template A
            "https://x.test/news/foo"]                                # group B
    pairs = ut.across_group_pairs(urls)
    # the two /b/ pages share a template -> excluded; each pairs with /news/foo -> 2 pairs
    assert len(pairs) == 2
    flat = {frozenset(p) for p in pairs}
    assert all("https://x.test/news/foo" in p for p in pairs)
    assert frozenset(("https://x.test/b/?page=2", "https://x.test/b/?page=3")) not in flat


def test_across_group_pairs_all_same_template_is_empty():
    # negative case of the exclusion filter: every page shares one template -> no cross pair
    pairs = ut.across_group_pairs(["https://x.test/b/?page=2", "https://x.test/b/?page=3",
                                   "https://x.test/b/?page=4"])
    assert pairs == []
