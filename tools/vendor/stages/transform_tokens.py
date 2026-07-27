#!/usr/bin/env python3
"""transform_tokens.py — W3C DTCG tokens.json → per-platform token files.

Style Dictionary-style transforms, stdlib only. Emits:
  - Dart:   <out>/dart/app_tokens.dart      (Color / double / String / List<double>)
  - Swift:  <out>/ios/AppTokens.swift        (UIColor / CGFloat)
  - XML:    <out>/android/tokens.xml         (<color> / <dimen> resources)

Deterministic: same tokens.json → same files. The factory's native primitives
consume their platform's token file so the *style* is identical across platforms
even though the widgets differ.

Usage:
    transform_tokens.py <tokens.json> <out-dir>
"""
import json
import os
import re
import sys


def camel(s: str) -> str:
    parts = [p for p in re.split(r"[^0-9a-zA-Z]+", s) if p]
    if not parts:
        return "token"
    parts[0] = re.sub(r"^[^a-zA-Z]+", "", parts[0]) or "t"
    return parts[0].lower() + "".join(p.capitalize() for p in parts[1:])


def parse_color(v: str):
    """Return (r,g,b,a) 0-255 (clamped) or None.

    Handles: #rgb, #rrggbb, #aarrggbb (alpha-first), rgb(), rgba(). Per CSS spec, rgba()
    alpha is 0-1, so it is clamped to [0,1] before ×255 (a stray 0-255 alpha like
    rgba(...,255) would otherwise yield 65025). rgb channels are clamped to [0,255] so an
    out-of-range input never produces a non-byte Color()."""
    v = v.strip()
    if v.startswith("#"):
        h = v[1:]
        if len(h) == 3:
            h = "".join(c * 2 for c in h)
        if len(h) == 6:
            h = "FF" + h
        if len(h) != 8:
            return None
        try:
            raw = (int(h[2:4], 16), int(h[4:6], 16), int(h[6:8], 16), int(h[0:2], 16))  # r,g,b,a
        except ValueError:
            return None
        return tuple(max(0, min(255, c)) for c in raw)
    m = re.match(r"rgba?\(([^)]+)\)", v)
    if m:
        parts = [p.strip() for p in m.group(1).split(",")]
        if len(parts) < 3:
            return None
        try:
            r, g, b = (max(0.0, min(255.0, float(parts[i]))) for i in (0, 1, 2))
            a = 255.0
            if len(parts) > 3:
                # CSS rgba() alpha is 0-1; clamp to that range before ×255 so a 0-255 alpha
                # (rgba(...,255)) maps to fully opaque (255), not 255*255=65025.
                a = max(0.0, min(1.0, float(parts[3]))) * 255
            return (int(round(r)), int(round(g)), int(round(b)), int(round(a)))  # r,g,b,a
        except ValueError:
            return None
    return None


def num(v: str) -> float | None:
    """Strip common CSS length units → pixels as a number, or None.

    rem/em → ×16 (the default root font-size). pt → ×4/3 (CSS: 1pt = 1/72in, 1px = 1/96in,
    so 1pt = 96/72 = 4/3 px). % → None: a percentage is not a fixed length (50% of what?),
    so it can't be a static `double`; the emitters emit a ponytail comment instead. A bare
    number with no unit is treated as px."""
    v = v.strip()
    m = re.match(r"^(-?\d+(?:\.\d+)?)(px|rem|em|pt|%)?$", v)
    if not m:
        return None
    n = float(m.group(1))
    unit = m.group(2)
    if unit in ("rem", "em"):
        n *= 16
    elif unit == "pt":
        n *= 4 / 3
    elif unit == "%":
        return None
    return n


def bezier_vals(v):
    r"""A cubic-bezier control-point list, from EITHER form a DTCG $value takes:
      • the CSS string "cubic-bezier(0.2, 0.85, 0.2, 1)" (the flat-scrape form), OR
      • the W3C DTCG list [0.2, 0.85, 0.2, 1.0] (palette.js / Designer-authored form —
        a cubicBezier $value is a JSON array of 4 numbers, NOT a string). Anything
        else → None. Validates a 4-number result so a malformed value skips cleanly."""
    if isinstance(v, (list, tuple)):
        try:
            pts = [float(x) for x in v]
        except (TypeError, ValueError):
            return None
        return pts if len(pts) == 4 else None
    if not isinstance(v, str):
        return None
    m = re.match(r"cubic-bezier\(([^)]+)\)", v)
    if not m:
        return None
    try:
        return [float(x.strip()) for x in m.group(1).split(",")]
    except ValueError:
        return None


def _fmt_num(x):
    """A control-point number formatted to read as a double: 1.0 stays 1.0 (not 1),
    0.85 stays 0.85. Matches the legacy Python-list-repr output downstream tests assert
    and keeps a List<double> literal unambiguous (an int 1 is valid in List<double> but
    1.0 is clearer). Up to 6 significant digits; trailing zeros preserved."""
    s = f"{float(x):.6f}".rstrip("0").rstrip(".")
    return s if "." in s else s + ".0"


