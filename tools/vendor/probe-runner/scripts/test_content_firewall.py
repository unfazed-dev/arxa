# test_content_firewall.py
import content_firewall as cf


def _node(role, **extra):
    n = {"id": 1, "role": role, "bbox": {"x": 0, "y": 0, "w": 100, "h": 40}}
    n.update(extra)
    return n


def test_classify_separates_content_from_mechanism():
    # raster + text are content; box is mechanism. Vary inputs (no collapse).
    assert cf.classify_node(_node("image"))["klass"] == "content"
    assert cf.classify_node(_node("text", text_len=12))["klass"] == "content"
    assert cf.classify_node(_node("box"))["klass"] == "mechanism"
    assert cf.classify_node(_node("unknown_box"))["klass"] == "mechanism"


def test_classify_svg_is_kept_content_with_class():
    # svg geometry is KEPT (user decision) but tagged for swap by size heuristic.
    small = cf.classify_node(_node("svg", bbox={"x": 0, "y": 0, "w": 24, "h": 24}))
    big = cf.classify_node(_node("svg", bbox={"x": 0, "y": 0, "w": 600, "h": 400}))
    assert small["klass"] == "kept-content" and small["svg_class"] == "icon"
    assert big["klass"] == "kept-content" and big["svg_class"] == "illustration"


def test_redact_strips_all_content_keys_keeps_mechanism():
    node = {
        "id": 7, "role": "image",
        "bbox": {"x": 0, "y": 0, "w": 100, "h": 40},
        "token_ref": {"bg": "surface"}, "anim_ref": ["hero#tx"],
        # planted content that must NOT survive:
        "text": "Handcrafted with urushi lacquer",
        "src": "https://kasane.example/photo.jpg",
        "background_image": "url(https://kasane.example/bg.png)",
        "alt": "a hand lacquering a keyboard", "title": "kasane",
        "aria_label": "hero image", "placeholder": "type here", "value": "secret",
    }
    out = cf.redact_node(node)
    for k in cf.CONTENT_KEYS:
        assert k not in out, f"content key {k!r} leaked"
    # mechanism survives:
    assert out["bbox"] == node["bbox"]
    assert out["token_ref"] == {"bg": "surface"}
    assert out["anim_ref"] == ["hero#tx"]


def test_redact_text_node_keeps_only_length_class():
    node = {"id": 9, "role": "text", "bbox": {"x": 0, "y": 0, "w": 80, "h": 20},
            "text": "Buy now", "text_len": 7,
            "font": {"size": 16, "weight": 600, "line": 20, "family": "Inter"}}
    out = cf.redact_node(node)
    assert "text" not in out
    assert out["text_len"] == 7          # length kept (mechanism for sizing)
    assert out["font"]["family"] == "Inter"


# append to test_content_firewall.py
import json


def _clean_bundle(d):
    """Write a minimal clean bundle/ under directory d; return d. Recursive
    mkdir so callers may pass a not-yet-created subdir."""
    d.mkdir(parents=True, exist_ok=True)
    (d / "assets").mkdir(parents=True, exist_ok=True)
    (d / "skeleton.json").write_text(json.dumps(
        {"nodes": [{"id": 1, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10}}]}))
    (d / "tokens.json").write_text(json.dumps({"palette": {"bg": "#fff"}}))
    (d / "motion.json").write_text(json.dumps([]))
    (d / "meta.json").write_text(json.dumps({"url": "x", "schema": 1}))
    return d


def test_audit_passes_clean_bundle(tmp_path):
    assert cf.audit_bundle(_clean_bundle(tmp_path)) == []


def test_audit_catches_each_leak_class(tmp_path):
    # one isolated clean bundle per class, then poison its skeleton.json.
    cases = {
        "datauri": json.dumps({"x": "data:image/png;base64,iVBORw0KGgo="}),
        "prose": json.dumps({"x": "Handcrafted with urushi lacquer by artisans"}),
        "url": json.dumps({"x": "https://kasane.example/hero.jpg"}),
    }
    for name, payload in cases.items():
        d = _clean_bundle(tmp_path / name)
        (d / "skeleton.json").write_text(payload)
        viol = cf.audit_bundle(d)
        assert viol, f"{name}: expected a violation"


