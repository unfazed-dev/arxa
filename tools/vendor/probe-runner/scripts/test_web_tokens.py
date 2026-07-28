# test_web_tokens.py
import web_tokens as wt


# ---- B1: parse_color + cluster_colors ----

def test_parse_color_rgb_and_hex():
    assert wt.parse_color("rgb(11, 11, 12)") == (11, 11, 12)
    assert wt.parse_color("rgba(245, 245, 240, 1)") == (245, 245, 240)
    assert wt.parse_color("#0b0b0c") == (11, 11, 12)
    assert wt.parse_color("transparent") is None
    assert wt.parse_color("rgba(0,0,0,0)") is None


def test_parse_color_clamps_out_of_range_rgb():
    # channels above 255 must clamp, not corrupt _hex into a 7-char string
    assert wt.parse_color("rgb(300,0,0)") == (255, 0, 0)
    assert wt._hex(wt.parse_color("rgb(300,0,0)")) == "#ff0000"
    assert len(wt._hex(wt.parse_color("rgb(300,0,0)"))) == 7
    assert wt.parse_color("rgba(300, 999, 256, 1)") == (255, 255, 255)


def test_parse_color_three_digit_hex():
    assert wt.parse_color("#abc") == (170, 187, 204)


def test_parse_color_invalid_returns_none():
    assert wt.parse_color("currentColor") is None
    assert wt.parse_color("transparent") is None
    assert wt.parse_color("none") is None
    assert wt.parse_color("not-a-color") is None
    assert wt.parse_color("") is None
    assert wt.parse_color(None) is None


def test_cluster_representative_is_dominant_area():
    # the largest-area shade must represent the merged cluster
    samples = [("rgb(10,10,11)", 5), ("rgb(11,11,12)", 1000)]
    clusters = wt.cluster_colors(samples, tol=8)
    assert len(clusters) == 1
    assert clusters[0][0] == wt._hex((11, 11, 12))
    assert clusters[0][1] == 1005


def test_cluster_merges_near_duplicates():
    samples = [
        ("rgb(11,11,12)", 1000.0),
        ("rgb(12,12,13)", 50.0),     # within tol of the first
        ("rgb(10,10,11)", 20.0),     # within tol of the first
        ("rgb(245,245,240)", 800.0), # distinct light
    ]
    clusters = wt.cluster_colors(samples, tol=8)
    assert len(clusters) == 2
    dark = next(c for c in clusters if c[1] > 1000)
    assert dark[1] == 1070.0


# ---- B2: assign_roles ----

def test_assign_roles_picks_bg_fg_accent():
    bg = [("rgb(11,11,12)", 5000.0), ("rgb(21,21,26)", 1200.0)]
    fg = [("rgb(245,245,240)", 400), ("rgb(154,154,147)", 120), ("rgb(200,85,42)", 30)]
    borders = [("rgb(42,42,48)", 60)]
    roles = wt.assign_roles(bg, fg, borders)
    assert roles["background"]["value"] == "#0b0b0c"
    assert roles["surface"]["value"] == "#15151a"
    assert roles["fg-primary"]["value"] == "#f5f5f0"
    assert roles["fg-muted"]["value"] == "#9a9a93"     # muted grey, lowest saturation
    assert roles["accent"]["value"] == "#c8552a"       # saturated outlier
    assert roles["border"]["value"] == "#2a2a30"
    for r in roles.values():
        assert r["confidence"] in ("high", "low")


def test_assign_roles_low_confidence_when_ambiguous():
    bg = [("rgb(11,11,12)", 5000.0)]
    fg = [("rgb(245,245,240)", 400)]
    borders = []
    roles = wt.assign_roles(bg, fg, borders)
    assert roles["surface"]["confidence"] == "low"     # no second bg
    assert roles["fg-muted"]["confidence"] == "low"    # no second text color
    assert roles["accent"]["confidence"] == "low"
    assert roles["border"]["confidence"] == "low"      # no border samples


def test_assign_roles_empty_input_no_crash():
    roles = wt.assign_roles([], [], [])
    for name in ("background", "surface", "fg-primary", "fg-muted", "accent", "border"):
        assert roles[name]["value"] is None
        assert roles[name]["confidence"] == "low"


# ---- B3: build_scales ----

def test_build_scales_dedups_and_sorts():
    nodes = [
        {"font": {"size": 16, "weight": 400, "family": "Inter"}},
        {"font": {"size": 16, "weight": 700, "family": "Inter"}},
        {"font": {"size": 64, "weight": 700, "family": "Inter"}},
        {"font": {"size": 14, "weight": 400, "family": "Georgia"}},
    ]
    spaces = [8.0, 8.0, 16.0, 24.0, 4.0]
    radii = [0.0, 4.0, 4.0, 12.0]
    shadows = ["0 1px 2px rgba(0,0,0,.1)", "none", "0 1px 2px rgba(0,0,0,.1)"]
    result = wt.build_scales(nodes, spaces, radii, shadows)
    # FLAT return shape (the §5.2 tokens.json scale fields), no "scales" wrapper
    assert result["type_scale"] == [14, 16, 64]
    assert result["weights"] == [400, 700]
    assert result["families"] == ["Georgia", "Inter"]
    assert result["spacing"] == [4, 8, 16, 24]
    assert result["radii"] == [0, 4, 12]
    assert result["shadows"] == ["0 1px 2px rgba(0,0,0,.1)"]


def test_build_scales_empty_input():
    result = wt.build_scales([], [], [], [])
    assert result["type_scale"] == []
    assert result["weights"] == []
    assert result["families"] == []
    assert result["spacing"] == []
    assert result["radii"] == []
    assert result["shadows"] == []


# ---- G10: collection pass descends open shadow roots ----

def test_collect_js_descends_shadow_roots():
    # The single in-page collection pass must recurse into el.shadowRoot, else
    # web-component design tokens (colors/type/radius scoped inside open shadow
    # roots) are missed. Guards against silent removal of the G10 descent.
    js = wt._COLLECT_JS
    assert "shadowRoot" in js, "collect JS no longer descends shadow roots (G10 regression)"