def _iter_tokens(tree, _path=()):
    """Yield (group_path, name, type, value) for every DTCG TOKEN (a node with $type),
    recursing through groups of arbitrary depth. A W3C DTCG document nests groups freely
    (color.brand.0, color.bg.surface) — a node is a token iff it carries $type, else it is a
    group. `name` is the camel'd leaf key so the identifier is stable; `group_path` is the
    parent group chain (for the // section comments). Handles both the flat scrape form
    (color.accent = token) and the nested DTCG form (palette.py's tonal ramp)."""
    if not isinstance(tree, dict):
        return
    for key, node in tree.items():
        if key.startswith("$") or not isinstance(node, dict):
            continue
        if "$type" in node:
            yield (_path, key, node["$type"], node.get("$value", ""))
        else:
            yield from _iter_tokens(node, _path + (key,))


def _token_name(group_path, key):
    """Identifier for a token. Matches the legacy contract for the flat scrape form —
    `color.accent` emits `accent` (NOT colorAccent), so generated app code that references
    `AppTokens.accent` keeps resolving. Nested ramps (palette.py's color.brand.0) need the
    parent group to form a valid identifier (a numeric leaf alone is not an identifier),
    so brand.0 → brand0 and bg.surface → surface. Rule: use the leaf alone when it is a
    valid identifier; otherwise prepend the nearest group that makes it one.

    Non-identifier characters are sanitized, never emitted verbatim: digits are valid
    mid-identifier (so brand.500 → brand500), but `-`/`@`/`#`/spaces are not valid in any of
    Dart/Swift/XML, so brand with a `-` leaf → brand (symbol stripped), `@x` leaf → brandx.
    The result is always a syntactically valid identifier (no invalid-id leak)."""
    # a valid Dart/Swift identifier starts with a letter — check the RAW key (camel() munges
    # a leading digit like "0" to "t", so checking the camel'd leaf would hide the need).
    if key[:1].isalpha():
        return camel(key)
    # numeric / symbol-only / mixed leaf (0, 10, 500, "-", "@x"): keep only the alphanumerics
    # as a suffix (digits survive → brand0/brand500; symbols are stripped → brand, brandx).
    suffix = "".join(c for c in key if c.isalnum())
    for grp in reversed(group_path):
        g = camel(grp)
        if g[:1].isalpha():
            return g + suffix   # e.g. brand+0 → brand0; brand+(-) → brand; brand+(@x) → brandx
    return "token" + (suffix or "0")   # empty group path: token0 / token500 (never empty)


# One shared walk feeds three platform emitters. Each platform supplies a header/footer,
# an indent, a group-comment format, and a per-`$type` line emitter (a function name → str,
# or None to skip that type on this platform). The previous three near-identical 30-line
# loops collapse to this table + one walker.
_PLATFORMS = {
    "dart": {
        "header": ["// AUTO-GENERATED by factory/stages/transform_tokens.py — do not edit.",
                   "// The shared token layer (identical across platforms).",
                   "import 'package:flutter/material.dart';", "",
                   "abstract final class AppTokens {"],
        "footer": ["}"],
        "indent": "  ",
        "group": lambda g: f"  // {g}",
    },
    "swift": {
        "header": ["// AUTO-GENERATED by factory/stages/transform_tokens.py — do not edit.",
                   "import UIKit", "", "public enum AppTokens {"],
        "footer": ["}"],
        "indent": "    ",
        "group": lambda g: f"    // {g}",
    },
    "android": {
        "header": ['<?xml version="1.0" encoding="utf-8"?>',
                   "<!-- AUTO-GENERATED by factory/stages/transform_tokens.py -->",
                   "<resources>"],
        "footer": ["</resources>"],
        "indent": "    ",
        "group": lambda g: f"    <!-- {g} -->",
    },
}


def _line(spec, indent, name, t, val):
    """Render one token's platform line, or None to skip. Shared per-type logic
    (parse_color / num / bezier_vals + the ease-in-out fallback) is computed once."""
    if t == "color":
        c = parse_color(val)
        if not c:
            return f"{indent}// ponytail: unparseable color {val!r} for {name}"
        return {
            "dart":    f"{indent}static const Color {name} = Color(0x{c[3]:02X}{c[0]:02X}{c[1]:02X}{c[2]:02X});",
            "swift":   f"{indent}public static let {name} = UIColor(red: {c[0] / 255:g}, green: {c[1] / 255:g}, blue: {c[2] / 255:g}, alpha: {c[3] / 255:g})",
            "android": f'{indent}<color name="{name}">#{c[3]:02X}{c[0]:02X}{c[1]:02X}{c[2]:02X}</color>',
        }[spec]
    if t in ("dimension", "number"):
        n = num(val)
        if n is None:
            return None
        return {
            "dart":    f"{indent}static const double {name} = {n:g};",
            "swift":   f"{indent}public static let {name}: CGFloat = {n:g}",
            "android": f'{indent}<dimen name="{name}">{n:g}dp</dimen>',
        }[spec]
    if t == "fontFamily":
        return {
            "dart":    f'{indent}static const String {name}Family = {json.dumps(val)};',
            "swift":   f"{indent}public static let {name}Family = {json.dumps(val)}",
            "android": f'    <!-- ponytail: fontFamily {name} = {val} (bind via res/font/) -->',
        }[spec]
    if t == "cubicBezier":
        bv = bezier_vals(val) or ([0.4, 0.0, 0.2, 1.0] if val == "ease-in-out" else None)
        if not bv:
            return None
        # Render the 4 control points. Preserve trailing-zero floats (1.0 not 1) so a
        # List<double> literal reads as doubles — match the legacy list-repr output the
        # self-test asserts and downstream Dart parses as doubles (1 → int is fine in a
        # List<double>, but 1.0 is unambiguous and matches the CSS-scrape form).
        pts = ", ".join(_fmt_num(x) for x in bv)
        return {
            "dart":    f"{indent}static const List<double> {name} = [{pts}];",
            "swift":   f"{indent}public static let {name}: [CGFloat] = [{pts}]",
            "android": f'    <!-- ponytail: cubicBezier {name} = [{pts}] (apply via Animator) -->',
        }[spec]
    if t == "shadow":
        return {
            "dart":    f"{indent}// ponytail: shadow token {name} (apply via BoxDecoration)",
            "swift":   f"{indent}// ponytail: shadow token {name} (apply via CALayer)",
            "android": f"    <!-- ponytail: shadow token {name} (apply via elevation/shapeAppearance) -->",
        }[spec]
    return None


