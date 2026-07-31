#!/usr/bin/env python3
"""web_tokens — extract a semantic palette (roles by area/frequency/contrast) +
type scale + spacing + radii + shadows (spec §5.2) from a page's computed styles.
Pure clustering/role funcs are unit-tested; main() is live-validated."""
from __future__ import annotations
import argparse
import json
import re
from pathlib import Path

from _common import die, emit_json
from _web_eval import add_transport_args, navigate, resolve_web_eval

_RGB = re.compile(r"rgba?\(\s*([0-9]+)\s*,\s*([0-9]+)\s*,\s*([0-9]+)\s*(?:,\s*([0-9.]+)\s*)?\)")


def parse_color(s):
    """Return (r,g,b) or None for transparent/unparseable."""
    if not s:
        return None
    s = s.strip()
    if s in ("transparent", "none", "currentColor"):
        return None
    m = _RGB.match(s)
    if m:
        a = float(m.group(4)) if m.group(4) is not None else 1.0
        if a == 0.0:
            return None
        return tuple(max(0, min(255, int(m.group(i)))) for i in (1, 2, 3))
    if s.startswith("#"):
        h = s[1:]
        if len(h) == 3:
            h = "".join(c * 2 for c in h)
        if len(h) >= 6:
            return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))
    return None


def _hex(rgb):
    return "#%02x%02x%02x" % rgb


def cluster_colors(samples, tol=8):
    """Merge near-duplicate colors. samples: [(css_color, area), ...].
    Returns [(representative_hex, total_area), ...] sorted by area desc.
    A new sample joins the nearest cluster within Chebyshev distance tol.
    Samples are processed largest-area first so the dominant shade seeds (and
    thus represents) each cluster, and greedy merge order is deterministic."""
    clusters = []  # each: [r, g, b, total_area]
    for css, area in sorted(samples, key=lambda s: s[1], reverse=True):
        rgb = parse_color(css)
        if rgb is None:
            continue
        best, best_d = None, None
        for c in clusters:
            d = max(abs(c[0] - rgb[0]), abs(c[1] - rgb[1]), abs(c[2] - rgb[2]))
            if d <= tol and (best_d is None or d < best_d):
                best, best_d = c, d
        if best is None:
            clusters.append([rgb[0], rgb[1], rgb[2], area])
        else:
            best[3] += area
    out = [(_hex((int(c[0]), int(c[1]), int(c[2]))), c[3]) for c in clusters]
    out.sort(key=lambda x: x[1], reverse=True)
    return out


def _saturation(rgb):
    """0..1 chroma fraction: (max-min)/max. Grey ~0, vivid ~1."""
    mx, mn = max(rgb), min(rgb)
    return 0.0 if mx == 0 else (mx - mn) / mx


def assign_roles(bg_samples, fg_samples, border_samples):
    """Assign spec §5.2 semantic palette roles from (css, weight) sample lists.

    background/surface by area (largest, then next); fg-primary by frequency;
    fg-muted = the LOWEST-saturation remaining text color (the muted grey);
    accent = the HIGHEST-saturation text color (the vivid outlier); border by
    frequency. Each role -> {"value": hex|None, "confidence": "high"|"low"}.
    """
    bg = cluster_colors(bg_samples)
    fg = cluster_colors(fg_samples)
    borders = cluster_colors(border_samples)

    def role(value, conf):
        return {"value": value, "confidence": conf}

    background = role(bg[0][0], "high") if bg else role(None, "low")
    if len(bg) > 1:
        surface = role(bg[1][0], "high")
    else:
        surface = role(bg[0][0] if bg else None, "low")

    fg_primary = role(fg[0][0], "high") if fg else role(None, "low")

    # fg-muted: the most-muted (lowest saturation) of the non-primary text colors
    rest = fg[1:]
    if rest:
        muted = min(rest, key=lambda c: _saturation(parse_color(c[0])))
        fg_muted = role(muted[0], "high")
    else:
        fg_muted = role(fg_primary["value"], "low")

    # accent: the most-saturated text color (vivid outlier)
    if fg:
        vivid = max(fg, key=lambda c: _saturation(parse_color(c[0])))
        if len(fg) > 1 and _saturation(parse_color(vivid[0])) > 0.3:
            accent = role(vivid[0], "high")
        else:
            accent = role(vivid[0], "low")
    else:
        accent = role(None, "low")

    border = role(borders[0][0], "high") if borders else role(None, "low")

    return {"background": background, "surface": surface,
            "fg-primary": fg_primary, "fg-muted": fg_muted,
            "accent": accent, "border": border}


