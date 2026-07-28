#!/usr/bin/env python3
"""Measure scroll-driven animation easing in a Flutter app with CERTIFIED
determinism — the Dart-VM-service sibling of `web_anim.py`.

The web probe's 100% confidence rests on two primitives: set an *exact* scroll
offset, and read the *exact* rendered transform. Flutter exposes both — but not
through DOM. This tool drives them over the VM service:

  set scroll : ScrollableState.position.jumpTo(offset)  (no physics → instant)
  read xform : RenderObject.getTransformTo(null) → Matrix4 (transform-to-root)

Samples feed the SAME engine-agnostic certification core as web_anim
(`_anim_core`): an easing fit is emitted only when the offset held, the value
reproduces on revisit, the curve is monotonic, and it matches a standard easing.

────────────────────────────────────────────────────────────────────────────
HOW IT BINDS (and why): the Flutter inspector's `valueId` is NOT a valid VM
`evaluate` targetId (the VM rejects it with error 113). So we do NOT use the
inspector at all. Instead we evaluate self-contained Dart *expressions* against
the root library (`getIsolate().rootLib.id`, always a valid targetId). The root
library imports flutter material, so `WidgetsBinding`, `Element`,
`ScrollableState`, `RenderObject` and `Matrix4` are all in scope. Each
expression is an immediately-invoked closure that walks
`WidgetsBinding.instance.rootElement` to locate the Scrollable / target widget.

VERIFIED end-to-end against Flutter 3.44.0 (macOS desktop) on 2026-05-28 with a
known easeOutQuad parallax: jumpTo set pixels exactly, getTransformTo read the
moving child's transform-to-root exactly, and the core certified easeOutQuad
(rms ≈ 0.01). The only Flutter-version assumptions are public, stable API
names (`rootElement`, `visitChildren`, `ScrollableState`, `getTransformTo`);
if a walk fails on another version the failing expression is printed.

NOTE: target the widget that *visually moves* (the content), not a Transform
wrapper above it — `getTransformTo` on a RenderTransform itself excludes the
translate it applies to its child.
────────────────────────────────────────────────────────────────────────────

Usage:
  flutter_attach.py --url http://127.0.0.1:PORT/      # cache the VM service URL
  flutter_anim.py --key hero                          # measure the keyed widget
  flutter_anim.py --type MyParallaxHeader --range 0:1400 --steps 28
  flutter_anim.py --self-test                         # verify the core offline
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_path, emit_json, out_path
from _anim_core import vecs_close, analyze_movers
from motion_adapter import motion_summary


# ---- VM-service evaluate expressions (library-scoped; see module docstring) ----

def _scroll_expr(action: str) -> str:
    """Walk to the first ScrollableState, then run `action` (which must `return`
    a String). Returns "NO_SCROLLABLE" if none found."""
    return ("(() { ScrollableState? s; "
            "void rec(Element e){ if(s!=null) return; "
            "if(e is StatefulElement && e.state is ScrollableState){ "
            "s = e.state as ScrollableState; return; } "
            "e.visitChildren(rec); } "
            "rec(WidgetsBinding.instance.rootElement!); "
            "if(s==null) return \"NO_SCROLLABLE\"; " + action + " })()")


def _jump_expr(y) -> str:
    return _scroll_expr("s!.position.jumpTo(%r); return s!.position.pixels.toString();"
                        % float(y))


def _pixels_expr() -> str:
    return _scroll_expr("return s!.position.pixels.toString();")


def _max_expr() -> str:
    return _scroll_expr("return s!.position.maxScrollExtent.toString();")


def _xform_expr(pred: str) -> str:
    """Walk to the first element matching `pred` whose renderObject is non-null,
    return its transform-to-root as a 16-float CSV. "NO_TARGET" if none."""
    return ("(() { RenderObject? ro; "
            "void rec(Element e){ if(ro!=null) return; "
            "if((" + pred + ") && e.renderObject!=null){ ro = e.renderObject; return; } "
            "e.visitChildren(rec); } "
            "rec(WidgetsBinding.instance.rootElement!); "
            "if(ro==null) return \"NO_TARGET\"; "
            "return ro!.getTransformTo(null).storage.map((d)=>d.toString()).join(\",\"); })()")


def _predicate(args) -> str:
    """Build a Dart bool predicate over `Element e` from --key/--type/--text."""
    parts = []
    for val, tmpl in (
        (args.key, "(e.widget.key?.toString() ?? \"\").contains('%s')"),
        (args.type, "e.widget.runtimeType.toString().contains('%s')"),
        (args.text, "e.widget.toString().contains('%s')"),
    ):
        if val:
            if "'" in val or "\\" in val:
                die("selector may not contain quotes or backslashes: %r" % val)
            parts.append(tmpl % val)
    if not parts:
        die("pass --type, --key, or --text to locate the moving widget (or --self-test)")
    return " && ".join(parts)


def _decompose(storage):
    """Matrix4 column-major storage[16] -> [tx,ty,sx,sy,rot,op]. op fixed 1.0
    (opacity needs a RenderOpacity ancestor walk — deferred to v2)."""
    m = storage
    tx, ty = m[12], m[13]
    sx = math.hypot(m[0], m[1])
    sy = math.hypot(m[4], m[5])
    rot = math.atan2(m[1], m[0]) * 180.0 / math.pi
    return [round(tx, 3), round(ty, 3), round(sx, 4), round(sy, 4), round(rot, 3), 1.0]


# ---------------- live VM path ----------------
# The root-library eval bridge (`VMLib`) lives in `_flutter`, shared verbatim
# with `flutter_eval`. It imports cleanly without a live VM (websocket import is
# lazy inside `rpc`), so `--self-test` below stays dependency-free.
from _flutter import VMLib


_RECIPE = (
    "VALIDATION RECIPE:\n"
    "  1. flutter run -d <device> --disable-service-auth-codes\n"
    "  2. flutter_attach.py --url http://127.0.0.1:<PORT>/   (from the run output)\n"
    "  3. flutter_anim.py --key <YourMovingWidgetKey>   (or --type / --text)\n"
    "This tool evaluates expressions against the root library and walks\n"
    "WidgetsBinding.instance.rootElement. If a walk/cast fails on your Flutter\n"
    "version the failing expression is printed above — adjust the API names in\n"
    "_scroll_expr/_xform_expr (e.g. rootElement, ScrollableState, getTransformTo).")


def _read_settled(lib, pred, y, tol, timeout, poll=0.05):
    """Jump to y, poll until pixels==y AND transform stops changing between reads."""
    px0 = lib.ev(_jump_expr(y))
    if px0 == "NO_SCROLLABLE":
        die("no Scrollable found in the widget tree (is the app scrollable?).\n" + _RECIPE)
    end = time.monotonic() + timeout
    prev = None
    while True:
        cur = lib.ev(_pixels_expr())
        if cur == "NO_SCROLLABLE":
            die("no Scrollable found in the widget tree.\n" + _RECIPE)
        px = float(cur)
        raw = lib.ev(_xform_expr(pred))
        if raw == "NO_TARGET":
            die("target widget not found in the tree (check --key/--type/--text).\n" + _RECIPE)
        vec = _decompose([float(x) for x in raw.split(",")])
        ok_y = abs(px - y) <= tol
        if ok_y and prev is not None and vecs_close([vec], [prev]):
            return px, vec, True
        prev = vec
        if time.monotonic() > end:
            return px, vec, ok_y
        time.sleep(poll)


def _run_live(args):
    pred = _predicate(args)
    try:
        lib = VMLib()
    except Exception as e:
        die("no Flutter VM service. run flutter_attach.py first. (%s)\n%s" % (e, _RECIPE))

    try:
        if args.range:
            lo, hi = (int(x) for x in args.range.split(":"))
        else:
            mx = lib.ev(_max_expr())
            if mx == "NO_SCROLLABLE":
                die("no Scrollable found in the widget tree.\n" + _RECIPE)
            lo, hi = 0, int(float(mx))
        if hi <= lo:
            die("empty scroll range %d:%d (maxScrollExtent too small?)" % (lo, hi))
        settle = args.settle / 1000.0
        step_ys = [round(lo + (hi - lo) * i / (args.steps - 1)) for i in range(args.steps)]
        mid_idx = len(step_ys) // 2

        rows_m, max_drift, unsettled = [], 0.0, 0
        for y in step_ys:
            px, vec, settled = _read_settled(lib, pred, y, args.tol, settle)
            max_drift = max(max_drift, abs(px - y))
            if not settled:
                unsettled += 1
            rows_m.append([vec])
        mid_vec = rows_m[mid_idx][0]
        _rpx, rvec, _ = _read_settled(lib, pred, step_ys[mid_idx], args.tol, settle)
    except Exception as e:
        die("VM eval failed (expression below is Flutter-version sensitive): %s\n%s"
            % (e, _RECIPE))

    drift_ok = max_drift <= args.tol and unsettled == 0
    movers = [{"sel": args.key or args.type or args.text, "txt": "", "rank": 0}]
    out_movers = analyze_movers(movers, step_ys, rows_m, [mid_vec], [rvec],
                                mid_idx, drift_ok, max_drift, unsettled)

    payload = {"engine": "flutter", "device": "vm-service",
               "scrollRange": [lo, hi], "steps": args.steps,
               "certifiedDeterministic": drift_ok, "maxDriftPx": round(max_drift, 2),
               "movers": out_movers,
               "series": {"scrollY": step_ys,
                          "perMover": [[r[0] for r in rows_m]]},
               # consistent per-axis best-reading block (klass="scroll"). Same
               # contract as web_anim; see motion_adapter.motion_summary.
               "motion_summary": motion_summary({"movers": out_movers}, "scroll")}
    out = Path(args.out) if args.out else out_path("flutter-anim", "json")
    out.write_text(json.dumps(payload, indent=2, ensure_ascii=False))
    _print_summary(payload)
    emit_path(out)
    return 0


def _print_summary(payload):
    print("engine: %s (%s)" % (payload["engine"], payload["device"]))
    print("certified-deterministic: %s (maxDrift %.2fpx)" %
          (payload["certifiedDeterministic"], payload["maxDriftPx"]))
    for m in payload["movers"]:
        print("  [%s] dominant=%s" % (m.get("sel"), m.get("dominant")))
        for c, e in m["channels"].items():
            ez = e.get("easing")
            if e["certified"]:
                tag = "%s rms=%.3f  CERTIFIED" % (ez["name"], ez["rms"])
            elif ez:
                tag = "%s rms=%.3f  UNCERTIFIED: %s" % (ez["name"], ez["rms"], e.get("reason", ""))
            else:
                tag = "UNCERTIFIED: " + e.get("reason", "")
            print("    %-3s %s→%s  %s" % (c, e["from"], e["to"], tag))


def _self_test():
    """Verify the certification core on a synthetic ease-out scroll→ty curve,
    and that a time-based (scroll-independent) channel is refused. No VM needed."""
    import random
    ys = [round(1400 * i / 27) for i in range(28)]
    mid = len(ys) // 2

    def ease_out(p):  # cubic-bezier(0,0,.58,1) approx via the same fit basis
        return 1 - (1 - p) ** 1.8

    rows_m = []
    for y in ys:
        p = y / 1400
        ty = -700.0 * ease_out(p)
        rows_m.append([[0.0, round(ty, 3), 1.0, 1.0, 0.0, 1.0]])
    mid_vec = rows_m[mid][0]
    revisit = [list(mid_vec)]  # exact reproduction → scrubbed
    movers = [{"sel": "SyntheticEaseOut", "txt": "", "rank": 0}]
    out = analyze_movers(movers, ys, rows_m, [mid_vec], revisit, mid, True, 0.0, 0)
    ty_e = out[0]["channels"].get("ty", {})
    scrubbed_ok = ty_e.get("certified") is True

    # time-based: ty jitters independent of scroll; revisit differs a lot
    rows_t = [[[0.0, round(random.uniform(-50, 50), 3), 1.0, 1.0, 0.0, 1.0]] for _ in ys]
    out_t = analyze_movers(movers, ys, rows_t, [rows_t[mid][0]],
                           [[0.0, rows_t[mid][0][1] + 80.0, 1.0, 1.0, 0.0, 1.0]],
                           mid, True, 0.0, 0)
    tb = out_t[0]["channels"].get("ty", {})
    timebased_refused = tb.get("certified") is False

    ok = scrubbed_ok and timebased_refused
    emit_json({"self_test": "pass" if ok else "FAIL",
               "scrubbed_certified": scrubbed_ok,
               "scrubbed_easing": ty_e.get("easing", {}).get("name"),
               "scrubbed_rms": ty_e.get("easing", {}).get("rms"),
               "timebased_refused": timebased_refused,
               "timebased_reason": tb.get("reason"),
               "decompose_check": _decompose(
                   [2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 1, 0, 12, 34, 0, 1])})
    return 0 if ok else 1


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--type", help="widget type to measure (e.g. MyParallaxHeader)")
    p.add_argument("--key", help="widget key fragment (e.g. 'hero' matches Key('hero'))")
    p.add_argument("--text", help="widget toString fragment")
    p.add_argument("--range", help="scroll range 'lo:hi' px (default 0:maxScrollExtent)")
    p.add_argument("--steps", type=int, default=24)
    p.add_argument("--settle", type=int, default=600, help="ms convergence timeout per step")
    p.add_argument("--tol", type=float, default=2.0, help="max |pixels-target| px to certify")
    p.add_argument("--out", help="output JSON path")
    p.add_argument("--self-test", action="store_true", dest="self_test",
                   help="verify the certification core offline (no VM needed)")
    args = p.parse_args()

    if args.self_test:
        return _self_test()
    if not any([args.type, args.key, args.text]):
        die("pass --type, --key, or --text to locate the moving widget (or --self-test)")
    return _run_live(args)


if __name__ == "__main__":
    sys.exit(main())
