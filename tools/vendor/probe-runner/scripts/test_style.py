import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _style import redact_style_value, redact_node_styles  # noqa: E402
from _style import redact_content_value, redact_pseudo  # noqa: E402
from _style import redact_theme, redact_pseudo_state, redact_responsive  # noqa: E402
from _style import redact_keyframes  # noqa: E402
from _style import redact_reduced_motion  # noqa: E402
from _style import redact_form_state  # noqa: E402
from _style import redact_container  # noqa: E402


def test_no_url_passthrough():
    assert redact_style_value("blur(10px)") == "blur(10px)"
    assert redact_style_value("polygon(0% 0%, 100% 0%, 100% 75%)") == "polygon(0% 0%, 100% 0%, 100% 75%)"


def test_external_https_url_redacted():
    assert redact_style_value('url("https://cdn.example.com/x.png")') == 'url("<asset>")'


def test_external_http_and_protocol_relative_redacted():
    assert redact_style_value('url("http://a/b.png")') == 'url("<asset>")'
    assert redact_style_value('url("//cdn/a.png")') == 'url("<asset>")'


def test_data_uri_redacted():
    assert redact_style_value('url("data:image/png;base64,AAAA")') == 'url("<asset>")'


def test_same_doc_fragment_kept():
    assert redact_style_value('url("#blur")') == 'url("#blur")'
    assert redact_style_value("url(#clip-shape)") == "url(#clip-shape)"


def test_layered_value_redacts_only_external_url():
    v = 'linear-gradient(135deg, rgb(1, 2, 3) 0%, rgb(4, 5, 6) 100%), url("https://a/b.png")'
    out = redact_style_value(v)
    assert "linear-gradient(135deg, rgb(1, 2, 3) 0%, rgb(4, 5, 6) 100%)" in out
    assert 'url("<asset>")' in out and "https://a/b.png" not in out


def test_mixed_internal_and_external_urls():
    v = 'url("#mask"), url("https://a/b.png")'
    out = redact_style_value(v)
    assert 'url("#mask")' in out and 'url("<asset>")' in out and "https" not in out


def test_idempotent():
    once = redact_style_value('url("https://a/b.png")')
    assert redact_style_value(once) == once


def test_redact_node_styles_maps_each_value():
    m = {"filter": "blur(2px)", "background-image": 'url("https://a/b.png")',
         "clip-path": "url(#c)"}
    assert redact_node_styles(m) == {
        "filter": "blur(2px)", "background-image": 'url("<asset>")', "clip-path": "url(#c)"}


def test_redact_node_styles_none_safe():
    assert redact_node_styles(None) is None
    assert redact_node_styles({}) == {}


def test_unquoted_external_url_redacted():
    assert redact_style_value("url(http://a/b.png)") == 'url("<asset>")'
    assert redact_style_value("url(https://cdn.example.com/x.png)") == 'url("<asset>")'


def test_unquoted_data_uri_redacted():
    assert redact_style_value("url(data:image/png;base64,AAAA)") == 'url("<asset>")'


def test_unquoted_fragment_kept():
    assert redact_style_value("url(#c)") == "url(#c)"


def test_content_string_redacted_to_text_marker():
    assert redact_content_value('"Read more"') == '"<text>"'
    assert redact_content_value("'Menu'") == '"<text>"'


def test_content_glyph_and_attr_resolved_redacted():
    assert redact_content_value('"→"') == '"<text>"'      # decorative glyph
    assert redact_content_value('"LABEL"') == '"<text>"'        # attr() resolved to a literal


def test_content_counter_and_quote_keywords_kept():
    assert redact_content_value("counter(foo)") == "counter(foo)"
    assert redact_content_value("counters(item, '.')") == "counters(item, '.')"
    assert redact_content_value("open-quote") == "open-quote"


def test_content_external_url_redacted_internal_kept():
    assert redact_content_value('url("https://a/b.png")') == 'url("<asset>")'
    assert redact_content_value('url("#frag")') == 'url("#frag")'


def test_content_mixed_url_and_string():
    assert redact_content_value('url("http://a/x.png") " label"') == 'url("<asset>") "<text>"'


def test_content_alt_text_form():
    assert redact_content_value('"icon" / "alt label"') == '"<text>" / "<text>"'


def test_content_empty_string_kept():
    assert redact_content_value('""') == '""'        # no text to redact


def test_content_none_normal_passthrough():
    assert redact_content_value("none") == "none"
    assert redact_content_value("normal") == "normal"
    assert redact_content_value(None) is None


def test_content_idempotent():
    once = redact_content_value('"Read more"')
    assert redact_content_value(once) == once         # "<text>" stays "<text>"
    u = redact_content_value('url("http://a/x.png")')
    assert redact_content_value(u) == u               # url("<asset>") stays


