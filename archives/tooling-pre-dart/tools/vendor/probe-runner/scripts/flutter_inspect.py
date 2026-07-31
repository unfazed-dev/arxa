#!/usr/bin/env python3
"""One-command Flutter verification: snapshot + tree + (optional) golden diff.

Composes existing verbs so a verification pass is a single call instead of three
manual steps with eyeballed pixel-math. Emits a compact JSON bundle:

  - screenshot: path to the device screenshot (ios_shot / adb_shot)
  - nodes: a FILTERED widget subtree (text/type/key/rect) — the "semantic-ish"
           snapshot an agent reasons over, far cheaper than raw pixels. Filter by
           --type / --text to keep it small (e.g. only AdaptiveButton + Text).
  - pixdiff: vs a --golden PNG if given (SSIM, 0=identical)
  - flagged: widgets whose rect is off-screen (y beyond viewport) or whose
             `enabled` is false — the common "why does it look broken" answers.

Usage:
  flutter_inspect.py --target ios
  flutter_inspect.py --target ios --type AdaptiveButton,Text --golden baseline.png
  flutter_inspect.py --target adb --text "Send code"
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
from _flutter import VMLib


def _shot(target: str, outdir: str) -> tuple[str | None, str | None]:
    """Capture a screenshot via ios_shot/adb_shot; return (path, error).

    On failure the child's stderr/stdout is returned in `error` — a bare None
    surfaced as `screenshot: null` with no reason (the swallowed-stderr bug)."""
    script = Path(__file__).with_name("ios_shot.py" if target == "ios" else "adb_shot.py")
    try:
        r = subprocess.run(["python3", str(script)], capture_output=True, text=True, timeout=30)
    except Exception as e:
        return None, f"{script.name} failed to run: {e}"
    if r.returncode != 0:
        err = (r.stderr or r.stdout or "").strip()
        return None, f"{script.name} rc={r.returncode}: {err or '(no output)'}"
    # the shot scripts print the saved path to stderr (emit_json) — find it
    import re
    m = re.search(r"(/[^\s\"]+\.png)", r.stdout + r.stderr)
    if not m:
        return None, f"{script.name} rc=0 but no .png path in output"
    return m.group(1), None


def _filtered_nodes(types: list[str] | None, text_substr: str | None) -> list[dict]:
    """Walk the widget tree over the VM; return nodes matching type/text with their
    screen rects. This is the compact "semantic snapshot" — text + role + bbox +
    enabled/label, the fields an agent reasons over. Filtered to keep it small."""
    type_pred = ""
    if types:
        type_pred = "||".join('rt=="%s"' % t.strip() for t in types)
    # Build a closure that collects matching widgets with rect + a few useful fields.
    pred = type_pred or 'true'  # if no type filter, match everything with a RenderBox
    text_clause = ('lbl.contains("%s")' % text_substr) if text_substr else None
    full_pred = pred if not text_clause else "(%s) && %s" % (pred, text_clause)
    expr = (
        '(() {'
        ' var rows=<String>[];'
        ' void w(Element e) {'
        '  var rt=e.widget.runtimeType.toString();'
        '  var key=(e.widget.key?.toString()??"");'
        '  var lbl="";'
        '  try{lbl=(e.widget as dynamic).label.toString();}catch(_){}'
        '  try{ if(lbl.isEmpty) lbl=(e.widget as dynamic).data.toString(); }catch(_){}'
        '  if(%(pred)s) {' % {"pred": full_pred}
        + '   var ro=e.renderObject;'
        '   if(ro is RenderBox){'
        '    var o=ro.localToGlobal(Offset.zero); var s=ro.size;'
        '    var en=""; try{en=(e.widget as dynamic).enabled.toString();}catch(_){}'
        '    rows.add(rt+"\\x1f"+key+"\\x1f"+lbl+"\\x1f"+o.dx.toString()+"\\x1f"+o.dy.toString()'
        '      +"\\x1f"+s.width.toString()+"\\x1f"+s.height.toString()+"\\x1f"+en);'
        '   }'
        '  }'
        '  e.visitChildren((c)=>w(c));'
        ' }'
        ' var r=WidgetsBinding.instance.rootElement;'
        ' if(r!=null) w(r);'
        ' return rows.join("\\x1e");'
        '})()'
    )
    try:
        raw = VMLib().ev(expr)
    except Exception as e:
        return [{"error": str(e)}]
    if not raw or raw == "":
        return []
    nodes = []
    for row in raw.split("\x1e"):
        f = row.split("\x1f")
        if len(f) < 8:
            continue
        try:
            x, y, w, h = (float(p) for p in f[3:7])
        except ValueError:
            continue
        nodes.append({
            "type": f[0], "key": f[1], "label": f[2],
            "rect": {"x": x, "y": y, "w": w, "h": h},
            "enabled": f[7] if f[7] else None,
        })
    return nodes


def _pixdiff(a: str, b: str) -> dict | None:
    pd = Path(__file__).with_name("pixdiff.py")
    try:
        r = subprocess.run(["python3", str(pd), a, b], capture_output=True, text=True, timeout=60)
    except Exception as e:
        # a timeout/spawn failure must not surface as a silent `pixdiff: null`
        return {"error": f"pixdiff.py failed to run: {e}"}
    if r.returncode != 0:
        return {"error": r.stderr.strip() or f"pixdiff.py rc={r.returncode} (no stderr)"}
    try:
        return json.loads(r.stdout)
    except Exception:
        return {"raw": r.stdout.strip()}


def _device_pixel_ratio() -> float:
    """The app's devicePixelRatio via the VM (logical-px → screenshot-px scale).
    Flutter rects (localToGlobal/size) are in LOGICAL px; ios_shot/adb_shot capture
    PHYSICAL px. Without this scale a rect sampled on the screenshot lands in the
    wrong place — the coordinate-space bug. Cached per process."""
    try:
        raw = VMLib().ev(
            'WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio.toString()')
        return float(raw)
    except Exception:
        return 3.0  # iPhone default; see color_assert._device_pixel_ratio for the rationale


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--target", choices=["ios", "adb"], required=True)
    p.add_argument("--type", help="comma-sep widget types to include (AdaptiveButton,Text)")
    p.add_argument("--text", help="only nodes whose label/text contains this")
    p.add_argument("--golden", help="golden PNG to diff the screenshot against (SSIM)")
    args = p.parse_args()

    import os
    outdir = os.environ.get("PROBE_RUNNER_OUTDIR", "/tmp/probe-runner")
    shot, shot_err = _shot(args.target, outdir)
    # Attach to the TARGET device's VM (not the global cache, which may hold a
    # different device's URL — sampling one device's tree against another's shot
    # is the multi-device mismatch bug).
    from _flutter import with_target_url
    with with_target_url(args.target):
        dpr = _device_pixel_ratio()
        types = args.type.split(",") if args.type else None
        nodes = _filtered_nodes(types, args.text)
        # logical-px viewport height from the VM (not hardcoded 874) so the
        # off-screen check is right on every device.
        try:
            vh = float(VMLib().ev(
                'WidgetsBinding.instance.platformDispatcher.views.first.physicalSize.height.toString()')) / dpr
        except Exception:
            vh = 844.0
    # Each node carries rect in BOTH spaces: `rect` = logical px (the Flutter
    # coordinate space, what localToGlobal returns) and `rect_px` = physical px
    # (the screenshot coordinate space, what color_assert/pixdiff region crops need).
    # Without rect_px, sampling a node's region on the screenshot misses — the
    # coordinate-space bug. dpr is echoed so a consumer can re-derive either space.
    for n in nodes:
        r = n.get("rect")
        if r:
            n["rect_px"] = {
                "x": int(round(r["x"] * dpr)), "y": int(round(r["y"] * dpr)),
                "w": int(round(r["w"] * dpr)), "h": int(round(r["h"] * dpr))}
    diff = _pixdiff(shot, args.golden) if (shot and args.golden) else None

    # flag off-screen + disabled (the common "looks broken" answers).
    flagged = []
    for n in nodes:
        r = n.get("rect", {})
        if r.get("y", 0) > vh or r.get("y", 0) < 0:
            flagged.append({"node": n, "reason": "off_screen"})
        elif n.get("enabled") == "false":
            flagged.append({"node": n, "reason": "disabled"})

    emit_json({"target": args.target, "screenshot": shot, "screenshot_error": shot_err,
               "dpr": dpr,
               "viewport_h": vh, "nodes": nodes,
               "node_count": len(nodes), "pixdiff": diff, "flagged": flagged})
    return 0


if __name__ == "__main__":
    sys.exit(main())
