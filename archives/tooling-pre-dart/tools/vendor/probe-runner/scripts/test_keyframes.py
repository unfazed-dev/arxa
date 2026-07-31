import os
import sys

sys.path.insert(0, os.path.dirname(__file__))  # noqa: E402
import _keyframes as kf  # noqa: E402

ANIMATABLE = ["transform", "opacity", "filter", "color", "background-color",
              "border-color", "box-shadow", "translate", "rotate", "scale"]


def _rule(name, frames):
    # frames: list of (keyText, [(prop, value), ...]). keyText mirrors the REAL CDP
    # CSSKeyframeRule.keyText Value shape {text, range}; the parser also tolerates a bare
    # string (the inline rule builders elsewhere exercise that fallback path).
    return {"animationName": {"text": name},
            "keyframes": [{"keyText": {"text": kt},
                           "style": {"cssProperties": [{"name": p, "value": v}
                                                       for p, v in props]}}
                          for kt, props in frames]}


def test_offset_from_keytext_percents_and_from_to():
    assert kf._offset_from_keytext("0%") == [0.0]
    assert kf._offset_from_keytext("50%") == [0.5]
    assert kf._offset_from_keytext("100%") == [1.0]
    assert kf._offset_from_keytext("from") == [0.0]
    assert kf._offset_from_keytext("to") == [1.0]
    assert kf._offset_from_keytext("0%, 100%") == [0.0, 1.0]   # comma list -> per offset
    assert kf._offset_from_keytext("garbage") == []


def test_parse_keyframes_single_animation_offsets_props_and_timing():
    rules = [_rule("spin", [("0%", [("transform", "rotate(0deg)")]),
                            ("100%", [("transform", "rotate(360deg)")])])]
    anim = {"animation-name": "spin", "animation-duration": "2s",
            "animation-timing-function": "linear", "animation-iteration-count": "infinite",
            "animation-direction": "normal", "animation-delay": "0s",
            "animation-fill-mode": "none"}
    out = kf.parse_keyframes(rules, anim, ANIMATABLE)
    assert len(out) == 1
    assert out[0]["timing"] == {"duration": "2s", "easing": "linear",
                                "iterations": "infinite", "direction": "normal",
                                "delay": "0s", "fill": "none"}
    assert out[0]["frames"] == [{"offset": 0.0, "props": {"transform": "rotate(0deg)"}},
                                {"offset": 1.0, "props": {"transform": "rotate(360deg)"}}]
    assert "animationName" not in str(out)   # author name dropped


def test_parse_keyframes_dedups_longhand_shorthand_and_filters_whitelist():
    # probe PR3: props arrive duplicated; non-animatable props must be filtered out.
    rules = [_rule("p", [("50%", [("transform", "scale(1.2)"), ("transform", "scale(1.2)"),
                                  ("opacity", "0.4"), ("width", "10px")])])]
    anim = {"animation-name": "p", "animation-duration": "3s"}
    out = kf.parse_keyframes(rules, anim, ANIMATABLE)
    assert out[0]["frames"] == [{"offset": 0.5,
                                 "props": {"transform": "scale(1.2)", "opacity": "0.4"}}]
    # width (not animatable) excluded; duplicate transform collapsed


def test_parse_keyframes_multi_animation_name_matched_pairing():
    # two animations; rules in REVERSE order -> must pair by name (transiently), timing
    # positionally by the animation-name list order, then drop the name.
    rules = [_rule("pulse", [("0%", [("opacity", "1")])]),
             _rule("spin", [("0%", [("transform", "rotate(0deg)")])])]
    anim = {"animation-name": "spin, pulse", "animation-duration": "2s, 3s",
            "animation-timing-function": "linear, ease"}
    out = kf.parse_keyframes(rules, anim, ANIMATABLE)
    assert len(out) == 2
    assert out[0]["frames"][0]["props"] == {"transform": "rotate(0deg)"}  # spin first
    assert out[0]["timing"]["duration"] == "2s" and out[0]["timing"]["easing"] == "linear"
    assert out[1]["frames"][0]["props"] == {"opacity": "1"}               # pulse second
    assert out[1]["timing"]["duration"] == "3s" and out[1]["timing"]["easing"] == "ease"


def test_parse_keyframes_drop_on_miss_and_empty():
    # animation-name references a @keyframes with no matching rule -> dropped.
    assert kf.parse_keyframes([], {"animation-name": "ghost"}, ANIMATABLE) == []
    # animation-name none -> nothing.
    assert kf.parse_keyframes([_rule("x", [("0%", [("opacity", "1")])])],
                              {"animation-name": "none"}, ANIMATABLE) == []


def test_frames_drop_property_with_missing_value():
    # a cssProperties entry lacking "value" must NOT reach output as {prop: None}.
    rule = {"animationName": {"text": "p"},
            "keyframes": [{"keyText": "0%", "style": {"cssProperties": [
                {"name": "opacity"},                       # no value -> dropped
                {"name": "transform", "value": "scale(1)"}]}}]}
    out = kf.parse_keyframes([rule], {"animation-name": "p"}, ANIMATABLE)
    assert out[0]["frames"] == [{"offset": 0.0, "props": {"transform": "scale(1)"}}]


def test_split_list_respects_paren_depth_for_cubic_bezier():
    # commas inside cubic-bezier(...) must not split; two animations -> two easings.
    assert kf._split_list("cubic-bezier(0.4, 0, 0.2, 1), ease") == \
        ["cubic-bezier(0.4, 0, 0.2, 1)", "ease"]
    assert kf._split_list("linear") == ["linear"]
    assert kf._split_list("") == []
    # multi-animation timing-function pairs correctly after paren-aware split
    rules = [{"animationName": {"text": "a"},
              "keyframes": [{"keyText": "0%", "style": {"cssProperties": [
                  {"name": "opacity", "value": "1"}]}}]},
             {"animationName": {"text": "b"},
              "keyframes": [{"keyText": "0%", "style": {"cssProperties": [
                  {"name": "opacity", "value": "0"}]}}]}]
    anim = {"animation-name": "a, b",
            "animation-timing-function": "cubic-bezier(0.4, 0, 0.2, 1), ease"}
    out = kf.parse_keyframes(rules, anim, ANIMATABLE)
    assert out[0]["timing"]["easing"] == "cubic-bezier(0.4, 0, 0.2, 1)"
    assert out[1]["timing"]["easing"] == "ease"


def test_parse_keyframes_keytext_cdp_value_dict_shape():
    # regression (host gate): real CDP keyText is a Value dict {text, range}, NOT a bare
    # string (the design PR3 mis-recorded this). The parser must unwrap .text.
    rules = [{"animationName": {"text": "spin"},
              "keyframes": [{"keyText": {"text": "0%", "range": {"startLine": 1}},
                             "style": {"cssProperties": [{"name": "opacity", "value": "0"}]}},
                            {"keyText": {"text": "100%", "range": {"startLine": 2}},
                             "style": {"cssProperties": [{"name": "opacity", "value": "1"}]}}]}]
    out = kf.parse_keyframes(rules, {"animation-name": "spin"}, ANIMATABLE)
    assert out[0]["frames"] == [{"offset": 0.0, "props": {"opacity": "0"}},
                                {"offset": 1.0, "props": {"opacity": "1"}}]