def build_scales(nodes, space_samples, radius_samples, shadow_samples):
    """Build the type/space/radius/shadow scales for tokens.json (spec §5.2).

    nodes supply the type scale (font sizes), weights, families; space/radius are
    numeric px lists; shadows are CSS box-shadow strings. Numeric scales deduped +
    sorted, families alphabetised, shadows deduped with none/empty dropped.
    Returns a FLAT dict (the §5.2 tokens.json scale fields)."""
    sizes, weights, families = set(), set(), set()
    for n in nodes:
        f = n.get("font") or {}
        if f.get("size"):
            sizes.add(round(float(f["size"])))
        if f.get("weight"):
            weights.add(int(f["weight"]))
        if f.get("family"):
            families.add(f["family"])

    def uniq_sorted(xs):
        out = set()
        for x in xs:
            try:
                out.add(round(float(x)))
            except (TypeError, ValueError):
                continue
        return sorted(out)

    return {
        "type_scale": sorted(sizes),
        "weights": sorted(weights),
        "families": sorted(families),
        "spacing": uniq_sorted(space_samples),
        "radii": uniq_sorted(radius_samples),
        "shadows": [s for s in dict.fromkeys(shadow_samples) if s and s != "none"],
    }


# One in-page pass over every element's computed style. Emits the exact shapes
# the pure funcs consume: bg/fg/border as (css, weight) pairs (bg weighted by
# rendered area; text/border by count), font nodes as {"font": {...}} for
# build_scales, plus flat numeric gap/padding + radius lists and shadow strings.
# G10: the walk DESCENDS open shadow roots — web-component design tokens live
# inside them and querySelectorAll() on a parent root does not cross the shadow
# boundary. Closed roots (mode:'closed') expose no shadowRoot handle and stay
# unreachable (documented hard limit, like a cross-origin iframe — §C8).
_COLLECT_JS = r"""
(() => {
  const out = {bg: [], fg: [], border: [], fonts: [], spaces: [],
               radii: [], shadows: []};
  const visit = (root) => {
    for (const el of root.querySelectorAll('*')) {
      const cs = getComputedStyle(el);
      const r = el.getBoundingClientRect();
      const area = Math.max(0, r.width) * Math.max(0, r.height);
      if (area > 0) out.bg.push([cs.backgroundColor, area]);
      const leaf = el.children.length === 0 &&
                   (el.textContent || '').trim().length > 0;
      if (leaf) {
        out.fg.push([cs.color, 1]);
        out.fonts.push({font: {size: parseFloat(cs.fontSize),
                               weight: parseInt(cs.fontWeight, 10) || 400,
                               family: cs.fontFamily}});
      }
      if (parseFloat(cs.borderTopWidth) > 0) out.border.push([cs.borderTopColor, 1]);
      for (const p of [cs.gap, cs.paddingTop, cs.paddingRight,
                       cs.paddingBottom, cs.paddingLeft]) {
        const n = parseFloat(p);
        if (n > 0) out.spaces.push(n);
      }
      const rad = parseFloat(cs.borderTopLeftRadius);
      if (rad > 0) out.radii.push(rad);
      if (cs.boxShadow && cs.boxShadow !== 'none') out.shadows.push(cs.boxShadow);
      if (el.shadowRoot) visit(el.shadowRoot);   // G10: cross the open shadow boundary
    }
  };
  visit(document);
  out.shadows = Array.from(new Set(out.shadows)).slice(0, 8);
  return out;
})()
"""


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--out", default=None, help="write tokens.json here")
    add_transport_args(p)  # supplies --url + transport/device flags
    args = p.parse_args()
    if not args.url:
        die("web_tokens needs --url (the page to extract design tokens from).")

    engine, ev, device = resolve_web_eval(args)
    try:
        if not hasattr(ev, "sess"):
            die("web_tokens needs a CDP transport (chrome host / --android / --cdp-port).")
        navigate(ev, engine, args.url)
        data = ev.ev(_COLLECT_JS)

        bg = [(c, a) for c, a in data["bg"]]
        fg = [(c, w) for c, w in data["fg"]]
        border = [(c, w) for c, w in data["border"]]
        roles = assign_roles(bg, fg, border)
        scales = build_scales(data["fonts"], data["spaces"],
                              data["radii"], data["shadows"])

        # spec §5.2 FLAT shape: palette dict + the six scale fields at top level.
        palette = {role: v["value"] for role, v in roles.items()}
        tokens = {"palette": palette, **scales}

        if args.out:
            Path(args.out).write_text(json.dumps(tokens, indent=2))
            emit_json({"ok": True, "out": args.out, "palette": palette,
                       "type_scale": scales["type_scale"]})
        else:
            emit_json(tokens)
    finally:
        ev.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