# The CANONICAL baseline vocabulary the shared primitives library (blueprint.py's
# _tpl_primitives + generate_view.py) hardcodes references to. For "any design"
# (ADR-0014) the token layer must guarantee these compile even when the design
# defines no tokens and no alias block — a minimal/empty-token design still links.
# Defaults are a neutral Material-flavored palette (proven against the atlet
# fixture). A design's OWN token/alias for the same name always wins (emitted
# earlier in _emit, so the name is in `existing` and the baseline skips it → no
# duplicate `static const Color`).
_CANON_BASELINE = {
    "accent":    "#3F51B5",  # primary action (Indigo 500)
    "accent2":   "#303F9F",  # pressed/secondary accent (Indigo 700)
    "accentSoft": "#1A3F51B5",  # accent @ 10% alpha (tinted fills)
    "paper":     "#FFFBFE",  # elevated surface / on-accent text (M3 surface)
    "bone":      "#F5F0E8",  # recessed surface tier 1
    "bone2":     "#EAE3D6",  # recessed surface tier 2
    "bone3":     "#DDD3C0",  # recessed surface tier 3 (borders on bone)
    "ink":       "#1C1B1F",  # primary text (M3 on-surface)
    "ink2":      "#3A3530",  # secondary text
    "ink3":      "#6E6760",  # tertiary/muted text
    "ink4":      "#9E9E9E",  # disabled/placeholder text
    "rule":      "#CAC4D0",  # hairline dividers (M3 outline variant)
    "danger":    "#B3261E",  # destructive (M3 error)
    "color24":   "#FFFFFF",  # pure white (overlays, sheets)
}


def _emit(tree, spec_key):
    s = _PLATFORMS[spec_key]
    lines = list(s["header"])
    cur_group = None
    for group_path, key, t, val in _iter_tokens(tree):
        glabel = ".".join(group_path) if group_path else "tokens"
        if glabel != cur_group:
            lines.append(s["group"](glabel))
            cur_group = glabel
        name = _token_name(group_path, key)
        line = _line(spec_key, s["indent"], name, t, val)
        if line is not None:
            lines.append(line)
    # canonical-alias layer (consultant ADR): a design's $extensions block maps each
    # legacy name the generator emits (accent/bone/ink3/...) → this design's semantic
    # token (a $ref path) or a literal $value hex. Appended as their own group so the
    # generator stays design-agnostic (one stable vocabulary) while each design owns its
    # mapping. Skipped silently if no alias block — legacy designs keep working as-is.
    alias_lines = _emit_aliases(tree, spec_key)
    if alias_lines:
        lines.append(s["group"]("crew.aliases"))
        lines.extend(alias_lines)
    # canonical-baseline layer: the primitives library hardcodes the 14 names in
    # _CANON_BASELINE; a design that defines none of them (minimal/empty-token
    # designs) would otherwise yield an empty AppTokens and fail to compile.
    # Emit a default for any canonical name still missing (not in the design's own
    # tokens, not in its aliases) so EVERY design links. A design's own value wins
    # (emitted above → in `existing` → skipped here → no duplicate const).
    existing = {_token_name(gp, key) for gp, key, _t, _v in _iter_tokens(tree)}
    ext = tree.get("$extensions", {}) if isinstance(tree, dict) else {}
    ext = ext if isinstance(ext, dict) else {}
    alias_block = ext.get(_ALIAS_EXT) or ext.get(_ALIAS_EXT_LEGACY) or {}
    alias_block = alias_block if isinstance(alias_block, dict) else {}
    existing.update(a for a in alias_block.keys() if isinstance(a, str))
    base_lines = [_line(spec_key, s["indent"], name, "color", hexv)
                  for name, hexv in _CANON_BASELINE.items() if name not in existing]
    if base_lines:
        lines.append(s["group"]("crew.baseline"))
        lines.extend(base_lines)
    lines.extend(s["footer"])
    return "\n".join(lines) + "\n"


# the $extensions key a design authors its alias mapping under. The canonical name
# is `com.fluttercrew.aliases` (design-agnostic — never atlet-specific). The legacy
# `com.atlet.crew.aliases` is read as a fallback so older authored designs keep working.
_ALIAS_EXT = "com.fluttercrew.aliases"
_ALIAS_EXT_LEGACY = "com.atlet.crew.aliases"