def test_audit_catches_raster_magic_bytes(tmp_path):
    _clean_bundle(tmp_path)
    (tmp_path / "assets" / "leak.bin").write_bytes(b"\x89PNG\r\n\x1a\n rest")
    viol = cf.audit_bundle(tmp_path)
    assert any("magic" in v["kind"] for v in viol)


def test_audit_allows_real_font_stacks_and_page_url(tmp_path):
    # mechanism that MUST pass: full font stacks (kept) + a non-media page URL.
    # font families live under keys 'family'/'families' (web_tokens) and in
    # skeleton node font blocks; the prose scan must not flag them. This is the
    # discriminating test — the naive value-substring exemption fails it.
    d = _clean_bundle(tmp_path)
    (d / "tokens.json").write_text(json.dumps({
        "palette": {"background": "#0b0b0c"},
        "type_scale": {
            "families": ["Helvetica Neue, Arial, sans-serif",
                         "system-ui, -apple-system, Segoe UI, Roboto, sans-serif"],
            "sizes": [16, 24, 64], "weights": [400, 700]}}))
    (d / "skeleton.json").write_text(json.dumps({"nodes": [
        {"id": 1, "role": "text", "bbox": {"x": 0, "y": 0, "w": 80, "h": 20},
         "text_len": 7,
         "font": {"size": 16, "weight": 600,
                  "family": "Helvetica Neue, Arial, sans-serif"}}]}))
    (d / "meta.json").write_text(json.dumps(
        {"url": "https://kasane.example/products/keyboard", "schema": 1}))
    assert cf.audit_bundle(d) == []


def test_prose_exemption_is_key_based_not_value_based():
    # a font stack with NO generic font keyword (no sans-serif/serif/etc): it can
    # only be exempted via the JSON KEY, never a value-substring match. This is
    # the genuinely discriminating test — it FAILS under a naive value-substring
    # exemption (which flags it) and PASSES only with key-based exemption.
    stack = "Neue Haas Grotesk Display Pro, Trade Gothic Next Condensed"
    assert cf._prose_in_json({"family": stack}, "tokens.json") == []   # key-exempt
    flagged = cf._prose_in_json({"caption": stack}, "skeleton.json")   # not exempt
    assert flagged and flagged[0]["kind"] == "prose"                   # negative ctrl


def test_audit_catches_nonascii_prose_but_keeps_jp_font_names():
    # Japanese (and other non-Latin) copy decodes via json.loads and must be
    # caught by the non-ASCII detector, NOT slip through the ASCII _PROSE.
    jp = "手作りの漆塗りキーボード。職人が仕上げた本物の製品。"
    assert cf._prose_in_json({"caption": jp}, "skeleton.json")          # caught
    assert cf._prose_in_json({"label": "キーボードドライバー"}, "skeleton.json")  # katakana
    # a Japanese FONT family is kept mechanism (exempt by key, before any scan):
    assert cf._prose_in_json({"family": "ヒラギノ角ゴ ProN, メイリオ"}, "tokens.json") == []


def test_prose_exempt_keys_are_font_only():
    # easing/timing/url are NO LONGER blanket-exempt — prose under them is caught.
    prose = "Buy our handcrafted keyboards today and save big now"
    assert cf._prose_in_json({"ease": prose}, "motion.json")
    assert cf._prose_in_json({"timing": prose}, "motion.json")
    assert cf._prose_in_json({"url": prose}, "meta.json")
    assert cf._PROSE_EXEMPT_KEYS == {"family", "families", "font",
                                     "font_family", "fontFamily"}


def test_audit_catches_iso_bmff_video_magic(tmp_path):
    # ISO-BMFF (mp4/mov/avif/heic): the "ftyp" box type is at byte offset 4,
    # so head.startswith() misses it. Must still be caught.
    _clean_bundle(tmp_path)
    (tmp_path / "assets" / "clip.mp4").write_bytes(
        b"\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom")
    viol = cf.audit_bundle(tmp_path)
    assert any("magic" in v["kind"] for v in viol)


def test_audit_scans_all_text_not_just_whitelisted_extensions(tmp_path):
    # prose in a .js (or extensionless) file must not slip the text-scan gate.
    _clean_bundle(tmp_path)
    (tmp_path / "assets" / "app.js").write_text(
        "var tagline = 'Handcrafted with urushi lacquer by artisans';")
    viol = cf.audit_bundle(tmp_path)
    assert any(v["kind"] == "prose" for v in viol)


