#!/usr/bin/env python3
"""generate_view.py — composition spec → home_view.dart. NO LLM, deterministic.

Reads capture_design.py's composition spec and emits the Flutter Home view by
TRANSLATING the design's own composition (not a hand-template): each node → a
primitive/widget, static text straight from the spec, dynamic slots bound to the
viewModel/Session via a documented design-field → data_model map. This is graded
against the DESIGN (design_gate), never against the hand-authored view.

What is genuinely spec-driven (the part the gate validates):
  • the 4 stat cards  — eyebrow/note/big/unit TEXT, variant tint, chart kind all
    read from the spec; only the chart CURVE data is fixed (the frontier).
  • the workout card  — structure (row→[title|metric], footer→[notes|play]) and
    the metric-right-of-title / play-on-footer-line ORDINALS come from the spec
    subtree; the field bindings come from the captured `bind` exprs.

What is a fixed composite (atlet-generic shell, flagged honestly):
  • the AdaptiveScaffold→AdaptiveRefresh→ListView frame, the greeting header
    (live date + vm.firstName/initials), and the "Your workouts" + New +
    AdaptiveSegmented filter bar. These are not design-structure the gate grades.

Charts/carousel/dashed/dots live in home_assets.dart (the un-generatable
CustomPainter / interaction frontier); this view imports them.

ponytail: v1 is atlet-shaped (the binding map + composite header/filter know this
design's vocabulary). Generalising to arbitrary designs is the follow-up; the
point proved here is spec→faithful-structure with the gate as judge.

Usage: generate_view.py <spec.json> <out home_view.dart>  | --self-test
"""
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# Assets stage: extracted SVGs are written as MANAGED asset files (assets/svg/*.svg)
# by the driver, not inlined as strings. path → svg content; content-hash names so the
# same mark dedupes and the path is machine-independent (golden-safe, ADR-0008).
_SVG_ASSETS = {}
# Asset-manager record of EVERY extracted glyph (rendered + dropped), keyed by id.
# Rendered glyphs are also bundled in _SVG_ASSETS; DROPPED glyphs (gate G3, below)
# live ONLY here — recorded, not shipped — so design mode / a future revisit can
# recover them. The driver writes this to a NON-bundled provenance/asset_ledger.json.
_SVG_LEDGER = {}


def _svg_id(svg):
    return "svg_" + hashlib.sha1(svg.encode("utf-8")).hexdigest()[:10]


def _svg_asset(svg, origin=""):
    """Register a RENDERED svg: bundle it (assets/svg/) AND ledger it (rendered:true)."""
    path = f"assets/svg/{_svg_id(svg)}.svg"
    _SVG_ASSETS[path] = svg
    _SVG_LEDGER.setdefault(path, {"id": path, "origin": origin, "rendered": True})
    return path


def _drop_glyph(node, origin, reason):
    """NATIVE-DECORATION GATE (G3): a native control carries only native-vocabulary
    decoration (SF Symbol / Material icon) — the catalog `action.button` contract has
    NO brand-glyph slot. A custom brand SVG (Google's G) is NOT native vocabulary, so
    it is DROPPED from the native render. The asset manager still RECORDS it (origin +
    dims + reason + the vector itself) in the non-bundled ledger so design mode / a
    future revisit can recover it. Emits no widget — record only."""
    svg = node["svg"]
    w = px(str(node.get("svgw") or "")) or px(node["style"].get("width"))
    h = px(str(node.get("svgh") or "")) or px(node["style"].get("height"))
    _SVG_LEDGER.setdefault(_svg_id(svg), {
        "id": _svg_id(svg), "origin": origin, "w": w, "h": h,
        "rendered": False, "dropReason": reason, "svg": svg})

# design mock-field (captured bind) → Dart expr on a Session `s`. The design's
# data.jsx names differ from data_model.json, so this is the reconciliation.
# Contract-driven: build_view populates this from data_model.json's seedFrom.map
# (inverted: seedKey → "s.<entityField>"), so the binding is THIS design's, not a
# hardcoded atlet copy. The atlet literal below is the legacy fallback (byte-stable
# when no data_model contract is wired — a self-test or a contract-less design).
BIND = {
    "w.name": "s.title",
    "bigVal": "s.metric",
    "bigUnit": "s.unit",
    "w.notes": 's.note ?? ""',
    "w.streak": "s.streak",
    "w.target": "s.metric",   # the per-record target/duration (the timer start value)
    "meta.label": "s.type",
}

# hex (UPPERCASE) → "AppTokens.<name>" Dart expr. Populated per-run by build_view
# from the design's tokens.json alias contract (transform_tokens.alias_hex_map), so
# the builder carries ZERO design-specific hex literals — a foreign design's palette
# resolves to its OWN token names by contract, not to atlet's. Legacy fallback: the
# prior hardcoded atlet map, used ONLY when no alias contract is wired (a self-test
# or a hand-authored design without tokens.json) so behavior is byte-stable there.
HEX2TOK = {
    "#1A1714": "AppTokens.ink", "#3A3530": "AppTokens.ink2",
    "#6E6760": "AppTokens.ink3", "#A39A8E": "AppTokens.ink4",
    "#F5F0E8": "AppTokens.bone", "#DDD3C0": "AppTokens.bone3",
    "#FBF8F2": "AppTokens.paper", "#D2522B": "AppTokens.accent",
    "#B8431F": "AppTokens.accent2", "#D8CFBE": "AppTokens.rule",
}

TOKENS = {}  # set per-run from the spec (for var() resolution)
STATE = {}   # this screen's local-state table (capture_data.json: useState defaults
# + derived) — the generator resolves conditional binds + prunes dead branches against it.
_NEEDS_FMTSEC = False  # a kept bind used fmtSec(...) → emit the MM:SS helper into the view
_OVERLAY = ""  # "dark" when the screen bg is dark → status-bar icons flip to light (AnnotatedRegion)
_TIMER = None  # this screen's live-countdown spec {value, init, running} (capture_data) or None.
# When set, the timer's state vars resolve to `viewModel.<var>` (reactive — StackedView
# rebuilds on notifyListeners), and a ternary on `running` becomes a live Dart conditional.


def _reactive_var(name):
    """If `name` is a reactive timer state var, its live Dart expr (`viewModel.x`); else None."""
    if _TIMER and name in (_TIMER.get("running"), _TIMER.get("value")):
        return "viewModel." + name
    return None


def _split_top(s, op):
    """Split `s` on top-level `op` (&& / ||), ignoring operators inside (), [], {},
    or string/template quotes."""
    out, depth, q, i, last = [], 0, None, 0, 0
    while i < len(s):
        ch = s[i]
        if q:
            if ch == q:
                q = None
        elif ch in "'\"`":
            q = ch
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif depth == 0 and s[i:i + len(op)] == op:
            out.append(s[last:i])
            i += len(op)
            last = i
            continue
        i += 1
    out.append(s[last:])
    return [p.strip() for p in out] if len(out) > 1 else [s.strip()]


def _outer_parens(s):
    """True iff the leading `(` matches the trailing `)` (whole expr parenthesised)."""
    if not (s[:1] == "(" and s[-1:] == ")"):
        return False
    depth = 0
    for i, ch in enumerate(s):
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return i == len(s) - 1
    return False


def _cond_value(cond):
    """Evaluate a JS-ish boolean condition against STATE. True/False, or None when
    it depends on data/anything not in the state table (→ caller keeps the branch)."""
    cond = (cond or "").strip()
    while _outer_parens(cond):
        cond = cond[1:-1].strip()
    if _reactive_var(cond):
        return None  # reactive timer var → not statically resolvable; defer to the live ternary
    for op, reduce_ in (("||", any), ("&&", all)):
        parts = _split_top(cond, op)
        if len(parts) > 1:
            vals = [_cond_value(p) for p in parts]
            if op == "&&" and any(v is False for v in vals):
                return False
            if op == "||" and any(v is True for v in vals):
                return True
            return reduce_(vals) if all(v is not None for v in vals) else None
    if cond.startswith("!"):
        inner = _cond_value(cond[1:])
        return None if inner is None else (not inner)
    m = re.match(r"([\w.]+)\s*===?\s*'([^']*)'$", cond)
    if m:
        v = STATE.get(m.group(1))
        return None if v is None else (str(v) == m.group(2))
    v = STATE.get(cond)
    return v if isinstance(v, bool) else None  # numbers/strings/unknown → unknown


def _cond_hidden(c):
    """A captured conditional branch ({expr, branch}) is hidden iff its condition
    provably resolves to not-this-branch. Unknown condition → shown (no regression)."""
    v = _cond_value(c.get("expr"))
    if v is None:
        return False
    return (not v) if c.get("branch") == "then" else bool(v)


def _split_ternary(b):
    """`COND ? A : B` → (cond, a, b) at the TOP level (nested ternaries/parens/strings
    respected), else None."""
    depth, q, qpos = 0, None, -1
    for i, ch in enumerate(b):
        if q:
            if ch == q:
                q = None
        elif ch in "'\"`":
            q = ch
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif depth == 0 and ch == "?" and qpos < 0:
            qpos = i
    if qpos < 0:
        return None
    depth, q = 0, None
    for i in range(qpos + 1, len(b)):
        ch = b[i]
        if q:
            if ch == q:
                q = None
        elif ch in "'\"`":
            q = ch
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif depth == 0 and ch == ":":
            return b[:qpos].strip(), b[qpos + 1:i].strip(), b[i + 1:].strip()
    return None


def _resolve_value(b):
    """A value expression → a Dart value expr (String/num), or None if not resolvable.
    Maps design field refs via BIND and follows derived aliases (remaining→w.target)."""
    b = (b or "").strip()
    rv = _reactive_var(b)
    if rv:  # live timer var (remaining) → reactive viewModel.remaining, NOT the static init
        return rv
    if b in BIND:
        return BIND[b]
    v = STATE.get(b)
    if isinstance(v, str) and v and v != b:  # derived alias, e.g. remaining→"w.target"
        return _resolve_value(v)
    return None


def _resolve_one(b):
    """A single bind expression → a Dart Text-content expression (a literal `'X'` or
    an interpolation `'${expr}'`), or None when it can't be resolved statically."""
    b = (b or "").strip()
    while _outer_parens(b):
        b = b[1:-1].strip()
    tern = _split_ternary(b)
    if tern:
        cond, a, c = tern
        val = _cond_value(cond)
        if val is True:
            return _resolve_one(a)
        if val is False:
            return _resolve_one(c)
        rc = _reactive_var(cond.strip())
        if rc:  # reactive condition → live Dart ternary (StackedView rebuilds on notify)
            ra = _resolve_one(a) or "''"
            rcc = _resolve_one(c) or "''"
            return f"({rc} ? {ra} : {rcc})"
        return None  # branch depends on data → leave to the (deferred) live VM
    if b[:1] in ("'", '"', "`"):
        inner = b[1:-1]
        if "${" not in inner:
            return "'" + inner.replace("\\", "\\\\").replace("'", "\\'") + "'"
        return None  # template interpolation → frontier
    m = re.match(r"(fmtSec|fmtSecMs)\((.+)\)$", b)
    if m:
        arg = _resolve_value(m.group(2).strip())
        if arg:
            global _NEEDS_FMTSEC
            _NEEDS_FMTSEC = True
            return "'${fmtSec(" + arg + ")}'"
        return None
    val = _resolve_value(b)
    return ("'${" + val + "}'") if val else None


def _resolve_bind_content(binds):
    """The first bind that resolves to a static Dart Text content, else the notes
    fallback, else None (caller emits '')."""
    for b in binds:
        c = _resolve_one(b)
        if c is not None:
            return c
    if any("notes" in b for b in binds):
        return "'${s.note ?? \"\"}'"
    return None


_FMTSEC_HELPER = '''

/// Formats a seconds count as MM:SS (the design's `fmtSec`). Emitted only when a
/// kept bind uses it (e.g. the countdown readout's start value).
String fmtSec(int s) {
  if (s < 0) s = 0;
  final m = (s ~/ 60).toString().padLeft(2, '0');
  final c = (s % 60).toString().padLeft(2, '0');
  return '$m:$c';
}
'''


# ---------------------------- helpers ----------------------------
def _resolve_var(v):
    seen = 0
    while isinstance(v, str) and v.startswith("var(") and seen < 8:
        m = re.match(r"var\(\s*(--[\w-]+)\s*(?:,([^()]*))?\)", v)
        if not m:
            break
        v = TOKENS.get(m.group(1), (m.group(2) or "").strip())
        seen += 1
    return v


def color_dart(v):
    if not v:
        return None
    v = _resolve_var(v.strip())
    if not v:
        return None
    up = v.upper()
    if up in HEX2TOK:
        return HEX2TOK[up]
    m = re.fullmatch(r"#([0-9A-Fa-f]{6})", v)
    if m:
        return f"const Color(0xFF{m.group(1).upper()})"
    if v in ("#fff", "#ffffff", "#FFF", "#FFFFFF", "white"):
        return "Colors.white"
    m = re.fullmatch(r"rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)", v)
    if m:
        r, g, b = m.group(1), m.group(2), m.group(3)
        a = m.group(4) or "1"
        # NOT `const` — Color.fromRGBO is a factory constructor, not a const constructor
        # (Flutter's Color only has a const int constructor). A prior version prefixed
        # `const` here → "doesn't have a constant constructor 'fromRGBO'" at G5. The
        # 6-digit hex path above IS const (Color(int) is const); rgba is not.
        return f"Color.fromRGBO({r}, {g}, {b}, {a})"
    return None


def px(v):
    if not v:
        return None
    m = re.fullmatch(r"(-?[\d.]+)px", v) or re.fullmatch(r"(-?[\d.]+)", v)
    return float(m.group(1)) if m else None


def weight(v):
    if not v:
        return None
    v = str(v).strip()
    if v in ("bold", "700"):
        return "FontWeight.w700"
    if v in ("600", "500", "800", "900", "400", "300"):
        return f"FontWeight.w{v}"
    return None


def num(x):
    return str(int(x)) if x == int(x) else str(x)


def dart_str(s):
    s = s.replace("\\", "\\\\")
    if "'" in s and '"' not in s:
        return '"' + s.replace("$", r"\$") + '"'
    return "'" + s.replace("'", r"\'").replace("$", r"\$") + "'"


def _pascal(s):
    return "".join(w[:1].upper() + w[1:] for w in re.split(r"[_\-\s]+", s) if w)


def _snake(s):
    return re.sub(r"[\-\s]+", "_", s).strip("_").lower()


def _border_dart(style):
    """CSS `border: <w>px solid <color>` → a Dart `Border.all(...)`, or None when there
    is no painted border. A bordered box IS visible even with no fill/size (the welcome
    ring: a 2px accent circle sized by its Stack slot)."""
    b = (style.get("border") or "").strip()
    if not b or b.lower() == "none":
        return None
    m = re.search(r"(\d+(?:\.\d+)?)px", b)
    bw = m.group(1) if m else "1"
    cm = re.search(r"#[0-9A-Fa-f]{3,8}|rgba?\([^)]*\)|var\([^)]*\)", b)
    col = color_dart(cm.group(0)) if cm else None
    if not col:
        return None
    return f"Border.all(color: {col}, width: {bw})"


def _deco_args(style):
    """CSS visual box → (size-args list, BoxDecoration string | None, visible bool).
    One source of truth for the box-model, shared by the decorative-leaf path
    (`_styled_box`) and the styled-CONTAINER wrap (`_box_wrap`). `visible` is True when
    there is a real fill / border / size — a radius-ONLY box draws nothing (the splash
    loader-fill degenerate-disc bug: 999px radius + no colour/size = an invisible disc)."""
    args = []
    w, h = px(style.get("width")), px(style.get("height"))
    if w is not None:
        args.append(f"width: {num(w)}")
    if h is not None:
        args.append(f"height: {num(h)}")
    deco = []
    bg = color_dart(style.get("background") or style.get("background-color"))
    if bg:
        deco.append(f"color: {bg}")
    bd = _border_dart(style)
    if bd:
        deco.append("border: " + bd)
    br = (style.get("border-radius") or "").strip()
    if br in ("50%", "999px") or br.endswith("9999px"):
        deco.append("shape: BoxShape.circle")
    else:
        r = px(br)
        if r is not None:
            deco.append(f"borderRadius: BorderRadius.circular({num(r)})")
    decoration = ("BoxDecoration(" + ", ".join(deco) + ")") if deco else None
    visible = bool(bg or bd or w is not None or h is not None)
    return args, decoration, visible


def _styled_box(style):
    """A decorative LEAF Box (logo / loader / ring — no text, no children) → a
    Container with its size + fill/border/radius. Returns '' when there is nothing
    visual to draw (a radius-only wrapper, or a bare layout box)."""
    args, deco, visible = _deco_args(style)
    if not visible:
        return ""
    if deco:
        args.append(f"decoration: {deco}")
    return "Container(" + ", ".join(args) + ")"


def text_style(style, classes):
    parts = []
    fs = px(style.get("font-size"))
    if fs:
        parts.append(f"fontSize: {num(fs)}")
    fw = weight(style.get("font-weight"))
    if fw:
        parts.append(fw and f"fontWeight: {fw}")
    col = color_dart(style.get("color"))
    if col:
        parts.append(f"color: {col}")
    if "num" in classes or "big" in classes:
        parts.append("fontFeatures: const [FontFeature.tabularFigures()]")
    return "TextStyle(" + ", ".join(p for p in parts if p) + ")"


def _bind_expr(binds):
    for b in binds:
        if b in BIND:
            return BIND[b]
    # ternary/compound notes expr → fall back to the note field
    if any("notes" in b for b in binds):
        return 's.note ?? ""'
    return None


def _button_label(node):
    """The button's human label, gathered from its subtree text and stripped of
    icon-glyph artifacts (a lone ':' is an Icon placeholder, not a label)."""
    texts = []

    def collect(n):
        t = (n.get("text") or "").strip()
        if t and t not in (":", "·"):
            texts.append(t)
        for c in n["children"]:
            collect(c)

    collect(node)
    label = " ".join(texts).strip().lstrip(":").strip()
    return label or "Continue"


def _field_placeholder(node):
    p = (node.get("props") or {}).get("placeholder")
    if p:
        return p
    for c in node["children"]:
        t = (c.get("text") or "").strip()
        if t:
            return t
    return ""


def _lum(hexcol):
    h = (hexcol or "").lstrip("#")
    if len(h) != 6:
        return 1.0
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255


def _find_svg(node):
    """First captured <svg> leaf in the subtree that isn't inside a loading spinner
    (the social-button ternary carries both a Spinner and the brand glyph; the
    `spinner` class sits on the wrapper, so skip the whole subtree, not just the svg)."""
    for n in node["children"]:
        if "spinner" in n["class"]:
            continue
        if n.get("prim") == "svg":
            return n
        d = _find_svg(n)
        if d:
            return d
    return None


def _svg_widget(node, tint=None):
    """A captured <svg> leaf → flutter_svg `SvgPicture.string` (the design's OWN vector,
    rendered at runtime — deterministic, no redraw). Tint ONLY currentColor glyphs (the
    Apple mark on a dark button); a uniform colorFilter would flatten multi-colour marks
    (Google's 4 brand fills, the Atlet gradient)."""
    svg = node["svg"]
    w = px(str(node.get("svgw") or "")) or px(node["style"].get("width"))
    h = px(str(node.get("svgh") or "")) or px(node["style"].get("height"))
    args = [dart_str(_svg_asset(svg))]
    if w:
        args.append(f"width: {num(w)}")
    if h:
        args.append(f"height: {num(h)}")
    if tint and "currentColor" in svg:
        args.append(f"colorFilter: ColorFilter.mode({tint}, BlendMode.srcIn)")
    return "SvgPicture.asset(" + ", ".join(args) + ")"


# ---------------------------- render fidelity (config) ----------------------------
# prim → canonical catalog leaf id; the render-mode override is keyed by this.
_PRIM_CANONICAL = {
    "AdaptiveButton": "action.button",
    "AdaptiveIconButton": "action.icon-button",
    "AdaptiveTextField": "input.text-field",
    "svg": "display.media",
}
# Resolved render config: {"fidelity": "native"|"design", "overrides": {leafId: mode}}.
# Default native everywhere — the catalog-prescribed native primitive per platform.
_RENDER = {"fidelity": "native", "overrides": {}}

# Native Adaptive* primitives own their own tap slot (onPressed / onChanged / onTap) and
# resolve any captured handler edge internally. The generic GestureDetector manager in
# emit() checks this to avoid double-wrapping a native control with a second tap layer.
# (Distinct from the _NATIVE_PRIMS set at line ~1042, which detects iOS UiKitView
# platform-view leaves for a different purpose — names kept separate to avoid collision.)
_NATIVE_PRIM_PREFIXES = ("AdaptiveButton(", "AdaptiveIconButton(", "AdaptiveAuthButton(",
                 "AdaptiveSwitch(", "AdaptiveSlider(", "AdaptiveChip(", "AdaptiveCard(")


def _render_mode(node):
    """`native` (catalog primitive, default) or `design` (reproduce the design
    exactly) for this node's canonical leaf — operator-set via config.render."""
    cid = _PRIM_CANONICAL.get(node.get("prim", ""))
    ov = _RENDER.get("overrides", {})
    if cid and cid in ov:
        return ov[cid]
    return _RENDER.get("fidelity", "native")


# ---------------------------- legibility (contrast) ----------------------------
# WCAG relative-luminance contrast. The SAME label-vs-background failure burned BOTH
# platforms (iOS dark-on-black Apple label; Android white-on-cream Google label that
# vanished): the label colour was never set to contrast the button fill. Fix: always
# emit an explicit label colour that contrasts the fill, + a GATE that hard-fails
# generation if it doesn't. LIMIT (honest): this gate guards the colour MATH we EMIT —
# it canNOT prove the platform actually rendered it (iOS ignored a fine colour). Only a
# per-platform screenshot proves the render. See changelog (v).
_INK_HEX = "#141414"   # dark proxy for AppTokens.ink in contrast math
_LEGIBLE_MIN = 4.5     # WCAG AA, normal text


def _wcag_contrast(h1, h2):
    def _lin(h):
        h = h.lstrip("#")
        ch = []
        for i in (0, 2, 4):
            x = int(h[i:i + 2], 16) / 255
            ch.append(x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4)
        return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]
    a, b = _lin(h1), _lin(h2)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


# Generic icon-name → (Material-tier glyph expr, SF Symbol) — native-vocabulary
# glyphs the appbox is allowed to render on native controls (NOT brand graphics).
# The Material-tier side resolves through KitGlyphs.lucide('<lucide-name>') —
# design-time icon names ARE Lucide names (kebab-case), resolved by-name against
# the kit's generated Lucide map (stacked_kit core, lucide_flutter-backed).
# The design's `<Icon name="…"/>` keeps its name as a node prop (Icon is a
# switch, not expanded), so a button wrapping one renders as a native
# AdaptiveIconButton with the mapped glyph.
_ICON = {
    "play": ("KitGlyphs.lucide('play')", "play.fill"),
    "pause": ("KitGlyphs.lucide('pause')", "pause.fill"),
    "reset": ("KitGlyphs.lucide('refresh-cw')", "arrow.clockwise"),
    "back": ("KitGlyphs.lucide('chevron-left')", "chevron.left"),
    "chevron-left": ("KitGlyphs.lucide('chevron-left')", "chevron.left"),
    "chevron-right": ("KitGlyphs.lucide('chevron-right')", "chevron.right"),
    "chevron": ("KitGlyphs.lucide('chevron-right')", "chevron.right"),
    "edit": ("KitGlyphs.lucide('pencil')", "pencil"),
    "check": ("KitGlyphs.lucide('check')", "checkmark"),
    "sound": ("KitGlyphs.lucide('volume-2')", "speaker.wave.2.fill"),
    "close": ("KitGlyphs.lucide('x')", "xmark"),
    "plus": ("KitGlyphs.lucide('plus')", "plus"),
}
_DEFAULT_ICON = ("KitGlyphs.lucide('circle')", "circle")


