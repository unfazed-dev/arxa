#!/usr/bin/env python3
"""_style — pure core for Regime-1 per-node CSS style redaction (no browser, no I/O).

web_skeleton captures resolved CSS values RAW (incl. url()) into a `_node_style`
sidecar; this module redacts the ONE content vector at packaging time: a url()
pointing at an EXTERNAL (http/https/protocol-relative) or data: asset becomes the
content-free marker url("<asset>"). A same-document #fragment ref (filter:url(#f),
clip-path:url(#c)) is MECHANISM and is kept verbatim. Everything else (gradients,
shapes, shadows, enums, metrics) is content-free as captured. Empirically grounded:
the firewall flags external/data url() (content-url/data-uri) and passes #fragment
refs + the "<asset>" marker. Deterministic; unit-tested; bundle_writer wraps it.

A RELATIVE url (url(/x.png), url(img.png)) is left verbatim by _is_external — safe
ONLY because computed-style url() is browser-resolved to an ABSOLUTE http(s) url
before capture (host gate proves url(/ext.png) reaches disk as url("<asset>")), so a
bare relative url never actually reaches this code from the capture path."""
import re

# An unquoted url() whose payload contains an unescaped ")" (e.g.
# url(data:image/svg+xml,<svg onload="f()">...)) is INVALID CSS and is never
# produced by CSSOM/CDP computed-style capture (which always double-quotes url()).
# The redactor targets valid CSS; the packaging firewall audit is the independent
# backstop for anything malformed. This is an honest ceiling, not full CSS parsing.

# A url() token: optional matching quote, then the target up to the close paren.
_URL = re.compile(r"""url\(\s*(['"]?)(.*?)\1\s*\)""", re.I | re.S)
_ASSET = 'url("<asset>")'


def _is_external(target):
    """True if a url() target is an external/data asset (content) rather than a
    same-document #fragment ref (mechanism)."""
    t = (target or "").strip().lower()
    return (t.startswith("http://") or t.startswith("https://")
            or t.startswith("//") or t.startswith("data:"))


def redact_style_value(value):
    """Replace every external/data: url(...) token in a resolved CSS value with the
    content-free marker url("<asset>"); keep same-doc #fragment url() and all other
    tokens verbatim. Returns the input unchanged when no external url() is present
    (idempotent — the marker has no external target)."""
    # Ceiling (verified, §C9-R-P9 final review): the "url(" early-out is safe even for
    # image-set/cross-fade. Chrome NORMALIZES computed background-image to url(...) form
    # — incl. the bare-string image-set("https://…") and extensionless/typed variants —
    # so a host-bearing value without a literal "url(" never reaches this code from the
    # capture path. The packaging firewall is the independent backstop regardless.
    if not value or "url(" not in value.lower():
        return value

    def _repl(m):
        return _ASSET if _is_external(m.group(2)) else m.group(0)

    return _URL.sub(_repl, value)


def redact_node_styles(style_map):
    """Redact every value in a {prop: resolved_value} map. None/empty-safe."""
    if not style_map:
        return style_map
    return {k: redact_style_value(v) for k, v in style_map.items()}


# A `content` value is a TOKEN LIST: '"label" counter(x) url(...) image-set(url(...) 1x)
# open-quote / "alt"'. Tokenize and classify each token so a url()'s inner quoted string
# is never re-redacted, and the url("<asset>")/"<text>" markers are never re-hit
# (idempotence). The CSS-function arm keeps a wrapper like image-set()/cross-fade()/
# gradient() WHOLE (one balanced-paren nesting level) so a url() Chrome resolves INSIDE it
# (e.g. `content: image-set(url("https://x") 1dppx)` — no space before url() — is verified
# reachable, §C9-R-P8) is not fragmented at its slashes; any url-containing token then
# routes through redact_style_value, which redacts the embedded url() in place.
_CONTENT_TOKEN = re.compile(r"""
      url\(\s*(['"]?).*?\1\s*\)            # url(...) — quoted or bare
    | "(?:[^"\\]|\\.)*"                     # double-quoted string
    | '(?:[^'\\]|\\.)*'                     # single-quoted string
    | counters?\([^)]*\)                   # counter()/counters() (kept as mechanism)
    | [\w-]+\((?:[^()]|\([^()]*\))*\)       # any CSS function: image-set/cross-fade/gradient
    | /                                    # alt-text separator
    | [^\s/]+                              # bareword keyword (open-quote, none, ...)
""", re.I | re.X | re.S)
_TEXT = '"<text>"'


def redact_content_value(content):
    """Redact a resolved pseudo-element `content` value (the one Regime-2 content
    vector). content is a token list; tokenize and classify each token:
    quoted strings (incl. attr-resolved literals) -> "<text>" (empty "" kept — no
    text to redact); ANY token carrying a url() (bare, or wrapped in image-set/
    cross-fade/gradient) -> redacted in place via redact_style_value (external/data
    url() -> url("<asset>"), same-doc url(#frag) kept); counter()/counters(), bare
    gradients (no url), the '/' alt separator, and quote keywords are kept (mechanism).
    none/normal/empty pass through unchanged."""
    if not content:
        return content
    if content.strip().lower() in ("none", "normal", ""):
        return content
    out = []
    for m in _CONTENT_TOKEN.finditer(content):
        tok = m.group(0)
        if tok[:1] in ("'", '"'):
            out.append(tok if len(tok) <= 2 else _TEXT)   # "" (empty) kept; text -> marker
        elif "url(" in tok.lower():
            out.append(redact_style_value(tok))            # bare OR function-wrapped url()
        else:
            out.append(tok)                                # counter()/gradient/keyword/'/'
    return " ".join(out)


