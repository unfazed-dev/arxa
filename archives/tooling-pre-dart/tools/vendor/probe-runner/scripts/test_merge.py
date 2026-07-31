"""Pure cross-route token-merge core units (G3b). No CDP."""


def test_freq_entries_core_and_sort():
    import _merge
    entries = _merge._freq_entries({"a": ["r00", "r01"], "b": ["r01"]}, n=2)
    assert entries[0] == {"value": "a", "routes": 2,
                          "route_ids": ["r00", "r01"], "core": True}
    assert entries[1] == {"value": "b", "routes": 1,
                          "route_ids": ["r01"], "core": False}


def test_freq_entries_dedups_route_ids():
    import _merge
    e = _merge._freq_entries({"a": ["r00", "r00", "r01"]}, n=2)
    assert e[0]["route_ids"] == ["r00", "r01"] and e[0]["routes"] == 2


def test_merge_scalars_freq_and_core():
    import _merge
    rows = [
        ("r00", {"type_scale": [16, 24], "weights": [400]}),
        ("r01", {"type_scale": [16], "weights": [400, 700]}),
    ]
    out = _merge.merge_scalars(rows)
    ts = {e["value"]: e for e in out["type_scale"]}
    assert ts[16]["core"] is True and ts[16]["routes"] == 2
    assert ts[24]["core"] is False and ts[24]["route_ids"] == ["r00"]
    assert set(out) == {"type_scale", "weights", "families",
                        "spacing", "radii", "shadows"}
    assert out["radii"] == []


def test_exact_role_groups_by_value():
    import _merge
    rows = [("r00", {"accent": "#3b82f6"}),
            ("r01", {"accent": "#3b82f6"}),
            ("r02", {"accent": "#ef4444"})]
    m = _merge._exact_role(rows, "accent")
    assert m == {"#3b82f6": ["r00", "r01"], "#ef4444": ["r02"]}


def test_exact_role_skips_null_and_missing():
    import _merge
    rows = [("r00", {"border": None}), ("r01", {})]
    assert _merge._exact_role(rows, "border") == {}


def test_merge_palette_exact_core_and_delta():
    import _merge
    rows = [("r00", {"background": "#fff", "accent": "#3b82f6"}),
            ("r01", {"background": "#fff", "accent": "#ef4444"})]
    pal = _merge.merge_palette(rows, cluster_tol=8)
    assert set(pal) == set(_merge.PALETTE_ROLES)
    bg = pal["background"]["exact"]
    assert len(bg) == 1 and bg[0]["value"] == "#fff" and bg[0]["core"] is True
    acc = {e["value"]: e for e in pal["accent"]["exact"]}
    assert acc["#3b82f6"]["core"] is False and acc["#ef4444"]["core"] is False
    assert pal["surface"]["exact"] == []


def test_clustered_merges_within_tol():
    import _merge
    # #0b0b0b vs #0c0c0c differ by 1 per channel -> within tol 8 -> one cluster
    rows = [("r00", {"background": "#0b0b0b"}), ("r01", {"background": "#0c0c0c"})]
    cl = _merge.merge_palette(rows, cluster_tol=8)["background"]["clustered"]
    assert len(cl) == 1
    assert cl[0]["routes"] == 2 and cl[0]["core"] is True
    # exact view still distinguishes them
    assert len(_merge.merge_palette(rows, 8)["background"]["exact"]) == 2


def test_clustered_separate_beyond_tol():
    import _merge
    rows = [("r00", {"accent": "#0b0b0b"}), ("r01", {"accent": "#f5f5f5"})]
    cl = _merge.merge_palette(rows, cluster_tol=8)["accent"]["clustered"]
    assert len(cl) == 2 and all(e["core"] is False for e in cl)


def test_clustered_per_role_isolation():
    import _merge
    # identical hex in different roles must never merge across roles
    rows = [("r00", {"accent": "#3b82f6", "border": "#3b82f6"})]
    pal = _merge.merge_palette(rows, cluster_tol=8)
    assert len(pal["accent"]["clustered"]) == 1
    assert len(pal["border"]["clustered"]) == 1


def test_build_design_system_shape():
    import _merge
    per_route = [
        ("r00", {"palette": {"background": "#fff", "accent": "#3b82f6"},
                 "type_scale": [16, 24]}),
        ("r01", {"palette": {"background": "#fff", "accent": "#ef4444"},
                 "type_scale": [16]}),
    ]
    ds = _merge.build_design_system(per_route, hosts=["e.com"], cluster_tol=8)
    assert ds["schema"] == "probe-runner/design-system@1"
    assert ds["hosts"] == ["e.com"]
    assert ds["merged_route_count"] == 2
    assert ds["route_ids"] == ["r00", "r01"]
    assert ds["cluster_tol"] == 8
    assert set(ds["palette"]) == set(_merge.PALETTE_ROLES)
    assert set(ds["scalars"]) == set(_merge.SCALAR_CATS)
    bg = ds["palette"]["background"]["exact"]
    assert bg[0]["value"] == "#fff" and bg[0]["core"] is True


def test_build_design_system_n1_all_core():
    import _merge
    ds = _merge.build_design_system(
        [("r00", {"palette": {"accent": "#3b82f6"}, "spacing": [8]})],
        hosts=["e.com"], cluster_tol=8)
    assert ds["merged_route_count"] == 1
    assert ds["palette"]["accent"]["exact"][0]["core"] is True
    assert ds["scalars"]["spacing"][0]["core"] is True


def test_merge_scalars_families_uses_family_key():
    import _merge
    stack = "Helvetica Neue, Arial, Liberation Sans"
    out = _merge.merge_scalars([("r00", {"families": [stack]}),
                                ("r01", {"families": [stack]})])
    fam = out["families"][0]
    assert "family" in fam and "value" not in fam
    assert fam["family"] == stack and fam["core"] is True
    # every other category keeps "value"
    ts = _merge.merge_scalars([("r00", {"type_scale": [16]})])["type_scale"][0]
    assert "value" in ts and "family" not in ts