def test_audit_passes_states_with_component(tmp_path):
    # A states.json carrying a per-state COMPONENT (re-rooted skeleton + colors +
    # font + mount) must audit content-free: raw rgb()/rgba() colors are short
    # structured CSS tokens the firewall's text scan does not flag (verified), font
    # family is exempt mechanism, role/bbox are geometry, selectors are structural.
    # No node text ever enters the component.
    d = _clean_bundle(tmp_path)
    states = {
        "schema": "probe-states/1", "url": "http://127.0.0.1/",
        "base_nodes": 10, "consent": None,
        "triggers_found": 1, "triggers_driven": 1,
        "states": [{
            "trigger": {"selector": "html > body > button:nth-of-type(1)",
                        "kind": "disclosure", "action": "click"},
            "n_appeared": 2,
            "appeared": [{"role": "region",
                          "bbox": {"x": 40, "y": 40, "w": 320, "h": 180}, "z": 0}],
            "component": {"n_nodes": 2, "nodes": [
                {"id": 0, "role": "region",
                 "bbox": {"x": 40, "y": 40, "w": 320, "h": 180}, "z": 0,
                 "sizing": {"w": "fixed", "h": "hug", "confidence": "high"},
                 "layout": {"mode": "block", "direction": "row"},
                 "colors": {"bg": "rgb(18, 52, 86)", "fg": "rgb(240, 240, 240)", "border": None},
                 "parent": None,
                 "mount": {"role": "box", "bbox": {"x": 0, "y": 0, "w": 1000, "h": 400},
                           "colors": {"bg": "rgba(0, 0, 0, 0)", "fg": None, "border": None}}},
                {"id": 1, "role": "text",
                 "bbox": {"x": 50, "y": 50, "w": 300, "h": 24}, "z": 0,
                 "sizing": {"w": "fill", "h": "hug", "confidence": "high"},
                 "layout": {"mode": "block", "direction": "row"},
                 "colors": {"bg": None, "fg": "rgb(200, 200, 200)", "border": None},
                 "font": {"size": 16.0, "weight": 700, "line_height": 24.0,
                          "letter_spacing": 0.0, "family": "sans-serif", "align": "left"},
                 "parent": 0, "mount": None}]}}]}
    (d / "states.json").write_text(json.dumps(states, indent=2))
    assert cf.audit_bundle(d) == []


def test_audit_passes_states_with_transition(tmp_path):
    # A states.json carrying a per-state TRANSITION (reveal motion-law: CSS property
    # NAMES, numeric timings, easing strings incl. cubic-bezier, bbox anchor) must
    # audit content-free. Easing strings + property names are short structured tokens
    # the firewall's text scan does not flag (same class as rgb()/font-family). No
    # page text, no keyframe values ever enter the transition.
    d = _clean_bundle(tmp_path)
    states = {
        "schema": "probe-states/1", "url": "http://127.0.0.1/",
        "base_nodes": 10, "consent": None,
        "triggers_found": 1, "triggers_driven": 1,
        "states": [{
            "trigger": {"selector": "html > body > button:nth-of-type(1)",
                        "kind": "disclosure", "action": "click"},
            "n_appeared": 1,
            "appeared": [{"role": "region",
                          "bbox": {"x": 40, "y": 40, "w": 320, "h": 180}, "z": 0}],
            "component": {"n_nodes": 1, "nodes": [
                {"id": 0, "role": "region",
                 "bbox": {"x": 40, "y": 40, "w": 320, "h": 180}, "z": 0,
                 "sizing": None, "layout": None,
                 "colors": {"bg": "rgb(18, 52, 86)", "fg": None, "border": None},
                 "parent": None, "mount": None}]},
            "transition": {"n_anims": 2, "anims": [
                {"node": 0, "props": ["opacity", "transform"],
                 "duration_ms": 240.0, "delay_ms": 0,
                 "easing": {"klass": "ease-out", "bezier": [0, 0, 0.58, 1]},
                 "certified": True, "reason": None},
                {"node": None, "props": ["opacity"],
                 "duration_ms": 180.0, "delay_ms": 0,
                 "easing": {"klass": "cubic-bezier", "bezier": [0.1, 0.9, 0.2, 1]},
                 "certified": True, "reason": "unbound"}]}}]}
    (d / "states.json").write_text(json.dumps(states, indent=2))
    assert cf.audit_bundle(d) == []


