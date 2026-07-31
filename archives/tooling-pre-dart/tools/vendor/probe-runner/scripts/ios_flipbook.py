#!/usr/bin/env python3
"""ios_flipbook -- frame-based motion recovery for a native iOS app's
time/event animation (tap-triggered translate, entrance), the iOS sibling of
flutter_flipbook / web_flipbook.

A native iOS app has no DOM/WAAPI and no Flutter VM, so the certification input
is a screen RECORDING. The iOS-native introspection oracle is idb's
accessibility tree (`idb ui describe-all`): every visible element reports a
`frame` (logical points). Like Core Animation, that frame jumps to its FINAL
value at animation start (the model layer, not the animating presentation
layer), so it is sampled only at REST and at SETTLE -> a start/end displacement
oracle, exactly the role Flutter VM `getTransformTo` plays for flutter_flipbook.

  1. resolve the tracked element's at-rest frame from `idb ui describe-all`
     (logical points) -> a device-px template region (x*dpr ...);
  2. screen-record (`xcrun simctl io ... recordVideo`) while firing a REAL
     `idb ui tap` on the trigger element;
  3. recover the motion law from the video (_native_flipbook, content-
     independent, t0/D-invariant fit);
  4. re-read the tracked element's frame at settle -> start/end displacement as
     an independent amplitude cross-check.

idb exposes only what an app publishes to accessibility. For an app whose mover
is not an accessibility element (e.g. a bare canvas), pass `--auto` to
auto-locate the region from pixels and `--tap-xy x,y` to fire a literal-point
tap; the idb displacement oracle is then skipped.

Usage:
  ios_flipbook.py --label box --tap-label Increment
  ios_flipbook.py --type Image --tap-type Button --seconds 2.5
  ios_flipbook.py --auto --tap-xy 196,760     # canvas / non-AX mover
"""
from __future__ import annotations

import argparse
import json
import signal
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json, out_path
from _ios import idb_run
from _native_flipbook import recover_from_video


# ---------------- pure logic (unit-tested in test_ios_flipbook.py) ----------

def frame_of(el: dict):
    """(x, y, w, h) in logical points from an idb describe-all element."""
    f = el["frame"]
    return (float(f["x"]), float(f["y"]), float(f["width"]), float(f["height"]))


def find_element(tree, type_=None, label=None, text=None):
    """First element in `tree` whose provided selectors all match (substring)
    and whose frame is non-degenerate. `type_` matches `type`; `label` matches
    `AXLabel`/`title`; `text` matches AXLabel/title/AXValue. None if no match."""
    if not (type_ or label or text):
        raise ValueError("pass --type, --label, or --text to locate an element")
    for el in tree:
        f = el.get("frame") or {}
        if (f.get("width") or 0) <= 0 or (f.get("height") or 0) <= 0:
            continue
        lab = el.get("AXLabel") or ""
        ttl = el.get("title") or ""
        if type_ and type_ not in (el.get("type") or ""):
            continue
        if label and (label not in lab and label not in ttl):
            continue
        if text:
            hay = " ".join((lab, ttl, el.get("AXValue") or ""))
            if text not in hay:
                continue
        return el
    return None


def region_devpx(frame_pts, dpr: float):
    """Logical-point (x,y,w,h) -> integer device-px region for the recording."""
    x, y, w, h = frame_pts
    return (max(0, int(x * dpr)), max(0, int(y * dpr)),
            max(1, int(w * dpr)), max(1, int(h * dpr)))


def displacement(frame0, frame1):
    """Start/end top-left displacement in logical points (the idb oracle)."""
    return {"tx": round(frame1[0] - frame0[0], 2),
            "ty": round(frame1[1] - frame0[1], 2)}


def derive_dpr(screenshot_px_w: float, root_pts_w: float) -> float:
    """iOS scale factor = screenshot pixel width / root view point width,
    snapped to the nearest integer (iOS DPRs are 1/2/3)."""
    if root_pts_w <= 0:
        return 1.0
    return float(round(screenshot_px_w / root_pts_w))


# ---------------- simulator I/O (live-validated, not unit-tested) -----------

