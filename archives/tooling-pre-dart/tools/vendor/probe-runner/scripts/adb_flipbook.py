#!/usr/bin/env python3
"""adb_flipbook -- frame-based motion recovery for a native Android app's
time/event animation (tap-triggered translate, entrance), the Android sibling
of `ios_flipbook` / `flutter_flipbook` / `web_flipbook`.

A native Android app has no DOM/WAAPI and no Flutter VM, so the certification
input is a screen RECORDING. The Android-native introspection oracle is
uiautomator's UI hierarchy dump: every view reports a `bounds` attribute in
DEVICE pixels. Like iOS Core Animation, a View's frame jumps to its FINAL value
at animation start, so it is sampled only at REST and at SETTLE -> a start/end
displacement oracle, exactly the role the idb frame plays for ios_flipbook.

PARITY NOTE: this closes the gap that iOS had `ios_flipbook` but Android had no
equivalent, despite having every building block (adb_ui_tree -> bounds,
adb_record -> screenrecord, adb_tap). Structurally SIMPLER than iOS:
uiautomator `bounds` are already in device px (same space as the screenrecord
output), so NO dpr derivation is needed (iOS must derive dpr because idb returns
logical points). dpr=1.0 for the recovery.

  1. resolve the tracked view's at-rest bounds from the uiautomator dump
     (device px) -> the template region (no scaling);
  2. screen-record (`adb shell screenrecord`) while firing a REAL
     `adb shell input tap` on the trigger view;
  3. recover the motion law from the video (_native_flipbook, content-
     independent, t0/D-invariant fit);
  4. re-read the tracked view's bounds at settle -> start/end displacement as
     an independent amplitude cross-check.

uiautomator exposes only what a View publishes. For a mover that is not in the
hierarchy (e.g. a canvas), pass `--auto` to auto-locate the region from pixels
and `--tap-xy x,y` to fire a literal-point tap; the bounds oracle is skipped.

Usage:
  adb_flipbook.py --resource-id com.example:id/box --tap-id com.example:id/btn
  adb_flipbook.py --text "Counter" --tap-text "Increment" --seconds 2.5
  adb_flipbook.py --auto --tap-xy 540,1800     # canvas / non-View mover
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json, out_path
from _native_flipbook import recover_from_video


# ─── pure logic (unit-tested in test_adb_flipbook.py) ─────────────────────────

# uiautomator bounds: "[x1,y1][x2,y2]" (device px). Verified against the
# Android uiautomator dump format (official docs + adb_ui_tree.py usage).
_BOUNDS_RE = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")


def parse_bounds(s: str):
    """"[x1,y1][x2,y2]" (device px string) -> (x, y, w, h) ints, or None.

    The uiautomator `bounds` attribute encodes top-left and bottom-right
    corners in device pixels. Returns the (x, y, width, height) tuple, or None
    for a degenerate/empty/unparseable bounds (e.g. "[0,0][0,0]")."""
    if not s:
        return None
    m = _BOUNDS_RE.search(s)
    if not m:
        return None
    x1, y1, x2, y2 = (int(g) for g in m.groups())
    w, h = x2 - x1, y2 - y1
    if w <= 0 or h <= 0:
        return None
    return (x1, y1, w, h)


def _flatten(root: ET.Element):
    """Yield every node in a uiautomator XML tree (DFS, including root).

    adb_ui_tree.xml_to_json nests children, but for element search we want a
    flat ordered iterable of all <node> elements regardless of depth."""
    yield root
    for child in root:
        yield from _flatten(child)


def find_view(root, *, resource_id=None, text=None, cls=None, desc=None):
    """First <node> in the uiautomator XML tree whose provided selectors all
    match (substring) and whose bounds are non-degenerate.

    Selectors match against the node's attributes:
      resource_id -> `resource-id` attr
      text        -> `text` attr
      cls         -> `class` attr (e.g. 'android.widget.Button')
      desc        -> `content-desc` attr
    Returns the ET.Element, or None if no match. Raises ValueError if no
    selector is given."""
    if not any((resource_id, text, cls, desc)):
        raise ValueError("pass --resource-id/--text/--class/--desc to locate a view")
    for node in _flatten(root):
        a = node.attrib
        if resource_id and resource_id not in (a.get("resource-id") or ""):
            continue
        if text and text not in (a.get("text") or ""):
            continue
        if cls and cls not in (a.get("class") or ""):
            continue
        if desc and desc not in (a.get("content-desc") or ""):
            continue
        if parse_bounds(a.get("bounds") or "") is None:
            continue  # skip degenerate/empty bounds
        return node
    return None


def bounds_of(node: ET.Element):
    """(x, y, w, h) device-px from a <node>'s bounds attr, or None."""
    return parse_bounds(node.attrib.get("bounds") or "")