def _icon_for(name):
    """Icon name → (materialExpr, sfDartExpr). A literal name maps via _ICON; a dynamic
    `cond ? 'a' : 'b'` driven by a reactive timer var becomes a live Dart conditional
    (the play↔pause toggle glyph); a static cond resolves to one branch."""
    name = (name or "").strip()
    tern = _split_ternary(name)
    if tern:
        cond, a, c = tern
        rc = _reactive_var(cond.strip())
        if rc:
            ma, sa = _icon_for(a)
            mc, sc = _icon_for(c)
            return (f"({rc} ? {ma} : {mc})", f"({rc} ? {sa} : {sc})")
        return _icon_for(a if _cond_value(cond) is True else c)
    if name[:1] in ("'", '"', "`"):
        name = name[1:-1]
    m, s = _ICON.get(name, _DEFAULT_ICON)
    return (m, f"'{s}'")


def _trailing_icon(node):
    """A trailing affordance AFTER a button's label — the design's `Send code <Icon …/>`
    (a forward chevron). DESIGN-AGNOSTIC: detects an `Icon` child node sitting after the
    label/text in a button (the 2nd-or-later child whose prim is Icon), reads its name, and
    maps it via _ICON to an SF Symbol. The design's rotated back-arrow (name=back +
    transform rotate(180deg)) is a FORWARD chevron → chevron.right. Returns the sfSymbol
    string (e.g. 'chevron.right') or None when no trailing icon. Never a literal — derived
    from the captured node structure."""
    kids = node.get("children") or []
    # the trailing Icon is the LAST child (after the text/spinner); find an Icon-child
    icon_child = None
    for c in kids:
        if isinstance(c, dict) and c.get("prim") == "Icon":
            icon_child = c  # keep the last one (the trailing slot)
    if not icon_child:
        return None
    name = (icon_child.get("props") or {}).get("name") or ""
    # a rotated back-arrow (rotate(180deg) on name=back) flips left→right: a disclosure ›.
    rotated = "rotate(180" in str(icon_child.get("style", "")) or \
        "rotate(-180" in str(icon_child.get("style", "")) or \
        "rotate(180" in json.dumps(icon_child.get("props", {}))
    _mat, sf = _icon_for(name)
    sf = sf.strip("'")
    if rotated and sf in ("chevron.left", "chevron.right"):
        return "chevron.right" if sf == "chevron.left" else "chevron.left"
    return sf


def _icon_action(name):
    """onPressed for a control icon button. On a live-timer screen the play/pause glyph
    drives toggle() and reset drives reset() (pattern inference — the `.ctrl` onClick is
    stripped at capture). Off-timer falls back to the captured handler / no-op."""
    n = (name or "").lower()
    # A back/dismiss glyph pops the Stacked route (NavigationService.back()) — the same
    # API _nav_call uses; _wire_nav_imports injects the import when this string appears.
    # back-family = back / left-chevron / close / xmark; a RIGHT chevron is a disclosure
    # affordance, never a back action, so it is deliberately excluded.
    if n.strip().strip("'\"") in ("back", "chevron-left", "close", "xmark"):
        return "() => locator<NavigationService>().back()"
    if _TIMER:
        if "play" in n or "pause" in n or (_TIMER.get("running") or "x") in n:
            return "() => viewModel.toggle()"
        if "reset" in n:
            return "() => viewModel.reset()"
    return "() {}"


def _icon_button(node):
    """A button whose only content is an `<Icon name=…/>` → a native AdaptiveIconButton."""
    icon_child = next((c for c in node.get("children", []) if c.get("tag") == "Icon"), None)
    name = (icon_child.get("props") or {}).get("name") if icon_child else None
    mat, sf = _icon_for(name)
    action = _icon_action(name)
    cls = node.get("class") or []
    primary = "primary" in cls
    tint = "AppTokens.accent" if primary else "AppTokens.ink2"
    sem = ("Play or pause" if "toggle" in action
           else "Reset" if "reset" in action
           else (re.sub(r"\W+", " ", name or "button").strip() or "button"))
    return (f"AdaptiveIconButton(icon: {mat}, sfSymbol: {sf}, tint: {tint}, "
            f"foreground: AppTokens.bone, size: {44 if primary else 36}, "
            f"semanticLabel: {dart_str(sem)}, onPressed: {action})")


def _icon_widget(node):
    """A bare `<Icon name=…/>` standing on its own (a decorative or content glyph that
    is NOT the sole child of a button) → a Flutter Icon. The glyph maps via `_icon_for`;
    the size comes from the JSX prop; the colour is left to inherit from the nearest
    IconTheme (CSS `color` on an ancestor → `_box_wrap` wraps the subtree in IconTheme),
    so e.g. the welcome check rides the badge's bone foreground."""
    props = node.get("props") or {}
    mat, _sf = _icon_for(props.get("name"))
    size = px(props.get("size"))
    own = color_dart(node["style"].get("color"))
    args = [mat]
    if size is not None:
        args.append(f"size: {num(size)}")
    if own:
        args.append(f"color: {own}")
    return "Icon(" + ", ".join(args) + ")"


def _has_real_text(node):
    """Actual content text anywhere in the subtree (NOT _button_label's CTA default,
    which returns 'Continue' for a text-less button)."""
    if (node.get("text") or "").strip():
        return True
    return any(_has_real_text(c) for c in node.get("children", []))


def _is_icon_button(node):
    return (node.get("tag") == "button"
            and any(c.get("tag") == "Icon" for c in node.get("children", []))
            and not _has_real_text(node))


def _contrast_fg(bg_hex):
    """Label colour (Dart) that best contrasts `bg_hex`: white on dark, ink on light."""
    return ("Colors.white" if _wcag_contrast(bg_hex, "#FFFFFF") >= _wcag_contrast(bg_hex, _INK_HEX)
            else "AppTokens.ink")


def _assert_legible(fg_dart, bg_hex, ctx):
    """LEGIBILITY GATE: hard-fail generation if a button's label/fill contrast is below
    WCAG AA — a washed-out label can never be emitted silently again."""
    fg_hex = "#FFFFFF" if fg_dart == "Colors.white" else _INK_HEX
    r = _wcag_contrast(fg_hex, bg_hex)
    if r < _LEGIBLE_MIN:
        raise SystemExit(f"LEGIBILITY GATE FAILED — {ctx}: label {fg_dart} on {bg_hex} "
                         f"= {r:.1f}:1 (< {_LEGIBLE_MIN}:1 WCAG AA)")
    return r


# Native mode renders EVERY button (incl. Apple/Google social) as the native primitive,
# consistently — one rule, no per-provider special case. Brand graphics drop (gate G3).
def _native_button(node, label):
    """`native` mode: the design button → the native `AdaptiveButton` primitive
    (glass / expressive / shadcn), carrying the design's palette via tint/foreground
    (native-legitimate) and the right semantic variant — NOT a raw Flutter button, and
    NOT an official-provider button. The Apple button is a native Liquid Glass button
    like every other; its logo drops via G3, exactly like Google's G."""
    cls, style = node["class"], node["style"]
    # DESIGN-AGNOSTIC variant inference: the design's button classes carry the
    # semantic role (not just auth). google → outlined; ghost/nav-plain/textual
    # affordances → ghost; destructive (Sign out / Cancel subscription) → destructive;
    # tinted/secondary → secondary; primary CTAs (incl. the beige Send-code, the dark
    # Apple, the accent Continue/Pay) → primary. A <button> with no distinguishing class
    # defaults to primary (the solid CTA). Mirrors _PRIM_CLASS intent — no per-screen fix.
    if "google" in cls:
        variant = "outline"               # design's outlined Google button
    elif "ghost" in cls or "nav-plain" in cls:
        variant = "ghost"                 # text/ghost affordances (Cancel, Back, nav)
    elif any("destructive" in c for c in cls):
        variant = "destructive"           # destructive CTAs (Sign out `destructive-plain`,
                                          # Cancel subscription) — substring match so a
                                          # `destructive-plain` token is caught (the class
                                          # is one hyphenated token, not `destructive` alone)
    elif "tinted" in cls or "secondary" in cls:
        variant = "secondary"             # muted/tinted CTA
    elif "primary" in cls:
        variant = "primary"               # the design's submit CTA (Send code)
    else:
        variant = "primary"               # solid CTAs incl. the dark Apple button
    raw = _resolve_var((style.get("background")
                        or style.get("background-color") or "").strip())
    tint = color_dart(raw)
    # ALWAYS emit an explicit contrasting label colour — never None / system-default /
    # `?? paper` (that is exactly what made the Apple label dark-on-black and the Google
    # label white-on-cream). The gate then proves the math; the platform must HONOUR it
    # (iOS LiquidGlassButton.labelColor, Android ExButton.contentColor).
    bg_hex = raw if re.fullmatch(r"#[0-9A-Fa-f]{6}", raw or "") else "#FBF8F2"
    # The design OFTEN authors its own on-fill label colour via CSS `color` (e.g. the
    # `--text-on-accent` warm-bone on a burnt-orange CTA). That is a deliberate, visible
    # design choice — NOT the silent washed-out-label case the legibility gate exists to
    # catch. So when the design set an explicit label colour, honour it (faithful render)
    # and only WARN if it slips under WCAG AA; the HARD gate runs only on the GENERATED
    # binary pick (white-vs-ink), which is where generator-introduced illegibility hides.
    cap_fg_hex = _resolve_var((style.get("color") or "").strip())
    if cap_fg_dart := color_dart(cap_fg_hex):
        fg = cap_fg_dart
        if re.fullmatch(r"#[0-9A-Fa-f]{6}", cap_fg_hex or ""):
            r = _wcag_contrast(cap_fg_hex, bg_hex)
            if r < _LEGIBLE_MIN:
                import sys as _sys
                print(f"  note: button[{' '.join(node['class']) or '?'}] label uses the "
                      f"design's authored colour ({cap_fg_hex} on {bg_hex} = {r:.1f}:1, "
                      f"< {_LEGIBLE_MIN}:1 AA) — honoured as a deliberate design choice, "
                      f"not generator-introduced.", file=_sys.stderr)
    else:
        fg = _contrast_fg(bg_hex)
        _assert_legible(fg, bg_hex, f"button[{' '.join(node['class']) or '?'}]")
    # STATE-CONDITIONAL COLOR CONTRACT (the freeze bug) — NARROWED to form-gated CTAs.
    # The design's .auth-btn.primary is ACCENT when enabled and BONE-3 when :disabled
    # (bundle.html:1867). The capture reads getComputedStyle() at ONE instant, and for a
    # form-gated submit the button is :disabled at capture (form empty → formValid=false),
    # so the capture freezes bone-3 as the eternal colour for BOTH states — the enabled
    # Send-code rendered beige. A single-state capture can NEVER represent a state rule.
    # The fix: for a form-gated primary CTA (the one path that emits `enabled:
    # viewModel.formValid`), drop the captured tint/foreground and let AdaptiveButton own
    # the state map (enabled ? accent : bone3 / enabled ? paper : ink4) — the colours then
    # derive from the token contract, not a frozen disabled value. NON-gated primaries
    # (Continue to shipping, Continue to payment) keep their captured tint — those are
    # always-enabled, so the captured value IS the true enabled colour (no freeze). This
    # discriminator is what keeps the fix surgical: it touches only the path with a real
    # disabled state, not every primary CTA in the app. (GLM-5.2 A3, HIGH confidence.)
    is_form_gated = (_FORM_VM and variant == "primary"
                     and _AUTH_FIELD_TYPES.get(_AUTH_FIELD, {}).get("re"))
    if is_form_gated:
        tint = None   # AdaptiveButton maps enabled→accent / disabled→bone3
        fg = None     # AdaptiveButton maps enabled→paper / disabled→ink4
    args = [f"label: {dart_str(label)}",
            f"variant: AdaptiveButtonVariant.{variant}", "expand: true"]
    # Native glass entrance: when this button node carries the design's `.rise` motion AND
    # a rise spec was captured, the glass leaf enters NATIVELY (fade+grow+rise via the
    # platform view's alpha + SwiftUI spring) instead of popping. The surrounding RiseIn
    # keeps skipOnGlass:true (pass-through on glass), so the native entrance is what shows;
    # on expressive/shadcn RiseIn animates the leaf itself. The spring/opacity/scale/lift
    # are cooked once per view (`_GLASS_ENTRANCE`); only the stagger delay varies per leaf.
    # Placed right after `expand` so it lands inside `parse_expected`'s RiseIn head window.
    if _GLASS_ENTRANCE is not None and _ENTRANCE_DELAY is not None:
        g = _GLASS_ENTRANCE
        args.append(
            f"enterOnAppear: GlassEntrance(delayMs: {_ENTRANCE_DELAY}, "
            f"responseS: {g['response_s']}, bounce: {g['bounce']}, "
            f"opacityFrom: {g['opacityFrom']}, scaleFrom: {g['scaleFrom']}, "
            f"liftPx: {float(g['liftPx'])})")
    # GATE G3 (native-decoration policy): native Liquid Glass / Expressive controls accept
    # only native-vocabulary decoration — an SF Symbol on iOS, a Material icon on Android —
    # NOT a custom brand graphic. So the design's brand glyph (Google's 4-colour G, the
    # Apple logo) is DROPPED from the native render and RECORDED in the asset ledger
    # (design mode renders it religiously via _styled_button). Applied to ALL buttons the
    # same way — no per-provider branch. The only way a dropped mark could ride a native
    # button is if it can be converted to an SF Symbol (see asset-ledger / frontier plan).
    glyph = _find_svg(node)
    if glyph:
        _drop_glyph(glyph, origin=f"{' '.join(node['class']) or 'button'} (native action.button)",
                    reason="native Liquid Glass button accepts only SF Symbols, not a custom brand graphic")
    if tint:
        args.append(f"tint: {tint}")
    if fg:
        args.append(f"foreground: {fg}")
    # A trailing affordance (the design's `Send code ›`) — derived from a trailing Icon
    # child in the button node (never a literal). Native-vocabulary: an SF Symbol for the
    # glass/expressive families, a Material IconData for shadcn.
    trailing = _trailing_icon(node)
    if trailing:
        args.append(f"trailingSfSymbol: {dart_str(trailing)}")
    # On a FORM screen each CTA drives the SSOT-generated auth VM (ADR-0013), dispatched
    # by the same `node["class"]` signal the variant logic above uses: the beige
    # `primary` CTA = the design's "Send code" → sendCode() (email OTP); `google` →
    # go('google'); any other solid provider CTA (e.g. Apple) → go('<provider>'). Native
    # OAuth is a gated placeholder until the OAuth slice; busy/error live in the VM base.
    # Off-form buttons stay no-op until their handler is wired.
    if _FORM_VM:
        cls = node["class"]
        if "primary" in cls:
            on = "viewModel.sendCode()"
            # The design's submit CTA: disabled until the field is valid (its
            # disabled={!valid} gate) + a spinner while the request is in flight (working).
            # Both VM-owned (ADR-0003): formValid lifts the validity gate, isBusy the load.
            # The gate is only emitted when the field's DECLARED type has one (email/tel/
            # password) — a free-text field has no formValid, so a text-typed design stays
            # always-enabled (the design had no disabled={!valid} to honour).
            if _AUTH_FIELD_TYPES.get(_AUTH_FIELD, {}).get("re"):
                args.append("enabled: viewModel.formValid")
            args.append("busy: viewModel.isBusy")
        elif "google" in cls:
            on = "viewModel.go('google')"
            # Provider CTAs disable (busy) while ANY auth is in flight — the design's
            # disabled={!!working} covers all three buttons as one in-flight gate.
            args.append("busy: viewModel.isBusy")
        else:
            on = "viewModel.go('apple')"
            args.append("busy: viewModel.isBusy")
        args.append(f"onPressed: () => {on}")
    else:
        # Off-form CTAs stay FUNCTIONAL on native (Liquid Glass / Expressive / shadcn):
        # resolve the captured handler edge (nav / sign-out / checkout / pay) by label or
        # distinctive class, falling back to a no-op only when no handler is wired yet.
        # This was the silent parity gap: native CTAs rendered but did nothing because the
        # off-form path hardcoded onPressed: () {}.
        h = _handler_for_node(node)
        args.append(f"onPressed: {h or '() {}'}")
    return "AdaptiveButton(" + ", ".join(args) + ")"


def _styled_button(node, label):
    """A flat branded button styled from the design's CAPTURED fill/border — the
    design's auth buttons are flat (outlined Google, solid-black Apple, beige
    Send-code), NOT native glass/expressive. Foreground contrasts the fill.
    onPressed is a no-op stub (VM-action wiring is the follow-up)."""
    style = node["style"]
    raw = _resolve_var((style.get("background")
                        or style.get("background-color") or "#FBF8F2").strip())
    bgd = color_dart(raw) or "AppTokens.paper"
    fg = ("Colors.white" if (re.fullmatch(r"#[0-9A-Fa-f]{6}", raw or "")
                             and _lum(raw) < 0.5) else "AppTokens.ink")
    border = str(style.get("border", ""))
    bm = re.search(r"#[0-9A-Fa-f]{6}", border)
    # shape + height from the design's CSS, not a hardcoded pill: auth buttons are
    # 14px rounded-rects (border-radius), ~50px tall (min-height), never stadium.
    rad = px(style.get("border-radius"))
    mh = px(style.get("min-height")) or 52
    shape = (f"RoundedRectangleBorder(borderRadius: BorderRadius.circular({num(rad)}))"
             if rad is not None else "StadiumBorder()")
    common = f"minimumSize: Size.fromHeight({num(mh)}), shape: {shape}"
    # brand glyph (Google/Apple) sits left of the label, like the design; tint passes
    # the button foreground so the currentColor Apple mark turns white on black.
    glyph = _find_svg(node)
    txt = f"Text({dart_str(label)})"
    if glyph:
        child = (f"Row(mainAxisSize: MainAxisSize.min, children: [{_svg_widget(glyph, tint=fg)}, "
                 f"const SizedBox(width: 10), {txt}])")
    else:
        child = txt
    if "solid" in border and bm:
        bcd = color_dart(bm.group(0)) or "AppTokens.rule"
        return ("SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () {}, "
                f"style: OutlinedButton.styleFrom(backgroundColor: {bgd}, foregroundColor: {fg}, "
                f"side: BorderSide(color: {bcd}), {common}), child: {child}))")
    return ("SizedBox(width: double.infinity, child: FilledButton(onPressed: () {}, "
            f"style: FilledButton.styleFrom(backgroundColor: {bgd}, foregroundColor: {fg}, "
            f"{common}), child: {child}))")


# ---------------------------- node emit ----------------------------
def main_axis(style):
    j = style.get("justify-content")
    return {"space-between": "spaceBetween", "center": "center",
            "flex-end": "end", "space-around": "spaceAround"}.get(j, "start")


def cross_axis(style):
    a = style.get("align-items")
    return {"center": "center", "flex-end": "end", "stretch": "stretch",
            "baseline": "baseline"}.get(a, "start")


def gap_box(style, horizontal):
    g = px(style.get("gap"))
    if not g:
        return None
    return f"SizedBox({'width' if horizontal else 'height'}: {num(g)})"


def _adaptive_gap(sb):
    """Convert a vertical `SizedBox(height: N)` gap (from gap_box) into the
    AdaptiveGap primitive — used for the gap that precedes a form auth-button,
    which may be orphaned when that CTA is platform-suppressed on expressive.
    Mirrors gap_box's number formatting so the captured px value is preserved
    verbatim on the non-suppressing families."""
    m = re.search(r"height:\s*([0-9.]+)", sb)
    n = m.group(1) if m else "0"
    return f"const AdaptiveGap({num(float(n))})"


# ---------------------------- CSS box model ----------------------------
_BOX_KEYWORDS = ("auto", "inherit", "initial", "normal")


def _one_edge(tok):
    if tok in _BOX_KEYWORDS:
        return 0.0
    v = px(tok)
    return v if v is not None else 0.0


def _edges(style, prop):
    """CSS box shorthand (`margin`/`padding`, 1-4 px tokens) merged with any
    `<prop>-top/right/bottom/left` longhands → (t, r, b, l) floats, or None when the
    node sets nothing. 'auto' → 0 (centering is cross-axis/textAlign, not margin)."""
    e = {"top": None, "right": None, "bottom": None, "left": None}
    sh = str(style.get(prop, "")).split()
    if sh:
        v = [_one_edge(t) for t in sh]
        if len(v) == 1:
            v = v * 4
        elif len(v) == 2:
            v = [v[0], v[1], v[0], v[1]]
        elif len(v) == 3:
            v = [v[0], v[1], v[2], v[1]]
        e["top"], e["right"], e["bottom"], e["left"] = v[0], v[1], v[2], v[3]
    for side in e:
        lv = style.get(f"{prop}-{side}")
        if lv is not None:
            e[side] = _one_edge(lv)
    if all(x is None for x in e.values()):
        return None
    return (e["top"] or 0.0, e["right"] or 0.0, e["bottom"] or 0.0, e["left"] or 0.0)


def _edge_insets(edges):
    """(t, r, b, l) → an EdgeInsets Dart literal, or None when all sides are 0.
    Negative CSS margins (e.g. a `margin-left:-2px` icon nudge) are CLAMPED to 0:
    Flutter's Padding asserts isNonNegative, so a raw negative crashes the whole view at
    render (the giant "BOTTOM OVERFLOWED" red box). ponytail: a few-px nudge → 0 is
    visually negligible; a real negative offset would need Transform.translate, not
    Padding — not worth it for a micro-nudge."""
    if not edges:
        return None
    t, r, b, l = (max(0.0, x) for x in edges)
    if t == r == b == l == 0:
        return None
    if t == b and r == l:
        a = []
        if t:
            a.append(f"vertical: {num(t)}")
        if r:
            a.append(f"horizontal: {num(r)}")
        return "EdgeInsets.symmetric(" + ", ".join(a) + ")"
    return f"EdgeInsets.fromLTRB({num(l)}, {num(t)}, {num(r)}, {num(b)})"


# primitives that already pad their own content (don't double-apply CSS padding).
_SELF_PAD = {"AdaptiveButton", "AdaptiveCard", "AdaptiveTextField", "IconButton", "Pip"}
_APPLY_BOX = False  # generic-screen translation only; home keeps its bespoke spacing
# Cooked-once native glass entrance (delay·spring·opacity·scale·lift) for THIS view,
# derived design-agnostically from the captured rise spec (durMs/curve/dy) via
# glass_entrance.design_to_glass. None → no captured entrance, so glass leaves don't get
# one. Only delayMs varies per leaf (the stagger); the spring/opacity/scale/lift are shared.
_GLASS_ENTRANCE = None
_HANDLERS = []  # this screen's handler edges (handlers.json) — generic-emit manager wires taps.
                # Empty on the bespoke home (it wires avatar/card explicitly → no double-wire).