def redact_pseudo(pseudos):
    """Redact one node's pseudo map {selector: {prop: raw value}}: the `content`
    prop uses redact_content_value; every other STRING prop reuses redact_style_value
    (the box url() vector — a pseudo background-image/filter). The `bbox` prop is a
    content-free geometry DICT (Regime-2 GEOMETRY follow-on) — passed through verbatim,
    NOT fed to the string value redactor. None/empty-safe."""
    if not pseudos:
        return pseudos
    return {sel: {p: (v if p == "bbox"
                      else redact_content_value(v) if p == "content"
                      else redact_style_value(v))
                  for p, v in style.items()}
            for sel, style in pseudos.items()}


def redact_theme(themes):
    """Redact one node's theme-delta map {condition: {prop: raw value}}: the
    `content` prop uses redact_content_value; every other prop reuses
    redact_style_value (external/data url() -> url("<asset>"); same-doc
    url(#frag), gradients, raw rgb() colors kept). Mirrors redact_pseudo. content
    never actually appears (theme deltas are element-node-scoped, where content
    resolves to `normal`) but is routed correctly as a safety belt. None/empty-
    safe; idempotent."""
    if not themes:
        return themes
    return {label: {p: (redact_content_value(v) if p == "content"
                        else redact_style_value(v))
                    for p, v in delta.items()}
            for label, delta in themes.items()}


# Regime-3b: forced pseudo-class (:hover/:focus/:active) deltas share the theme-delta
# shape ({condition_or_state_label: {prop: raw value}}) byte-for-byte, so they share the
# redactor. Alias (NOT a wrapper) so the two can never drift. DISTINCT from the
# bundle-level `states` (G4 interaction-state) artifact — this is per-node CSS restyle.
redact_pseudo_state = redact_theme

# Regime-3c: responsive multi-viewport reflow deltas share the same
# {width_label: {prop: raw value}} delta shape, so they reuse the redactor. Alias
# (NOT a wrapper) so the two can never drift. Values are CSS keywords/lengths/track-
# lists (no content/url in the RESPONSIVE_PROPS universe), so the redactor is a near-
# no-op here, but the alias keeps firewall recursion + canary symmetry with theme.
redact_responsive = redact_theme


# Regime-P13 reduced-motion: the per-node delta is the flat {label:{prop:value}} theme
# shape (single label "reduce"), so its redactor is the SAME walker — an alias, exactly
# like redact_pseudo_state / redact_responsive. (Contrast redact_keyframes, which needed
# its own walker for the [{timing,frames}] shape.)
redact_reduced_motion = redact_theme


# Form-state (:checked/:disabled): the per-node delta is the flat {label:{prop:value}} theme
# shape (labels "checked"/"disabled"), so its redactor is the SAME walker — an alias, exactly
# like redact_reduced_motion / redact_pseudo_state / redact_responsive. (Contrast
# redact_keyframes, which needed its own walker for the [{timing,frames}] shape.)
redact_form_state = redact_theme

# Fixed-width @container: the per-node delta is the flat {label:{prop:value}} theme shape
# (labels "<container_node_id>@<width>"), so its redactor is the SAME walker — an alias,
# exactly like redact_responsive / redact_reduced_motion / redact_form_state. @container is
# @media's size-threshold sibling, so values are CONTAINER_PROPS (== RESPONSIVE_PROPS) layout
# keywords / lengths / track-lists — no content/url — but the alias keeps firewall recursion +
# canary symmetry with theme. PASSTHROUGH redactor: the firewall is the SOLE backstop.
redact_container = redact_theme


def redact_keyframes(anims):
    """Redact one node's CSS @keyframes timeline list — shape
    [{timing: {...}, frames: [{offset: float, props: {prop: raw value}}]}]. timing
    values are content-free enums/numbers (kept verbatim); each frame prop value routes
    through redact_style_value (external/data url() -> url("<asset>"); same-doc
    url(#frag)/gradients/raw colors kept) via redact_node_styles. NOT an alias of
    redact_theme: the [{timing,frames}] shape differs from the flat {label:{prop:value}}
    theme/pseudo_state/responsive shape, so it needs its own walker. None/empty-safe;
    idempotent. The @keyframes NAME is never present here (dropped at capture)."""
    if not anims:
        return anims
    out = []
    for a in anims:
        frames = [{"offset": fr.get("offset"),
                   "props": redact_node_styles(fr.get("props") or {})}
                  for fr in a.get("frames", [])]
        out.append({"timing": a.get("timing"), "frames": frames})
    return out