def center_of(rect):
    """Device-px center (cx, cy) of an (x, y, w, h) rect (for input tap)."""
    x, y, w, h = rect
    return (x + w // 2, y + h // 2)


def displacement(rect0, rect1):
    """Start/end top-left displacement in device px (the uiautomator oracle)."""
    return {"tx": rect1[0] - rect0[0], "ty": rect1[1] - rect0[1]}


# ─── device I/O (live-only; not unit-tested) ──────────────────────────────────

def _dump_tree():
    """uiautomator dump -> parsed ET.Element. Mirrors adb_ui_tree.py:30-34 but
    returns the tree instead of writing JSON. Uses /data/local/tmp (always
    adb-pullable on Android >= 4)."""
    from _adb import adb_shell, adb_cmd
    remote = "/data/local/tmp/wd_fb.xml"
    adb_shell(f"uiautomator dump {remote}")
    local = Path(tempfile.mkdtemp(prefix="adbfb-")) / "window_dump.xml"
    adb_cmd(["pull", remote, str(local)], stderr=subprocess.DEVNULL)
    adb_cmd(["shell", "rm", "-f", remote], check=False)
    return ET.parse(local).getroot()


def _record_start(seconds, out):
    """Start `adb shell screenrecord` for `seconds` (+1s headroom) writing to a
    device path; Popen returned so the caller can wait(). Mirrors
    flutter_flipbook._adb_record_start."""
    from _adb import adb_bin, serial
    remote = "/sdcard/pr-adb-flipbook.mp4"
    base = [adb_bin()]
    s = serial()
    if s:
        base += ["-s", s]
    base += ["shell", "screenrecord", "--time-limit", str(int(seconds) + 1), remote]
    proc = subprocess.Popen(base, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return proc, remote


def _record_finish(proc, remote, out):
    from _adb import adb_cmd
    proc.wait()
    adb_cmd(["pull", remote, str(out)], stderr=subprocess.DEVNULL)
    adb_cmd(["shell", "rm", "-f", remote], check=False)
    return out


def _tap(cx, cy):
    from _adb import adb_cmd
    adb_cmd(["shell", "input", "tap", str(int(cx)), str(int(cy))])


# ─── main ─────────────────────────────────────────────────────────────────────

def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--resource-id", dest="resource_id")
    p.add_argument("--text")
    p.add_argument("--class", dest="cls")
    p.add_argument("--desc")
    p.add_argument("--auto", action="store_true",
                   help="auto-locate the mover from pixels (non-View mover); skips the bounds oracle")
    p.add_argument("--tap-id", dest="tap_id")
    p.add_argument("--tap-text")
    p.add_argument("--tap-class", dest="tap_cls")
    p.add_argument("--tap-desc")
    p.add_argument("--tap-xy", help="literal 'x,y' device-px point to tap")
    p.add_argument("--seconds", type=float, default=2.5, help="record window after the tap")
    p.add_argument("--fps", type=float, default=30)
    p.add_argument("--lead", type=float, default=0.8, help="record spin-up before the tap")
    p.add_argument("--settle", type=float, default=0.8, help="post-record settle before re-reading bounds")
    p.add_argument("--scale", action="store_true")
    p.add_argument("--no-trim", action="store_true")
    p.add_argument("--out", default=None)
    args = p.parse_args()

    tree = _dump_tree()

    rect0 = None
    if args.auto:
        region = None  # _native_flipbook auto-locates
    else:
        node = find_view(tree, resource_id=args.resource_id, text=args.text,
                         cls=args.cls, desc=args.desc)
        if node is None:
            die("tracked view not found in the uiautomator dump "
                "(check --resource-id/--text/--class/--desc, or use --auto for a non-View mover)")
        rect0 = bounds_of(node)
        region = rect0  # already device px; dpr=1.0

    # resolve trigger tap point in DEVICE px. adb `input tap` takes integer
    # device px (unlike ios_flipbook's idb ui tap, which takes logical points
    # and so parses float) — the int coercion matches the underlying API.
    if args.tap_xy:
        cx, cy = (int(float(v)) for v in args.tap_xy.split(","))
        tap_pt = (cx, cy)
    else:
        if not any((args.tap_id, args.tap_text, args.tap_cls, args.tap_desc)):
            die("pass a trigger: --tap-id/--tap-text/--tap-class/--tap-desc or --tap-xy")
        tnode = find_view(tree, resource_id=args.tap_id, text=args.tap_text,
                          cls=args.tap_cls, desc=args.tap_desc)
        if tnode is None:
            die("trigger view not found (check --tap-id/--tap-text/--tap-class/--tap-desc or --tap-xy)")
        tap_pt = center_of(bounds_of(tnode))

    out = Path(args.out) if args.out else out_path("adb-flipbook", "mp4")
    proc, remote = _record_start(args.seconds, out)
    time.sleep(args.lead)
    _tap(*tap_pt)
    time.sleep(args.seconds)
    _record_finish(proc, remote, out)

    # bounds displacement oracle: re-read the tracked view after it settles
    disp = None
    if rect0 is not None:
        time.sleep(args.settle)
        node1 = find_view(_dump_tree(), resource_id=args.resource_id,
                          text=args.text, cls=args.cls, desc=args.desc)
        if node1 is not None:
            disp = displacement(rect0, bounds_of(node1))

    # Android: device px throughout, so dpr=1.0 (no logical->device conversion).
    rec = recover_from_video(str(out), fps=args.fps, region=region, dpr=1.0,
                             do_scale=args.scale, trim=not args.no_trim)

    cross = None
    if disp:
        rtx = rec["channels"]["tx"].get("amp") or 0.0
        rty = rec["channels"]["ty"].get("amp") or 0.0
        cross = {"bounds_displacement_px": disp,
                 "recovered_px": {"tx": rtx, "ty": rty},
                 "tx_match_px": round(abs(rtx - disp["tx"]), 2),
                 "ty_match_px": round(abs(rty - disp["ty"]), 2)}

    from motion_adapter import motion_summary
    emit_json({"engine": "android", "video": str(out), "dpr": 1.0,
               "region_devpx": list(region) if region else None,
               "tracked": {"resource_id": args.resource_id, "text": args.text,
                           "class": args.cls, "desc": args.desc},
               "trigger_pt": list(tap_pt), "recovery": rec,
               "bounds_crosscheck": cross,
               # consistent per-axis best-reading block (klass="time")
               "motion_summary": motion_summary(rec, "time")})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