# When the design declares a primaryNav (bottom tab bar), the tab destinations are NOT
# top-level routes — they're hosted in HomeShellView's IndexedStack. So a nav edge whose
# target is a TAB must switch the shell's tab (RootNavigationViewModel.onTabSelected(i)),
# NOT navigateTo<Target>View() (that route doesn't exist). Maps tab screen-id → index.
# Set once per run by the manager (generate_views.py) from breakdown::primaryNav; empty
# when there's no shell → _nav_call falls through to the route path (no regression).
_TAB_TARGETS = {}


# Classes whose node `_emit_impl` returns a BESPOKE widget (the auth divider's
# label+rules Row, the splash loader bar) — the generic decoration wrap must NOT
# re-wrap/size them (it would clip the divider Row to a 1px hairline Container).
_BESPOKE_BOX_CLASSES = {"auth-divider", "splash-bottom"}


def _box_wrap(node, widget):
    """Apply the node's CSS box-model to its emitted widget: inner `padding` (skipped
    for primitives that pad themselves) then outer `margin`, as Padding wrappers. This
    is what preserves the design's vertical rhythm — the margins/paddings the
    translation used to drop. No-op on the bespoke home path (`_APPLY_BOX` False)."""
    if not _APPLY_BOX or not widget:
        return widget
    prim = str(node["prim"])
    style = node["style"]
    if prim not in _SELF_PAD and not prim.startswith("chart:"):
        pad = _edge_insets(_edges(style, "padding"))
        if pad:
            widget = f"Padding(padding: {pad}, child: {widget})"
    # A plain CONTAINER (Box/Row/Column with children) carrying CSS visual style —
    # background, border, radius or an explicit size — paints a Container around its
    # children. _box_wrap used to keep ONLY padding/margin, so styled surfaces WITH
    # children (the welcome check badge, account profile avatar + list-row fills)
    # rendered as bare content. Childless leaves are already decorated by _styled_box;
    # special prims (AdaptiveCard/Button/TextField/Icon/chart…) own their decoration.
    if (prim in ("Box", "Row", "Column") and node.get("children")
            and not _BESPOKE_BOX_CLASSES & set(node.get("class") or [])):
        args, deco, visible = _deco_args(style)
        if visible:
            inner = widget
            col = color_dart(style.get("color"))
            if col:  # CSS `color` inherits to descendant glyphs; IconTheme covers Icons
                     # (which carry no explicit colour — e.g. the welcome check on its badge).
                     # Text already gets its own colour from text_style, so it is unaffected.
                inner = f"IconTheme.merge(data: IconThemeData(color: {col}), child: {inner})"
            if deco:
                args.append(f"decoration: {deco}")
            args.append(f"child: {inner}")
            widget = "Container(" + ", ".join(args) + ")"
    mar = _edge_insets(_edges(style, "margin"))
    if mar:
        widget = f"Padding(padding: {mar}, child: {widget})"
    return widget


_NATIVE_PRIMS = {"AdaptiveButton", "IconButton", "Segmented"}  # iOS UiKitView platform views


def _has_native(node):
    """True if the subtree contains an iOS Liquid Glass platform view (button /
    icon-button / segmented). Wrapping one in Opacity/Transform (what RiseIn does)
    breaks native compositing — such a node animates only on expressive/shadcn."""
    return any(str(n.get("prim")) in _NATIVE_PRIMS for n in _walk([node]))


def _motion_wrap(node, widget):
    """Wrap a `.rise` node's widget in RiseIn (the design's staggered entrance).
    Generic path only (`_APPLY_BOX`); home keeps its hand-authored RiseIn. A
    pure-Flutter subtree passes skipOnGlass:false so it animates on iOS too; a
    subtree holding a native platform view falls back to the glass-safe skip."""
    if not _APPLY_BOX or not widget:
        return widget
    mo = node.get("motion")
    if not mo:
        return widget
    kind = mo.get("kind")
    # One-shot effects (a ring expanding+fading to nothing, a check scale-popping) —
    # captured design-agnostically by keyframe shape (capture_design.effect_styles).
    if kind == "pulse":
        return f"PulseRing(durationMs: {mo['durMs']}, child: {widget})"
    if kind == "pop":
        return f"PopIn(durationMs: {mo['durMs']}, child: {widget})"
    if kind != "rise-in":
        return widget
    safe = "skipOnGlass: false, " if not _has_native(node) else ""
    # durationMs + curve + dy are the captured entrance tokens (motion.dart, any
    # design); the per-element delayMs is the captured animation-delay → a TRUE
    # staggered start (controller-driven, post-frame — see RiseIn in primitives).
    return (f"RiseIn(delayMs: {mo['delayMs']}, durationMs: kRiseMs, "
            f"curve: kRiseCurve, dy: kRiseDy, {safe}child: {widget})")


def _children(nodes, sess):
    return [emit(n, sess) for n in nodes if emit(n, sess)]


_ROW_W_UNBOUNDED = False  # True while emitting a Row child that gets UNBOUNDED width
# (a non-flex Row child / horizontal-scroll child): an Expanded/Flexible there throws.

_HOME_CARD = False  # True only inside the home _sessionCard(s) builder. Gates the
# home-card-SPECIFIC binds (the `Last … streak` footer, the type Pip → s.type) so a
# DIFFERENT model-bound screen (e.g. Detail, also sess=True) doesn't inherit home-isms.

_FORM_VM = False  # True while emitting a FORM screen (a screen carrying a text input —
# the auth-entry/signin). Binds the field + submit CTAs to the VM's form contract
# (emailController + submit() + isBusy/error wrap in the VM). Set per-screen in
# _generic_view; reset in build_view so it never leaks to home/detail (which have no
# text input and a different VM). OTP emits 0 AdaptiveTextField → never matches.

_AUTH_FIELD = "text"  # the FORM screen's submit-field type (input[type] captured from the
# design) → drives the controller name + keyboardType + validity gate via
# _AUTH_FIELD_TYPES. DERIVED from the spec (never a literal): a tel-form design gets the
# phone gate. Set per-screen in _generic_view; reset in build_view.

# A social-auth provider button — class contains google/apple (the design's "Continue with
# Google/Apple"). Routed to AdaptiveAuthButton (the native OS sign-in button). DESIGN-
# AGNOSTIC: read from the design's button class.
_PROVIDER_RE = re.compile(r"\b(google|apple)\b")



def _row_or_col(node, sess, horizontal):
    global _ROW_W_UNBOUNDED
    raw = node["children"]
    sb = gap_box(node["style"], horizontal)
    ma = main_axis(node["style"])
    parts = []
    for c in raw:
        # In a ROW only, the first content block expands so siblings sit at the
        # edges (CSS flex / space-between without an explicit width). NEVER in a
        # Column — Expanded under an unbounded-height Column throws at boot. And
        # NEVER when this Row is itself width-UNBOUNDED (a non-flex child of an
        # outer Row, or a horizontal scroll child): an Expanded/Flexible there
        # throws "RenderFlex children have non-zero flex but incoming width
        # constraints are unbounded", which aborts the WHOLE screen → blank.
        # Match CSS shrink-to-fit instead: size to content (no flex).
        will_flex = (horizontal and not parts and len(raw) > 1
                     and not _ROW_W_UNBOUNDED
                     and (c["prim"] in ("Column", "Box")
                          or (c["prim"] == "Text" and ma == "spaceBetween")))
        # A Row gives a NON-flex child unbounded width; a flex child gets a bounded
        # slice. A Column passes its own width constraint down → children inherit.
        prev = _ROW_W_UNBOUNDED
        if horizontal:
            _ROW_W_UNBOUNDED = not will_flex
        try:
            e = emit(c, sess)
        finally:
            _ROW_W_UNBOUNDED = prev
        if not e:
            continue
        e = _motion_wrap(c, _box_wrap(c, e))
        if will_flex:
            wrap = "Expanded" if c["prim"] in ("Column", "Box") else "Flexible"
            e = f"{wrap}(child: {e})"
        if parts and sb:
            # The gap that PRECEDES a form auth-button child (AdaptiveAuthButton)
            # may become an orphan: on the expressive family that CTA is platform-
            # suppressed (returns SizedBox.shrink), and the design's raw gap would
            # sit before a now-zero-size widget, throwing off the even centering of
            # the remaining CTAs. Emit AdaptiveGap IN PLACE OF the raw SizedBox for
            # that one gap — it renders the captured gap on glass/shadcn (no
            # suppression) and collapses on expressive, co-locating the gap's
            # visibility with the SAME family decision that hides the CTA. Every
            # other captured gap stays a plain SizedBox (no render-strategy coupling
            # in the generic path). DESIGN-AGNOSTIC: keyed on the captured button
            # class (google|apple) on a form screen — never a literal.
            if (not horizontal and _FORM_VM
                    and _PROVIDER_RE.search(" ".join(c.get("class") or []))):
                parts.append(_adaptive_gap(sb))
            else:
                parts.append(sb)
        parts.append(e)
    if not parts:
        return ""  # every child dropped → no widget (caller falls back / omits)
    kids = ",\n".join(parts)
    widget = "Row" if horizontal else "Column"
    extra = "" if horizontal else "mainAxisSize: MainAxisSize.min, "
    ca = cross_axis(node["style"])
    extra += f"crossAxisAlignment: CrossAxisAlignment.{ca}, "
    if ca == "baseline":
        extra += "textBaseline: TextBaseline.alphabetic, "
    if ma != "start":
        extra += f"mainAxisAlignment: MainAxisAlignment.{ma}, "
    # the dashed footer rule is inserted by the parent (_col_body), not here, so
    # it is not duplicated.
    return f"{widget}({extra}children: [\n{kids},\n])"


_ENTRANCE_DELAY = None  # nearest `.rise` ancestor's stagger delay (ms), for glass-leaf entrance


def _handler_for_node(node):
    """If this node matches a captured handler edge (handlers.json) with a wireable
    handler, return the Dart onTap closure; else None. Match by label (specific), else a
    distinctive class. Generic-screen path only (_HANDLERS is empty on the bespoke home)."""
    if not _HANDLERS:
        return None
    label = (node.get("text") or "").strip()
    classes = node.get("class") or []
    for e in _HANDLERS:
        sel = e.get("selector") or {}
        if not ((label and sel.get("label") == label)
                or (sel.get("class") and not sel.get("label") and sel["class"] in classes)):
            continue
        # Sign-out (auth action). The design clears auth + setAuthStage('splash'), but routing
        # to splash re-triggers the SMOKE_AUTOLOGIN shim → straight back to Home (sign-out defeated).
        # A real logout clears the whole nav stack and lands on signin, so there is no authed route
        # left underneath and no splash autologin to undo it.
        if (e.get("kind") == "auth" and e.get("target") == "splash"
                and "signout" in (e.get("prop") or "").lower()):
            return ("() async { await locator<SupabaseAuthService>().signOut(); "
                    "locator<NavigationService>().clearStackAndShow(Routes.signinView); }")
        nav = _nav_call(e)
        if nav:
            return "() => " + nav
    return None


def emit(node, sess):
    """Dispatch wrapper. (1) While emitting a `.rise` node's SUBTREE, expose its stagger
    delay as `_ENTRANCE_DELAY` so descendant glass leaves enter natively at the container's
    delay (Restored on exit). (2) Handler-manager (generic path): a node matching a captured
    handler edge gets wrapped in a tap → its target/action."""
    global _ENTRANCE_DELAY
    cond = node.get("cond")
    if cond and _cond_hidden(cond):
        return ""  # dead conditional branch — provably hidden for the captured initial state
    mo = node.get("motion")
    if mo and mo.get("kind") == "rise-in":
        prev = _ENTRANCE_DELAY
        _ENTRANCE_DELAY = mo["delayMs"]
        try:
            out = _emit_impl(node, sess)
        finally:
            _ENTRANCE_DELAY = prev
    else:
        out = _emit_impl(node, sess)
    # Native primitives (AdaptiveButton / AdaptiveIconButton / AdaptiveAuthButton /
    # AdaptiveSwitch / AdaptiveSlider / AdaptiveChip / AdaptiveCard) own their own tap
    # slot (onPressed / onChanged / onTap) — they resolve the handler edge internally, so
    # the GestureDetector manager must NOT double-wrap them. Match on the emitted widget's
    # leading token, not a char-window of the body (onPressed sits deep in the string and
    # a 60-char window missed it → a native button got a second, conflicting tap layer).
    if out and _HANDLERS and not out.startswith(_NATIVE_PRIM_PREFIXES):
        h = _handler_for_node(node)
        if h:
            out = f"GestureDetector(behavior: HitTestBehavior.opaque, onTap: {h}, child: {out})"
    return out


def _emit_impl(node, sess):
    prim, cls, style = node["prim"], node["class"], node["style"]

    if node.get("svg") and "spinner" not in cls:  # vector leaf (logo / brand mark)
        return _svg_widget(node)

    if "auth-divider" in cls:
        txt = next((c.get("text", "") for c in node["children"] if c.get("text")), "")
        return ("Row(children: [const Expanded(child: Divider(color: AppTokens.rule)), "
                f"Padding(padding: const EdgeInsets.symmetric(horizontal: 12), "
                f"child: Text({dart_str(txt.upper())}, style: const TextStyle(fontSize: 11, "
                "letterSpacing: 1.2, fontWeight: FontWeight.w600, color: AppTokens.ink3))), "
                "const Expanded(child: Divider(color: AppTokens.rule))])")

    if "splash-bottom" in cls:
        # The splash loader (track + animated fill + live %) is a DYNAMIC frontier
        # component the deterministic box translator can't reproduce — it dropped the
        # bar to an invisible zero-size Container. Route the whole subtree to the
        # bespoke SplashProgress, filling over the design's captured DUR (kSplashFillMs).
        return "SplashProgress(durationMs: kSplashFillMs)"

    if prim.startswith("chart:"):
        # GENERIC chart dispatch — the widget NAME + data-constant NAME come from
        # the design's own component (node['tag']), not a hardcoded atlet vocabulary.
        # The spec carries BOTH prim (the generic kind: bars/heat/trend) AND tag (the
        # design's component name, e.g. 'StatBars' for atlet, 'DonutChart' for a foreign
        # design). The emitted widget call + the k* data constant it references are
        # derived from the tag, so any design's chart components resolve to THEIR names.
        # The home_assets.dart stub (tpl_home_assets_stub) declares each referenced
        # symbol; the operator fills the real CustomPainter bodies (the frontier).
        tag = node.get("tag") or "Chart"
        kind = prim.split(":", 1)[1]
        const = "k" + tag  # kStatBars, kHeatmap, kTrendLine, kDonutChart, …
        if kind == "bars":
            return f"{tag}(values: {const}Values, labels: {const}Labels, max: 0)"
        if kind == "heat":
            return f"{tag}(weeks: {const})"
        if kind == "trend":
            return f"{tag}(points: {const})"
        return f"{tag}()"  # unknown chart kind — name still tracks the design's tag

    if prim == "IconButton":  # the .play CTA — NATIVE leaf (iOS Liquid Glass /
        # Android Compose Expressive). A leaf icon-button is a glass/expressive
        # candidate and stays native even inside the lite workout card; the
        # primitive tight-boxes the platform view (SizedBox.square) so it can't
        # drift row-to-row. Only composite surfaces & whole rows go lite.
        return ("AdaptiveIconButton(icon: KitGlyphs.lucide('play'), sfSymbol: 'play.fill', "
                "tint: AppTokens.ink, foreground: AppTokens.bone, size: 36, "
                "onPressed: () {}, semanticLabel: 'Start workout')")

    if _is_icon_button(node):  # a design control button (e.g. detail .ctrl reset/play/pause)
        # wrapping a single <Icon name=…/> → native AdaptiveIconButton with the mapped
        # glyph; on a live-timer screen play/pause→toggle, reset→reset.
        return _icon_button(node)

    if prim == "Pip":  # workout type pip — bound label (home card only)
        label = "s.type.toUpperCase()" if (sess and _HOME_CARD) else "''"
        return ("Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), "
                "decoration: BoxDecoration(color: AppTokens.bone, borderRadius: BorderRadius.circular(999), "
                "border: Border.all(color: AppTokens.rule)), "
                "child: Row(mainAxisSize: MainAxisSize.min, children: [ "
                "Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppTokens.accent, shape: BoxShape.circle)), "
                "const SizedBox(width: 6), "
                f"Text({label}, style: const TextStyle(fontSize: 10, letterSpacing: 1.0, fontWeight: FontWeight.w600, color: AppTokens.ink2)) ]))")

    if prim == "AdaptiveButton":
        # A SOCIAL-AUTH provider button (class google/apple) → the brand-governed
        # AdaptiveAuthButton (the native OS sign-in button: Apple's SignInWithAppleButton on
        # glass, the official Google "G" on a styled button). DESIGN-AGNOSTIC: the provider
        # is read from the design's button class, the brand marks are the official assets.
        # Off-form social buttons (no _FORM_VM) stay plain AdaptiveButtons.
        if _FORM_VM and _PROVIDER_RE.search(" ".join(node.get("class") or [])):
            provider = "google" if "google" in " ".join(node["class"]) else "apple"
            label = _button_label(node)
            return (f"AdaptiveAuthButton(provider: {dart_str(provider)}, "
                    f"label: {dart_str(label)}, busy: viewModel.isBusy, "
                    f"onPressed: () => viewModel.go({dart_str(provider)}))")
        # native (default) → the platform-native AdaptiveButton primitive;
        # design (opt-in per config.render) → reproduce the design exactly.
        if _render_mode(node) == "design":
            return _styled_button(node, _button_label(node))
        return _native_button(node, _button_label(node))

    if prim == "AdaptiveTextField":
        # On a FORM screen the field binds to the VM's form controller (named for the
        # field's DECLARED type via _AUTH_FIELD_TYPES — emailController / phoneController /
        # passwordController) AND its onChanged → VM re-validates so the submit CTA enables
        # on valid input (the design's disabled-while-invalid gate). The keyboardType is
        # ALSO type-derived (email → emailAddress), so the native keyboard matches the
        # declared field. Else a throwaway controller (no VM to bind).
        ph = _field_placeholder(node)
        if _FORM_VM:
            ft = _AUTH_FIELD_TYPES.get(_AUTH_FIELD, _AUTH_FIELD_TYPES["text"])
            ctl, kt = ft["ctl"], ft["kt"]
            hook = ", onChanged: viewModel.onFieldChanged" if ft["re"] else ""
            return (f"AdaptiveTextField(controller: viewModel.{ctl}"
                    + f", keyboardType: {kt}"
                    + (f", placeholder: {dart_str(ph)}" if ph else "")
                    + hook + ")")
        kt = _TEXT_FIELD_KT.get((node.get("props") or {}).get("type") or "")
        return ("AdaptiveTextField(controller: TextEditingController()"
                + (f", keyboardType: {kt}" if kt else "")
                + (f", placeholder: {dart_str(ph)}" if ph else "") + ")")

    if prim == "AdaptiveCard":
        bg = color_dart(style.get("background"))
        stat = "stat-card" in cls
        # A TAPPABLE card (product-tile / address-card / rate-card / plan-card /
        # order-row / tracking-card / list-row) has a captured handler edge → resolve it
        # so the native card's own onTap (glass LiquidGlassContainer.interactive /
        # expressive InkWell / shadcn) carries the action, instead of a dead surface.
        # stat/workout cards keep no tap (unchanged behaviour).
        handler = _handler_for_node(node)
        pad = ("const EdgeInsets.fromLTRB(20, 18, 20, 16)" if stat
               else "const EdgeInsets.symmetric(horizontal: 18, vertical: 16)")
        col = _col_body(node, sess)
        args = []
        if bg:
            args.append(f"tint: {bg}")
        # All emitted cards are CONTENT (the stat deck + workout list rows + the tappable
        # selectable cards) → OPAQUE. lite: true renders in Flutter (_soft: solid fill +
        # 1px rule border + rounded = the design's flat card), never a glass platform view.
        # Glass is reserved for floating chrome (toolbar/tabbar/sheet), not cards —
        # docs/design-systems/liquid-glass.md THE RULE + the stat-deck=opaque decision.
        # (Workout rows also need this vs the iOS hybrid-comp clip.) A native glass surface
        # per list row janks; the tappable cards still get a correct InkWell onTap via lite.
        args.append("lite: true")
        # stat cards are design --r-lg (24); workout cards keep the AdaptiveCard
        # default --r-md (16). The radius is the glass surface's cornerRadius.
        if stat:
            args.append("radius: 24")
        if handler:
            args.append(f"onTap: {handler}")
        args.append(f"padding: {pad}")
        args.append(f"child: {col}")
        return "AdaptiveCard(" + ", ".join(args) + ")"

    if prim == "AdaptiveChip":
        # A selectable pill (filter-chip / label-pill / mini-seg-opt / seg-opt /
        # fb-tag / tempo-chip / fb-emoji / avatar-color-dot). The design marks the
        # selected state with an `active`/`current`/`selected` class; the label is the
        # subtree text. The tap resolves to the captured handler (setCategory /
        # setBilling / setSelectedPlan / toggleTag …) so the native chip is FUNCTIONAL.
        label = _button_label(node)
        sel_cls = {"active", "current", "selected"}
        selected = bool(set(cls) & sel_cls)
        handler = _handler_for_node(node)
        tint = color_dart(style.get("background"))
        args = [f"label: {dart_str(label)}",
                f"selected: {'true' if selected else 'false'}"]
        if tint:
            args.append(f"tint: {tint}")
        args.append(f"onTap: {handler or '() {}'}")
        return "AdaptiveChip(" + ", ".join(args) + ")"

    if prim == "AdaptiveSwitch":
        # A toggle (ios-switch / switch). The design marks the on-state with an `on`
        # class; the value is captured at the initial state. The control is
        # component-internal (the owning row owns the state in a real app), so
        # onChanged is a no-op stub until the VM layer owns the setting — same policy
        # as off-form CTAs before their handler is wired.
        on = "on" in cls
        tint = color_dart(style.get("background"))
        args = [f"value: {'true' if on else 'false'}"]
        if tint:
            args.append(f"tint: {tint}")
        args.append("onChanged: (v) {}")
        return "AdaptiveSwitch(" + ", ".join(args) + ")"

    if prim == "AdaptiveSlider":
        # A range input (tip-range / tweak-slider). min/max/step/value come from the
        # design's props; onChanged is a no-op stub (component-internal state) until
        # the VM layer owns the value. A non-literal value (a JSX state expr like
        # {tipAmount}) is un-parseable at gen time → default to min (the live value
        # is VM-owned in the real app).
        props = node.get("props") or {}
        mn = px(str(props.get("min"))) if props.get("min") is not None else 0.0
        mx = px(str(props.get("max"))) if props.get("max") is not None else 1.0
        mn = mn if mn is not None else 0.0
        mx = mx if mx is not None else 1.0
        raw_val = px(str(props.get("value"))) if props.get("value") is not None else None
        val = raw_val if raw_val is not None else mn
        raw_step = px(str(props.get("step"))) if props.get("step") is not None else None
        divisions = None
        if raw_step and raw_step > 0 and mx > mn:
            divisions = max(1, int(round((mx - mn) / raw_step)))
        tint = color_dart(style.get("accent-color") or style.get("color"))
        args = [f"value: {num(val)}", f"min: {num(mn)}", f"max: {num(mx)}"]
        if divisions is not None:
            args.append(f"divisions: {divisions}")
        if tint:
            args.append(f"tint: {tint}")
        args.append("onChanged: (v) {}")
        return "AdaptiveSlider(" + ", ".join(args) + ")"

    if prim == "Text":
        return _text(node, sess)

    if prim == "Icon":  # a standalone glyph (welcome check, list-row icon) → Flutter Icon
        return _icon_widget(node)

    # A container with position:absolute children → a Stack (they OVERLAY siblings, not
    # sit beside them). The welcome ring (`position:absolute; inset:0`) encircles the
    # centered check badge; a Row/Column would lay them out side-by-side.
    if (prim in ("Row", "Column", "Box") and node["children"]
            and any((c.get("style") or {}).get("position") == "absolute"
                    for c in node["children"])):
        return _stack_body(node, sess)

    if prim == "Row":
        return _row_or_col(node, sess, horizontal=True)
    if prim == "Column":
        return _row_or_col(node, sess, horizontal=False)

    # Box / unknown: leaf with content → Text; container → Column; styled leaf →
    # Container (decorative boxes: logos, loaders, rings — previously dropped).
    # Inline RICH TEXT (<u>/<a> woven into prose) → Text.rich. Those inline elements are
    # also children, so this must precede the container check (the footer's Terms/Privacy).
    if node.get("inlines"):
        return _text(node, sess)
    # A node with CHILDREN is a container — render them, even if it also carries a stray
    # `bind` from a control-flow `{expr}` captured between its children. The text/bind LEAF
    # path is for TRUE leaves only; otherwise a container that picked up a stray bind was
    # misclassified as a Text and silently dropped its whole subtree (this collapsed the
    # entire account-scroll: 9 rich children → empty render).
    if node["children"]:
        return (_col_body(node, sess)
                or (_text(node, sess) if (node.get("text") or node.get("bind")) else "")
                or _styled_box(style))
    if node.get("text") or node.get("bind"):
        return _text(node, sess)
    return _styled_box(style)


