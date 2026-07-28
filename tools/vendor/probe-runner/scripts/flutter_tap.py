#!/usr/bin/env python3
"""Tap a Flutter widget located by key/type/text.

For mobile sims/emu, after VM service resolves the widget's
bounding rect we delegate the physical tap to `ios_tap.py` or
`adb_tap.py` depending on environment.

For `macos` and `web` targets the Flutter inspector RPC does not expose
transform-to-root for a widget, so absolute tap coords cannot be
synthesised from the inspector tree alone. These targets are reported
as an honest-gap (rc=2) with a fallback hint pointing at the
semantics-tree path (enable `flutter_semantics`, then locate via
`ax_tree`/`web_dom --selector flt-semantics` and dispatch
`click.py`/`web_click.py`).

Usage:
  flutter_tap.py --target ios|adb|macos|web [--key X | --type T | --text S]
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
from _flutter import first_isolate, rpc


_SIZE_RE = re.compile(r"Size\(([\d.]+),\s*([\d.]+)\)")


def _walk_for_size(n: dict) -> tuple[float, float] | None:
    """Look for a serialised `Size(w, h)` in any property/description.

    The Flutter inspector exposes `RenderObject.size` as a `DiagnosticsNode`
    whose `description` is the string `"Size(w, h)"`. We recurse so the first
    render-object descendant of the target widget wins.
    """
    desc = n.get("description") or ""
    m = _SIZE_RE.search(desc)
    if m:
        return (float(m.group(1)), float(m.group(2)))
    for prop in (n.get("properties") or []):
        r = _walk_for_size(prop)
        if r:
            return r
    for c in (n.get("children") or []):
        r = _walk_for_size(c)
        if r:
            return r
    return None


def _render_size(node: dict) -> tuple[float, float] | None:
    """Best-effort: return the widget's render-box size (w, h), or None.

    Calls `ext.flutter.inspector.getLayoutExplorerNode`. Its payload exposes
    the size two ways:
    - a structured top-level `size: {"width": "56.0", "height": "56.0"}` dict,
    - the RenderObject's `properties[]` carrying a `Size(w, h)` description.
    Prefer the structured dict; fall back to the property walk.

    Used purely to discriminate two failure modes for the caller's warning:
    - size resolved → widget exists in the render tree but transform-to-root
      is not exposed by the inspector RPC surface, so absolute tap coords
      cannot be synthesised.
    - size None → widget either has no render box yet (off-screen, not laid
      out) or the inspector returned nothing useful.
    """
    val = node.get("valueId")
    if not val:
        return None
    try:
        lay = rpc(
            "ext.flutter.inspector.getLayoutExplorerNode",
            {"groupName": "probe-runner", "id": val, "subtreeDepth": 1},
            isolate=first_isolate(),
        )
    except Exception:
        return None
    body = (lay or {}).get("result") if isinstance((lay or {}).get("result"), dict) else lay
    body = body or {}

    sd = body.get("size")
    if isinstance(sd, dict):
        try:
            w = float(sd.get("width"))
            h = float(sd.get("height"))
            if w > 0 and h > 0:
                return (w, h)
        except (TypeError, ValueError):
            pass

    ro = body.get("renderObject") or {}
    sz = _walk_for_size(ro)
    if not sz or sz[0] <= 0 or sz[1] <= 0:
        return None
    return sz


def _rect_via_vm(key: str | None, type_: str | None, text: str | None):
    """Locate the FIRST widget matching key/type/text and return its screen rect
    (x, y, w, h) in logical points, by walking the element tree over the Dart VM
    service and reading localToGlobal + size.

    This is the reliable rect source: the inspector RPC (getLayoutExplorerNode)
    exposes size but NOT transform-to-root, so it can't synthesise tap coords. The
    tree-walk eval (proven in flutter_skeleton) reads BOTH. The match predicate
    checks the widget's runtimeType, Key.toString(), and — for Text/widgets whose
    description carries it — the rendered label. Returns None if no match lays out.
    """
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _flutter import VMLib
    # One closure: walk every Element, test the predicate, return the first match's
    # rect. Matches on: type name (widgetRuntimeType), key, or a label/text field.
    # try/catch around dynamic field reads so a widget lacking .label/.text doesn't
    # abort the walk. Multi-line is fine — _flutter.ev collapses newlines (sdk#41671).
    pred_parts = []
    if type_:
        pred_parts.append('rt=="%s"' % type_)
    if key:
        pred_parts.append('key.contains("%s")' % key)
    if text:
        pred_parts.append('lbl.contains("%s")' % text)
    pred = "||".join(pred_parts) if pred_parts else "false"
    expr = (
        '(() {'
        ' var out="none";'
        ' void w(Element e) {'
        ' var wgt=e.widget;'
        ' if(wgt is Offstage && wgt.offstage) return;'
        ' if(wgt is Visibility && !wgt.visible) return;'
        ' var rt=wgt.runtimeType.toString();'
        ' var key=(wgt.key?.toString()??"");'
        ' var lbl="";'
        ' try{lbl=(wgt as dynamic).label.toString();}catch(_){}'
        ' try{ if(lbl.isEmpty) lbl=(wgt as dynamic).data.toString(); }catch(_){}'
        ' if(%s){'
        ' var ro=e.renderObject;'
        ' if(ro is RenderBox){'
        ' var o=ro.localToGlobal(Offset.zero); var s=ro.size;'
        ' out=o.dx.toString()+","+o.dy.toString()+","+s.width.toString()+","+s.height.toString();'
        ' return;'
        ' }'
        ' }'
        ' if(wgt is IndexedStack){'
        ' var kids=<Element>[]; e.visitChildren((c)=>kids.add(c));'
        ' var idx=wgt.index;'
        ' if(idx!=null && idx<kids.length) w(kids[idx]);'
        ' return;'
        ' }'
        ' e.visitChildren((c)=>w(c));'
        ' }'
        ' var r=WidgetsBinding.instance.rootElement;'
        ' if(r!=null) w(r);'
        ' return out;'
        '})()' % pred
    )
    try:
        val = VMLib().ev(expr)
    except Exception:
        return None
    if not val or val == "none":
        return None
    try:
        x, y, w, h = (float(p) for p in val.split(","))
        if w > 0 and h > 0:
            return (x, y, w, h)
    except (ValueError, TypeError):
        return None
    return None


_FALLBACK_HINT = {
    "ios": (
        "enumerate real widgets with flutter_tree.py / flutter_inspect.py, or "
        "screenshot via flutter_shot.py --allow-device-fallback and dispatch "
        "ios_tap.py <x> <y> by coordinates (native platform-view content is "
        "invisible to the widget tree)."
    ),
    "adb": (
        "enumerate real widgets with flutter_tree.py / flutter_inspect.py, or "
        "screenshot via flutter_shot.py --allow-device-fallback and dispatch "
        "adb_tap.py <x> <y> by coordinates (native platform-view content is "
        "invisible to the widget tree)."
    ),
    "macos": (
        "fall back to flutter_semantics.py enable + ax_tree.py against the "
        "Flutter macOS app window, then dispatch click.py <x> <y> (Quartz). "
        "shot.py <app-owner> can help locate the widget visually."
    ),
    "web": (
        "fall back to flutter_semantics.py enable + web_dom.py "
        "--selector 'flt-semantics' (or web_a11y.py) to locate the "
        "widget's semantic node, then web_click.py --selector against "
        "that node."
    ),
}


def _fallback_commands(target: str, key: str | None, type_: str | None,
                       text: str | None) -> list[str] | None:
    """Concrete, runnable command sequence for the fallback paths: the
    semantics+host-click sequence when macos/web tap synthesis is impossible
    (rc=2), and the locate-then-tap-by-coordinates sequence for ios/adb when a
    selector cannot resolve (no match, or a matched widget with no render box).
    One line per step so an operator or agent can run them directly. The
    selector token is the best available locator from what the caller passed."""
    sel = key or type_ or text or "<widget-locator>"
    if target == "web":
        return [
            "python3 scripts/flutter_semantics.py enable",
            f"# locate the flt-semantics node for {sel!r}:",
            "python3 scripts/web_dom.py --selector 'flt-semantics'",
            f"python3 scripts/web_click.py --selector 'flt-semantics'   # or a tighter selector",
        ]
    if target == "macos":
        return [
            "python3 scripts/flutter_semantics.py enable",
            "# owner = the Flutter macOS app's window-owner name (e.g. 'app'):",
            "python3 scripts/ax_tree.py <app-owner>",
            "# read the AX frame for the matched semantics node, then:",
            "python3 scripts/click.py <x> <y>",
        ]
    if target in ("ios", "adb"):
        tap_verb = "ios_tap.py" if target == "ios" else "adb_tap.py"
        return [
            "# enumerate the widgets actually in the tree (keys/types/labels):",
            "python3 scripts/flutter_tree.py   # or: flutter_inspect.py",
            "# native platform-view content is invisible to the widget tree —",
            "# screenshot the device and tap by coordinates instead:",
            "python3 scripts/flutter_shot.py --allow-device-fallback",
            f"python3 scripts/{tap_verb} <x> <y>",
        ]
    return None  # unreachable: --target is argparse-constrained to the 4 above


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--target", choices=["ios", "adb", "macos", "web"], required=True)
    p.add_argument("--key"); p.add_argument("--type"); p.add_argument("--text")
    args = p.parse_args()

    find = Path(__file__).with_name("flutter_find.py")
    cmd = ["python3", str(find)]
    if args.key: cmd += ["--key", args.key]
    if args.type: cmd += ["--type", args.type]
    if args.text: cmd += ["--text", args.text]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        die(r.stderr.strip() or f"flutter_find exited {r.returncode}")
    import json as _j
    res = _j.loads(r.stdout)
    if res.get("count", 0) == 0:
        tried = ", ".join(
            f"--{k} {v!r}" for k, v in
            (("key", args.key), ("type", args.type), ("text", args.text)) if v)
        cmds = _fallback_commands(args.target, args.key, args.type, args.text)
        die(
            f"no widget matched selector(s): {tried or '(none passed)'}. "
            "Note: content rendered by a native platform view (e.g. a kit's "
            "KitNativeButton label) is NOT a Text widget in the Flutter "
            "element tree, so --text can never match it — locate by --key or "
            "--type instead, or tap by coordinates. Next steps:\n  "
            + "\n  ".join(cmds or []))

    node = res["matches"][0]
    # PRIMARY: resolve the rect via the VM tree-walk (localToGlobal + size). This is
    # the reliable tap-coordinate source — the inspector RPC gives size but not position.
    rect = _rect_via_vm(args.key, args.type, args.text)

    # Dispatch a physical tap for mobile targets now that we have the rect.
    if rect and args.target in ("ios", "adb"):
        x = rect[0] + rect[2] / 2.0
        y = rect[1] + rect[3] / 2.0
        tap_script = Path(__file__).with_name(
            "ios_tap.py" if args.target == "ios" else "adb_tap.py")
        tr = subprocess.run(["python3", str(tap_script), str(x), str(y)],
                            capture_output=True, text=True)
        payload = {"target": args.target, "matched": node, "rect": list(rect),
                   "tapped": [x, y], "tap_rc": tr.returncode,
                   "tap_stdout": tr.stdout.strip() or None,
                   "tap_stderr": tr.stderr.strip() or None}
        if tr.returncode != 0:
            cause = ("idb companion not connected for the booted simulator"
                     if args.target == "ios" else
                     "no adb device connected/authorized — check `adb devices`")
            payload["tap_error"] = (f"{tap_script.name} failed — see tap_stderr; "
                                    f"common cause: {cause}")
        emit_json(payload)
        return 0 if tr.returncode == 0 else 3

    # macos/web cannot synthesise taps (no transform-to-root from the inspector RPC);
    # surface the concrete fallback command sequence so the operator/agent can run the
    # semantics+host-click path directly. ios/adb only reach here when the matched
    # widget has no render box — their sequence is locate-then-tap-by-coordinates.
    hint = _FALLBACK_HINT[args.target]
    fallback_cmds = _fallback_commands(args.target, args.key, args.type, args.text)
    if rect:
        warning = (
            f"matched widget at rect ({rect[0]:.0f},{rect[1]:.0f},"
            f"{rect[2]:.0f}x{rect[3]:.0f}), but the Flutter inspector RPC surface "
            "does not expose its transform-to-root, so absolute tap coordinates "
            f"cannot be synthesised for {args.target}. {hint}"
        )
    else:
        warning = (
            "matched widget has no render box in the inspector tree "
            "(not laid out, off-screen, or release build). Verify the "
            f"widget is on screen. ({args.target}): {hint}"
        )
    emit_json({"target": args.target, "warning": warning, "matched": node,
               "rect": list(rect) if rect else None,
               "fallback_commands": fallback_cmds})
    # macos/web: rc=2 honest-gap — no transform-to-root from inspector RPC,
    # caller must dispatch the semantics-tree fallback (see _FALLBACK_HINT).
    # ios/adb: rc=0 preserved; caller can still consume `matched`+`render_size`
    # to dispatch ios_tap.py/adb_tap.py with explicit --x --y.
    if args.target in ("macos", "web"):
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