def test_audit_passes_skeleton_with_redacted_style(tmp_path):
    # A skeleton.json whose nodes carry a content-free `style` (resolved values:
    # filter/gradient/clip-path #ref/border + a redacted external bg image) audits
    # clean. Same structured-token class as rgb()/box-shadow; the one content vector
    # (external url) is already the url("<asset>") marker.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "style": {
                         "filter": "blur(4px)",
                         "backdrop-filter": "blur(8px)",
                         "background-image": "linear-gradient(135deg, rgb(18, 52, 86) 0%, rgb(240, 240, 240) 100%), url(\"<asset>\")",
                         "clip-path": "url(\"#clip-shape\")",
                         "box-shadow": "rgba(0, 0, 0, 0.2) 0px 4px 8px 0px, rgb(18, 52, 86) 0px 0px 0px 1px inset",
                         "border-right-style": "dashed",
                         "border-right-color": "rgb(1, 2, 3)",
                         "border-top-left-radius": "8px",
                         "transform-origin": "200px 130px",
                         "mix-blend-mode": "multiply"}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    assert cf.audit_bundle(d) == []


def test_audit_canary_unredacted_external_url_in_style_trips(tmp_path):
    # Proves the redaction is load-bearing: an UN-redacted external image url in a
    # node style MUST trip the firewall (so a regression in _style cannot ship).
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "style": {"background-image": "url(\"https://cdn.example.com/x.png\")"}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    assert cf.audit_bundle(d) != []


def test_audit_passes_skeleton_with_cut2_style(tmp_path):
    # Cut-2 resolved values (text-shadow, outline, background longhands, object-position,
    # background-clip:text, transform-style) are content-free -> audit clean. No url().
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "style": {
                         "text-shadow": "rgb(0, 0, 0) 1px 1px 2px",
                         "outline-style": "solid",
                         "outline-width": "2px",
                         "outline-color": "rgb(1, 2, 3)",
                         "outline-offset": "3px",
                         "background-repeat": "no-repeat",
                         "background-position": "10px 20px",
                         "background-clip": "text",
                         "object-fit": "cover",
                         "object-position": "25% 75%",
                         "overflow-x": "hidden",
                         "transform-style": "preserve-3d",
                         "perspective": "800px",
                         "writing-mode": "vertical-rl"}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    assert cf.audit_bundle(d) == []


def test_audit_passes_skeleton_with_pseudo(tmp_path):
    # A node["pseudo"] carrying redacted content ("<text>"), inline rgb() colors, an
    # internal #ref clip-path and a redacted external bg audits clean — same
    # structured-token class as node["style"]; the content vector is already redacted.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "pseudo": {
                         "::before": {"content": '"<text>"', "color": "rgb(255, 0, 0)",
                                      "text-shadow": "rgb(0, 0, 0) 1px 1px 2px"},
                         "::after": {"background-image": 'url("<asset>")',
                                     "clip-path": 'url("#c")', "content": '""'},
                         "::marker": {"color": "rgb(0, 128, 0)"}}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    assert cf.audit_bundle(d) == []


def test_audit_canary_unredacted_url_in_pseudo_trips(tmp_path):
    # Proves the pseudo redaction is load-bearing: an UN-redacted external url in a
    # pseudo (here background-image) MUST trip the firewall.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "pseudo": {"::after": {
                         "background-image": 'url("https://cdn.example.com/x.png")'}}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    assert cf.audit_bundle(d) != []


def test_audit_passes_image_set_content_redacted(tmp_path):
    # A pseudo `content: image-set(url(...) 1dppx)` redacted in place to url("<asset>")
    # audits clean — the fixed tokenizer keeps the wrapper whole and redacts the url.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "pseudo": {"::before": {
                         "content": 'image-set(url("<asset>") 1dppx)'}}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    assert cf.audit_bundle(d) == []


def test_audit_canary_unredacted_image_set_url_in_content_trips(tmp_path):
    # The raw, UN-redacted image-set content url (contiguous, as Chrome resolves it) MUST
    # trip the firewall — proving the backstop covers this input form. (The §C9-R-P8 bug
    # was that the OLD redactor FRAGMENTED this at its slashes into a firewall-EVADING
    # shape; the fix instead produces a clean url("<asset>") marker — see the redactor
    # unit tests + test_audit_passes_image_set_content_redacted above.)
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "pseudo": {"::before": {
                         "content": 'image-set(url("https://cdn.example.com/secret-path.png") 1dppx)'}}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    assert cf.audit_bundle(d) != []