def _stack_body(node, sess):
    """A container with position:absolute children → a Stack, alignment center (CSS flow
    children center under the absolute overlay). `inset:0` → Positioned.fill (the welcome
    ring filling its 120px slot); other offsets are a frontier (centered fallback)."""
    parts = []
    for c in node["children"]:
        e = emit(c, sess)
        if not e:
            continue
        e = _motion_wrap(c, _box_wrap(c, e))
        st = c.get("style") or {}
        if st.get("position") == "absolute" and (st.get("inset") or "").strip() in ("0", "0px"):
            e = f"Positioned.fill(child: {e})"
        parts.append(e)
    if not parts:
        return ""
    return "Stack(alignment: Alignment.center, children: [\n" + ",\n".join(parts) + ",\n])"


def _col_body(node, sess):
    """A node's children as a Column (cards/blocks), gap-spaced, footer-dashed."""
    raw = node["children"]
    sb = gap_box(node["style"], horizontal=False)
    parts = []
    for c in raw:
        e = emit(c, sess)
        if not e:
            continue
        e = _motion_wrap(c, _box_wrap(c, e))
        if parts and sb:
            parts.append(sb)  # column gap (also serves as space above a footer)
        if "footer" in c["class"]:  # design's dashed border-top rule
            parts.append("const DashedLine()")
            parts.append("const SizedBox(height: 12)")
        parts.append(e)
    if not parts:
        return ""  # every child dropped → no widget (caller falls back / omits)
    ca = cross_axis(node["style"]) if node["style"].get("align-items") else "start"
    return ("Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: "
            f"CrossAxisAlignment.{ca}, children: [\n" + ",\n".join(parts) + ",\n])")


_INLINE_UNDERLINE = {"u", "a"}  # design's inline links read as underlined text


def _rich_text(node, style, cls):
    """Mixed loose text + inline <u>/<a>/<b>… → Text.rich, preserving the order and
    the edge spaces the flat `text` drops. <u>/<a> render underlined (the design's
    Terms/Privacy links). Tap-wiring stays the standing footer-links task — these
    <u> carry no href, so parity here is the underlined label, not navigation."""
    up = style.get("text-transform") == "uppercase"
    segs = node["inlines"]
    last = len(segs) - 1
    spans = []
    for i, s in enumerate(segs):
        txt = s.get("t", s.get("text", ""))
        if up:
            txt = txt.upper()
        if i == 0:
            txt = txt.lstrip()  # trim the line's outer edges (leading/trailing
        if i == last:
            txt = txt.rstrip()  # whitespace from the source div), keep inner gaps
        if not txt:
            continue
        if s.get("tag") in _INLINE_UNDERLINE:
            spans.append(f"TextSpan(text: {dart_str(txt)}, "
                         "style: const TextStyle(decoration: TextDecoration.underline))")
        else:
            spans.append(f"TextSpan(text: {dart_str(txt)})")
    head = (f"Text.rich(TextSpan(style: {text_style(style, cls)}, "
            f"children: [{', '.join(spans)}])")
    align = {"center": "TextAlign.center", "right": "TextAlign.right",
             "end": "TextAlign.right"}.get(style.get("text-align"))
    if align:
        head += f", textAlign: {align}"
    return head + ")"


def _text(node, sess):
    cls, style, binds = node["class"], node["style"], node.get("bind", [])
    if sess and _HOME_CARD and "caption" in cls and "num" in cls:
        # design footer: "Last {w.last} · {w.streak}× streak" (interleave was split)
        content = "'Last ${_lastLabel(s.occurredOn)} · ${s.streak}× streak'"
    elif sess and binds:
        # Resolve conditional/derived binds against the state table (resting ? 'Rest'
        # : 'Countdown' → 'Countdown'); fmtSec(remaining) → fmtSec(s.metric). Falls
        # back to the BIND map / notes. Unresolvable (data-dependent) → '' for now.
        content = _resolve_bind_content(binds) or "''"
    elif node.get("inlines"):
        return _rich_text(node, style, cls)  # inline links/emphasis → rich text
    else:
        t = node.get("text", "")
        if not t:
            return ""
        content = None
        if binds and any("''" in b or '""' in b for b in binds):
            # A conditional name-append `X ? `, ${X}` : ''` (auth.jsx WelcomeView's
            # `name` prop — render the athlete's name when present). The static capture
            # had no name → flattened to a stray space before the punctuation
            # ("Welcome ."). BIND it to the view-model name (firstName, fallback-safe)
            # so the design's "Welcome, {name}." actually renders — don't drop it.
            if any(re.search(r"\$\{name\}", b) for b in binds):
                bound = re.sub(r"\s*([.!?,;:])\s*$",
                               r", ${viewModel.firstName}\1", t, count=1)
                if bound != t:
                    content = f"'{bound}'"  # raw Dart interpolation (not dart_str-escaped)
            if content is None:
                # An interpolation whose initial-frame value is its empty branch with no
                # bindable name → drop the stray space the emptied placeholder left
                # before sentence punctuation: "Welcome ." → "Welcome.".
                t = re.sub(r"\s+([.!?,;:])", r"\1", t)
        if content is None:
            if style.get("text-transform") == "uppercase":
                t = t.upper()
            content = dart_str(t)
    align = {"center": "TextAlign.center", "right": "TextAlign.right",
             "end": "TextAlign.right"}.get(style.get("text-align"))
    ta = f"textAlign: {align}, " if align else ""
    text = f"Text({content}, {ta}style: {text_style(style, cls)})"
    # The design constrains body copy via CSS max-width (e.g. .auth-sub { max-width: 32ch }
    # — the "Log your workouts…" subtitle). Without honouring it the text stretched full-
    # width (the width drift the operator flagged). DESIGN-AGNOSTIC: Nch → N × ~7px (the
    # average advance width of the body face); the constraint is a finite CSS property
    # captured into node.style, never a literal. Wrapped in a ConstrainedBox so the bound
    # survives in a flex parent (a plain maxWidth on a Text in a stretch Column is ignored).
    mw = _max_width(style)
    if mw:
        return f"ConstrainedBox(constraints: const BoxConstraints(maxWidth: {mw}), child: {text})"
    return text


# 1ch ≈ the advance width of '0' in the body face. ~7px is the practical average for the
# 14–17px sans body copy the appbox ships; the exact per-face value is a phase-2 refinement.
_CH_PX = 7.0


def _max_width(style):
    """The design's max-width constraint → a logical-pixel double, or None. Resolves Nch
    (character units) and Npx. DESIGN-AGNOSTIC: derived from the captured CSS property."""
    mw = (style or {}).get("max-width")
    if not mw:
        return None
    m = re.fullmatch(r"(\d+(?:\.\d+)?)ch", str(mw).strip())
    if m:
        return round(float(m.group(1)) * _CH_PX, 1)
    m = re.fullmatch(r"(\d+(?:\.\d+)?)px", str(mw).strip())
    if m:
        return round(float(m.group(1)), 1)
    return None


# ---------------------------- region finders ----------------------------
def _walk(nodes):
    for n in nodes:
        yield n
        yield from _walk(n["children"])


def _find(nodes, pred):
    for n in _walk(nodes):
        if pred(n):
            return n
    return None


def _stat_cards(spec):
    return [n for n in _walk(spec["tree"]) if "stat-card" in n["class"]]


def _workout_card(spec):
    # the list card — NOT the long-press ctx-menu preview copy
    for n in _walk(spec["tree"]):
        if "workout-card" in n["class"]:
            return n
    return None


# ---------------------------- view assembly ----------------------------
def _stats_deck_method(spec):
    cards = [emit(c, sess=False) for c in _stat_cards(spec)]
    body = ",\n            ".join(cards)
    return ("  Widget _statsDeck(HomeViewModel vm) {\n"
            "    // Spec-driven: the 4 cards (eyebrow/note/big/unit + chart kind +\n"
            "    // variant tint) are translated from the design composition. Only the\n"
            "    // chart curve data is fixed (the frontier).\n"
            f"    return StatsCarousel(cards: [\n            {body},\n    ]);\n  }}")


def _session_card_method(spec, card_nav=None):
    global _HOME_CARD
    card = _workout_card(spec)
    _HOME_CARD = True  # home-card-specific binds (Last…streak footer, type Pip) are live here
    try:
        body = emit(card, sess=True)
    finally:
        _HOME_CARD = False
    if card_nav:
        # design: tapping a workout card opens its Detail (handlers.json edge), passing the
        # tapped Session as a route-arg (Stacked-generated) so DetailView binds against it.
        # The inner play button keeps its own tap (absorbs first); the card body tap navigates.
        nav = card_nav.replace("navigateToDetailView()", "navigateToDetailView(workout: s)")
        body = ("GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => "
                + nav + ", child: " + body + ")")
    return ("  /// Spec-driven: structure + metric-right-of-title / play-on-footer\n"
            "  /// ordinals come from the design's workout-card subtree; field slots\n"
            "  /// are bound to the Session via the design→data_model map.\n"
            "  Widget _sessionCard(Session s) {\n"
            f"    return {body};\n  }}")


def _your_workouts_text(spec):
    n = _find(spec["tree"], lambda x: "workouts-title" in x["class"] and x.get("text"))
    if not n:
        n = _find(spec["tree"], lambda x: x.get("text", "").lower().startswith("your workout"))
    return n["text"] if n else "Your workouts"


def _header_src(avatar_nav=None):
    """The home `_header` method source. The avatar is wired to its captured handler
    edge (handlers.json): `avatar_nav` is the Dart NavigationService call for tapping
    it (design: avatar → Account). None → plain (byte-identical to the no-handler case,
    so designs without an avatar edge don't drift)."""
    avatar = (
        "Container(\n"
        "          width: 38, height: 38, alignment: Alignment.center,\n"
        "          decoration: const BoxDecoration(color: AppTokens.ink, shape: BoxShape.circle),\n"
        "          child: Text(vm.initials, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: AppTokens.bone)),\n"
        "        )"
    )
    if avatar_nav:
        # whole 38×38 box tappable (opaque), not just the glyph
        avatar = ("GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => "
                  + avatar_nav + ", child: " + avatar + ")")
    return '''  /// Composite (atlet-generic shell, not design-structure the gate grades):
  /// eyebrow `WEEKDAY · HH:MM` over `{greeting},\\n{firstName}.` + initials avatar.
  Widget _header(HomeViewModel vm) {
    final now = DateTime.now();
    const days = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final eyebrow = '${days[now.weekday - 1]} · $hh:$mm';
    final greet = now.hour < 12 ? 'Morning' : now.hour < 18 ? 'Afternoon' : 'Evening';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eyebrow.toUpperCase(),
                  style: TextStyle(fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w600, color: AppTokens.ink3)),
              const SizedBox(height: 6),
              Text('$greet,\\n${vm.firstName}.',
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, height: 1.05, letterSpacing: -0.5, color: AppTokens.ink)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        ''' + avatar + ''',
      ],
    );
  }'''


def _filter_row_method(spec):
    title = dart_str(_your_workouts_text(spec))
    return ('''  /// Composite: spec "Your workouts" title + count badge + New + the
  /// AdaptiveSegmented filter (renders native glass on iOS / M3 on Android).
  Widget _filterRow(HomeViewModel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Text(''' + title + ''',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTokens.ink)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppTokens.accentSoft, borderRadius: BorderRadius.circular(20)),
                child: Text('${vm.countFor(vm.filter)}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTokens.accent)),
              ),
            ]),
            AdaptiveButton(label: 'New', variant: AdaptiveButtonVariant.secondary, sfSymbol: 'plus', icon: LucideIcons.plus, onPressed: () {}),
          ],
        ),
        const SizedBox(height: 14),
        AdaptiveSegmented(labels: HomeViewModel.segLabels, selectedIndex: vm.filter, onChanged: vm.setFilter),
      ],
    );
  }''')


HEAD = '''// AUTO-GENERATED by flutter_crew generate_view.py from the design composition
// spec (capture_design.py). Do NOT hand-edit — regenerate. Graded against the
// DESIGN by design_gate, never against the hand-authored view.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // SystemUiOverlayStyle (reactive status bar)
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:stacked/stacked.dart';

import '../app_tokens.dart';
import '../domain/ports/session_repository.dart';
import '../ui/primitives.dart' hide RiseIn; // home keeps its own RiseIn (home_assets)
import 'home_assets.dart';
import 'home_viewmodel.dart';

class HomeView extends StackedView<HomeViewModel> {
  const HomeView({super.key});

  @override
  Widget builder(BuildContext context, HomeViewModel viewModel, Widget? child) {
    if (viewModel.isBusy && !viewModel.dataReady) {
      // The design has no loading view — show the paper background (continuous with
      // splash→home), NOT a bare centered spinner. The session fetch is sub-second and
      // the splash's own progress bar already carried the "loading" signal.
      return const AdaptiveScaffold(body: SizedBox.shrink());
    }
    if (viewModel.hasError) {
      return AdaptiveScaffold(body: Center(child: Text('Could not load sessions: ${viewModel.error}')));
    }
    final sessions = viewModel.filtered;
    // Light paper surface → DARK status-bar icons, declared HERE (not just globally) so
    // returning from a dark screen (Detail) reactively restores it (Flutter #54029).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light),
      child: AdaptiveScaffold(
        body: AdaptiveRefresh(
          onRefresh: viewModel.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _header(viewModel),
              const SizedBox(height: 20),
              _statsDeck(viewModel),
              const SizedBox(height: 22),
              _filterRow(viewModel),
              const SizedBox(height: 16),
              for (var i = 0; i < sessions.length; i++)
                RiseIn(delayMs: 70 * i, child: Padding(padding: const EdgeInsets.only(bottom: 12), child: _sessionCard(sessions[i]))),
              if (sessions.isEmpty)
                Padding(padding: const EdgeInsets.all(40), child: Center(child: Text('No sessions yet.', style: TextStyle(color: AppTokens.ink3)))),
            ],
          ),
        ),
      ),
    );
  }
'''

TAIL = '''
  /// Relative "Last" label from the date (design's `last`): today / Nd / Nw.
  String _lastLabel(DateTime d) {
    final days = DateTime.now().difference(d).inDays;
    if (days <= 0) return 'today';
    if (days < 7) return '${days}d';
    return '${(days / 7).floor()}w';
  }

  @override
  HomeViewModel viewModelBuilder(BuildContext context) => HomeViewModel();
}
'''


GENERIC_HEAD = '''// AUTO-GENERATED by flutter_crew generate_view.py from the design composition
// spec (capture_design.py). Do NOT hand-edit — regenerate. Graded against the
// DESIGN by design_gate, never against the hand-authored view.
{imports}

class {Name}View extends StackedView<{Name}ViewModel> {{
  const {Name}View({{super.key{ctor_args}}});
{fields}
  @override
  Widget builder(BuildContext context, {Name}ViewModel viewModel, Widget? child) {{
{busy_gate}{model_local}    return {overlay_open}AdaptiveScaffold({scaffold_bg}body: {body}){overlay_close};
  }}
{ready}
  @override
  {Name}ViewModel viewModelBuilder(BuildContext context) => {Name}ViewModel({vm_args});
}}
'''


def tpl_vm_base(name, snake, timer):
    """The GENERATED countdown state-machine base (regenerated freely). The
    hand-editable {name}ViewModel EXTENDS it. `timer` = {value, init, running} from
    capture_data; `init` (e.g. w.target) maps to the route-arg record via the BIND map."""
    init = _resolve_value(timer["init"]) or "0"  # w.target → s.metric → workout.metric
    init = init.replace("s.", "workout.")
    return f'''// AUTO-GENERATED by flutter_crew (generate_view.py) — the {name} countdown state
// machine. Regenerated every run; do NOT hand-edit. {name}ViewModel extends this and
// IS the hand-editable extension point. Pattern detected by capture_data (ticker +
// `{timer["running"]}` + `{timer["value"]}`←record field).
import 'dart:async';

import 'package:stacked/stacked.dart';

import '../domain/ports/session_repository.dart';

abstract class {name}ViewModelBase extends BaseViewModel {{
  {name}ViewModelBase(this.workout);
  final Session workout;

  late int {timer["value"]} = {init};  // initial = the record's target/duration
  bool {timer["running"]} = false;
  Timer? _ticker;

  void start() {{
    if ({timer["running"]}) return;
    {timer["running"]} = true;
    notifyListeners();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {{
      if ({timer["value"]} <= 0) {{
        pause();
        return;
      }}
      {timer["value"]} -= 1;
      notifyListeners();
    }});
  }}

  void pause() {{
    {timer["running"]} = false;
    _ticker?.cancel();
    notifyListeners();
  }}

  void toggle() => {timer["running"]} ? pause() : start();

  void reset() {{
    pause();
    {timer["value"]} = {init};
    notifyListeners();
  }}

  // Workout complete: the timer ran down to 0 and is no longer running. Drives the
  // post-completion FeedbackSheet overlay (the design's `useFeedback(done)` → sheet
  // opens 700ms after done). Derived — no separate `done` field to keep in sync.
  bool get done => !{timer["running"]} && {timer["value"]} <= 0;

  @override
  void dispose() {{
    _ticker?.cancel();
    super.dispose();
  }}
}}
'''


def tpl_vm_stub(name, snake):
    """The extension-point VM, rewritten to EXTEND the generated base. Emitted only
    when the existing stub is still the empty default (never clobbers hand-written logic)."""
    return f'''// FACTORY EXTENSION POINT — hand-edit freely; the factory regenerates ONLY the
// `.gen.dart` base (the countdown state machine), never this file once you add logic.
// @appbox-extension-point: presentation/{snake}_viewmodel
import '{snake}_viewmodel.gen.dart';

class {name}ViewModel extends {name}ViewModelBase {{
  {name}ViewModel(super.workout);
  // TODO(builder): override start/pause/reset or add screen actions here.
}}
'''


def tpl_vm_overlays_base(name, snake, flags):
    """The GENERATED overlay-state base for a screen whose view emits gated sheet/modal
    overlays (Option C). Each `<flag>Open` bool (planOpen, createOpen, …) drives a
    `Visibility(viewModel.<flag>Open)` layer in the view; `open<Flag>`/`close<Flag>`
    flip it + notifyListeners so the sheet shows/hides reactively. The hand-editable
    `{name}ViewModel` extends this (tpl_vm_overlays_stub) — the flags are generated,
    never hand-authored. `flags` = the ordered unique flag names (lower-camel, no
    `Open` suffix). Empty flags → no base (the screen has no overlays)."""
    if not flags:
        return ""
    fields = "\n".join(f"  bool _{f}Open = false;" for f in flags)
    getters = "\n".join(f"  bool get {f}Open => _{f}Open;" for f in flags)
    methods = "\n".join(
        f"  void open{f.capitalize()}() {{ _{f}Open = true; notifyListeners(); }}\n"
        f"  void close{f.capitalize()}() {{ _{f}Open = false; notifyListeners(); }}"
        for f in flags)
    return f'''// AUTO-GENERATED by flutter_crew (generate_view.py) — the {name} overlay-state
// base. Regenerated every run; do not hand-edit. {name}ViewModel extends this.
// The `<flag>Open` bools drive the gated sheet/modal overlays the view emits
// (Option C: sheets/scrims as Visibility-gated Stack layers).
import 'package:stacked/stacked.dart';

abstract class {name}ViewModelBase extends BaseViewModel {{
{fields}
{getters}
{methods}
}}
'''


def tpl_vm_overlays_stub(name, snake):
    """The extension-point VM extending the overlay-state base (mirrors tpl_vm_stub but
    no-arg ctor — overlay screens have no route-arg record)."""
    return f'''// FACTORY EXTENSION POINT — hand-edit freely; the factory regenerates ONLY the
// `.gen.dart` base (the overlay-state flags), never this file once you add logic.
// @appbox-extension-point: presentation/{snake}_viewmodel
import '{snake}_viewmodel.gen.dart';

class {name}ViewModel extends {name}ViewModelBase {{
  {name}ViewModel();
  // TODO(builder): add screen actions / data here. Overlay flags are on the base.
}}
'''


def tpl_vm_home_base(name, snake, seed_rows=None):
    """The GENERATED home ViewModel base — stubs the members the bespoke home_view
    references (dataReady/filtered/refresh/firstName/initials/countFor/filter/
    segLabels/setFilter) with honest defaults so the app compiles + the operator fills
    the real logic in the extension VM. Mirrors the timer/overlay base pattern: the
    base is regenerated, the hand-editable {name}ViewModel extends it. Home is the
    bespoke path (hand-tuned layout) — its view emits VM binds the generic translator
    doesn't, so the members are stubbed, not derived.

    `seed_rows` (optional): the design's seed data, reconciled to Session constructor
    args (a list of Dart `Session(...)` literal strings). When present, `filtered`
    returns those rows as a list — the seed is REACHABLE on the first frame
    (P4 data-parity GREEN), so the home screen renders the design's workout cards
    instead of "No sessions yet." This is the closed-loop emitter fix: the design's
    OWN seed flows into the VM the same run that emits the view, with no hand-edit.
    The list is NON-const (Session.occurredOn is a DateTime, not const-constructible;
    DateTime.parse() is a method call, forbidden in a const expression) — but the
    values are still literals evaluated once at construction, so frame-1 availability
    is identical to a const list. Absent (a contract-less design or a screen with no
    seed) → `const []` (the honest empty default; P4 no-ops GREEN for a contract-less
    design)."""
    if not seed_rows:
        filtered_body = "const []"
        data_ready = "false"
    else:
        # non-const list literal (DateTime.parse isn't const-evaluable); the values
        # are still literals, so this is constructed once + frame-1 available.
        filtered_body = "<Session>[\n" + "".join(f"      {r},\n" for r in seed_rows) + "    ]"
        data_ready = "true"
    return f'''// AUTO-GENERATED by flutter_crew (generate_view.py) — the {name} home VM base.
// Regenerated every run; do not hand-edit. {name}ViewModel extends this and fills
// the real business logic (fetch sessions, filter by segment, derive initials).
// The stubs are honest defaults so the app compiles + shows empty state until wired.
import 'package:stacked/stacked.dart';

import '../domain/ports/session_repository.dart';

abstract class {name}ViewModelBase extends BaseViewModel {{
  // data-loading state. When the design declares seed rows, `filtered` returns them
  // (the seed is reachable on frame 1 — the design's workout cards render, not the
  // empty state). Override to drive from a repository fetch in a real backend build.
  bool get dataReady => {data_ready};
  List<Session> get filtered => {filtered_body};
  Future<void> refresh() async {{}}

  // profile — override to read from a profile repository.
  String get firstName => '';
  String get initials => '';

  // segmented filter — override with the design's categories + counts. segLabels is
  // emitted on the STUB (below), not here — the bespoke home_view references it at the
  // class level (HomeViewModel.segLabels), and Dart statics aren't inherited, so a
  // static on the base wouldn't reach HomeViewModel.segLabels.
  int get filter => 0;
  void setFilter(int i) {{}}
  int countFor(int seg) => 0;
}}
'''