def _resolve_alias_ref(tree, ref):
    """Resolve a dotted token path ('color.brand.0') to its $value, or None. Walks the
    DTCG tree the same _iter_tokens does, but follows a fixed path to a leaf $value."""
    node = tree
    for part in ref.split("."):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    if isinstance(node, dict):
        return node.get("$value")
    return node


def _emit_aliases(tree, spec_key):
    """Emit the canonical-alias Color lines for this design. Each alias resolves to a
    hex via either a $ref (preferred — points at a real semantic token) or a literal
    $value. A line is skipped if it can't resolve (no hard fail — the generator will
    surface the missing name as a compile error the operator can map). Returns a list
    of platform-formatted lines (empty if no alias block present)."""
    s = _PLATFORMS[spec_key]
    ext = tree.get("$extensions", {}) if isinstance(tree, dict) else {}
    ext = ext if isinstance(ext, dict) else {}   # a malformed list/scalar $extensions must not crash
    aliases = ext.get(_ALIAS_EXT) or ext.get(_ALIAS_EXT_LEGACY) or {}
    if not aliases:
        return []
    # Collect the semantic token names already emitted by _emit's main loop so an
    # alias that flattens to the SAME identifier (ink←color.fg.ink, rule←color.border.
    # rule, danger←color.status.danger, paper←color.bg.paper) is NOT re-emitted — a
    # duplicate `static const Color ink` is a hard compile error. The alias block is
    # only meant to add legacy names that have NO semantic equivalent in this design.
    existing = {_token_name(gp, key) for gp, key, _t, _v in _iter_tokens(tree)}
    out = []
    for name, spec in aliases.items():
        if not isinstance(spec, dict):
            continue
        if name in existing:
            continue  # the semantic token already provides this name — skip the alias
        raw = None
        if "$ref" in spec:
            raw = _resolve_alias_ref(tree, spec["$ref"])
        if raw is None and "$value" in spec:
            raw = spec["$value"]
        if raw is None:
            continue
        line = _line(spec_key, s["indent"], name, "color", raw)
        if line is not None:
            out.append(line)
    return out


def alias_hex_map(tree):
    """The reverse of _emit_aliases: hex (UPPERCASE) → AppTokens.<name> Dart expr.

    The builder (generate_view.color_dart) consumes this INSTEAD of a hardcoded
    HEX2TOK literal map — every hex the design paints resolves to a token name the
    transform emitted, so the builder carries ZERO design-specific hex literals
    (design-agnostic by contract). Two sources unioned:

      1. every $type:color token's own name (color.fg.ink → ink → #1A1714), so a
         hex used directly resolves to its semantic name;
      2. each alias in $extensions.com.fluttercrew.aliases, resolved to its hex via
         $ref / $value, so a legacy name (accent/bone) the builder emits also resolves.

    The collision policy is ALIAS-WINS: when a hex maps to both a semantic leaf and an
    alias (accent #D2522B ↔ color.brand.0), the ALIAS name wins — because the alias names
    are the builder's closed vocabulary (it emits AppTokens.accent, not AppTokens.brand0).
    The emit side (_emit_aliases) still dedupes to avoid a duplicate const; the reverse
    map just prefers the name the builder actually references. Returns {} when there is
    no alias block (a legacy design with only scraped CSS tokens → the builder falls back
    to emitting raw Color() hexes, never a broken name)."""
    out = {}
    if not isinstance(tree, dict):
        return out
    # 1. semantic color leaves (floor — overridden by aliases on collision)
    for gp, key, t, val in _iter_tokens(tree):
        if t != "color":
            continue
        hexv = _norm_hex(val)
        if hexv:
            out[hexv] = "AppTokens." + _token_name(gp, key)
    # 2. alias block — WINS on collision (the names the builder emits)
    ext = tree.get("$extensions", {})
    aliases = ext.get(_ALIAS_EXT) or ext.get(_ALIAS_EXT_LEGACY) or {}
    for name, spec in aliases.items():
        if not isinstance(spec, dict) or name.startswith("_"):
            continue
        raw = None
        if "$ref" in spec:
            raw = _resolve_alias_ref(tree, spec["$ref"])
        if raw is None and "$value" in spec:
            raw = spec["$value"]
        hexv = _norm_hex(raw)
        if hexv:
            out[hexv] = "AppTokens." + name  # override the semantic leaf
    return out


def _norm_hex(val):
    """A color $value → its 6-digit UPPERCASE hex ('#1A1714'), or None. So the alias
    map keys match the UPPERCASE comparison generate_view.color_dart does. Accepts #rgb,
    #rrggbb, #aarrggbb (alpha discarded — a token-level tint, not a per-use alpha)."""
    if not isinstance(val, str):
        return None
    v = val.strip()
    if not v.startswith("#"):
        return None
    h = v[1:]
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    if len(h) == 8:      # #aarrggbb — drop the alpha pair
        h = h[2:]
    if len(h) != 6:
        return None
    try:
        int(h, 16)
    except ValueError:
        return None
    return "#" + h.upper()


def emit_dart(tree: dict) -> str:
    return _emit(tree, "dart")


def emit_swift(tree: dict) -> str:
    return _emit(tree, "swift")