def test_redact_pseudo_redacts_content_and_box_url():
    pseudos = {"::before": {"content": '"Buy now"', "color": "rgb(1, 2, 3)"},
               "::after": {"background-image": 'url("https://a/b.png")', "content": '""'}}
    out = redact_pseudo(pseudos)
    assert out["::before"]["content"] == '"<text>"'
    assert out["::before"]["color"] == "rgb(1, 2, 3)"          # box value untouched
    assert out["::after"]["background-image"] == 'url("<asset>")'
    assert out["::after"]["content"] == '""'


def test_redact_pseudo_none_safe():
    assert redact_pseudo(None) is None
    assert redact_pseudo({}) == {}


def test_redact_pseudo_passes_bbox_through_untouched():
    # GEOMETRY follow-on: the pseudo's own bbox is content-free mechanism (floats). redact_pseudo
    # maps redact_style_value over every non-content prop (expects strings) — the bbox DICT must be
    # passed through verbatim, not fed to the value redactor. content/url still redacted.
    pseudos = {"::after": {"content": '"Sale"',
                           "bbox": {"x": 1.5, "y": 2.0, "w": 200.0, "h": 1.0},
                           "background-image": 'url("https://a/b.png")'}}
    out = redact_pseudo(pseudos)
    assert out["::after"]["bbox"] == {"x": 1.5, "y": 2.0, "w": 200.0, "h": 1.0}  # untouched
    assert out["::after"]["content"] == '"<text>"'
    assert out["::after"]["background-image"] == 'url("<asset>")'


def test_content_image_set_wrapped_url_redacted():
    # Chrome resolves `content: image-set(url("/e.png") 1x)` to a function-wrapped url
    # with NO space before url( (verified reachable, §C9-R-P8). The url MUST be redacted
    # in place, not fragmented at its slashes (the bug this guards).
    assert redact_content_value('image-set(url("https://cdn.example.com/x.png") 1dppx)') \
        == 'image-set(url("<asset>") 1dppx)'
    assert redact_content_value('-webkit-image-set(url("http://a/x.png") 1x)') \
        == '-webkit-image-set(url("<asset>") 1x)'
    # internal same-doc url() inside a wrapper is kept (mechanism)
    assert redact_content_value('image-set(url("#frag") 1x)') == 'image-set(url("#frag") 1x)'


def test_content_image_set_no_host_or_path_survives():
    # the load-bearing assertion: NO part of the external host/path leaks through.
    out = redact_content_value('image-set(url("https://cdn.example.com/secret-path.png") 1dppx)')
    assert "cdn.example.com" not in out
    assert "secret-path" not in out
    assert out == 'image-set(url("<asset>") 1dppx)'


def test_content_bare_gradient_kept():
    # a gradient resolves to colors only (no url) -> content-free mechanism, kept verbatim.
    g = "linear-gradient(rgb(255, 0, 0), rgb(0, 0, 255))"
    assert redact_content_value(g) == g


def test_content_image_set_idempotent():
    once = redact_content_value('image-set(url("https://cdn.example.com/x.png") 1dppx)')
    assert redact_content_value(once) == once         # image-set(url("<asset>") 1dppx) stays


def test_redact_theme_redacts_box_url_keeps_rgb():
    themes = {"dark": {"color": "rgb(240, 240, 240)",
                       "background-image": 'url("https://a/b.png")'},
              "contrast": {"color": "rgb(0, 0, 0)"}}
    out = redact_theme(themes)
    assert out["dark"]["color"] == "rgb(240, 240, 240)"          # raw rgb kept
    assert out["dark"]["background-image"] == 'url("<asset>")'    # external url redacted
    assert out["contrast"]["color"] == "rgb(0, 0, 0)"


def test_redact_theme_keeps_same_doc_fragment_url():
    out = redact_theme({"dark": {"clip-path": "url(#c)"}})
    assert out["dark"]["clip-path"] == "url(#c)"


def test_redact_theme_routes_content_through_content_redactor():
    out = redact_theme({"dark": {"content": '"Buy now"'}})
    assert out["dark"]["content"] == '"<text>"'


def test_redact_theme_none_and_empty_safe():
    assert redact_theme(None) is None
    assert redact_theme({}) == {}


def test_redact_theme_image_set_background_no_host_leak():
    # background-image image-set() resolved value: must redact via the STYLE path
    # (not content) with NO host/path surviving. Regression-lock for the style-side
    # image-set handling, since THEME_PROPS routes background-image through
    # redact_style_value, not redact_content_value.
    out = redact_theme({"dark": {"background-image":
        'image-set(url("https://cdn.example.com/secret-path.png") 1x)'}})
    v = out["dark"]["background-image"]
    assert "cdn.example.com" not in v and "secret-path" not in v
    assert v == 'image-set(url("<asset>") 1x)'