def test_audit_passes_skeleton_with_theme(tmp_path):
    # A node["theme"] carrying a PROPERLY-REDACTED theme delta (rgb() color tokens +
    # a redacted external bg image as url("<asset>")) must audit CLEAN — the firewall's
    # string-walker recurses into node.theme[label][prop] as an independent backstop,
    # but the already-redacted values are structured CSS tokens that do not trip any rule.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "theme": {
                         "dark": {"color": "rgb(240, 240, 240)",
                                  "background-image": 'url("<asset>")'}}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    assert cf.audit_bundle(d) == []


def test_audit_canary_unredacted_url_in_theme_trips(tmp_path):
    # Regression-lock: the flat content-url detector catches a retained external url
    # serialized anywhere in the theme JSON. Does NOT prove key-aware walk recursion.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "theme": {
                         "dark": {"background-image": 'url("https://leak.example.com/secret.png")'}}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    viol = cf.audit_bundle(d)
    assert viol, "un-redacted external url in theme delta must trip the audit"


def test_audit_canary_unredacted_image_set_in_theme_trips(tmp_path):
    # Regression-lock: an external url retained inside an image-set(...) wrapper in a
    # theme delta is still caught by the flat content-url detector (the advisor-flagged
    # image-set form). Note: caught via the flat scan, same as the bare-url canary above.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "theme": {
                         "dark": {"background-image":
                                  'image-set(url("https://leak.example.com/secret.png") 1x)'}}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    viol = cf.audit_bundle(d)
    assert viol, "un-redacted image-set url in theme delta must trip the audit"


def test_audit_canary_unredacted_prose_in_theme_trips(tmp_path):
    # Structural proof that audit_bundle's key-aware walker recurses into
    # node["theme"][label][prop]: an un-redacted PROSE leak under a theme prop
    # trips ONLY via _prose_in_json/_walk_strings (the flat _CONTENT_URL/_DATA_URI/
    # _B64_BLOB detectors do NOT match plain prose). If redact_theme ever failed to
    # redact a content value, THIS is the backstop that must catch it.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "theme": {
                         "dark": {"content": "This is leaked prose content here now"}}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    viol = cf.audit_bundle(d)
    assert viol, "un-redacted prose in theme delta must trip the audit"
    assert any(v.get("kind") == "prose" for v in viol), \
        "must trip via the key-aware prose walk (proves theme-path recursion), not a flat detector"


def test_audit_canary_unredacted_prose_in_pseudo_state_trips(tmp_path):
    # Structural proof that audit_bundle's key-aware walker recurses into
    # node["pseudo_state"][label][prop]: an un-redacted PROSE leak under a pseudo-state
    # prop trips ONLY via _prose_in_json/_walk_strings (the flat _CONTENT_URL/_DATA_URI/
    # _B64_BLOB detectors do NOT match plain prose). If redact_pseudo_state ever failed
    # to redact a content value, THIS is the backstop that must catch it. Mirrors the
    # theme prose canary.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "pseudo_state": {
                         "hover": {"content": "This is leaked prose content here now"}}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    viol = cf.audit_bundle(d)
    assert viol, "un-redacted prose in pseudo_state delta must trip the audit"
    assert any(v.get("kind") == "prose" for v in viol), \
        "must trip via the key-aware prose walk (proves pseudo_state recursion), not a flat detector"


def test_audit_canary_unredacted_prose_in_responsive_trips(tmp_path):
    # Structural proof that audit_bundle's key-aware walker recurses into
    # node["responsive"][width_label][prop]: an un-redacted PROSE leak under a
    # responsive prop trips ONLY via _prose_in_json/_walk_strings (the flat
    # _CONTENT_URL/_DATA_URI/_B64_BLOB detectors do NOT match plain prose). If
    # redact_responsive ever failed to redact a content value (e.g. a leaked author
    # grid-line name run), THIS is the backstop that must catch it. Mirrors the theme
    # and pseudo_state prose canaries.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "responsive": {
                         "768": {"display": "This is leaked prose content here now"}}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    viol = cf.audit_bundle(d)
    assert viol, "un-redacted prose in responsive delta must trip the audit"
    assert any(v.get("kind") == "prose" for v in viol), \
        "must trip via the key-aware prose walk (proves responsive recursion), not a flat detector"