# ── seed → Session reconciliation ─────────────────────────────────────────────
# The design's seed rows (data_model.json data_model.seed) use the DESIGN's field
# names (name/target/notes/last); the Session entity (session_repository.dart,
# generated from the SAME data_model) uses reconciled names (title/metric/note/
# occurredOn). This maps design rows → Session(...) Dart constructor literals so
# the home VM base can wire the seed deterministically (P4 data-parity GREEN) with
# no hand-edit. Pure + unit-tested; design-agnostic (driven by the field map, not
# atlet literals).
# design seedKey → Session ctor param. The design→entity reconciliation: the data
# model's seedFrom.map (entityField ← seedKey) is the SSOT; when absent (the legacy
# capture_data shape, no entities[]) we fall back to the canonical atlet mapping
# (name→title, target→metric, notes→note, last→occurredOn). Either path resolves a
# foreign design's seed to ITS entity's fields, not atlet's.
_SEED_DEFAULT_MAP = {
    "name": "title", "target": "metric", "notes": "note", "last": "occurredOn",
}
# the Session ctor's required positional order (matches session_repository.dart's
# `Session({required this.id, required this.title, ...})` — all named, so order is
# the ctor's declaration order, used only for the literal's readability).
_SESSION_FIELDS = ("id", "title", "type", "metric", "unit", "note", "streak", "occurredOn")


def _dart_str(s):
    """A Python str → a Dart single-quoted string literal with escapes."""
    return "'" + str(s).replace("\\", "\\\\").replace("'", "\\'") + "'"


def _seed_to_session_literals(seed_rows, field_map=None):
    """Design seed rows → a list of `Session(...)` Dart constructor-literal strings.

    `seed_rows`: the data_model's seed list (each row a dict of design field→value).
    `field_map`: design seedKey → Session ctor param (defaults to _SEED_DEFAULT_MAP;
    the caller passes the seedFrom.map-inverted contract when available — i.e. the
    inverse of `seedFrom.map` which is `{entityField: seedKey}`). Returns [] for an
    empty seed. Each row becomes a `Session(id: ..., title: ..., ...)` literal with:
    strings → quoted, ints → bare, the `occurredOn` source (a phrase like '2d ago')
    → a fixed-anchor ISO date (deterministic — matches blueprint._date_from_last).
    Rows missing a required field are skipped (honest: a partial row would not
    compile).

    Design-agnostic: the design's own seedKeys drive the reconciliation via
    `field_map`, never hardcoded atlet keys. For atlet (no seedFrom.map → the legacy
    capture_data shape) the caller passes no field_map and the _SEED_DEFAULT_MAP
    fallback applies (name→title, target→metric, notes→note, last→occurredOn). For
    a foreign design whose seed uses `title`/`value`/`description`, the inverted
    seedFrom.map resolves them to THIS design's entity fields, not atlet's."""
    if not seed_rows:
        return []
    # seedKey → entityField (CAMELCASE — matches _SESSION_FIELDS, the Dart ctor param
    # names). Start from the atlet canonical default, override with the caller's
    # seedFrom.map-inverted contract. The INVERSE map: seedFrom.map is
    # {entityField: seedKey}, so invert to {seedKey: entityField} for the row lookup.
    # The field_map from parity.seed_field_map carries SNAKE_CASE entity fields
    # (occurred_on — blueprint's data_model field naming); normalize them to camelCase
    # (occurredOn) so they match _SESSION_FIELDS + the emitted Session(...) ctor params.
    def _to_camel(s):
        p = [x for x in re.split(r"[^0-9a-zA-Z]+", s) if x]
        return p[0].lower() + "".join(x[:1].upper() + x[1:] for x in p[1:]) if p else s
    fmap = {k: _to_camel(v) for k, v in _SEED_DEFAULT_MAP.items()}
    if field_map:
        fmap.update({k: _to_camel(v) for k, v in field_map.items()})
    # entityField → seedKey (the reverse of fmap) so the loop can find the design
    # key that maps to each Session ctor param. For entity fields NOT in the map
    # (id, type, unit, streak), the design seedKey IS the entity field name
    # (identity) — atlet's seed uses `id`/`type`/`unit`/`streak` directly, and a
    # foreign design that doesn't remap them carries them under the same names.
    # The EXPLICIT field_map must win over the default: build rev from field_map
    # first, then fill gaps from _SEED_DEFAULT_MAP (setdefault reverses the
    # priority — the first-seen wins — so process explicit-before-default).
    rev = {}
    if field_map:
        for seed_key, ent_field in field_map.items():
            rev.setdefault(ent_field, seed_key)
    for seed_key, ent_field in _SEED_DEFAULT_MAP.items():
        rev.setdefault(ent_field, seed_key)
    from datetime import date, timedelta
    # FIXED anchor (NOT today) — determinism: the seed literal must not churn
    # run-to-run. Mirrors blueprint._date_from_last's anchor discipline.
    anchor = date(2025, 4, 18)
    out = []
    for row in seed_rows:
        if not isinstance(row, dict):
            continue
        # required fields: id + the title source (the design key mapping to 'title').
        id_key = rev.get("id", "id")
        title_key = rev.get("title", "name")
        if id_key not in row or title_key not in row:
            continue  # required id+title absent → skip (won't compile)
        # build the ctor-arg dict (Session param → Dart literal) from the design's
        # OWN keys via rev (entityField → seedKey), not hardcoded atlet keys. For an
        # unmapped field, the seedKey IS the entity field name (identity — atlet's
        # id/type/unit/streak are carried under the same names).
        def _val(ent_field, default=None):
            sk = rev.get(ent_field, ent_field)
            return row.get(sk, default)
        args = {"id": _dart_str(_val("id", "")),
                "title": _dart_str(_val("title", "")),
                "type": _dart_str(_val("type", "") or ""),
                "metric": str(int(_val("metric", 0) or 0)),
                "unit": _dart_str(_val("unit", "") or ""),
                "streak": str(int(_val("streak", 0) or 0))}
        note = _val("note")
        args["note"] = _dart_str(note) if note is not None else "null"
        # 'last' phrase → ISO date (deterministic). 'Yesterday'→-1, 'Nd ago'→-N,
        # 'Nw ago'→-7N, else the anchor. Mirrors blueprint._date_from_last.
        last = str(_val("occurredOn", "") or "").strip().lower()
        days = 0
        if last == "yesterday":
            days = 1
        else:
            mt = re.match(r"(\d+)\s*([dw])", last)
            if mt:
                days = int(mt.group(1)) * (7 if mt.group(2) == "w" else 1)
        occurred = (anchor - timedelta(days=days)).isoformat()
        args["occurredOn"] = "DateTime.parse('%s')" % occurred
        # emit in the Session ctor's declaration order (named args, so order is
        # readability only — Dart doesn't care, but a stable order aids diffing).
        body = ", ".join(f"{f}: {args[f]}" for f in _SESSION_FIELDS if f in args)
        out.append(f"Session({body})")
    return out


def tpl_vm_home_stub(name, snake):
    """The extension-point home VM extending the generated base. segLabels is a STATIC
    here (the bespoke home_view references it at the class level: HomeViewModel.segLabels)
    — Dart statics aren't inherited, so it lives on the subclass, not the base."""
    return f'''// FACTORY EXTENSION POINT — hand-edit freely; the factory regenerates ONLY the
// `.gen.dart` base (the stubbed home members), never this file once you add logic.
// @appbox-extension-point: presentation/{snake}_viewmodel
import '{snake}_viewmodel.gen.dart';

class {name}ViewModel extends {name}ViewModelBase {{
  {name}ViewModel();
  // The design's segment labels (a const — referenced at the class level by the view).
  // TODO(builder): replace with the design's category labels (CATEGORIES in data.jsx).
  static List<String> get segLabels => const [];
  // TODO(builder): wire the real logic — fetch sessions (filtered/refresh/dataReady),
  // read the profile (firstName/initials), drive the segment filter (filter/setFilter/
  // countFor). The base stubs return empty defaults until you do.
}}
'''


# ── home_assets.dart frontier stub (generic, symbol-derived) ──────────────────
# The generated home_view.dart imports home_assets.dart for the bespoke chart
# widgets + data constants the deterministic box translator can't reproduce (the
# CustomPainter / interaction frontier). This stub declares each REFERENCED symbol
# as a minimal placeholder so `dart analyze` passes out-of-the-box; the operator
# replaces the bodies with the design's real painters. GENERIC: the symbol set is
# derived from the emitted home_view.dart (whatever chart tags + shell composites
# it actually references), NOT a hardcoded atlet list — a foreign design's
# DonutChart/PulseRing/kDonutChartValues are declared just as atlet's StatBars/
# kStatBarsValues are. Force-written ONLY when home_assets.dart is absent (the
# @appbox-extension-point guard: a hand-authored one is sacrosanct once the operator
# adds real painters).
_HOME_ASSETS_SHELL_WIDGETS = ("RiseIn", "StatsCarousel", "DashedLine")
# Known framework/library types the home view calls but does NOT own — these are
# imported from material/stacked/ui.primitives, not home_assets.dart. A call-site
# for one of these is NOT a home_assets symbol. (Session is the domain entity.)
_HOME_ASSETS_EXCLUDE = frozenset({
    "HomeView", "HomeViewModel", "Widget", "StatelessWidget", "StatefulWidget",
    "Container", "Column", "Row", "Padding", "Center", "SizedBox", "Expanded",
    "Flexible", "Stack", "Positioned", "Text", "Icon", "GestureDetector",
    "AdaptiveScaffold", "AdaptiveRefresh", "AdaptiveCard", "AdaptiveButton",
    "AdaptiveSegmented", "AdaptiveChip", "AdaptiveIconButton", "AdaptiveButtonVariant",
    "AdaptiveTextField", "AdaptiveAuthButton",
    "AnnotatedRegion", "SystemUiOverlayStyle", "ListView", "BoxDecoration",
    "BorderRadius", "BorderAll", "Border", "EdgeInsets", "MainAxisAlignment",
    "CrossAxisAlignment", "MainAxisSize", "Alignment", "Offset", "TextStyle",
    "FontWeight", "Brightness", "Colors", "HitTestBehavior", "ScrollPhysics",
    "AlwaysScrollableScrollPhysics", "StackedView", "BaseViewModel", "Session",
    "Navigator", "Material", "InkWell", "Tooltip", "Hero", "DefaultTextStyle",
    "Color", "ColorSwatch", "MaterialAccentColor", "MaterialColor",  # Flutter color types —
    # a chart stub must NOT shadow these (a home_view `Color(0xFF...)` / `Color.fromRGBO`
    # call-site is Flutter's Color, not a home_assets symbol). Without this, the stub
    # declared `class Color extends StatelessWidget`, shadowing Flutter's Color → every
    # `Color.fromRGBO`/`Color(0xFF...)` call broke at G5.
})


def _extract_call_sites(home_view_src):
    """Find `Name(named: ..., named: ...)` call-sites in the emitted home_view and
    return {Name: {named_params: [...], has_positional: bool}} for each Name that is
    NOT a known framework type (_HOME_ASSETS_EXCLUDE) and NOT defined as a local
    class in the view. The named params are the keys the stub must declare so the
    call-site compiles. Generic — derives from the emitted source."""
    # local class defs in the view (HomeView's own helper classes, if any) → not home_assets
    local_classes = set(re.findall(r"class\s+([A-Z][A-Za-z0-9]*)\b", home_view_src))
    # match `Name(` then balanced args up to the matching `)`. Cheap approx: capture
    # `Name(` + the named-param keys `(\w+):` until the next `\n`-less `)` at depth 0.
    # The home view's calls are single-line or multi-line but each call's named args
    # are `<key>:` tokens. We capture the call name + the named keys inside it.
    sites: dict[str, dict] = {}
    # tokenize: find each PascalCase `Name(` occurrence, then scan forward for named
    # params until the matching close paren (depth-aware).
    for m in re.finditer(r"\b([A-Z][A-Za-z0-9]*)\s*\(", home_view_src):
        name = m.group(1)
        if name in _HOME_ASSETS_EXCLUDE or name in local_classes:
            continue
        # scan forward from the `(` for named params + matching `)`
        start = m.end()  # just after `(`
        depth, i, named, has_pos = 1, start, [], False
        n = len(home_view_src)
        while i < n and depth > 0:
            c = home_view_src[i]
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            elif depth == 1 and c not in " \t\n,":
                # a named param? `key:`
                km = re.match(r"([a-z][A-Za-z0-9]*)\s*:", home_view_src[i:])
                if km:
                    named.append(km.group(1))
                    i += km.end()
                    continue
                # a positional arg token (not a key:) → record presence
                has_pos = True
            i += 1
        entry = sites.setdefault(name, {"named_params": [], "has_positional": False})
        for p in named:
            if p not in entry["named_params"]:
                entry["named_params"].append(p)
        if has_pos:
            entry["has_positional"] = True
    return sites


def home_assets_symbols(home_view_src):
    """Scan an emitted home_view.dart for the symbols it references from
    home_assets.dart. Returns {classes: [{name, named_params, has_positional}],
    consts: [name...]} so tpl_home_assets_stub can declare each with a MATCHING
    constructor signature (the named params the call-site passes). Generic —
    derives from the emitted source, never a hardcoded list.

    Detects: (1) chart widget + shell-composite call-sites (Name(named:...)) that
    aren't framework types or local classes, (2) the `k<...>` data constants
    referenced. The shell composites (RiseIn/StatsCarousel/DashedLine) are included
    if called. k* constants that belong to motion.dart (kRiseMs/kRiseCurve/kRiseDy/
    kSplashFillMs/kSplashHoldMs) are excluded — they're imported from motion.dart."""
    sites = _extract_call_sites(home_view_src)
    classes = [{"name": n, **info} for n, info in sites.items()]
    # ensure the shell composites are present if referenced (they should already be
    # captured by _extract_call_sites, but guard in case the call shape differs)
    names = {c["name"] for c in classes}
    for w in _HOME_ASSETS_SHELL_WIDGETS:
        if re.search(rf"\b{w}\s*\(", home_view_src) and w not in names:
            classes.append({"name": w, "named_params": [], "has_positional": False})
    # k* constants referenced (excluding motion.dart's)
    consts, seen_k = [], set()
    for m in re.finditer(r"\b(k[A-Z][A-Za-z0-9]*)\b", home_view_src):
        n = m.group(1)
        if n not in seen_k and n not in ("kRiseMs", "kRiseCurve", "kRiseDy",
                                         "kSplashFillMs", "kSplashHoldMs"):
            seen_k.add(n)
            consts.append(n)
    return {"classes": classes, "consts": consts}


def tpl_home_assets_stub(symbols):
    """Emit a home_assets.dart stub declaring exactly the symbols the emitted
    home_view.dart references, each with a constructor MATCHING the call-site's
    named params (so `dart analyze` passes — the stub accepts what the view passes).
    Each class → a StatelessWidget with `this.<param>` fields (nullable, optional)
    + a build() returning SizedBox.shrink(); each const → an empty list. The
    operator replaces the bodies with the design's real CustomPainter widgets +
    data (derived from data.jsx). Generic: the symbol set + signatures are
    caller-derived (home_assets_symbols), so any design's chart vocabulary
    (StatBars(values,labels,max)/DonutChart(segments)/...) is declared with the
    right signature, not a hardcoded list."""
    cls_decls = []
    for c in symbols.get("classes", []):
        name = c["name"]
        params = c.get("named_params", []) or []
        # declare each named param as an optional nullable field + ctor param
        if params:
            fields = "\n".join(f"  final dynamic {p};" for p in params)
            ctor_params = ", ".join(f"this.{p}" for p in params)  # optional + nullable
            decl = (f"class {name} extends StatelessWidget {{\n"
                    f"  const {name}({{super.key, {ctor_params}}});\n"
                    f"{fields}\n"
                    f"  @override\n"
                    f"  Widget build(BuildContext context) => const SizedBox.shrink();  // TODO: real painter\n"
                    f"}}\n")
        else:
            decl = (f"class {name} extends StatelessWidget {{\n"
                    f"  const {name}({{super.key}});\n"
                    f"  @override\n"
                    f"  Widget build(BuildContext context) => const SizedBox.shrink();  // TODO: real painter\n"
                    f"}}\n")
        cls_decls.append(decl)
    const_decls = []
    for k in symbols.get("consts", []):
        const_decls.append(f"const List<dynamic> {k} = [];  // TODO: wire real data (data.jsx)\n")
    body = "".join(cls_decls + const_decls)
    return (
        "// FACTORY EXTENSION POINT — hand-edit freely; the factory will NOT overwrite this\n"
        "// file once you add real chart painters. @appbox-extension-point: presentation/home_assets\n"
        "//\n"
        "// The bespoke home chart widgets + data constants the generated home_view.dart imports.\n"
        "// These are the generation FRONTIER (no CSS→CustomPainter codegen): the operator authors\n"
        "// the real painters parameterized by the k* data constants (derived from data.jsx). This\n"
        "// STUB declares each referenced symbol with a constructor MATCHING the call-site's named\n"
        "// params so `dart analyze` passes out-of-the-box; replace each body with the design's real\n"
        "// widget. GENERIC: the symbol set + signatures are derived from what the emitted home_view\n"
        "// actually references, so any design's chart vocabulary (StatBars/DonutChart/...) is\n"
        "// declared here with the right signature, not a hardcoded list.\n"
        "import 'package:flutter/material.dart';\n"
        "\n" + body
    )


def tpl_vm_splash_base(name, snake, next_pascal, smoke_autologin=True, home_route="homeShellView"):
    """The GENERATED splash ViewModel base (regenerated every run). Holds the
    designed splash for kSplashHoldMs (CAPTURED from the design's SplashView JS,
    emitted to motion.dart by the manager), then REPLACE-routes to the next
    authStage screen so back doesn't return to the splash. The next screen is
    DERIVED from breakdown.json::screenFlow (design-agnostic: any conformant
    design's auth-gated splash advances to its declared next screen) and passed
    in as `next_pascal` (e.g. "Signin" → replaceWithSigninView). The hand-editable
    {name}ViewModel extends this (tpl_vm_splash_stub).

    This fixes the stuck-at-100% bug: the prior frozen @appbox-extension-point stub
    had no runStartupLogic, so _startup_method returned None, so build_view
    emitted no onViewModelReady, so the transition never fired — same class of
    bug that hit welcome/home (fixed by generating their VMs from the SSOT).

    busy/error wrap is mandatory on async (ADR-0003). The SMOKE_AUTOLOGIN hook
    (compile-time treeshaken) signs the seeded user in and goes straight to Home
    — lets the smoke render real seeded data headlessly; tree-shaken out of
    normal builds. Gated on SupabaseAuthService being present (smoke_autologin)."""
    autologin = f'''
  static const _autoLoginEmail = String.fromEnvironment('SMOKE_AUTOLOGIN');
  static const _autoLoginPassword = String.fromEnvironment('SMOKE_PASSWORD');
''' if smoke_autologin else ""

    autologin_import = (
    "import '../infrastructure/supabase_auth_service.dart';\n" if smoke_autologin else "")

    autologin_branch = f"""
      if (_autoLoginEmail.isNotEmpty && _autoLoginPassword.isNotEmpty) {{
        await locator<SupabaseAuthService>().signInWithPassword(
            email: _autoLoginEmail, password: _autoLoginPassword);
        await _navigationService.clearStackAndShow(Routes.{home_route});
        return;
      }}""" if smoke_autologin else ""

    return f'''// AUTO-GENERATED by flutter_crew (generate_view.py) — the {name} startup VM.
// Regenerated every run from the design SSOT (screenFlow + captured splash
// timing); do NOT hand-edit. {name}ViewModel extends this and IS the hand-editable
// extension point.
import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import '../app/app.locator.dart';
import '../app/app.router.dart';
import 'motion.dart';  // kSplashHoldMs — splash hold CAPTURED from the design (not a stub)
{autologin_import}
/// Built by `flutter_crew` from breakdown `screenFlow` (authStage: splash →
/// {next_pascal}). On ready, hold the designed splash then REPLACE (not push)
/// so back doesn't return to the splash. busy/error wrap is mandatory on async
/// (ADR-0003).
///
/// Smoke hook: when SMOKE_AUTOLOGIN (a --dart-define) is set, sign the seeded
/// user in and go straight to home — lets the smoke render real seeded data
/// headlessly. Compile-time const → tree-shaken out of normal builds.
abstract class {name}ViewModelBase extends BaseViewModel {{
  final _navigationService = locator<NavigationService>();{autologin}

  Future<void> runStartupLogic() async {{
    setError(null);
    setBusy(true);
    try {{
      await Future<void>.delayed(const Duration(milliseconds: kSplashHoldMs));{autologin_branch}
      await _navigationService.replaceWith{next_pascal}View();
    }} catch (e) {{
      setError(e);
      await _navigationService.replaceWith{next_pascal}View();
    }} finally {{
      setBusy(false);
    }}
  }}
}}
'''


def tpl_vm_splash_stub(name, snake):
    """The extension-point splash VM extending the generated base. The base
    carries the full startup→navigate logic (derived from screenFlow), so the
    stub is a thin extension seam — the operator adds splash-specific logic
    here. Force-overwritten like home/auth (the base carries all real logic;
    not a hand-edit point until the operator adds to it). Self-heals a poisoned
    stub from a prior buggy run."""
    return f'''// FACTORY EXTENSION POINT — hand-edit freely; the factory regenerates ONLY the
// `.gen.dart` base (the splash startup state machine), never this file once you
// add logic. @appbox-extension-point: presentation/{snake}_viewmodel
import '{snake}_viewmodel.gen.dart';

class {name}ViewModel extends {name}ViewModelBase {{
  // The base's runStartupLogic() holds the designed splash then routes to the
  // next authStage screen (splash→signin). Override it here to customise.
  // TODO(builder): override runStartupLogic() or add splash-specific actions.
}}
'''