def test_redact_pseudo_state_is_redact_theme_alias():
    # Regime-3b pseudo-class deltas share the theme delta shape exactly; the redactor
    # is the SAME function (alias, not a copy) so the two can never drift.
    assert redact_pseudo_state is redact_theme


def test_redact_pseudo_state_redacts_external_url_keeps_rgb():
    out = redact_pseudo_state({"hover": {"color": "rgb(0, 128, 0)",
                                         "background-image": 'url("https://a/b.png")'}})
    assert out["hover"]["color"] == "rgb(0, 128, 0)"           # raw rgb kept
    assert out["hover"]["background-image"] == 'url("<asset>")'  # external url redacted


def test_redact_responsive_is_redact_theme_alias():
    # Regime-3c responsive deltas share the {label:{prop:value}} delta shape exactly;
    # the redactor is the SAME function (alias, not a copy) so the two cannot drift.
    assert redact_responsive is redact_theme


def test_redact_responsive_keeps_layout_value_redacts_url():
    out = redact_responsive({"768": {"display": "block",
                                     "background-image": 'url("https://a/b.png")'}})
    assert out["768"]["display"] == "block"          # layout keyword kept verbatim
    assert out["768"]["background-image"] == 'url("<asset>")'   # external url redacted


def test_redact_keyframes_keeps_timing_and_layout_redacts_url():
    anims = [{"timing": {"duration": "2s", "easing": "linear", "iterations": "infinite",
                         "direction": "normal", "delay": "0s", "fill": "none"},
              "frames": [{"offset": 0.0, "props": {"transform": "rotate(0deg)"}},
                         {"offset": 1.0, "props": {"transform": "rotate(360deg)",
                                                   "filter": 'url("https://a/b.svg#x")'}}]}]
    out = redact_keyframes(anims)
    assert out[0]["timing"]["iterations"] == "infinite"        # timing kept verbatim
    assert out[0]["frames"][0]["offset"] == 0.0                # offset kept
    assert out[0]["frames"][0]["props"]["transform"] == "rotate(0deg)"   # layout value kept
    assert out[0]["frames"][1]["props"]["filter"] == 'url("<asset>")'    # external url redacted


def test_redact_reduced_motion_is_redact_theme_alias():
    # reduced_motion is a flat {label:{prop:value}} delta, identical in shape to a theme
    # delta -> the redactor is the SAME function (alias), like redact_pseudo_state/responsive.
    assert redact_reduced_motion is redact_theme
    out = redact_reduced_motion({"reduce": {"animation-name": "none",
                                            "transition-duration": "0s",
                                            "scroll-behavior": "auto"}})
    assert out == {"reduce": {"animation-name": "none", "transition-duration": "0s",
                              "scroll-behavior": "auto"}}
    assert redact_reduced_motion(None) is None


def test_redact_form_state_is_redact_theme_alias():
    # form_state is a flat {label:{prop:value}} delta (labels "checked"/"disabled"), identical in
    # shape to a theme delta -> the redactor is the SAME function (alias), like
    # redact_reduced_motion / redact_pseudo_state / redact_responsive.
    assert redact_form_state is redact_theme
    out = redact_form_state({"checked": {"opacity": "0.5", "accent-color": "rgb(11, 22, 33)"},
                             "disabled": {"opacity": "0.4", "cursor": "not-allowed"}})
    assert out == {"checked": {"opacity": "0.5", "accent-color": "rgb(11, 22, 33)"},
                   "disabled": {"opacity": "0.4", "cursor": "not-allowed"}}
    assert redact_form_state(None) is None


def test_redact_container_is_redact_theme_alias():
    from _style import redact_theme
    assert redact_container is redact_theme           # alias, not a wrapper (cannot drift)
    delta = {"0@240": {"display": "flex", "font-size": "11px"}}
    assert redact_container(delta) == delta           # passthrough on the flat shape
    assert redact_container(redact_container(delta)) == delta   # idempotent
    assert redact_container(None) is None             # None-safe (matches redact_theme)


def test_redact_keyframes_is_not_redact_theme_alias_and_none_safe():
    # Distinct SHAPE ([{timing,frames}] vs flat {label:{prop}}) => its own walker, not an alias.
    assert redact_keyframes is not redact_theme
    assert redact_keyframes(None) is None
    assert redact_keyframes([]) == []
    # a frame missing "props" normalizes to an empty dict (uniform shape, never None)
    assert redact_keyframes([{"timing": {}, "frames": [{"offset": 0.0}]}]) == \
        [{"timing": {}, "frames": [{"offset": 0.0, "props": {}}]}]