def test_audit_canary_unredacted_prose_in_keyframes_trips(tmp_path):
    # Structural proof that audit_bundle's key-aware walker recurses into
    # node["keyframes"][i]["frames"][j]["props"][prop] (through a LIST, not just dicts):
    # an un-redacted PROSE leak under a frame prop trips ONLY via the key-aware prose walk
    # (the flat _CONTENT_URL/_DATA_URI/_B64_BLOB detectors do NOT match plain prose). If
    # redact_keyframes ever failed to redact a content value, THIS is the backstop. Mirrors
    # the theme/pseudo_state/responsive prose canaries.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "keyframes": [{"timing": {"duration": "2s"},
                                    "frames": [{"offset": 0.0,
                                                "props": {"transform":
                                                          "This is leaked prose content here now"}}]}]}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    viol = cf.audit_bundle(d)
    assert viol, "un-redacted prose in a keyframes frame must trip the audit"
    assert any(v.get("kind") == "prose" for v in viol), \
        "must trip via the key-aware prose walk (proves keyframes/list recursion), not a flat detector"


def test_audit_canary_unredacted_prose_in_reduced_motion_trips(tmp_path):
    # Structural proof that audit_bundle's key-aware walker recurses into
    # node["reduced_motion"]["reduce"][prop]: an un-redacted PROSE leak there trips ONLY
    # via the key-aware prose walk (the flat URL/base64 detectors do NOT match plain prose).
    # If redact_reduced_motion ever failed to redact a value, THIS is the backstop. Mirrors
    # the theme/pseudo_state/responsive/keyframes prose canaries.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "reduced_motion": {"reduce": {"animation-name":
                                                   "This is leaked prose content here now"}}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    viol = cf.audit_bundle(d)
    assert viol, "un-redacted prose in a reduced_motion delta must trip the audit"
    assert any(v.get("kind") == "prose" for v in viol), \
        "must trip via the key-aware prose walk (proves reduced_motion recursion), not a flat detector"


def test_audit_canary_unredacted_prose_in_form_state_trips(tmp_path):
    # Structural proof that audit_bundle's key-aware walker recurses into
    # node["form_state"][label][prop]: an un-redacted PROSE leak there trips ONLY via the
    # key-aware prose walk (flat URL/base64 detectors do NOT match plain prose). Backstop if
    # redact_form_state ever failed. Mirrors the reduced_motion/theme/pseudo_state canaries.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "form_state": {"checked": {"accent-color":
                                                "This is leaked prose content here now"}}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    viol = cf.audit_bundle(d)
    assert viol, "un-redacted prose in a form_state delta must trip the audit"
    assert any(v.get("kind") == "prose" for v in viol), \
        "must trip via the key-aware prose walk (proves form_state recursion), not a flat detector"


def test_audit_canary_cursor_url_in_form_state_trips(tmp_path):
    # cursor is the new prop in FORM_PROPS; `cursor: url(...)` can embed a path -> a content
    # vector. The url ends in `.cur` (NOT a media/font extension), so the original _CONTENT_URL
    # allowlist missed it -> _CSS_URL_REF (url()-wrapper, extension-agnostic) is the backstop.
    # CRITICAL: use the REAL serialized shape — Chrome computes cursor url() QUOTED
    # (`url("https://…")`, probe research/capture-gap-probes/probe_url_shape.py), and json.dumps
    # escapes the inner quote on disk to `url(\"https…`. The detector must match that escaped
    # form, not just a naked `url(https…` (which would false-green this canary).
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "form_state": {"disabled":
                                    {"cursor": 'url("https://evil.example.com/secret/path.cur"), auto'}}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    viol = cf.audit_bundle(d)
    assert viol, "a cursor url() in a form_state delta must trip the audit"
    assert any(v.get("kind") == "content-url" for v in viol), \
        "must trip via the url() content-url detector (proves _CSS_URL_REF reaches the escaped form)"