def _booted_udid(explicit=None) -> str:
    if explicit:
        return explicit
    r = subprocess.run(["xcrun", "simctl", "list", "devices", "booted"],
                       capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if "Booted" in line and "(" in line:
            # "    Name (UDID) (Booted)"
            parts = [p for p in line.split("(") if ")" in p]
            for p in parts:
                cand = p.split(")")[0].strip()
                if len(cand) >= 32 and "-" in cand:
                    return cand
    die("no booted iOS simulator (boot one: ios_boot.py / xcrun simctl boot)")


def _describe_all(udid: str):
    r = idb_run(["ui", "describe-all", "--udid", udid], capture=True)
    return json.loads(r.stdout)


def _root_point_width(tree) -> float:
    best = 0.0
    for el in tree:
        f = el.get("frame") or {}
        best = max(best, float(f.get("width") or 0))
    return best


def _screenshot_px_width(udid: str, tmp: Path) -> float:
    png = tmp / "ios-fb-shot.png"
    subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", str(png)],
                   check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    from PIL import Image
    with Image.open(png) as im:
        return float(im.width)


def _record_start(udid: str, out: Path):
    # h264 + --force so ffmpeg can split frames (default codec is HEVC)
    cmd = ["xcrun", "simctl", "io", udid, "recordVideo",
           "--codec=h264", "--force", str(out)]
    return subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _record_stop(proc):
    proc.send_signal(signal.SIGINT)
    try:
        proc.wait(timeout=15)
    except subprocess.TimeoutExpired:
        proc.kill()


def _tap(udid: str, x: float, y: float):
    idb_run(["ui", "tap", str(int(x)), str(int(y)), "--udid", udid], capture=True)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--udid", default=None, help="target sim (default: the booted one)")
    p.add_argument("--type"); p.add_argument("--label"); p.add_argument("--text")
    p.add_argument("--auto", action="store_true",
                   help="auto-locate the mover from pixels (non-AX mover); skips the idb oracle")
    p.add_argument("--tap-type"); p.add_argument("--tap-label"); p.add_argument("--tap-text")
    p.add_argument("--tap-xy", help="literal 'x,y' point to tap (when the trigger is not an AX element)")
    p.add_argument("--seconds", type=float, default=2.5, help="record window after the tap")
    p.add_argument("--fps", type=float, default=30)
    p.add_argument("--lead", type=float, default=0.8, help="record spin-up before the tap")
    p.add_argument("--settle", type=float, default=0.8, help="post-record settle before re-reading the frame")
    p.add_argument("--scale", action="store_true")
    p.add_argument("--no-trim", action="store_true")
    p.add_argument("--out", default=None)
    args = p.parse_args()

    udid = _booted_udid(args.udid)
    import tempfile
    tmp = Path(tempfile.mkdtemp(prefix="iosfb-"))

    tree = _describe_all(udid)
    root_w = _root_point_width(tree)
    if root_w < 100:
        die("no foreground app in the accessibility tree (root width %.0fpt); "
            "launch the app before recording" % root_w)
    dpr = derive_dpr(_screenshot_px_width(udid, tmp), root_w)

    frame0 = None
    if args.auto:
        region = None  # _native_flipbook auto-locates
    else:
        el = find_element(tree, args.type, args.label, args.text)
        if el is None:
            die("tracked element not found in the accessibility tree "
                "(check --type/--label/--text, or use --auto for a non-AX mover)")
        frame0 = frame_of(el)
        region = region_devpx(frame0, dpr)

    # resolve trigger tap point (logical points; idb ui tap takes points)
    if args.tap_xy:
        tx, ty = (float(v) for v in args.tap_xy.split(","))
        tap_pt = (tx, ty)
    elif args.tap_type or args.tap_label or args.tap_text:
        tel = find_element(tree, args.tap_type, args.tap_label, args.tap_text)
        if tel is None:
            die("trigger element not found (check --tap-type/--tap-label/--tap-text or --tap-xy)")
        fx, fy, fw, fh = frame_of(tel)
        tap_pt = (fx + fw / 2, fy + fh / 2)
    else:
        die("pass a trigger: --tap-type/--tap-label/--tap-text or --tap-xy")

    out = Path(args.out) if args.out else out_path("ios-flipbook", "mp4")
    proc = _record_start(udid, out)
    time.sleep(args.lead)
    _tap(udid, *tap_pt)
    time.sleep(args.seconds)
    _record_stop(proc)

    # idb displacement oracle: re-read the tracked frame after it settles
    vm_disp = None
    if frame0 is not None:
        time.sleep(args.settle)
        el1 = find_element(_describe_all(udid), args.type, args.label, args.text)
        if el1 is not None:
            vm_disp = displacement(frame0, frame_of(el1))

    rec = recover_from_video(str(out), fps=args.fps, region=region, dpr=dpr,
                             do_scale=args.scale, trim=not args.no_trim,
                             workdir=str(tmp))

    cross = None
    if vm_disp:
        rtx = rec["channels"]["tx"].get("amp") or 0.0
        rty = rec["channels"]["ty"].get("amp") or 0.0
        cross = {"idb_displacement_pts": vm_disp,
                 "recovered_pts": {"tx": rtx, "ty": rty},
                 "tx_match_px": round(abs(rtx - vm_disp["tx"]), 2),
                 "ty_match_px": round(abs(rty - vm_disp["ty"]), 2)}

    emit_json({"engine": "ios", "udid": udid, "video": str(out), "dpr": dpr,
               "region_devpx": list(region) if region else None,
               "tracked": {"type": args.type, "label": args.label, "text": args.text},
               "trigger_pt": list(tap_pt), "recovery": rec,
               "idb_crosscheck": cross})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