def emit_android(tree: dict) -> str:
    return _emit(tree, "android")


def main(argv):
    if len(argv) != 3:
        print("usage: transform_tokens.py <tokens.json> <out-dir>", file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8") as f:
        tree = json.load(f)
    out = argv[2]
    os.makedirs(os.path.join(out, "dart"), exist_ok=True)
    os.makedirs(os.path.join(out, "ios"), exist_ok=True)
    os.makedirs(os.path.join(out, "android"), exist_ok=True)
    with open(os.path.join(out, "dart", "app_tokens.dart"), "w", encoding="utf-8") as f:
        f.write(emit_dart(tree))
    with open(os.path.join(out, "ios", "AppTokens.swift"), "w", encoding="utf-8") as f:
        f.write(emit_swift(tree))
    with open(os.path.join(out, "android", "tokens.xml"), "w", encoding="utf-8") as f:
        f.write(emit_android(tree))
    print(f"wrote dart/app_tokens.dart, ios/AppTokens.swift, android/tokens.xml → {out}")
    return 0


# ---------- self-test (contract: assert the corrected behavior) ----------
# Every emitter/pure function is exercised across every input class. The negative cases
# assert what the function REJECTS (returns None). The contract: rgba alpha is CSS-spec
# 0-1 (clamped before ×255); rgb channels clamped to [0,255]; pt → ×4/3 px; % is not a
# static length (None → ponytail comment); and all three emitters are at PARITY (color +
# fontFamily real + shadow note on Dart/Swift/Android — no token silently disappears).
def _self_test():
    import tempfile, shutil
    HERE = os.path.dirname(os.path.abspath(__file__))

    fails = []

    def eq(label, got, want):
        if got != want:
            fails.append(f"{label}: got {got!r}, want {want!r}")
        else:
            print(f"PASS: {label}")

    def ok(label, cond, detail=""):
        if not cond:
            fails.append(f"{label}: expected True{(' — ' + detail) if detail else ''}")
        else:
            print(f"PASS: {label}")

    # ===== parse_color — every accepted form =====
    eq("parse_color #rgb (3-digit, doubled, opaque FF alpha)", parse_color("#abc"), (0xaa, 0xbb, 0xcc, 255))
    eq("parse_color #rrggbb (6-digit, prepended FF)", parse_color("#1a2b3c"), (0x1a, 0x2b, 0x3c, 255))
    eq("parse_color #aarrggbb (8-digit, alpha FIRST)", parse_color("#801a2b3c"), (0x1a, 0x2b, 0x3c, 0x80))
    eq("parse_color #ABC uppercase", parse_color("#ABC"), (0xaa, 0xbb, 0xcc, 255))
    eq("parse_color rgb()", parse_color("rgb(10,20,30)"), (10, 20, 30, 255))
    eq("parse_color rgb() with whitespace", parse_color("rgb( 10 , 20 , 30 )"), (10, 20, 30, 255))
    # rgba alpha is CSS-spec 0-1: clamp to [0,1] then ×255. rgba(...,0.5) → 128.
    eq("parse_color rgba() 0-1 alpha ×255", parse_color("rgba(10,20,30,0.5)"), (10, 20, 30, 128))
    eq("parse_color rgba() alpha 1.0 → opaque", parse_color("rgba(10,20,30,1.0)"), (10, 20, 30, 255))
    # a stray 0-255 alpha (rgba(...,255)) clamps to 1.0 → opaque, NOT 255×255=65025
    eq("parse_color rgba() 0-255 alpha clamps to opaque (not 65025)",
       parse_color("rgba(10,20,30,255)"), (10, 20, 30, 255))
    eq("parse_color rgba() negative alpha clamps to 0",
       parse_color("rgba(10,20,30,-1)"), (10, 20, 30, 0))

    # ===== parse_color — every rejected form (must return None, never raise for str) =====
    for bad in ("#abcd", "#12345", "#1234567", "red", "blue", "hsl(0,100%,50%)",
                "", "#zzzzzz", "rgb(10,20)", "rgb(a,b,c)", "rgb(10,20,30,)", "transparent"):
        eq(f"parse_color {bad!r} → None", parse_color(bad), None)
    # rgb channels are clamped to [0,255] (no out-of-range byte reaches a Color())
    eq("parse_color rgb(300,0,0) clamps to 255", parse_color("rgb(300,0,0)"), (255, 0, 0, 255))
    eq("parse_color rgb(-10,0,0) clamps to 0", parse_color("rgb(-10,0,0)"), (0, 0, 0, 255))

    # ===== num — accepted (rem/em scaled to *16) =====
    eq("num bare integer", num("12"), 12.0)
    eq("num negative decimal", num("-1.5"), -1.5)
    eq("num px unit (passthrough)", num("12px"), 12.0)
    eq("num rem → *16", num("1rem"), 16.0)
    eq("num em → *16", num("2em"), 32.0)
    eq("num zero rem", num("0rem"), 0.0)
    # pt → ×4/3 px (CSS: 1pt = 1/72in, 1px = 1/96in). 12pt → 16px.
    eq("num pt → ×4/3 px", num("12pt"), 16.0)
    # % is NOT a fixed length (50% of what?) → None; emitters emit a ponytail comment instead.
    eq("num % → None (not a static length)", num("50%"), None)
    eq("num surrounding whitespace stripped", num("  12px  "), 12.0)

    # ===== num — rejected =====
    for bad in (".5", "12.", "12mm", "12vw", "1e3", "+12", "", "0x10", "12px !important"):
        eq(f"num {bad!r} → None", num(bad), None)

    # ===== bezier_vals =====
    eq("bezier cubic-bezier() spaced", bezier_vals("cubic-bezier(0.4, 0.0, 0.2, 1.0)"),
       [0.4, 0.0, 0.2, 1.0])
    eq("bezier no-space", bezier_vals("cubic-bezier(0.4,0.0,0.2,1.0)"), [0.4, 0.0, 0.2, 1.0])
    eq("bezier leading-dot values", bezier_vals("cubic-bezier(.5,.5,.5,.5)"), [0.5, 0.5, 0.5, 0.5])
    # a DTCG cubicBezier $value is always a bare cubic-bezier(...) string; an embedded form
    # (e.g. "foo cubic-bezier(...) bar") is not a valid token value → None (re.match, anchored).
    eq("bezier embedded in larger string → None (not a bare token value)",
       bezier_vals("foo cubic-bezier(0.4,0,0.2,1) bar"), None)
    # bezier_vals itself does NOT map named easings (only emit_dart's fallback handles ease-in-out)
    eq("bezier ease-in-out → None (named not mapped here)", bezier_vals("ease-in-out"), None)
    eq("bezier empty", bezier_vals(""), None)
    eq("bezier non-numeric values → None", bezier_vals("cubic-bezier(a,b,c,d)"), None)

    # ===== _token_name — the legacy contract + numeric namespacing + symbol sanitization =====
    eq("_token_name alpha leaf → leaf only (legacy contract)",
       _token_name(("color",), "accent"), "accent")
    eq("_token_name hyphenated leaf → camelCased leaf",
       _token_name(("color",), "status-bar-bg"), "statusBarBg")
    eq("_token_name numeric leaf namespaced under deepest group",
       _token_name(("color", "brand"), "0"), "brand0")
    eq("_token_name numeric 500 namespaced", _token_name(("color", "brand"), "500"), "brand500")
    # the immediate group (bg) is dropped for an alpha leaf — surface, not bgSurface
    eq("_token_name alpha leaf under nested group still leaf-only",
       _token_name(("color", "bg"), "surface"), "surface")
    eq("_token_name numeric leaf with empty path → token+key",
       _token_name((), "0"), "token0")
    # FIX: symbol-only / mixed keys sanitize to valid identifiers (never emit brand- or brand@x)
    eq("_token_name symbol-only leaf → group alone (symbol stripped)",
       _token_name(("color", "brand"), "-"), "brand")
    eq("_token_name symbol-only leaf @ → group alone",
       _token_name(("color", "brand"), "@"), "brand")
    eq("_token_name mixed symbol+alnum → alphanumerics kept (@x → brandx)",
       _token_name(("color", "brand"), "@x"), "brandx")
    eq("_token_name empty leaf → group alone (no collision-risk bare empty)",
       _token_name(("color", "brand"), ""), "brand")
    eq("_token_name symbol-only with empty path → token0 (never empty/invalid)",
       _token_name((), "-"), "token0")
    # the produced identifier is always valid: starts with a letter, alnum-only thereafter
    import re as _re
    for gp, k in [(("color",), "accent"), (("color", "brand"), "0"), (("color", "brand"), "-"),
                  (("color", "brand"), "@x"), ((), "500"), ((), "@")]:
        nm = _token_name(gp, k)
        assert _re.fullmatch(r"[A-Za-z][A-Za-z0-9]*", nm), \
            f"_token_name({gp},{k!r}) → {nm!r} is not a valid identifier"
    ok("_token_name always yields a valid identifier (letter-led, alnum-only)", True)

    # ===== _iter_tokens — flat vs nested DTCG, $-keys + non-dict skipped =====
    flat = {"color": {"accent": {"$type": "color", "$value": "#fff"},
                      "$description": "ignored"}}
    flat_tokens = list(_iter_tokens(flat))
    eq("_iter_tokens flat form yields the token", len(flat_tokens), 1)
    eq("_iter_tokens flat token key", flat_tokens[0][1], "accent")

    nested = {"color": {"brand": {"0": {"$type": "color", "$value": "#000"},
                                  "$description": "ramp"},
                        "bg": {"surface": {"$type": "color", "$value": "#fff"}}}}
    n = list(_iter_tokens(nested))
    eq("_iter_tokens nested yields 2 tokens (0 + surface)", len(n), 2)
    ok("_iter_tokens nested group_path carries the chain",
       ("color", "brand") in {t[0] for t in n} and ("color", "bg") in {t[0] for t in n})

    bareleaf = {"color": {"accent": "#fff"}}   # bare string, not {$value}
    eq("_iter_tokens skips bare-string leaves (strict DTCG {$type,$value})",
       list(_iter_tokens(bareleaf)), [])

    # ===== THE PHASE-5 REGRESSION: nested DTCG emits color consts (was 0 before the fix) =====
    ramp_doc = {"color": {"brand": {str(t): {"$type": "color", "$value": "#0E7C66"}
                                    for t in (0, 10, 50, 100, 500)},
                          "bg": {"surface": {"$type": "color", "$value": "#FBFCFC"},
                                 "status-bar-bg": {"$type": "color", "$value": "#01221A"}},
                          "fg": {"on-accent": {"$type": "color", "$value": "#FFFFFF"}}}}
    dart_ramp = emit_dart(ramp_doc)
    ramp_consts = [l for l in dart_ramp.splitlines() if "static const Color" in l]
    ok("REGRESSION nested DTCG emits color consts (not 0)", len(ramp_consts) >= 6,
       f"got {len(ramp_consts)} consts")
    ok("REGRESSION numeric leaves namespaced brand0/brand500",
       "brand0" in dart_ramp and "brand500" in dart_ramp)
    ok("REGRESSION alpha leaves stay leaf-only (surface, onAccent, statusBarBg)",
       "surface" in dart_ramp and "onAccent" in dart_ramp and "statusBarBg" in dart_ramp)
    # no colorAccent regression: a token directly under color.<alpha> is NOT prefixed with 'color'
    ok("REGRESSION no group-prefix on alpha leaves (no 'colorAccent')",
       "colorAccent" not in dart_ramp and "colorSurface" not in dart_ramp)

    # ===== byte-identical regression vs the atlet-scrape golden (flat form) =====
    atlet_tokens = os.path.join(HERE, "..", "test", "fixtures", "atlet",
                                ".blueprint", "atlet", "tokens.json")
    if os.path.exists(atlet_tokens):
        atlet_tree = json.load(open(atlet_tokens))
        # the committed pkg's app_tokens.dart is the frozen contract — must reproduce byte-for-byte
        golden_dart = os.path.join(HERE, "..", "test", "fixtures", "atlet", ".blueprint", "atlet",
                                   "pkg", "templates", "lib", "app_tokens.dart")
        if os.path.exists(golden_dart):
            produced = emit_dart(atlet_tree)
            committed = open(golden_dart).read()
            ok("REGRESSION atlet flat tokens → byte-identical to committed app_tokens.dart",
               produced == committed,
               "first diff line: " + next((a for a, b in zip(produced.splitlines(),
                committed.splitlines()) if a != b), "(length differs)"))
    # always also assert a known leaf survives (not colorAccent / not dropped)
    flat_color = emit_dart({"color": {"accent": {"$type": "color", "$value": "#D2522B"},
                                      "bone-2": {"$type": "color", "$value": "#EAE3D6"}}})
    ok("REGRESSION flat leaf names preserved (accent, bone2)",
       "accent" in flat_color and "bone2" in flat_color and "colorAccent" not in flat_color)

    # ===== alias_hex_map: the contract the builder consumes instead of HEX2TOK =====
    # semantic leaves resolve; alias $ref + alias $value resolve; #rgb/#aarrggbb normalized;
    # a tree with no alias block yields the semantic-leaf map only (never crashes).
    contract = {
        "color": {"fg": {"ink": {"$type": "color", "$value": "#1A1714"}},
                  "brand": {"0": {"$type": "color", "$value": "#D2522B"}}},
        "$extensions": {"com.fluttercrew.aliases": {
            "_description": "skip me",
            "ink":  {"$ref": "color.fg.ink"},     # collides with semantic leaf → leaf wins
            "accent": {"$ref": "color.brand.0"},
            "bone": {"$value": "#F5F0E8"},
            "ink2": {"$value": "#3a3530"},         # lowercase → normalized UPPER
            "short": {"$value": "#abc"},           # #rgb → expanded
        }}}
    ahm = alias_hex_map(contract)
    # alias WINS on collision: ink $ref=#1A1714 collides with semantic color.fg.ink →
    # the alias name (AppTokens.ink) wins over the leaf (which is also `ink` here, so
    # same result); accent $ref=#D2522B collides with color.brand.0 → alias wins.
    eq("alias_hex_map $ref alias wins over semantic leaf", ahm.get("#D2522B"), "AppTokens.accent")
    eq("alias_hex_map $value alias", ahm.get("#F5F0E8"), "AppTokens.bone")
    eq("alias_hex_map normalizes lowercase", ahm.get("#3A3530"), "AppTokens.ink2")
    eq("alias_hex_map expands #rgb", ahm.get("#AABBCC"), "AppTokens.short")
    eq("alias_hex_map semantic leaf when no alias collides", ahm.get("#1A1714"), "AppTokens.ink")
    # no alias block → semantic-leaf map only (lenient, never raises)
    noext = alias_hex_map({"color": {"x": {"$type": "color", "$value": "#000000"}}})
    eq("alias_hex_map no-alias-block still yields semantic leaf",
       noext.get("#000000"), "AppTokens.x")
    ok("alias_hex_map never raises on degenerate input",
       alias_hex_map({}) == {} and alias_hex_map(None) == {})
    # the design-v2 fixture: every referenced builder name must resolve via the contract
    dv2 = json.load(open(os.path.join(HERE, "..", "test", "fixtures", "atlet",
                                      "design-v2", "tokens.json")))
    dv2_map = alias_hex_map(dv2)
    # names the design-v2 generated views reference (the closed builder vocab)
    for name in ("accent", "accent2", "accentSoft", "bone", "bone3",
                 "ink", "ink2", "ink3", "paper", "rule"):
        vals = [h for h, n in dv2_map.items() if n == "AppTokens." + name]
        ok(f"design-v2 contract resolves builder name {name!r}", bool(vals),
           f"no hex maps to AppTokens.{name}")

    # ===== emit_dart emits EVERY alias in the block, not just the first =====
    # REGRESSION: an early `return out` indented inside the for-loop made emit_dart emit
    # only the FIRST alias (accent) and drop the rest → app_tokens.dart missing ink3/bone3/
    # color24 → flutter analyze errors on every generated view. This multi-alias block is
    # the exact shape that catches it (a single-alias block would pass even with the bug).
    multi = {"color": {"fg": {"ink": {"$type": "color", "$value": "#1A1714"}}},
             "$extensions": {"com.fluttercrew.aliases": {
                 "accent": {"$ref": "color.fg.ink"},
                 "bone3": {"$value": "#FFDDD3C0"},
                 "ink3": {"$ref": "color.fg.ink"},
                 "color24": {"$value": "#FFFFFFFF"}}}}
    dart = emit_dart(multi)
    for alias in ("accent", "bone3", "ink3", "color24"):
        ok(f"emit_dart emits alias {alias!r} (not just the first)",
           f"static const Color {alias}" in dart,
           f"emit_dart dropped alias {alias!r} — early return inside the loop")

    # ===== cross-platform emit PARITY (all 3 emit color + fontFamily + shadow note) =====
    # WAS an asymmetry (Dart-only); now Swift+Android emit fontFamily (real) and shadow
    # (ponytail comment) so no token silently disappears on a platform. cubicBezier resolves
    # via bezier_vals on all three (ease-in-out fallback too).
    asym = {"color": {"accent": {"$type": "color", "$value": "#0E7C66"}},
            "font": {"sans": {"$type": "fontFamily", "$value": "Sora"}},
            "motion": {"rise": {"$type": "cubicBezier", "$value": "cubic-bezier(0.25,0.9,0.3,1)"}},
            "shadow": {"card": {"$type": "shadow", "$value": "0 2px 4px rgba(0,0,0,0.1)"}}}
    da, sw, an = emit_dart(asym), emit_swift(asym), emit_android(asym)
    # color on all three
    ok("parity: color on all 3 platforms",
       "accent" in da and "accent" in sw and "accent" in an)
    # fontFamily: Dart + Swift emit a real binding; Android notes it (res/font/ is the binding)
    ok("parity: Dart emits fontFamily binding", "sansFamily" in da)
    ok("parity: Swift emits fontFamily binding", "sansFamily" in sw)
    ok("parity: Android notes fontFamily (res/font/)", "fontFamily sans" in an)
    # shadow: all three emit the ponytail comment (no native static form on any platform)
    ok("parity: Dart notes shadow", "shadow token" in da)
    ok("parity: Swift notes shadow", "shadow token" in sw)
    ok("parity: Android notes shadow", "shadow token" in an)
    # ease-in-out fallback resolves on all three (the hardcoded [0.4,0.0,0.2,1.0])
    ei_doc = {"motion": {"ease": {"$type": "cubicBezier", "$value": "ease-in-out"}}}
    for label, out in (("Dart", emit_dart(ei_doc)), ("Swift", emit_swift(ei_doc)),
                       ("Android", emit_android(ei_doc))):
        ok(f"parity: {label} ease-in-out → [0.4,0.0,0.2,1.0]", "0.4, 0.0, 0.2, 1.0" in out)


    # ===== degenerate inputs don't crash; produce valid-but-empty scaffolds =====
    # includes a non-dict $extensions (list) — _emit_aliases must guard against it
    # (a malformed $extensions crashed there before the baseline work fixed it).
    for degenerate in ({}, [], {"$schema": "x"}, {"color": {}},
                       {"$extensions": ["not", "a", "dict"]}):
        out = emit_dart(degenerate)
        ok(f"emit_dart degenerate {degenerate!r} → valid scaffold (class + close)",
           "abstract final class AppTokens" in out and "}" in out)

    # ===== main: 3 files created; wrong arg count → exit 2 =====
    tmp = tempfile.mkdtemp(prefix="_tt_selftest_")
    sample = os.path.join(tmp, "in.json")
    json.dump({"color": {"accent": {"$type": "color", "$value": "#0E7C66"}}}, open(sample, "w"))
    rc = main(["transform_tokens.py", sample, os.path.join(tmp, "out")])
    eq("main exit code 0 on success", rc, 0)
    for f in ("dart/app_tokens.dart", "ios/AppTokens.swift", "android/tokens.xml"):
        ok(f"main created {f}", os.path.exists(os.path.join(tmp, "out", f)))
    eq("main wrong arg count → exit 2", main(["transform_tokens.py", sample]), 2)
    shutil.rmtree(tmp, ignore_errors=True)

    if fails:
        print("\ntransform_tokens self-test FAIL — %d assertion(s):" % len(fails))
        for f in fails:
            print("  " + f)
        return False
    print("\ntransform_tokens self-test PASS — "
          "parse_color/num/bezier/_token_name/_iter_tokens + Phase-5 regression + "
          "cross-platform parity + main (all input classes covered)")
    return True


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(0 if _self_test() else 1)
    sys.exit(main(sys.argv))