def test_audit_canary_unredacted_prose_in_container_trips(tmp_path):
    import content_firewall as cf
    bundle = tmp_path / "b"
    bundle.mkdir()
    # A node whose `container` delta value smuggles unredacted prose (the failure mode:
    # if a redactor regressed to leak a content string into a @container delta). The flat
    # {label:{prop:value}} shape mirrors what apply_node_container emits.
    leak = "The quick brown fox jumped over the lazy dog repeatedly"   # > _PROSE 24-char floor
    skeleton = {"nodes": [{"id": 0, "role": "box",
                           "container": {"7@240": {"text-align": leak}}}]}
    (bundle / "skeleton.json").write_text(json.dumps(skeleton))
    viol = cf.audit_bundle(str(bundle))
    assert any(v["kind"] == "prose" for v in viol), \
        f"firewall failed to catch prose in a container delta: {viol}"


def test_audit_catches_non_base64_data_uri_encodings(tmp_path):
    # The audit data: backstop must be encoding-AGNOSTIC, matching the redactor it backs
    # (_style._is_external treats ANY data: as content). base64-only lagged it: a bare
    # url-encoded / ;utf8 / plain-text data URI reaching disk from a future capture path
    # would pass the gate silently. `short_text` is below the _PROSE 24-char floor, so it
    # proves the *data-uri* rule fires (not an accidental prose catch); `base64_png` is the
    # regression lock that the broadening did not drop the original base64 coverage.
    cases = {
        "urlenc_svg":  "data:image/svg+xml,%3Csvg%3E%3C/svg%3E",
        "utf8_svg":    "data:image/svg+xml;utf8,<svg/>",
        "short_text":  "data:text/plain,Buy",
        "empty_meta":  "data:,",
        "base64_png":  "data:image/png;base64,iVBORw0KGgo=",
    }
    for name, payload in cases.items():
        d = _clean_bundle(tmp_path / name)
        (d / "skeleton.json").write_text(json.dumps({"x": payload}))
        viol = cf.audit_bundle(d)
        assert any(v["kind"] == "data-uri" for v in viol), \
            f"{name}: expected a data-uri violation, got {viol}"


def test_audit_data_uri_signature_zero_false_positive(tmp_path):
    # The broadened data: signature must NOT fire on legitimate strings. The genuinely
    # discriminating cases (which a BARE `data:[…],` would false-positive, and only the
    # `(?<![a-zA-Z])` word-boundary anchor passes): a value embedding `metadata:foo,` and
    # `somedata:x,` — there `data` is preceded by a letter, so it is NOT a data-URI token start.
    # Plus the easy cases: a JSON key named "data" (serializes as `"data":` — the quote breaks
    # the `data:` literal) and `data:` followed by a space (run stops before the comma).
    d = _clean_bundle(tmp_path)
    (d / "skeleton.json").write_text(json.dumps(
        {"data": "value",
         "note": "report metadata:foo,bar embedded here",   # bare regex FPs; anchor passes
         "n2": "the somedata:x,y token",                     # bare regex FPs; anchor passes
         "k": "the data: here, separated"}))                 # space after colon -> no match
    viol = cf.audit_bundle(d)
    assert not any(v["kind"] == "data-uri" for v in viol), \
        f"false-positive data-uri violation on legitimate strings: {viol}"


def test_aria_role_landmark_audits_clean(tmp_path):
    # Characterization: a node carrying aria_role="navigation" (a landmark token,
    # <=13 chars, well under the _PROSE >=25-char threshold) is mechanism-safe.
    # aria_role is preserved by redact_node (not in CONTENT_KEYS); no logic change needed.
    d = _clean_bundle(tmp_path)
    (d / "skeleton.json").write_text(json.dumps(
        {"nodes": [{"id": 0, "role": "box", "aria_role": "navigation",
                    "bbox": {"x": 0, "y": 0, "w": 10, "h": 10}}]}))
    assert cf.audit_bundle(d) == []


def test_audit_clean_on_pseudo_bbox_geometry(tmp_path):
    # GEOMETRY follow-on: a node's pseudo map carries a content-free bbox (floats) alongside the
    # redacted style. Geometry is mechanism (identical in kind to every node's own bbox) — it must
    # NOT trip the audit. Floats serialize as JSON numbers, never scanned as strings.
    d = _clean_bundle(tmp_path)
    (d / "skeleton.json").write_text(json.dumps({"nodes": [
        {"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 200, "h": 40},
         "pseudo": {"::after": {"bbox": {"x": 0, "y": 39, "w": 200, "h": 1},
                                "background-color": "rgb(1, 2, 3)", "content": "<text>"}}}]}))
    assert cf.audit_bundle(d) == []
