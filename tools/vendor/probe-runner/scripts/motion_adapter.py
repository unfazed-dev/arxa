#!/usr/bin/env python3
"""motion_adapter — convert raw web_anim / web_flipbook JSON → motion.json
contract rows consumable by bundle_writer.match_motion.

Pure data transformation; no browser, no network. Every public function here
is unit-tested in test_motion_adapter.py. The CLI main() (file I/O, argparse)
is live-only and not covered by unit tests.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from typing import Any, Optional

from _common import die, emit_json

# ─── helpers ──────────────────────────────────────────────────────────────────

_BEZIER_RE = re.compile(
    r"cubic-bezier\(\s*"
    r"([+-]?\d+(?:\.\d+)?)\s*,\s*"
    r"([+-]?\d+(?:\.\d+)?)\s*,\s*"
    r"([+-]?\d+(?:\.\d+)?)\s*,\s*"
    r"([+-]?\d+(?:\.\d+)?)\s*\)"
)

_AXIS_MAP: dict[str, str] = {
    "tx": "x",
    "ty": "y",
    "sx": "scale-x",
    "sy": "scale-y",
    "rot": "rotate",
    "op": "opacity",
    "tz": "translate-z",
    "rotX": "rotate-x",
    "rotY": "rotate-y",
}

_REQUIRED_KEYS = (
    "name", "anchor", "easing", "cubic_bezier",
    "amplitude", "axis", "window", "klass", "source", "rms",
)


def parse_bezier(s: Optional[str]) -> Optional[list[float]]:
    """Parse "cubic-bezier(x1,y1,x2,y2)" (spaces tolerated) → [float×4].

    Returns None for None, empty string, "-", or non-matching input.
    """
    if not s:
        return None
    m = _BEZIER_RE.search(s)
    if m is None:
        return None
    return [float(m.group(i)) for i in range(1, 5)]


def axis_for_channel(ch: str) -> str:
    """Map web_anim/flipbook channel key → contract axis name.

    Known: tx→x, ty→y, sx→scale-x, sy→scale-y, rot→rotate, op→opacity.
    Unknown channels pass through unchanged.
    """
    return _AXIS_MAP.get(ch, ch)


def adapt_web_anim(
    anim_out: dict[str, Any],
    *,
    certified_only: bool = True,
) -> list[dict[str, Any]]:
    """Convert web_anim raw output → list of motion.json contract rows (klass="scroll").

    Args:
        anim_out: The full web_anim JSON dict (must contain "movers" list).
        certified_only: When True (default) skip entries where certified != True.

    Returns:
        List of contract rows, one per (mover, channel) pair that passes filters.
    """
    rows: list[dict[str, Any]] = []
    for mover in anim_out["movers"]:
        sel: str = mover["sel"]
        anchor: float = float(mover["absY"])
        rank = mover.get("rank")
        # absX is the REST center-x (web_anim emits it transform-corrected). When
        # present it lets bundle_writer bind co-located movers (same y, different
        # x — e.g. mirror hero words) to their correct distinct nodes.
        abs_x = mover.get("absX")
        channels: dict[str, Any] = mover.get("channels", {})

        for ch, entry in channels.items():
            # Handle multi-segment channels first (one row per certified segment).
            # _anim_core only sets entry["segments"] when the list is NON-EMPTY,
            # so `if seg_list:` is exact: key absent -> None (fall through to the
            # single path); key present -> non-empty list. A [] is never produced
            # upstream, so there is no silent-drop ambiguity here.
            seg_list = entry.get("segments")
            if seg_list:
                base = f"{sel}#{rank}#{ch}" if rank is not None else f"{sel}#{ch}"
                for si, seg in enumerate(seg_list):
                    if certified_only and seg.get("certified") is not True:
                        continue
                    cb = parse_bezier(seg["easing"]["bezier"])
                    if cb is None:
                        continue
                    row: dict[str, Any] = {
                        "name": f"{base}#s{si}",
                        "anchor": anchor,
                        "easing": seg["easing"]["name"],
                        "cubic_bezier": cb,
                        "amplitude": float(seg["to"]) - float(seg["from"]),
                        "axis": axis_for_channel(ch),
                        "window": [float(v) for v in seg["activeScroll"]],
                        "klass": "scroll",
                        "source": "web_anim",
                        "rms": float(seg["easing"]["rms"]),
                    }
                    if abs_x is not None:
                        row["anchor_x"] = float(abs_x)
                    rows.append(row)
                continue  # segmented channel done; skip single path

            # skip if no resolvable active range or no easing
            if "activeScroll" not in entry or "easing" not in entry:
                continue
            if certified_only and entry.get("certified") is not True:
                continue

            ez = entry["easing"]
            # skip if bezier string is unparseable (e.g. "-"); adapter must not
            # emit a row that assert_contract would reject
            cb = parse_bezier(ez["bezier"])
            if cb is None:
                continue

            # amplitude is SIGNED (to - from) so motion DIRECTION survives — two
            # mirror movers translate opposite ways and must not collapse to one
            # magnitude. Fall back to "range" (already a magnitude) only when
            # to/from are unavailable.
            try:
                amplitude = float(entry["to"]) - float(entry["from"])
            except (KeyError, TypeError, ValueError):
                amplitude = float(entry["range"])

            # rank disambiguates two same-selector movers (mirror hero words both
            # had sel "h1" -> collided as "h1#tx"); rank is unique per scan.
            name = f"{sel}#{rank}#{ch}" if rank is not None else f"{sel}#{ch}"
            row: dict[str, Any] = {
                "name": name,
                "anchor": anchor,
                "easing": ez["name"],
                "cubic_bezier": cb,
                "amplitude": amplitude,
                "axis": axis_for_channel(ch),
                "window": [float(v) for v in entry["activeScroll"]],
                "klass": "scroll",
                "source": "web_anim",
                "rms": float(ez["rms"]),
            }
            if abs_x is not None:
                row["anchor_x"] = float(abs_x)
            rows.append(row)

    return rows


def adapt_flipbook(
    fb_out: dict[str, Any],
    anchor: float,
    *,
    window: Optional[list[float]] = None,
) -> list[dict[str, Any]]:
    """Convert web_flipbook raw output → list of motion.json contract rows (klass="time").

    Accepts BOTH payload shapes a flipbook can take (mirrors `motion_summary`):
      - the web_flipbook CLI wrapper: `{"selector": ..., "recovery": {"channels": ...}}`
      - the native CLI wrapper (ios_/adb_/flutter_flipbook): `{"recovery": {"channels": ...}}`
        (no `selector` — web-only)
      - the raw `recover_from_video` / `analyze_frames` dict: `{"channels": ...}`
        (top-level channels, no `recovery` wrapper)
    `selector` is web-only; native payloads fall back to "mover" in the row `name`
    (the caller supplies a per-element `anchor`; uniqueness across movers is the
    caller's concern, same as web_anim's same-selector case handled via `rank`).

    Args:
        fb_out: A web_flipbook / *_flipbook output (wrapped OR raw shape).
        anchor: REST page-y of the animated element in px (caller must supply; flipbook doesn't emit it).
        window: Scroll/time window [t0, t1]; defaults to [0.0, 1.0].

    Returns:
        List of contract rows, one per channel where easing is not None/falsy.
    """
    selector: str = fb_out.get("selector") or "mover"
    # `recovery` is present on the CLI wrappers (web + native) but ABSENT on the raw
    # recover_from_video / analyze_frames dict (channels live top-level there).
    src = fb_out.get("recovery") or fb_out
    channels: dict[str, Any] = src["channels"]
    eff_window: list[float] = list(window) if window is not None else [0.0, 1.0]

    rows: list[dict[str, Any]] = []
    for ch, ch_entry in channels.items():
        # skip channels with null/falsy easing
        if not ch_entry.get("easing"):
            continue
        # skip if bezier string is unparseable (e.g. "-"); adapter must not
        # emit a row that assert_contract would reject
        cb = parse_bezier(ch_entry.get("bezier"))
        if cb is None:
            continue

        # skip channels with an incomplete numeric payload (null/missing amp or
        # rms); cannot form a valid contract row. amp is read defensively:
        # _flipbook.fit_channel and _scale_channel both emit it, but a future
        # channel that omits it should fall back to (to - from) rather than be
        # silently dropped (the original bug: _scale_channel lacked `amp`).
        try:
            amp = ch_entry.get("amp")
            if amp is None:
                amp = float(ch_entry["to"]) - float(ch_entry["from"])
            amplitude = abs(float(amp))
            rms = float(ch_entry["rms"])
        except (KeyError, TypeError, ValueError):
            continue

        row: dict[str, Any] = {
            "name": f"{selector}#{ch}",
            "anchor": float(anchor),
            "easing": ch_entry["easing"],
            "cubic_bezier": cb,
            "amplitude": amplitude,
            "axis": axis_for_channel(ch),
            "window": eff_window,
            "klass": "time",
            "source": "web_flipbook",
            "rms": rms,
        }
        rows.append(row)

    return rows


def assert_contract(row: dict[str, Any]) -> None:
    """Raise AssertionError if row violates the motion.json contract.

    Checks: all 10 required keys present, klass is "scroll" or "time",
    cubic_bezier is a 4-float list, window is a 2-element list,
    anchor/amplitude/rms are numeric.
    """
    for k in _REQUIRED_KEYS:
        assert k in row, f"missing required key: {k!r}"

    assert row["klass"] in {"scroll", "time"}, (
        f"klass must be 'scroll' or 'time', got {row['klass']!r}"
    )

    cb = row["cubic_bezier"]
    assert isinstance(cb, list) and len(cb) == 4, (
        f"cubic_bezier must be a 4-element list, got {cb!r}"
    )

    win = row["window"]
    assert isinstance(win, list) and len(win) == 2, (
        f"window must be a 2-element list, got {win!r}"
    )

    for numeric_key in ("anchor", "amplitude", "rms"):
        val = row[numeric_key]
        assert isinstance(val, (int, float)), (
            f"{numeric_key} must be numeric, got {type(val).__name__!r}"
        )

    # anchor_x is OPTIONAL (back-compat: y-only captures omit it) but must be
    # numeric when present.
    if "anchor_x" in row:
        assert isinstance(row["anchor_x"], (int, float)), (
            f"anchor_x must be numeric, got {type(row['anchor_x']).__name__!r}"
        )


def combine(
    anim_rows: list[dict[str, Any]],
    flipbook_rows: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Concatenate anim rows then flipbook rows (stable order)."""
    return list(anim_rows) + list(flipbook_rows)


# ─── motion_summary ───────────────────────────────────────────────────────────
#
# A SMALL, consistent per-mover summary lifted from the raw verb payloads, so a
# direct consumer (an agent, or a human reading stdout) does not have to parse
# three different raw shapes to learn "what moved, how far, what easing, how
# confident". It consumes ONLY existing field names — no schema break — and
# reports the BEST (most-confident) reading per channel.
#
# The honest two-model contract it surfaces:
#   klass "scroll" (web_anim / flutter_anim): easing + rms + certified +
#     activeScroll window. NO duration — prop = f(scrollY) is timeless.
#   klass "time" (web_flipbook / *_flipbook): amplitude + easing + reliable
#     (a confidence flag). Duration lives only in the web getAnimations oracle,
#     not in pixel recovery, so it is intentionally absent here.

def motion_summary(payload: dict[str, Any], klass: str) -> dict[str, Any]:
    """Lift the best per-channel motion facts from a raw verb payload into a
    small, consistent block.

    Args:
        payload: a web_anim / flutter_anim output (must contain "movers") when
            klass=="scroll", or a *_flipbook output (must contain
            "recovery.channels", or top-level "channels") when klass=="time".
        klass: "scroll" or "time" — selects the source shape + the confidence
            flag name surfaced.

    Returns:
        {"klass": klass, "channels": {<axis>: {
            "easing": str|None, "amplitude": float, "rms": float,
            "window": [lo,hi],
            "confidence": "high"|"low",   # high = certified/reliable
            "source_channel": str         # the raw channel key (tx/ty/scale/...)
        }}}

    Pure data transformation; no I/O. Empty payload -> {"klass":..., "channels":{}}.
    """
    summary: dict[str, Any] = {"klass": klass, "channels": {}}
    channels: dict[str, Any] = {}

    if klass == "scroll":
        # web_anim / flutter_anim: payload["movers"][i]["channels"][ch] = entry
        for mover in payload.get("movers", []):
            for ch, entry in (mover.get("channels") or {}).items():
                # A segmented channel: surface the best segment.
                segs = entry.get("segments")
                if segs:
                    cand = [{"from": s.get("from"), "to": s.get("to"),
                             "rms": (s.get("easing") or {}).get("rms"),
                             "easing": (s.get("easing") or {}).get("name"),
                             "certified": s.get("certified"),
                             "window": s.get("activeScroll")}
                            for s in segs]
                else:
                    cand = [entry]
                if not cand:
                    continue
                best = cand[0]
                for c in cand[1:]:
                    if _better(c, best):
                        best = c
                ez = best.get("easing")
                # scroll rows store easing as a {name,bezier,rms} dict (anim) or a
                # bare string (a segment candidate built above).
                if isinstance(ez, dict):
                    easing_name = ez.get("name")
                    rms = ez.get("rms")
                else:
                    easing_name = ez
                    rms = best.get("rms")
                try:
                    frm = float(best.get("from"))
                    to = float(best.get("to"))
                    amp = to - frm
                except (TypeError, ValueError):
                    amp = None
                win = best.get("window") or best.get("activeScroll")
                axis = axis_for_channel(ch)
                row = {
                    "easing": easing_name,
                    "amplitude": round(amp, 3) if amp is not None else None,
                    "rms": round(float(rms), 4) if isinstance(rms, (int, float)) else None,
                    "window": [float(v) for v in win] if win else None,
                    "confidence": "high" if best.get("certified") else "low",
                    "source_channel": ch,
                }
                # keep the strongest reading when two movers share an axis
                if axis not in channels or _better(row, channels[axis]):
                    channels[axis] = row
    else:
        # klass == "time": web_flipbook / *_flipbook. channels live under
        # payload["recovery"]["channels"] (web/flutter/ios) or top-level
        # payload["channels"] (the raw analyze_frames / recover_from_video dict).
        src = payload.get("recovery") or payload
        for ch, entry in (src.get("channels") or {}).items():
            if not entry.get("easing"):
                continue
            amp = entry.get("amp")
            try:
                amp_val = abs(float(amp)) if amp is not None else (
                    float(entry["to"]) - float(entry["from"]))
            except (KeyError, TypeError, ValueError):
                continue
            rms = entry.get("rms")
            axis = axis_for_channel(ch)
            row = {
                "easing": entry.get("easing"),
                "amplitude": round(amp_val, 3),
                "rms": round(float(rms), 4) if isinstance(rms, (int, float)) else None,
                "window": None,  # time klass has no scroll window; t0/D unknown
                "confidence": "high" if entry.get("reliable") else "low",
                "source_channel": ch,
            }
            if axis not in channels or _better(row, channels[axis]):
                channels[axis] = row

    summary["channels"] = channels
    return summary


def _better(a: dict[str, Any], b: dict[str, Any]) -> bool:
    """True when summary-row a is a stronger reading than b (higher confidence,
    then lower rms). Used to pick the best mover per axis."""
    ca = 1 if a.get("confidence") == "high" else 0
    cb = 1 if b.get("confidence") == "high" else 0
    if ca != cb:
        return ca > cb
    ra = a.get("rms") if isinstance(a.get("rms"), (int, float)) else 9.99
    rb = b.get("rms") if isinstance(b.get("rms"), (int, float)) else 9.99
    return ra < rb


# ─── CLI ─────────────────────────────────────────────────────────────────────

def main() -> int:
    """motion_adapter — convert web_anim / web_flipbook JSON → motion.json contract rows.

    Usage:
        motion_adapter.py [--anim anim.json] [--flipbook fb.json]
                          [--flipbook-anchor FLOAT] [--keep-uncertified]
                          --out motion.json
    """
    ap = argparse.ArgumentParser(
        prog="motion_adapter.py",
        description="Convert web_anim/web_flipbook raw output to motion.json contract rows.",
    )
    ap.add_argument("--anim", metavar="FILE", help="web_anim JSON output file")
    ap.add_argument("--flipbook", metavar="FILE", help="web_flipbook JSON output file")
    ap.add_argument(
        "--flipbook-anchor", metavar="FLOAT", type=float,
        help="REST page-y of the flipbook element (required with --flipbook)",
    )
    ap.add_argument(
        "--keep-uncertified", action="store_true",
        help="Include uncertified web_anim entries (default: skip)",
    )
    ap.add_argument("--out", metavar="FILE", required=True, help="Output motion.json path")
    args = ap.parse_args()

    if not args.anim and not args.flipbook:
        die("at least one of --anim or --flipbook is required")

    if args.flipbook and args.flipbook_anchor is None:
        die("--flipbook requires --flipbook-anchor FLOAT")

    anim_rows: list[dict[str, Any]] = []
    if args.anim:
        with open(args.anim) as f:
            anim_out = json.load(f)
        anim_rows = adapt_web_anim(anim_out, certified_only=not args.keep_uncertified)

    fb_rows: list[dict[str, Any]] = []
    if args.flipbook:
        with open(args.flipbook) as f:
            fb_out = json.load(f)
        fb_rows = adapt_flipbook(fb_out, args.flipbook_anchor)

    rows = combine(anim_rows, fb_rows)

    with open(args.out, "w") as f:
        json.dump(rows, f, indent=2)

    emit_json({
        "ok": True,
        "rows": len(rows),
        "anim_rows": len(anim_rows),
        "flipbook_rows": len(fb_rows),
        "out": args.out,
    })
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