# Closed, FINITE mapping: a design's declarative field type (HTML input[type] /
# inputMode — captured verbatim into node.props) → the Dart validity contract the auth
# VM emits. This is the design-agnostic seam: the generator NEVER hardcodes atlet's email
# regex. A design with type="email" gets the email gate; type="tel" → a phone gate;
# type="password" → a length gate. Each entry yields {controller name, keyboardType,
# validity RegExp, error string}. Unknown/missing type → "text" (no gate — submit always
# enabled), so a field-less or free-text design degrades safely. Derived from the spec,
# never a literal. (The validity gate the design's disabled={!valid} expresses is a
# RUNTIME check; this mapping turns the design's DECLARED type into the equivalent VM
# predicate — not arbitrary-JSX-parsing, which would violate the stub rule.)
_AUTH_FIELD_TYPES = {
    "email":    {"ctl": "emailController",    "kt": "TextInputType.emailAddress",
                 "re": r"^[^\s@]+@[^\s@]+\.[^\s@]+$", "err": "Enter a valid email"},
    "tel":      {"ctl": "phoneController",    "kt": "TextInputType.phone",
                 "re": r"^\+?[\d\s\-()]{7,}$", "err": "Enter a valid phone number"},
    "password": {"ctl": "passwordController", "kt": "TextInputType.visiblePassword",
                 "re": r"^.{8,}$", "err": "At least 8 characters"},
    "text":     {"ctl": "inputController",    "kt": "TextInputType.text",
                 "re": None, "err": None},  # no gate — free text
}

# The keyboardType for a NON-form text field (a generic input the design typed, not an
# auth submit) — derived from the captured input[type] so the native keyboard matches the
# declared field (an email-shaped search box gets the email keyboard). A subset of
# _AUTH_FIELD_TYPES' `kt`; kept separate because generic inputs carry no validity gate.
_TEXT_FIELD_KT = {t: _AUTH_FIELD_TYPES[t]["kt"] for t in _AUTH_FIELD_TYPES}


def _auth_field(spec):
    """The auth screen's submit-field type, DERIVED from the spec (the captured
    input[type] of the form's first text field) — never a hardcoded literal. Returns the
    _AUTH_FIELD_TYPES key (defaults to "text" when no typed field / unknown type)."""
    for n in _walk(spec.get("tree") or []):
        if str(n.get("prim")) != "AdaptiveTextField":
            continue
        t = (n.get("props") or {}).get("type") or ""
        return t if t in _AUTH_FIELD_TYPES else "text"
    return "text"


def _spec_providers(spec):
    """The auth providers the design declares as sign-in BUTTONS (class google/apple),
    DERIVED from the spec's button nodes — never a literal. Unions with the handler-derived
    set so the view (which emits AdaptiveAuthButton for class google/apple), the VM dispatch,
    AND the service method + plugin dep all agree on the provider set. A design with an
    Apple button but a handler that missed go('apple') still gets appleOAuth this way."""
    found = set()
    for n in _walk(spec.get("tree") or []):
        if str(n.get("prim")) not in ("AdaptiveButton", "AdaptiveAuthButton"):
            continue
        cls = " ".join(n.get("class") or [])
        m = _PROVIDER_RE.search(cls)
        if m:
            found.add(m.group(1))
    return found


def tpl_vm_auth(name, snake, oauth=(), field_type="email", home_route="homeShellView"):
    """The GENERATED auth ViewModel (ADR-0013): a single CONCRETE VM, no extension seam.
    Auth logic comes from the design SSOT (email-OTP + provider sign-in), so it is
    regenerated every run and is NOT a hand-edit point — the frozen @appbox-extension-point
    hatch is removed for auth screens (user directive: zero hand-authored target code).
    The submit field's controller + validity gate are DERIVED from `field_type` (the
    design's captured input[type]) via _AUTH_FIELD_TYPES — no atlet literals, any design.
    sendCode() runs the email-OTP path; go() dispatches native provider sign-in
    (Google/Apple) for whichever providers the design's go('<provider>') buttons declared
    — `oauth` is that token tuple. The matching SupabaseAuthService.signInWith<Provider>()
    methods are emitted by the same handler scan (blueprint._derive_auth_methods), so the
    two stages agree. Client IDs arrive out-of-band via --dart-define; unconfigured → the
    service throws a clear message that surfaces here (never a crash). No buttons (oauth
    empty) → go() is a no-op notice."""
    ft = _AUTH_FIELD_TYPES.get(field_type, _AUTH_FIELD_TYPES["text"])
    ctl, gate_re, gate_err = ft["ctl"], ft["re"], ft["err"]
    # A typed field with a validity gate → lift validity to a VM observable + an onChanged
    # hook (named for the field) so the submit CTA binds enabled: formValid. A free-text
    # field (no gate) skips the gate — the submit stays always-enabled (the design has no
    # disabled={!valid} to honour). The controller name is type-derived, not hardcoded.
    if gate_re:
        gate_block = (
            f"  static final RegExp _fieldRe = RegExp(r'{gate_re}');\n"
            f"  bool formValid = false;\n"
            f"  /// Live validity — the design's submit CTA is disabled until this field\n"
            f"  /// passes (its disabled={{!valid}} gate). Lifted to a VM observable so the\n"
            f"  /// generated AdaptiveButton binds enabled: formValid. Derived from the\n"
            f"  /// field's DECLARED type ({field_type!r}), never a hardcoded literal.\n"
            f"  void onFieldChanged(String v) {{\n"
            f"    final next = _fieldRe.hasMatch(v.trim());\n"
            f"    if (next != formValid) {{\n"
            f"      formValid = next;\n"
            f"      notifyListeners();\n"
            f"    }}\n"
            f"  }}\n\n")
        send_guard = (
            f"    if (!_fieldRe.hasMatch(email)) {{\n"
            f"      setError({dart_str(gate_err)});\n"
            f"      return;\n"
            f"    }}\n")
    else:
        gate_block = ""
        send_guard = ""
    if oauth:
        cases = "".join(
            f"        case '{p}':\n"
            f"          await _auth.signInWith{p[:1].upper()}{p[1:]}();\n"
            f"          break;\n"
            for p in oauth)
        # OAuth client IDs arrive via --dart-define. UNCONFIGURED (the factory default —
        # the design preview has no live OAuth) → the service would throw on the very first
        # line; instead of a silent swallow, run the design's MOCK intent: traverse to Home
        # so the social button is demonstrably live in preview. CONFIGURED → real native
        # OAuth runs; any real failure surfaces via FeedbackService (observable, not masked).
        # The same String.fromEnvironment contract the service checks — no env detection
        # leaking into prod (a prod build with real defines takes the real path).
        # NOTE: use `!= ''` not `.isNotEmpty` — String.isNotEmpty is a getter, not
        # const-evaluable, so `const ... .isNotEmpty` is a compile error (const_eval).
        oauth_configured = " || ".join(
            f"const String.fromEnvironment('{d}') != ''" for d in
            ("GOOGLE_SERVER_CLIENT_ID", "APPLE_SERVICE_ID"))
        go_body = (
            "    setError(null);\n"
            "    setBusy(true);\n"
            "    try {\n"
            f"      const _oauthConfigured = {oauth_configured};\n"
            "      if (!_oauthConfigured) {\n"
            "        // Preview mode (no OAuth defines) → run the design's mock intent:\n"
            "        // the social button advances to Home. Visible, not silent.\n"
            f"        await _nav.clearStackAndShow(Routes.{home_route});\n"
            "        return;\n"
            "      }\n"
            "      switch (provider) {\n"
            f"{cases}"
            "        default:\n"
            "          setError('$provider sign-in is not configured.');\n"
            "          return;\n"
            "      }\n"
            f"      await _nav.clearStackAndShow(Routes.{home_route});\n"
            "    } catch (e) {\n"
            "      setError(e);\n"
            "      locator<FeedbackService>().error('Sign-in failed: $e');\n"
            "    } finally {\n"
            "      setBusy(false);\n"
            "    }")
        go_doc = ("  /// Native provider sign-in (" + "/".join(oauth) + "): obtains an "
                  "idToken via\n  /// the platform plugin and exchanges it with Supabase, "
                  "then clears the stack to\n  /// Home. UNCONFIGURED OAuth defines "
                  "(preview) → advances to Home (the design's mock\n  /// intent); "
                  "CONFIGURED → real OAuth, failures surface via FeedbackService "
                  "(see operator-auth-setup.md).")
    else:
        go_body = "    setError('$provider sign-in needs OAuth setup (no provider buttons in the design).');"
        go_doc = ("  /// Provider sign-in placeholder — the design declared no go('<provider>') "
                  "buttons.\n  /// ponytail: no-op notice; a design with Google/Apple buttons "
                  "wires the real path.")
    return f'''// AUTO-GENERATED by flutter_crew (generate_view.py) — the {name} auth ViewModel.
// Regenerated every run from the design SSOT; do NOT hand-edit (auth logic is generated,
// not hand-authored — ADR-0013; no extension seam for auth screens).
import 'package:flutter/widgets.dart';

import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import '../app/app.locator.dart';
import '../app/app.router.dart';
import '../infrastructure/supabase_auth_service.dart';
import '../ui/feedback_service.dart';

class {name}ViewModel extends BaseViewModel {{
  final SupabaseAuthService _auth = locator<SupabaseAuthService>();
  final NavigationService _nav = locator<NavigationService>();

  final TextEditingController {ctl} = TextEditingController();

{gate_block}  /// The design's "Send code" CTA: emails a one-time code, then advances to the
  /// OTP screen (no deep link — the code is entered in-app).
  Future<void> sendCode() async {{
    final email = {ctl}.text.trim();
{send_guard}    setError(null);
    setBusy(true);
    try {{
      await _auth.sendEmailOtp(email: email);
      await _nav.navigateToOtpView(email: email);
    }} catch (e) {{
      setError(e);
    }} finally {{
      setBusy(false);
    }}
  }}

{go_doc}
  Future<void> go(String provider) async {{
{go_body}
  }}

  @override
  void dispose() {{
    {ctl}.dispose();
    super.dispose();
  }}
}}
'''


def tpl_vm_welcome(name, snake, home_route="homeShellView"):
    """The GENERATED welcome-interstitial VM: a brief greeting pulse, then routes to
    Home. CAPTURED from the design (auth.jsx WelcomeView: `setTimeout(onDone, 1400)`),
    not a guess. Replaces the frozen @appbox-extension-point stub (user directive: zero
    hand-authored target code; the interstitial must actually advance to Home).
    ponytail: hold value inlined from the design; per-design welcome-timing capture
    (like splash's kSplashHoldMs) is a noted follow-up."""
    return f'''// AUTO-GENERATED by flutter_crew (generate_view.py) — the {name} interstitial VM.
// Regenerated every run from the design SSOT; do NOT hand-edit.
import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import '../app/app.locator.dart';
import '../app/app.router.dart';
import '../domain/ports/profile_repository.dart';

class {name}ViewModel extends BaseViewModel {{
  final _profiles = locator<ProfileRepository>();

  {name}ViewModel() {{
    _loadName();
    // Design pulse: hold the greeting, then advance to Home
    // (auth.jsx WelcomeView: setTimeout(onDone, 1400)).
    Timer(const Duration(milliseconds: 1400), _toHome);
  }}

  /// Signed-in athlete's display name → the design's "Welcome, {{name}}." bind
  /// (auth.jsx WelcomeView `name` prop). Same profile Port Home's greeting reads;
  /// falls back to "Athlete" before the (cached, fast) profile resolves.
  String? _athleteName;

  String get firstName {{
    final n = _athleteName?.trim() ?? '';
    return n.isEmpty ? 'Athlete' : n.split(RegExp(r'\\s+')).first;
  }}

  Future<void> _loadName() async {{
    try {{
      final ps = await _profiles.all();
      if (ps.isNotEmpty) {{
        _athleteName = ps.first.displayName;
        notifyListeners();
      }}
    }} catch (_) {{/* greeting keeps its fallback */}}
  }}

  void _toHome() => locator<NavigationService>().clearStackAndShow(Routes.{home_route});
}}
'''


def tpl_vm_otp(name, snake):
    """The GENERATED OTP-verify ViewModel (ADR-0013): holds the email the code was
    sent to (route arg from sign-in) and verifies a 6-digit code via the design's
    email-OTP path (verifyEmailOtp → verifyOTP type:email). On success it advances to
    the Welcome interstitial (design flow: otp → welcome → home); a bad code surfaces an
    inline error."""
    return f'''// AUTO-GENERATED by flutter_crew (generate_view.py) — the {name} OTP-verify
// ViewModel. Regenerated every run from the design SSOT; do NOT hand-edit.
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import '../app/app.locator.dart';
import '../app/app.router.dart';
import '../infrastructure/supabase_auth_service.dart';

class {name}ViewModel extends BaseViewModel {{
  {name}ViewModel(this.email);

  /// The address the one-time code was sent to (passed from the sign-in screen).
  final String email;

  final SupabaseAuthService _auth = locator<SupabaseAuthService>();
  final NavigationService _nav = locator<NavigationService>();

  /// Set when verifyOtp rejects the code → the boxes turn accent + the inline
  /// "that code didn't match" message shows. Cleared on the next attempt.
  bool codeError = false;

  /// Auto-called by the 6-box input once all digits are filled (design UX).
  Future<void> verify(String code) async {{
    codeError = false;
    setError(null);
    setBusy(true);
    try {{
      await _auth.verifyEmailOtp(email: email, token: code);
      await _nav.clearStackAndShow(Routes.welcomeView);
    }} catch (e) {{
      codeError = true;
      setBusy(false);
      notifyListeners();
      return;
    }}
    setBusy(false);
  }}

  /// Re-request a code (design's "Resend" affordance).
  Future<void> resend() async {{
    setError(null);
    try {{
      await _auth.sendEmailOtp(email: email);
    }} catch (e) {{
      setError(e);
    }}
  }}
}}
'''


def tpl_view_otp(name, snake):
    """The GENERATED OTP-verify view: a TARGETED auth-flow template (like the splash's
    SplashProgress) because the generic spec translator collapses the design's six
    code boxes into one static container with no input. This renders a real 6-box
    auto-advancing code field wired to {name}ViewModel.verify, shows the email the
    code went to, and the inline error. Styled from AppTokens to match the design."""
    return f'''// AUTO-GENERATED by flutter_crew (generate_view.py) — the {name} OTP-verify
// view. Targeted auth-flow template (functional 6-box code input the generic
// translator can't produce). Regenerated every run; do NOT hand-edit.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import '../app_tokens.dart';
import '../app/app.locator.dart';
import '../ui/primitives.dart';
import '{snake}_viewmodel.dart';

class {name}View extends StackedView<{name}ViewModel> {{
  const {name}View({{super.key, this.email = ''}});

  final String email;

  @override
  Widget builder(BuildContext context, {name}ViewModel viewModel, Widget? child) {{
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: AdaptiveScaffold(
        backgroundColor: AppTokens.paper,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 12, 26, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    color: AppTokens.ink,
                    onPressed: () => locator<NavigationService>().back(),
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset('assets/svg/svg_ee30f39c9f.svg',
                          width: 64, height: 64),
                      const SizedBox(height: 22),
                      Text('VERIFY EMAIL',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
                              color: AppTokens.accent)),
                      const SizedBox(height: 8),
                      Text('Enter your code.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 30, color: AppTokens.ink)),
                      const SizedBox(height: 10),
                      Text.rich(
                        TextSpan(
                          style: TextStyle(fontSize: 14, color: AppTokens.ink3),
                          children: [
                            const TextSpan(text: 'We sent a 6-digit code to '),
                            TextSpan(
                                text: email.isEmpty ? 'your email' : email,
                                style: TextStyle(
                                    color: AppTokens.ink,
                                    fontWeight: FontWeight.w600)),
                            const TextSpan(text: '.'),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      _OtpBoxes(
                          hasError: viewModel.codeError,
                          enabled: !viewModel.isBusy,
                          onCompleted: viewModel.verify),
                      const SizedBox(height: 14),
                      if (viewModel.codeError)
                        Text("That code didn't match. Try again.",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: AppTokens.accent))
                      else if (viewModel.isBusy)
                        const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: AdaptiveProgress()),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: viewModel.isBusy ? null : viewModel.resend,
                        child: Text('Resend code',
                            style: TextStyle(fontSize: 13, color: AppTokens.ink3)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }}

  @override
  {name}ViewModel viewModelBuilder(BuildContext context) =>
      {name}ViewModel(email);
}}

/// Functional 6-box one-time-code field: each box holds one digit, auto-advances on
/// entry, steps back on delete, and fires [onCompleted] once all six are filled (the
/// design's auto-verify UX). The generic spec translator can't produce this.
class _OtpBoxes extends StatefulWidget {{
  const _OtpBoxes({{
    required this.onCompleted,
    required this.hasError,
    required this.enabled,
  }});

  final ValueChanged<String> onCompleted;
  final bool hasError;
  final bool enabled;

  @override
  State<_OtpBoxes> createState() => _OtpBoxesState();
}}

class _OtpBoxesState extends State<_OtpBoxes> {{
  late final List<TextEditingController> _c =
      List.generate(6, (_) => TextEditingController());
  late final List<FocusNode> _f = List.generate(6, (_) => FocusNode());

  @override
  void dispose() {{
    for (final c in _c) {{
      c.dispose();
    }}
    for (final n in _f) {{
      n.dispose();
    }}
    super.dispose();
  }}

  void _onChanged(int i, String v) {{
    if (v.isNotEmpty && i < 5) {{
      _f[i + 1].requestFocus();
    }} else if (v.isEmpty && i > 0) {{
      _f[i - 1].requestFocus();
    }}
    final code = _c.map((c) => c.text).join();
    if (code.length == 6) {{
      FocusScope.of(context).unfocus();
      widget.onCompleted(code);
    }}
  }}

  @override
  Widget build(BuildContext context) {{
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 6; i++)
          SizedBox(
            width: 46,
            height: 56,
            child: TextField(
              controller: _c[i],
              focusNode: _f[i],
              enabled: widget.enabled,
              autofocus: i == 0,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 1,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w600, color: AppTokens.ink),
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: AppTokens.paper,
                contentPadding: EdgeInsets.zero,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: widget.hasError ? AppTokens.accent : AppTokens.rule,
                      width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTokens.ink, width: 1.5),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTokens.rule, width: 1.5),
                ),
              ),
              onChanged: (v) => _onChanged(i, v),
            ),
          ),
      ],
    );
  }}
}}
'''


def stub_is_default(text):
    """A VM stub with no hand-written behavior → safe to upgrade to `extends …Base`.
    Heuristic: carries the extension-point marker and declares no methods/fields."""
    if "@appbox-extension-point" not in text:
        return False
    body = re.search(r"class\s+\w+ViewModel\b.*?\{(.*)\}", text, re.S)
    inner = (body.group(1) if body else "").strip()
    inner = re.sub(r"//[^\n]*|/\*.*?\*/", "", inner, flags=re.S).strip()
    return inner == ""  # only comments/TODOs inside the class body


def _flex_grows(style):
    """A CSS flex child that grows (`flex:1`, `flex-grow:1`) → Flutter Expanded,
    so centered/space-between layouts fill the screen like the design."""
    f = style.get("flex") or style.get("flex-grow") or ""
    first = str(f).strip().split()[0] if f else ""
    return first not in ("", "0", "none", "initial")


def _scrolls(style):
    """A CSS `overflow[-y]: auto|scroll` container → wrap in SingleChildScrollView so it
    scrolls INSIDE its bounded (Expanded) slot instead of overflowing (the account settings
    list: flex:1 + overflow-y:auto). SingleChildScrollView is platform-view safe (no
    intrinsic measurement, unlike IntrinsicHeight/SliverFillRemaining)."""
    return (style.get("overflow-y") or style.get("overflow") or "") in ("auto", "scroll")


def _model_bound(spec):
    """A generic screen that binds per-record fields (the design's `w.*` model var,
    e.g. Detail's `<Detail w={active}/>`) takes the tapped record as a Stacked
    route-arg (`final Session workout`); its binds resolve against it (`final s =
    workout;`) via the BIND reconciliation map. Detected from the captured binds."""
    return any(re.search(r"\bw\.", b)
               for n in _walk(spec.get("tree", []))
               for b in n.get("bind", []))


def _overlay_wrap(icons_light):
    """(open, close) for an AnnotatedRegion<SystemUiOverlayStyle> wrapping a screen's
    scaffold. icons_light=True (dark surface) → light status-bar icons; False (light
    surface) → dark icons. statusBarBrightness is the iOS knob and is INVERTED
    (Brightness.dark ⇒ light icons); statusBarIconBrightness is Android."""
    return (("AnnotatedRegion<SystemUiOverlayStyle>(value: const SystemUiOverlayStyle("
             "statusBarColor: Colors.transparent, "
             f"statusBarIconBrightness: Brightness.{'light' if icons_light else 'dark'}, "
             f"statusBarBrightness: Brightness.{'dark' if icons_light else 'light'}), child: "),
            ")")


# OPTION-C overlay classification (consultant ADR). A sibling top-level root is a
# STACKED overlay (a bottom-sheet/scrim/modal layered on top of the main screen),
# NOT a screen-state branch. Design-agnostic class-token match — the design's own
# naming convention for sheets/scrim/modal/backdrop. Never matches the main screen
# (filtered by the caller). A `*-scrim`/backdrop is a full-bleed dim layer; a
# `*-sheet`/`*-modal` is a bottom- or center-anchored panel.
_OVERLAY_CLASS_RE = re.compile(
    r"(^|[-_ ])(sheet|scrim|modal|backdrop|overlay|popover)([-_ ]|$)|^(fb-|create-|edit-|plan-|product-|cart-|checkout-)")


def _is_overlay_root(node):
    """True iff this sibling root is a stacked sheet/scrim/modal (NOT the main screen)."""
    if not node.get("children"):
        return False
    return any(_OVERLAY_CLASS_RE.search(c) for c in node.get("class", []))


def _overlay_gate(node):
    """The VM boolean expression that shows this overlay. Infers from the design's
    semantics: a `*-scrim`/backdrop + its paired `*-sheet` share ONE gate. The
    feedback sheet (post-completion) gates on `viewModel.done` (the derived getter
    on the timer VM base); a create/edit sheet gates on a per-screen `viewModel.
    <name>Open` flag. Returns a Dart bool expression."""
    cls = " ".join(node.get("class", []))
    if "fb-" in cls:           # the post-workout feedback sheet — gated by completion
        return "viewModel.done"
    # a generic create/edit/plan sheet — gated by a per-screen open flag. The flag
    # name derives from the sheet class (create-sheet → viewModel.createOpen). The
    # VM exposes these as bool fields; default `false` keeps it hidden initially.
    m = re.search(r"(create|edit|plan|product|cart|checkout)[-_]?sheet", cls)
    if m:
        return f"viewModel.{m.group(1)}Open"
    return "false"  # unknown overlay: hidden (never auto-shown); wire when its VM lands


def _collect_overlays(siblings, screen_id):
    """Emit each stacked overlay sibling as a gated Stack layer. A scrim → a full-
    bleed dim Container behind the sheet; a sheet → a Positioned bottom-aligned panel.
    Both wrapped in Visibility(gate) so they appear only when the VM flag is set —
    present at parity with the design instead of pruned to "". Empty list for screens
    with no overlays (the common case → no Stack, no overhead)."""
    out = []
    for n in siblings:
        if not _is_overlay_root(n):
            continue
        gate = _overlay_gate(n)
        cls = " ".join(n.get("class", []))
        inner = emit(n, sess=False)
        if not inner.strip():
            continue
        is_scrim = "scrim" in cls or "backdrop" in cls
        if is_scrim:
            layer = (f"Positioned.fill(child: IgnorePointer(child: Container("
                     f"color: Colors.black54)))")
        else:
            # bottom sheet: align to the bottom, full width, the design's panel. The
            # wrap opens 3 (Positioned → SafeArea → Material) around the emitted inner
            # tree, so it must close 3 — a missing ')' was unbalancing deep-sheet views.
            layer = (f"Positioned(left: 0, right: 0, bottom: 0, child: SafeArea("
                     f"top: false, child: Material(color: Colors.transparent, child: {inner})))")
        out.append(f"Visibility(visible: {gate}, child: {layer})")
    return out


def _generic_body(spec, sess=False):
    """Walk the design's own composition into the screen body. A screen component
    may render multiple state-branches as sibling top-level containers (SignInView:
    form state + verify-code state) plus overlays (spinner) — render the FIRST real
    screen container only (kills duplicate-state bleed). The body fills the viewport
    AND scrolls when tall (LayoutBuilder + minHeight + IntrinsicHeight), with
    flex-grow children Expanded so the design's vertical centering / footer-at-bottom
    is preserved; cross-axis stretch so children fill width and their own alignment
    (centered containers) takes effect."""
    roots = spec["tree"]
    screens = [r for r in roots if r.get("children") and not any(
        k in c for c in r["class"] for k in ("spinner", "overlay"))]
    root = screens[0] if screens else (roots[0] if roots else None)
    if root is None:
        return "const SizedBox.shrink()", "", []
    # OPTION-C overlays (consultant ADR): a sibling top-level root that is a
    # bottom-sheet/scrim/modal (the detail FeedbackSheet: `.fb-scrim` + `.fb-sheet`,
    # gated by `done`) is NOT a screen-state branch — it is STACKED UI layered on top
    # of the main screen. The initial-state pruning policy (emit() drops provably-
    # hidden branches) is correct for in-screen state, but a sheet/modal is a separate
    # overlay the design shows LATER (post-completion, on tap). Collect these roots and
    # emit each as a `Visibility`-gated Stack layer driven by a VM flag, so the content
    # exists at parity with the design instead of being pruned to "". A root qualifies
    # iff its class names a sheet/scrim/modal/backdrop (design-agnostic token match),
    # OR it sits at position:fixed/absolute (a scrim backdrop). Never the main screen.
    overlays = _collect_overlays([r for r in roots if r is not root], screen_id="")
    # The screen root's OWN background + text colour. `_generic_body` strips the
    # root container (emits its children), so a full-bleed dark screen (e.g. the
    # timer/detail view, bg #1A1714 + light text) would otherwise render its
    # light-on-dark content invisibly on the default paper scaffold. Lift the bg
    # onto the scaffold and cascade `color` to descendants via DefaultTextStyle
    # (reproducing CSS colour inheritance Flutter doesn't do implicitly).
    rs = root.get("style", {})
    root_bg = color_dart(rs.get("background") or rs.get("background-color"))
    root_color = color_dart(rs.get("color"))
    scaffold_bg = f"backgroundColor: {root_bg}, " if root_bg else ""
    # Status-bar overlay: a dark screen needs LIGHT status-bar icons. The global default
    # (main(), blueprint.py) is tuned for the light home surface, so a dark screen like the
    # detail/timer view would render the clock/battery dark-on-dark — invisible. Detect
    # darkness from the root bg hex; _generic_view wraps the scaffold in an
    # AnnotatedRegion<SystemUiOverlayStyle> the framework reads per-route.
    global _OVERLAY
    _raw_bg = rs.get("background") or rs.get("background-color") or ""
    _m = re.search(r"#[0-9A-Fa-f]{6}", _raw_bg)
    # Always classify (never "") — EVERY screen must declare a style so navigating back
    # restores it (Flutter #54029/#24893: a route with no AnnotatedRegion keeps the prior
    # route's style → light Home kept dark Detail's light icons → invisible clock).
    _OVERLAY = "dark" if (_m and _contrast_fg(_m.group(0)) == "Colors.white") else "light"

    def _finish(body):
        if root_color:
            body = (f"DefaultTextStyle.merge(style: TextStyle(color: {root_color}), "
                    f"child: {body})")
        return body, scaffold_bg, overlays

    src = root["children"] if root.get("children") else [root]
    kids, has_expanded = [], False
    for c in src:
        e = emit(c, sess)
        if not e:
            continue
        e = _motion_wrap(c, _box_wrap(c, e))
        if _flex_grows(c["style"]):
            if _scrolls(c["style"]):
                cma = main_axis(c["style"])
                if cma != "start":
                    # CENTERED-SCROLL: the design's scrollable body is also vertically
                    # centered (e.g. signin .auth-body: flex:1; overflow-y:auto;
                    # justify-content:center). A plain SingleChildScrollView + inner
                    # Column(mainAxisSize:min) leaves center INERT (the column shrink-
                    # wraps to content height → nothing to center against → content
                    # hugs the top, not the design's mid-screen placement). The fix is
                    # the standard Flutter "center, but scroll on overflow" idiom:
                    # LayoutBuilder gives the viewport height → ConstrainedBox(minHeight)
                    # forces the wrapper Column to at least viewport-tall → mainAxisSize.max
                    # + mainAxisAlignment.center centers `e` within that height; scroll
                    # engages only when content exceeds the viewport. NO IntrinsicHeight
                    # (would query native-leaf intrinsics → blank-screen crash, per the
                    # guard above) — ConstrainedBox + mainAxisSize.max never queries
                    # intrinsics, so LiquidGlassButton/UiKitView leaves stay safe.
                    #
                    # NOTE: do NOT pre-wrap with Expanded here — the uniform
                    # `Expanded(child: {e})` wrap below (line ~2915) applies the SINGLE
                    # Expanded for every flex-grow child. A pre-Expanded here produced
                    # `Expanded(child: Expanded(child: LayoutBuilder(...)))` — competing
                    # ParentDataWidgets (a debug-mode assertion + RenderFlex overflow).
                    e = (f"LayoutBuilder(builder: (ctx, _c) => "
                         f"SingleChildScrollView(child: ConstrainedBox("
                         f"constraints: BoxConstraints(minHeight: _c.maxHeight), "
                         f"child: Column(mainAxisSize: MainAxisSize.max, "
                         f"mainAxisAlignment: MainAxisAlignment.{cma}, "
                         f"crossAxisAlignment: CrossAxisAlignment.stretch, "
                         f"children: [{e}]))))")
                else:
                    e = f"SingleChildScrollView(child: {e})"  # bounded by the Expanded below
            e = f"Expanded(child: {e})"
            has_expanded = True
        kids.append(e)
    if not kids:
        return "const SizedBox.shrink()", scaffold_bg, overlays
    ma = main_axis(root["style"])
    scroll_pad = _edge_insets(_edges(root["style"], "padding"))

    def _pad(w):
        return f"Padding(padding: {scroll_pad}, child: {w})" if scroll_pad else w

    # CRITICAL: never intrinsic-measure a subtree with native platform-view leaves
    # (a LiquidGlassButton UiKitView has no intrinsic size; AdaptiveButton(expand)
    # uses a LayoutBuilder that throws on intrinsic queries). So NO IntrinsicHeight /
    # SliverFillRemaining (both measure intrinsics → blank-screen crash).
    if has_expanded:
        # FILL: a bounded Column straight in the scaffold body — Expanded distributes
        # the height, the scaffold bounds it, nothing queries intrinsics. (Overflow
        # only if content > screen, e.g. keyboard up — flagged; scroll-fill that also
        # measures intrinsics is the thing that crashes on native leaves.)
        col = ("Column(crossAxisAlignment: CrossAxisAlignment.stretch, "
               f"mainAxisAlignment: MainAxisAlignment.{ma}, children: [\n"
               + ",\n".join(kids) + ",\n])")
        return _finish(f"SafeArea(child: {_pad(col)})")
    pad = f"padding: {scroll_pad}, " if scroll_pad else ""
    if ma != "start":
        # CENTERED / DISTRIBUTED screen (the design's root justify-content is
        # center/end/space-*, e.g. the welcome interstitial). A top-aligned scroll
        # column drifts the content to the top; instead fill the scaffold body and
        # align — the SAME proven SafeArea+Column shape as FILL (no scroll, no
        # intrinsic query → native-leaf safe), with the design's own cross-axis so the
        # icon/text center horizontally as designed (align-items).
        ca = cross_axis(root["style"])
        # The root container's `gap` between its siblings — _row_or_col interposes this
        # for inner columns, but this root branch used to drop it (welcome's 44px
        # icon↔text gap vanished). Interpose the same SizedBox between children.
        sb = gap_box(root["style"], horizontal=False)
        if sb and len(kids) > 1:
            spaced = []
            for i, k in enumerate(kids):
                if i:
                    spaced.append(sb)
                spaced.append(k)
            kids = spaced
        col = (f"Column(mainAxisAlignment: MainAxisAlignment.{ma}, "
               f"crossAxisAlignment: CrossAxisAlignment.{ca}, children: [\n"
               + ",\n".join(kids) + ",\n])")
        # A Column shrink-wraps its cross-axis to its widest child; SafeArea/Padding then
        # LEFT-aligns that narrow column, so crossAxisAlignment.center/end silently
        # degrades to a left-hug — align-items:center looked left on device. Force full
        # width so the design's align-items truly centers. Gated on center/end so
        # start/stretch screens (splash space-between has ca=start) do not move.
        if ca in ("center", "end"):
            col = f"SizedBox(width: double.infinity, child: {col})"
        return _finish(f"SafeArea(child: {_pad(col)})")
    # FLOW: natural-size content that scrolls (long screens like account). No
    # Expanded/IntrinsicHeight → platform-view safe; the scroll view lays the child
    # out at its natural height without measuring intrinsics.
    col = ("Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: "
           f"CrossAxisAlignment.stretch, children: [\n" + ",\n".join(kids) + ",\n])")
    return _finish(f"SingleChildScrollView({pad}child: {col})")


def _generic_view(spec, screen_id, startup=None):
    """A non-home screen: <Name>View composing the design's translated tree. The
    home dashboard keeps its bespoke composites (build_view); every other screen
    is the generic deterministic translation graded by design_gate. `startup` (a
    ViewModel method name) wires onViewModelReady so a screen's startup/navigation
    logic runs when it mounts (e.g. splash → runStartupLogic)."""
    global TOKENS, _FORM_VM, _AUTH_FIELD
    TOKENS = spec.get("tokens", {})
    name = _pascal(screen_id)
    snake = _snake(screen_id)
    # FORM screen detection: a screen carrying a text input is the auth-entry/sign-in form
    # — bind its field + submit CTAs to the VM's form contract. OTP (code cells) emits 0
    # AdaptiveTextField, home/detail none → they never match. The submit field's TYPE is
    # DERIVED from the spec (the captured input[type]) → _AUTH_FIELD drives the controller
    # name + keyboardType + validity gate. Never a hardcoded atlet email literal.
    _FORM_VM = any(str(n.get("prim")) == "AdaptiveTextField"
                   for n in _walk(spec.get("tree") or []))
    _AUTH_FIELD = _auth_field(spec)
    # A per-record screen (binds `w.*`) takes the tapped Session as a Stacked route-arg
    # on the GENERATED view; binds resolve against `s` (the BIND map maps w.name→s.title).
    # The data wiring is generated — the ViewModel stays a hand-edit stub (no hand-patch).
    model = _model_bound(spec)
    body, scaffold_bg, overlays = _generic_body(spec, sess=model)
    # OPTION-C overlays: layer the collected sheets/modals on top of the body in a
    # Stack. Each overlay is already a gated widget (Visibility driven by a VM flag);
    # they sit ABOVE the body (Stack order), full-bleed, matching the design's stacked
    # scrim+sheet. An empty overlays list → body as-is (no Stack for plain screens).
    if overlays:
        body = ("Stack(children: [" + body + ", "
                + ", ".join(overlays) + "])")
    # REACTIVE status bar: EVERY screen wraps its scaffold in an AnnotatedRegion declaring
    # its own style (dark bg → light icons; light bg → dark icons), so push/pop always
    # restores the right icons (the framework reads the topmost AnnotatedRegion per frame —
    # a screen with none silently inherits the previous route's style). _generic_body set
    # _OVERLAY from the screen's bg luminance.
    overlay_open, overlay_close = _overlay_wrap(_OVERLAY == "dark")
    ctor_args = ", required this.workout" if model else ""
    fields = "  final Session workout;\n" if model else ""
    model_local = "    final s = workout;\n" if model else ""
    # A live-countdown screen's VM extends the generated countdown base, which takes
    # the tapped record (init `remaining` = workout.metric). Plain model-bound screens
    # keep a no-arg stub VM (the View holds the record directly).
    vm_args = "workout" if (model and _TIMER) else ""
    # The splash IS its own loading indicator (branded logo + caption + loader run
    # during the startup hold) — so it renders its body while busy. Every other screen,
    # while busy, shows its OWN background (the design has no loading view) — NOT a bare
    # centered spinner, which read as an off-design view flashing between splash and home.
    busy_gate = "" if snake == "splash" else (
        "    if (viewModel.isBusy) {\n"
        f"      return const AdaptiveScaffold({scaffold_bg}body: SizedBox.shrink());\n"
        "    }\n")
    ready = ""
    if startup:
        # (Chunk 2: the live-timer screen no longer auto-starts — it begins Paused and
        # the generated play/pause control drives viewModel.toggle(), faithful to the design.)
        ready = (f"\n  @override\n  void onViewModelReady({name}ViewModel viewModel)"
                 f" => viewModel.{startup}();\n")
    pkgs = ["import 'package:flutter/material.dart';",
            "import 'package:stacked/stacked.dart';"]
    if overlay_open:  # SystemUiOverlayStyle / Brightness live in services.dart
        pkgs.append("import 'package:flutter/services.dart';")
    if "Shad" in body:
        pkgs.append("import 'package:shadcn_ui/shadcn_ui.dart';")
    if "SvgPicture" in body:
        pkgs.append("import 'package:flutter_svg/flutter_svg.dart';")
    if "GlassEntrance(" in body:  # view constructs the native entrance descriptor
        pkgs.append("import 'package:native_liquid_glass/native_liquid_glass.dart';")
    rels = ["import '../app_tokens.dart';",
            "import '../ui/primitives.dart';",
            f"import '{snake}_viewmodel.dart';"]
    if "SplashProgress" in body or "RiseIn(" in body:  # read captured motion tokens
        rels.append("import 'motion.dart';")  # kSplashFillMs / kRiseMs / kRiseCurve
    if model:  # the route-arg record type (the domain entity the list uses)
        rels.append("import '../domain/ports/session_repository.dart';")
    imports = "\n".join(sorted(pkgs) + [""] + sorted(rels))
    out = GENERIC_HEAD.format(imports=imports, Name=name, body=body, ready=ready,
                              busy_gate=busy_gate, scaffold_bg=scaffold_bg,
                              ctor_args=ctor_args, fields=fields, model_local=model_local,
                              vm_args=vm_args, overlay_open=overlay_open,
                              overlay_close=overlay_close)
    if _NEEDS_FMTSEC:  # a kept bind used fmtSec(...) → ship the MM:SS formatter
        out += _FMTSEC_HELPER
    return out


def _assert_content_parity(spec, dart):
    """CONTENT-PARITY GATE — every inline label the design wrote into a line of
    copy (an <u>Terms</u>/<a> mid-sentence) must survive into the emitted view.
    Catches the class where capture keeps the words but the emitter drops them:
    the footer rendered "agree to Atlet's  and ." with the links gone. The fix is
    a Text.rich span, never a flattened Text. Case-insensitive — a run may be
    upper-cased by text-transform."""
    low = dart.lower()
    missing = []
    for n in _walk(spec.get("tree", [])):
        for seg in n.get("inlines", []):
            t = (seg.get("text") or "").strip()
            if "tag" in seg and t and t.lower() not in low:
                missing.append(t)
    if missing:
        raise SystemExit(
            "CONTENT-PARITY GATE FAILED — inline label(s) present in the design but "
            f"dropped from the view: {missing}. Emit a Text.rich span, don't flatten.")


_DEGEN_BOX = re.compile(
    r"Container\(\s*decoration:\s*BoxDecoration\(\s*shape:\s*BoxShape\.circle\s*\)\s*\)"
    r"|Container\(\s*\)")


def _assert_no_degenerate_box(dart):
    """RENDER-COVERAGE GATE (the deterministic floor) — a node must never emit a
    degenerate Container: a shape/radius-only box with no colour AND no size, or a
    bare `Container()`. Those render NOTHING, which is how the splash loader bar
    silently vanished. Whitelist-free (no per-screen exceptions): a sizeless+
    colourless box is always a dropped visual. The real completeness net is the
    design-vs-render visual diff (docs/plans/pipeline-completeness-and-visual-parity.md);
    this catches the cheap, unambiguous class deterministically."""
    if _DEGEN_BOX.search(dart):
        raise SystemExit(
            "RENDER-COVERAGE GATE FAILED — a node rendered to a degenerate "
            "(sizeless + colourless) Container; a visible element was dropped. "
            "Route dynamic/complex elements to a bespoke widget, or fix _styled_box.")


def _nav_call(edge):
    """A captured handler edge (handlers.json) → a Dart NavigationService call, generic
    over the @StackedApp-generated router extensions (navigateTo<Name>View / back), or
    None for kinds the emitter doesn't wire yet (mutation/action/local → VM-gen).

    Shell-aware: when the target is a TAB destination (hosted in HomeShellView's
    IndexedStack, not a top-level route), switch the shell's tab via
    RootNavigationViewModel.onTabSelected(i) instead of navigateTo<Target>View() —
    that route doesn't exist and would be a compile error."""
    if not edge:
        return None
    k, t = edge.get("kind"), edge.get("target")
    if k == "nav-back":
        return "locator<NavigationService>().back()"
    if k in ("nav", "modal") and t:
        # a tab destination → switch the shell tab (not a route navigation)
        if t in _TAB_TARGETS:
            return f"locator<RootNavigationViewModel>().onTabSelected({_TAB_TARGETS[t]})"
        view = "".join(w.capitalize() for w in re.split(r"[_-]", t)) + "View"
        return f"locator<NavigationService>().navigateTo{view}()"
    return None


def _wire_nav_imports(dart):
    """Inject imports a view needs for its locator-injected nav/auth handlers
    (NavigationService + generated router extensions; SupabaseAuthService for Sign-out).
    Only what's actually used and not already imported."""
    need = []
    if "locator<NavigationService>" in dart:
        need += ["package:stacked_services/stacked_services.dart",
                 "../app/app.locator.dart", "../app/app.router.dart"]
    if "locator<RootNavigationViewModel>" in dart:
        need += ["root_navigation_viewmodel.dart"]
    if "locator<SupabaseAuthService>" in dart:
        need += ["../app/app.locator.dart", "../infrastructure/supabase_auth_service.dart"]
    inject = "".join(f"import '{p}';\n" for p in dict.fromkeys(need) if f"'{p}'" not in dart)
    if not inject:
        return dart
    ms = list(re.finditer(r"^import .*;\n", dart, re.M))
    pos = ms[-1].end() if ms else 0
    return dart[:pos] + inject + dart[pos:]


def build_view(spec, screen_id=None, startup=None, render=None, interactions=None, state=None):
    """Home → bespoke dashboard composites; every other screen → generic
    translation. screen_id (snake, from the breakdown screenFlow) names the
    View/ViewModel; `startup` wires onViewModelReady to a VM lifecycle method.
    `render` = config.render ({fidelity, overrides}) — selects native vs design
    rendering per canonical leaf; default native. `interactions` = this screen's
    handler edges (handlers.json) — the manager wires nav/modal taps to the router."""
    global TOKENS, _APPLY_BOX, _RENDER, _GLASS_ENTRANCE, _HANDLERS, _ROW_W_UNBOUNDED
    global STATE, _NEEDS_FMTSEC, _TIMER, _OVERLAY, _FORM_VM
    global HEX2TOK, BIND
    _ROW_W_UNBOUNDED = False  # body starts width-bounded (scaffold gives finite width)
    _NEEDS_FMTSEC = False
    _OVERLAY = ""
    _FORM_VM = False  # set True per-screen in _generic_view when a text input is present
    _AUTH_FIELD = "text"  # reset so a prior auth screen's field type never leaks
    # This screen's local-state table (capture_data.json): useState defaults + derived
    # flags, flattened. The generator resolves conditional binds + prunes dead branches
    # against it. Absent → empty → conditional binds stay unresolved (no regression).
    STATE, _TIMER = {}, None
    if state:
        STATE = {k: v for k, v in state.items() if k not in ("_derived", "_timer")}
        STATE.update(state.get("_derived", {}))
        _TIMER = state.get("_timer")  # live-countdown spec → reactive viewModel.<var> binding
    TOKENS = spec.get("tokens", {})
    # Contract-driven lookups (replace the atlet-literal maps): the alias hex→name map
    # and the seed binding map come from the design's OWN frozen contracts (tokens.json
    # $extensions aliases + data_model.json seedFrom.map), passed in via the spec by
    # generate_views. The contract AUGMENTS the legacy defaults and WINS on overlap (a
    # foreign design's palette/bindings override atlet's), while atlet-home-composite
    # vocabulary the contract can't express (bigVal/bigUnit/meta.label — the bespoke
    # stat-deck helpers) survives via the legacy fallback. Net: any design resolves its
    # OWN tokens + w.<field> data refs by contract; the atlet literal is the floor.
    if spec.get("aliasHexMap"):
        HEX2TOK = {**HEX2TOK, **spec["aliasHexMap"]}
    if spec.get("bindMap"):
        BIND = {**BIND, **spec["bindMap"]}
    _RENDER = render or {"fidelity": "native", "overrides": {}}
    # Cook the native glass entrance ONCE from the captured rise spec (design-agnostic:
    # any durMs/curve/dy → spring·opacity·scale·lift), gated on a real captured entrance.
    # Reset per view so home (no entrance) and entrance-less designs get nothing.
    _GLASS_ENTRANCE = None
    rd = spec.get("riseDurMs")
    if rd and rd > 0:
        from glass_entrance import design_to_glass
        _GLASS_ENTRANCE = design_to_glass({
            "delayMs": 0,  # per-leaf stagger is applied at the call-site, not here
            "durMs": rd,
            "curve": tuple(spec.get("riseCurve") or (0.215, 0.61, 0.355, 1.0)),
            "dy": spec.get("riseDy", 0),
        })
    sid = _snake(screen_id) if screen_id else _snake(
        re.sub(r"View$", "", spec.get("entry", "home")))
    if sid == "home" or spec.get("entry") == "Home":
        _APPLY_BOX = False  # home uses its own hand-tuned spacing, not CSS box-model
        _HANDLERS = []      # home wires avatar/card explicitly below — no generic double-wire
        edges = interactions or []
        # avatar tap → Account; workout card tap → Detail. Edge-driven from handlers.json.
        avatar = next((e for e in edges
                       if (e.get("selector") or {}).get("class") == "avatar" and e.get("target")), None)
        card = next((e for e in edges
                     if (e.get("selector") or {}).get("component") == "WorkoutCard"
                     and e.get("kind") == "nav"), None)
        parts = [HEAD, _header_src(_nav_call(avatar)), "", _stats_deck_method(spec), "",
                 _filter_row_method(spec), "", _session_card_method(spec, _nav_call(card)), TAIL]
        out = _wire_nav_imports("\n".join(parts))
    else:
        _APPLY_BOX = True  # generic screens: honor the design's CSS margins/paddings
        _HANDLERS = interactions or []  # generic-emit manager wires this screen's edges (Sign-out, …)
        out = _wire_nav_imports(_generic_view(spec, sid, startup=startup))
    _assert_content_parity(spec, out)  # no inline label silently dropped
    _assert_no_degenerate_box(out)     # no visible element dropped to an empty box
    return out


# ---------------------------- self-test ----------------------------
def _self_test():
    import capture_design as cd
    root = os.path.dirname(HERE)
    djsx = os.path.join(root, "test", "fixtures", "atlet", "design", "home.jsx")
    dcss = os.path.join(root, "test", "fixtures", "atlet", "design", "styles.css")
    spec = cd.build_spec(open(djsx).read(), open(dcss).read())
    out = build_view(spec)

    must = [
        "class HomeView extends StackedView<HomeViewModel>",
        "StatsCarousel(cards:",
        # GENERIC chart dispatch — the widget NAME + data-constant NAME come from
        # the design's own component tag (node['tag']='StatBars' for atlet), not a
        # hardcoded atlet vocabulary. The const name is `k` + tag (kStatBars, kHeatmap,
        # kTrendLine). A foreign design's DonutChart would emit kDonutChartValues here.
        "StatBars(values: kStatBarsValues",
        "Heatmap(weeks: kHeatmap)",
        "TrendLine(points: kTrendLine)",
        "AdaptiveSegmented(labels: HomeViewModel.segLabels",
        "Widget _sessionCard(Session s)",
        "s.title", "s.metric", "s.type.toUpperCase()", "s.streak",
        "DashedLine()",
        "Your workouts",
    ]
    missing = [m for m in must if m not in out]
    assert not missing, f"generated view missing: {missing}"

    # GENERIC chart dispatch proof: the OLD atlet-hardcoded const names are GONE
    # (kWeekVolume/kHeat/kTrend were the atlet literals; the tag-driven emit produces
    # kStatBarsValues/kHeatmap/kTrendLine). If these leak back, the dispatch regressed
    # to the hardcoded atlet vocabulary.
    for stale in ("kWeekVolume", "kWeekLabels", "kHeat)", "kTrend)"):
        assert stale not in out, f"stale atlet const {stale!r} leaked back into the emit"

    # foreign-design discrimination: a synthetic chart node with a NON-atlet tag
    # (DonutChart) emits DonutChart(...) + kDonutChartValues — the dispatch is
    # tag-driven, not atlet-hardcoded. Proves any design's chart vocabulary resolves.
    import copy as _copy
    foreign_spec = _copy.deepcopy(spec)
    _patched = []
    def _patch_charts(nodes):
        for n in nodes or []:
            if str(n.get("prim", "")).startswith("chart:"):
                n["tag"] = "DonutChart"  # a foreign chart component name
                _patched.append(n.get("prim"))
            _patch_charts(n.get("children"))
    _patch_charts(foreign_spec.get("tree"))
    if _patched:  # only assert if the atlet home actually has chart nodes
        foreign_out = build_view(foreign_spec)
        assert "DonutChart(values: kDonutChartValues" in foreign_out, \
            "a foreign chart tag (DonutChart) must emit DonutChart(kDonutChartValues) — tag-driven dispatch"
        assert "StatBars(" not in foreign_out, \
            "the foreign-tag patch must replace atlet's StatBars with DonutChart entirely"

    # spec-driven, not hardcoded: all 4 stat eyebrows present as static text
    for ey in ("THIS WEEK", "CONSISTENCY", "TODAY"):
        assert ey in out, f"stat eyebrow {ey} not emitted from spec"
    # metric-right-of-title ordinal: in the workout card the title block expands
    assert "Expanded(child:" in out, "no Expanded — title/metric Row would overflow"
    # balanced parens (cheap syntax smoke)
    assert out.count("(") == out.count(")"), (out.count("("), out.count(")"))
    assert out.count("[") == out.count("]")

    print("self-test: PASS  (%d lines, %d stat cards, %d chars)"
          % (out.count(chr(10)) + 1, len(_stat_cards(spec)), len(out)))

    # ── seed → Session reconciliation (the P4 data-parity closed-loop emitter fix).
    #    The design's seed rows (data_model.json) → Session(...) Dart literals, so
    #    tpl_vm_home_base wires `filtered` to return them on frame 1 (the design's
    #    workout cards render, not "No sessions yet."). Discrimination: 5 seed rows
    #    → 5 Session literals; a stubbed base (no seed) → `const []`; the literal
    #    carries the reconciled field names (title/metric/note/occurredOn), not the
    #    design's (name/target/notes/last). ──
    seed = [
        {"id": "w1", "name": "Sunrise 5k", "type": "distance", "target": 5, "unit": "km",
         "notes": "Steady aerobic, river loop", "last": "2d ago", "streak": 4},
        {"id": "w2", "name": "Push Day", "type": "reps", "target": 60, "unit": "reps",
         "notes": "Bodyweight pyramid", "last": "Yesterday", "streak": 7},
    ]
    lits = _seed_to_session_literals(seed)
    assert len(lits) == 2, lits
    # field reconciliation: design name→title, target→metric, notes→note, last→date
    assert "title: 'Sunrise 5k'" in lits[0], lits[0]
    assert "metric: 5" in lits[0], lits[0]
    assert "note: 'Steady aerobic, river loop'" in lits[0], lits[0]
    assert "occurredOn: DateTime.parse('2025-04-16')" in lits[0], lits[0]  # 2d before anchor
    assert "occurredOn: DateTime.parse('2025-04-17')" in lits[1], lits[1]  # Yesterday
    assert "streak: 7" in lits[1], lits[1]
    # the wired base: filtered returns the seed (NOT const []); dataReady true.
    # The list is NON-const (Session.occurredOn is a DateTime — DateTime.parse()
    # is a method call, forbidden in a const expression), but the values are still
    # literals evaluated once at construction (frame-1 availability identical).
    wired = tpl_vm_home_base("Home", "home", seed_rows=lits)
    assert "get filtered => <Session>[" in wired and "Session(" in wired, \
        "wired base must return the seed list, not const []"
    assert "get dataReady => true" in wired, "wired base: dataReady true (seed present)"
    # the unwired base (no seed): the honest empty default (P4 no-ops GREEN for a
    # contract-less design — the stub is not a false-green because there's no seed
    # to reach). This is the back-compat path.
    unwired = tpl_vm_home_base("Home", "home")
    assert "get filtered => const []" in unwired, "no-seed base → const [] (back-compat)"
    assert "get dataReady => false" in unwired, "no-seed base → dataReady false"
    # empty seed → same as no seed (the [] path, not a wired list).
    assert "const []" in tpl_vm_home_base("Home", "home", seed_rows=[]), "empty seed → const []"
    # a row missing required id+name is skipped (won't compile → honest skip).
    assert len(_seed_to_session_literals([{"type": "reps"}])) == 0, "skip partial rows"
    # string escaping: an apostrophe in the name must not break the Dart literal.
    esc = _seed_to_session_literals([{"id": "w9", "name": "Leg Day", "type": "reps",
                                       "target": 30, "unit": "reps", "streak": 1}])
    assert len(esc) == 1 and "title: 'Leg Day'" in esc[0], esc

    # ── Issue 4: a FOREIGN design's seed resolves to ITS entity's fields via the
    #    inverted seedFrom.map, NOT atlet's hardcoded keys. A foreign design whose
    #    seed uses `title`/`value`/`description`/`when` (not name/target/notes/last)
    #    must map title→title, value→metric, description→note, when→occurredOn.
    #    seedFrom.map is {entityField: seedKey}, so the inverted {seedKey:
    #    entityField} is the field_map. Without this, the foreign seed's `title`
    #    field would be silently dropped (the fallback looks for `name`, absent)
    #    → a compiling-but-semantically-wrong Session(). ──
    foreign_seed = [
        {"id": "r1", "title": "Morning Ride", "value": 25, "unit": "km",
         "type": "distance", "streak": 3, "description": "River loop, steady pace",
         "when": "3d ago"},
    ]
    # seedFrom.map: {title: title, metric: value, note: description, occurredOn: when}
    # → inverted: {title: title, value: metric, description: note, when: occurredOn}
    foreign_fmap = {"title": "title", "value": "metric",
                    "description": "note", "when": "occurredOn"}
    flits = _seed_to_session_literals(foreign_seed, field_map=foreign_fmap)
    assert len(flits) == 1, f"foreign seed must reconcile (got {len(flits)}): {flits}"
    assert "title: 'Morning Ride'" in flits[0], f"foreign title→title: {flits[0]}"
    assert "metric: 25" in flits[0], f"foreign value→metric: {flits[0]}"
    assert "note: 'River loop, steady pace'" in flits[0], f"foreign description→note: {flits[0]}"
    assert "occurredOn: DateTime.parse('2025-04-15')" in flits[0], f"foreign when→occurredOn (3d before anchor): {flits[0]}"
    # THE REGRESSION GUARD: without the field_map, the foreign seed's `title` key
    #    is NOT `name` → the row is skipped (required title source missing). This
    #    proves the field_map is what makes a foreign design resolve — the fallback
    #    alone cannot handle a foreign schema.
    no_fmap = _seed_to_session_literals(foreign_seed)  # no field_map → _SEED_DEFAULT_MAP
    assert len(no_fmap) == 0, \
        "without field_map a foreign seed (no 'name' key) must be skipped (Issue 4 regression)"

    print("self-test: PASS  (seed→Session reconciliation: %d literals wired, "
          "foreign field_map: %d)" % (len(lits), len(flits)))
    return True


def _self_test_generic():
    """Generic-screen: box-model survives (both modes), and the render-fidelity
    config selects native primitive (default) vs design-religious rendering."""
    import capture_design as cd
    root = os.path.dirname(HERE)
    dd = os.path.join(root, "test", "fixtures", "atlet", "design")
    css = open(os.path.join(dd, "styles.css")).read()
    jsx = "\n".join(open(os.path.join(dd, n)).read()
                    for n in ("auth.jsx", "icons.jsx", "data.jsx"))
    spec = cd.build_spec(jsx, css, source="signin", entry="SignInView")
    _SVG_ASSETS.clear()
    _SVG_LEDGER.clear()

    # --- mode-independent: box-model + the logo render as a MANAGED ASSET ---
    nat = build_view(spec, "signin")  # default = native
    box = ["EdgeInsets.fromLTRB(26, 18, 26, 20)",  # auth-body padding
           "EdgeInsets.fromLTRB(0, 0, 0, 26)",     # auth-sub margin-bottom
           "EdgeInsets.fromLTRB(0, 22, 0, 18)"]    # auth-divider margin
    assert all(m in nat for m in box), "box-model lost"
    assert "SvgPicture.asset(" in nat and "SvgPicture.string(" not in nat, \
        "logo must be a managed asset (assets/svg/*.svg), not an inline string"
    assert any("#D2522B" in v for v in _SVG_ASSETS.values()), "logo svg asset missing"

    # --- STRUCTURE: the centered-scroll flex-grow child emits EXACTLY ONE Expanded.
    #     A prior version pre-wrapped the LayoutBuilder in Expanded, then the uniform
    #     flex-grow wrap added a SECOND → `Expanded(child: Expanded(child: ...))` —
    #     competing ParentDataWidgets (a debug-mode assertion + RenderFlex overflow on
    #     the signin screen). The single-Expanded invariant must hold. ---
    assert "Expanded(child: Expanded(" not in nat, \
        "competing ParentDataWidgets: a flex-grow child must wrap in Expanded ONCE, " \
        "not twice (the centered-scroll LayoutBuilder must NOT pre-Expanded)"

    # --- NATIVE: BOTH social buttons are native AdaptiveAuthButtons (the brand-governed
    #     OS sign-in button — Apple's SignInWithAppleButton on glass, the official Google
    #     "G" on a styled button, design-agnostic: provider read from the design's class).
    #     Each brand glyph (Google G, Apple logo) is DROPPED (gate G3) and RECORDED in the
    #     non-bundled asset ledger. The native OS button owns its own brand marks, so the
    #     design's bespoke SVG glyphs are NOT carried into the view. No apple.logo. ---
    assert "AdaptiveAuthButton(provider: 'google'" in nat, \
        "Google → native AdaptiveAuthButton(provider: 'google') (the OS sign-in button)"
    assert "AdaptiveAuthButton(provider: 'apple'" in nat, \
        "Apple → native AdaptiveAuthButton(provider: 'apple') (the OS sign-in button)"
    assert "apple.logo" not in nat, "no restricted apple.logo SF Symbol in native mode"
    assert "assetIcon:" not in nat, \
        "gate G3: a native OS sign-in button must NOT carry a custom brand glyph"
    # AdaptiveAuthButton owns its native brand marks (Apple's SignInWithAppleButton, the
    # official Google "G"), so the design's bespoke SVG brand glyphs are NEITHER carried
    # NOR dropped — they're bypassed entirely (the routing returns before the SVG glyph
    # path). The proof: NO google/apple content leaks into the bundled assets, and the
    # only asset is the app logo. (The prior ledger-drop assertions were stale: they
    # predated the AdaptiveAuthButton routing that bypasses the glyph path.)
    assert not any("#4285F4" in v for v in _SVG_ASSETS.values()), \
        "no Google brand colour leaks into bundled assets (the native button owns it)"
    assert all("google" not in v.lower() and "apple" not in v.lower()
               for v in _SVG_ASSETS.values()), \
        "no google/apple svg content leaks into bundled assets (native button owns brand)"
    assert "OutlinedButton(" not in nat and "FilledButton(" not in nat, \
        "native mode must not emit raw Flutter buttons (the recurring bug)"

    # --- FORM-STATE WIRING (Seam A): the design's submit CTA is disabled until the field
    #     is valid (auth.jsx: disabled={!valid}) + a spinner while in flight. The view must
    #     bind enabled: viewModel.formValid + busy: viewModel.isBusy on that CTA, and the
    #     field onChanged → viewModel.onFieldChanged. The contract is TYPE-DERIVED from the
    #     spec (the captured input[type]) — the email controller + keyboardType + gate all
    #     derive from _AUTH_FIELD, NEVER a hardcoded atlet literal. ---
    assert "enabled: viewModel.formValid" in nat, \
        "Send-code CTA must bind enabled to the VM validity gate"
    assert "busy: viewModel.isBusy" in nat, \
        "CTAs must bind busy to the VM in-flight gate"
    assert "onChanged: viewModel.onFieldChanged" in nat, \
        "field must feed the VM validity gate via onChanged"
    # TYPE-DERIVED (not hardcoded): the atlet signin declares type="email", so the derived
    # field type is email → emailController + the emailAddress keyboard. Asserting the
    # derived names (not a literal email regex) proves any design gets its own gate.
    assert "controller: viewModel.emailController" in nat, \
        "email-typed design must derive the emailController (from input[type=email])"
    assert "keyboardType: TextInputType.emailAddress" in nat, \
        "email-typed field must derive the emailAddress keyboard (from input[type])"

    # --- CONTENT PARITY: the footer's inline <u>Terms</u>/<u>Privacy</u> links survive
    #     as underlined rich text (was dropped → "agree to Atlet's  and .") ---
    assert "Text.rich(" in nat, "footer must emit Text.rich for the inline <u> links"
    for w in ("Terms", "Privacy"):
        assert w in nat, f"inline footer link {w!r} dropped from the view"
    assert "TextDecoration.underline" in nat, "inline <u> links must render underlined"
    # the gate proves itself: a view that dropped 'Terms' MUST hard-fail
    try:
        _assert_content_parity(spec, nat.replace("Terms", ""))
        raise AssertionError("content-parity gate did NOT fail on a dropped inline label")
    except SystemExit:
        pass

    # --- MOTION: the design's `.rise` + per-element animationDelay → RiseIn entrance ---
    assert "RiseIn(" in nat, "rise-in motion must wrap the design's `.rise` elements"
    assert "delayMs: 460" in nat, "footer `.rise` keeps its captured 460ms stagger"
    assert "skipOnGlass: false" in nat, \
        "pure-Flutter rise nodes (logo/text/footer) must animate under glass too"
    # the stagger now rides the captured design tokens (true delayed start, design
    # curve) — not the old duration-inflation hack
    assert all(t in nat for t in ("durationMs: kRiseMs", "curve: kRiseCurve", "dy: kRiseDy")), \
        "RiseIn must carry the captured design duration + easing + rise-distance tokens"
    assert "import 'motion.dart';" in nat, "a view with RiseIn must import the motion tokens"

    # --- SPLASH: renders its branded body during startup (no busy→spinner gate) + hold
    #     CAPTURED from the design's SplashView JS (DUR 1800 + onReady 320 = 2120ms) ---
    sp = cd.build_spec(jsx, css, source="splash", entry="SplashView")
    assert sp.get("splashHoldMs") == 2120, \
        f"splash hold must be captured from design JS (DUR+onReady), got {sp.get('splashHoldMs')}"
    assert sp.get("splashFillMs") == 1800, \
        f"splash bar fill duration must be the design DUR, got {sp.get('splashFillMs')}"
    spv = build_view(sp, "splash", startup="runStartupLogic")
    assert "if (viewModel.isBusy)" not in spv, \
        "splash must render its branded body during the hold, not a bare spinner"
    assert "RiseIn(" in spv, "splash logo/caption keep their rise-in entrance"
    # the loader is the bespoke animated bar (track+fill+live %), NOT the dropped
    # invisible Container the box translator produced
    assert "SplashProgress(durationMs: kSplashFillMs)" in spv, \
        "splash loader must route to the bespoke animated SplashProgress bar"
    assert "import 'motion.dart';" in spv, "splash view must import the captured timing"
    # the RENDER-COVERAGE floor gate proves itself: a degenerate box hard-fails,
    # and the splash no longer emits the invisible empty circle (the dropped bar)
    try:
        _assert_no_degenerate_box("x = Container(decoration: BoxDecoration(shape: BoxShape.circle));")
        raise AssertionError("render-coverage gate did NOT fail on a degenerate Container")
    except SystemExit:
        pass
    assert "BoxShape.circle))" not in spv, "splash must not emit the degenerate empty disc"

    # --- DESIGN (opt-in per config.render): reproduce the design exactly. The override
    #     applies to the form's primary CTA (the Send-code button) → the design's 14px
    #     radius + the design-religious FilledButton. The SOCIAL buttons stay native
    #     (AdaptiveAuthButton) in BOTH modes — they're the OS sign-in button, never a
    #     design replica, so there's no tinted Apple mark (ColorFilter.mode) and no
    #     SignInWithAppleButton in the view. ---
    des = build_view(spec, "signin",
                     render={"fidelity": "native",
                             "overrides": {"action.button": "design"}})
    assert "BorderRadius.circular(14)" in des, "design mode: 14px rounded button (the CTA)"
    assert "AdaptiveAuthButton(provider: 'google'" in des, \
        "design mode: social buttons stay native (AdaptiveAuthButton, not a replica)"
    assert "SignInWithAppleButton(" not in des, \
        "design mode: never the official Sign in with Apple button"

    # every emitted button routes to the native primitive (AdaptiveAuthButton /
    # AdaptiveButton), which OWNS the legible state-mapped foreground internally
    # (AdaptiveCard._resolveColors: primary→accent/paper enabled, bone3/ink4 disabled).
    # The call sites emit NO frozen tint/foreground for a primary CTA — that's the
    # state-conditional-colour fix (commit 7b60714): a single-state capture can't
    # represent a :disabled rule, so the primitive owns the state map, not the call
    # site. The proof: every button IS a native primitive (no raw FilledButton/OutlinedButton
    # leak), so the primitive's legibility contract covers them.
    import re as _re
    buttons = _re.findall(r"\b(AdaptiveAuthButton|AdaptiveButton|AdaptiveIconButton)\(", nat)
    assert len(buttons) >= 3, f"at least 3 native button primitives expected (got {buttons})"
    # the LEGIBILITY GATE proves itself: a washed-out pairing (white on cream ≈ 1.1:1, the
    # exact Android-Google bug) MUST hard-fail; a contrasting one must pass.
    try:
        _assert_legible("Colors.white", "#FBF8F2", "self-test")
        raise AssertionError("legibility gate did NOT fail on white-on-cream")
    except SystemExit:
        pass
    assert _assert_legible("AppTokens.ink", "#FBF8F2", "self-test") > 4.5, "ink-on-cream must pass"

    # home stays untouched: _APPLY_BOX off + native default after a home build
    build_view(cd.build_spec(open(os.path.join(dd, "home.jsx")).read(), css))
    assert _APPLY_BOX is False, "home build must leave _APPLY_BOX off"
    print("generic self-test: PASS  (managed assets + native AdaptiveAuthButton social "
          "buttons, brand marks owned by the OS sign-in + design CTA override)")
    return True


def _self_test_splash_vm():
    """The generated splash VM base + stub: holds for kSplashHoldMs then
    REPLACE-routes to the next authStage screen (design-derived, not hardcoded).
    The stub extends the base; _startup_method finds runStartupLogic through it."""
    base = tpl_vm_splash_base("Splash", "splash", "Signin", smoke_autologin=True)
    for m in ("runStartupLogic", "replaceWithSigninView", "kSplashHoldMs",
              "class SplashViewModelBase", "BaseViewModel", "SMOKE_AUTOLOGIN",
              "setBusy(true)", "setError(e)"):
        assert m in base, f"splash VM base missing: {m}"
    # balanced braces (cheap syntax smoke)
    assert base.count("{") == base.count("}"), (base.count("{"), base.count("}"))
    # the autologin-treeshaken variant still routes to signin as the fallback
    base_no_smoke = tpl_vm_splash_base("Splash", "splash", "Signin", smoke_autologin=False)
    assert "replaceWithSigninView" in base_no_smoke, "no-smoke base must still route to signin"
    # the no-smoke variant drops the autologin CODE (const/import/signIn path); the
    # docstring still mentions SMOKE_AUTOLOGIN (prose, not code) — that's fine.
    assert "_autoLoginEmail" not in base_no_smoke, "no-smoke base must drop the autologin const"
    assert "supabase_auth_service" not in base_no_smoke, "no-smoke base must drop the auth import"
    assert "signInWithPassword" not in base_no_smoke, "no-smoke base must drop the autologin branch"
    stub = tpl_vm_splash_stub("Splash", "splash")
    for m in ("class SplashViewModel extends SplashViewModelBase",
              "import 'splash_viewmodel.gen.dart';"):
        assert m in stub, f"splash VM stub missing: {m}"
    assert stub.count("{") == stub.count("}"), (stub.count("{"), stub.count("}"))
    # _startup_method (generate_views.py) reads the STUB file and matches
    # \brunStartupLogic\s*\( — the stub's TODO names runStartupLogic() so the
    # heuristic fires and build_view wires onViewModelReady → runStartupLogic.
    import re as _re
    assert _re.search(r"\brunStartupLogic\s*\(", stub), \
        "stub must name runStartupLogic() so _startup_method wires onViewModelReady"
    print("splash VM self-test: PASS  (base + stub, design-derived splash→Signin)")
    return True


def main(argv):
    if "--self-test" in argv:
        sys.path.insert(0, HERE)
        return 0 if (_self_test() and _self_test_generic()
                     and _self_test_splash_vm()) else 1
    screen = None
    if "--screen" in argv:
        i = argv.index("--screen")
        screen = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    spec = json.load(open(argv[1], encoding="utf-8"))
    out = build_view(spec, screen)
    with open(argv[2], "w", encoding="utf-8") as f:
        f.write(out)
    print(f"generated {out.count(chr(10)) + 1} lines → {argv[2]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
