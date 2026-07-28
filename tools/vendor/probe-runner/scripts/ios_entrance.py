#!/usr/bin/env python3
"""ios_entrance — multi-element ENTRANCE-motion probe for a native iOS app.

The sibling the *_flipbook verbs deliberately do NOT cover: a LAUNCH- or
ROUTE-triggered STAGGERED entrance cascade where MANY elements appear together
(opacity-fade + small translate), not a single tap-triggered mover. The flipbook
verbs are single-element + tap-triggered + translation-keyed, so on an
opacity-dominated entrance they recover (0,0) = "no motion" (verified live on a
Flutter signin cascade). The right signal there is per-element LUMINANCE onset,
not template translation.

This verb records one cold-launch/route entrance, then for each tracked element
derives a coarse onset description — {kind: fade|pop|none, onset_s, settle_s,
amplitude, present} — by sampling per-frame mean luminance of the element's
region. It is CONTENT-INDEPENDENT (only screenshots + the AX-derived region
rects) and HONEST about precision: sim framebuffer noise + opacity-dominance
preclude per-element easing certification, so this verb asserts nothing about
curves. The motion FAMILY (fade vs pop vs none) + onset ORDER + band is the
certifiable signal; a consumer compares that against an emitted contract.

Observation vs assertion split: this verb emits RAW per-element facts. The
CONTRACT assertion (e.g. "each RiseIn should fade at ~delayMs; glass leaves
pop") is the CONSUMER's job — exactly the split every other probe-runner verb
enforces. See flutter-crew stages/motion_device.py:motion_device_parity for the
reference consumer that consumes this shape.

  ios_entrance.py --udid <udid> --bundle <id> [--seconds 6] [--fps 30]
  ios_entrance.py --udid <udid> --bundle <id --select label:WELCOME,label:title
  ios_entrance.py --self-test

Region source (pick one):
  --select label:Foo,label:Bar  — idb AX labels (default: ALL non-degenerate frames,
                                 top-to-bottom = source order; the cascade order)
  --regions x,y,w,h:x,y,w,h     — literal device-px rects (no AX dependency)
"""
from __future__ import annotations

import argparse
import glob
import json
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json, out_path  # noqa: E402
from _ios import idb_run  # noqa: E402


# ---------------- pure logic (unit-tested in test_ios_entrance.py) -----------

def classify(lum: list[float], fps: float,
             lum_thr: float = 0.012, pop_frames: int = 2) -> tuple[str, float | None, float | None, float]:
    """Classify a per-region luminance series -> (kind, onset_s, settle_s, delta).

    kind: 'none' (no change above lum_thr), 'pop' (steps within pop_frames —
    appears fully-formed, e.g. a native glass leaf whose opacity animation is
    blocked), 'fade' (gradual). onset/settle are seconds from the series start
    (None when kind == 'none'). delta is final - first luminance (signed).

    COARSE BY DESIGN. Sim framebuffer noise + opacity-dominance make sub-frame
    timing / easing certification flaky; this asserts the FAMILY + band only.
    """
    if len(lum) < 3:
        return "none", None, None, 0.0
    base = sum(lum[:3]) / 3
    fin = sum(lum[-3:]) / 3
    d = fin - base
    if abs(d) < lum_thr:
        return "none", None, None, round(d, 4)
    on = se = None
    for i, v in enumerate(lum):
        f = (v - base) / d if d else 0.0
        if on is None and f > 0.15:
            on = i
        if on is not None and f > 0.85:
            se = i
            break
    if se is None:
        se = len(lum) - 1
    kind = "pop" if (se - on) <= pop_frames else "fade"
    return kind, round(on / fps, 3), round(se / fps, 3), round(d, 4)


def recover_observed(frame_paths: list[str], regions: list[dict], fps: float,
                     present_std_thr: float = 0.04) -> list[dict]:
    """Per-region onset description over a frame sequence.

    regions: [{label, x, y, w, h}] in IMAGE px (top-to-bottom order preserved).
    Returns one entry per region: {label, kind, onset_s, settle_s, lum_delta,
    present}. `present` = the settled region has visual structure (std > thr)
    vs an empty background — disambiguates a POPPED-in leaf from a MISSING one
    (a 'none' kind alone cannot). Uses _flipbook.region_luminance (the proven
    opacity proxy) + a settled-frame std; never cv2-tracks (translation is the
    wrong signal on an opacity-dominated entrance).
    """
    from _flipbook import region_luminance  # noqa: E402
    import cv2  # noqa: E402
    import numpy as np  # noqa: E402
    settled = cv2.cvtColor(cv2.imread(frame_paths[-1]), cv2.COLOR_BGR2GRAY).astype(float) / 255.0
    out: list[dict] = []
    for r in regions:
        x, y, w, h = int(r["x"]), int(r["y"]), int(r["w"]), int(r["h"])
        lum = region_luminance(frame_paths, (x, y, w, h))
        kind, on, se, d = classify(lum, fps)
        sub = settled[y:y + h, x:x + w]
        std = float(sub.std()) if sub.size else 0.0
        out.append({"label": r["label"], "kind": kind, "onset_s": on,
                    "settle_s": se, "lum_delta": d,
                    "present": std > present_std_thr, "settled_std": round(std, 4)})
    return out


def regions_from_tree(tree: list[dict], dpr: float,
                      select: list[str] | None = None) -> list[dict]:
    """idb describe-all tree -> ordered device-px regions.

    Logical-point frames -> device px (x*dpr ...). Skips degenerate frames.
    select: optional list of AX labels; when present, keeps only elements whose
    AXLabel/title contains one of them, preserving source order. When absent,
    ALL non-degenerate frames are kept (top-to-bottom = the cascade order).
    """
    out: list[dict] = []
    for el in tree:
        f = el.get("frame") or {}
        w = float(f.get("width") or 0)
        h = float(f.get("height") or 0)
        if w <= 0 or h <= 0:
            continue
        lab = el.get("AXLabel") or el.get("title") or ""
        if select:
            if not any(s in lab for s in select):
                continue
        x, y = float(f.get("x") or 0), float(f.get("y") or 0)
        out.append({"label": lab or f"el{len(out)}",
                    "x": x * dpr, "y": y * dpr, "w": w * dpr, "h": h * dpr})
    return out


def parse_regions(spec: str) -> list[dict]:
    """'x,y,w,h:x,y,w,h' -> [{label, x,y,w,h}] (literal device-px rects)."""
    out: list[dict] = []
    for i, part in enumerate(spec.split(":")):
        vals = [float(v) for v in part.split(",")]
        if len(vals) != 4:
            die(f"--regions rect must be 'x,y,w,h' (got {part!r})")
        out.append({"label": f"region{i}", "x": vals[0], "y": vals[1],
                    "w": vals[2], "h": vals[3]})
    return out


# ---------------- simulator I/O (live-validated, not unit-tested) -----------

def _booted_udid(explicit: str | None = None) -> str:
    if explicit:
        return explicit
    r = subprocess.run(["xcrun", "simctl", "list", "devices", "booted"],
                       capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if "Booted" in line and "(" in line:
            for p in (pp for pp in line.split("(") if ")" in pp):
                cand = p.split(")")[0].strip()
                if len(cand) >= 32 and "-" in cand:
                    return cand
    die("no booted iOS simulator (boot one: ios_boot.py / xcrun simctl boot)")


def _describe_all(udid: str) -> list[dict]:
    r = idb_run(["ui", "describe-all", "--udid", udid], capture=True)
    return json.loads(r.stdout)


def _root_point_width(tree: list[dict]) -> float:
    return max((float((el.get("frame") or {}).get("width") or 0) for el in tree),
               default=0.0)


def _screenshot_px_width(udid: str, tmp: Path) -> float:
    png = tmp / "ios-entr-shot.png"
    subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", str(png)],
                   check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    from PIL import Image
    with Image.open(png) as im:
        return float(im.width)


def derive_dpr(screenshot_px_w: float, root_pts_w: float) -> float:
    """iOS scale = screenshot px width / root view point width, snapped to int."""
    if root_pts_w <= 0:
        return 1.0
    return float(round(screenshot_px_w / root_pts_w))


def _record_start(udid: str, out: Path):
    cmd = ["xcrun", "simctl", "io", udid, "recordVideo",
           "--codec=h264", "--force", str(out)]
    return subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _record_stop(proc: subprocess.Popen):
    proc.send_signal(signal.SIGINT)
    try:
        proc.wait(timeout=15)
    except subprocess.TimeoutExpired:
        proc.kill()


# ---------------- self-test: synthetic luminance with known onsets ----------

def _synth(kind: str, n: int = 30) -> list[float]:
    """A synthetic per-frame luminance series of a known FAMILY.

    fade: 0.10 -> 0.90 over the middle 60% of frames (gradual).
    pop:  flat 0.10 until frame 12, then 0.90 to the end (instant step).
    none: flat 0.50 throughout (no change).
    """
    if kind == "none":
        return [0.50] * n
    if kind == "pop":
        return [0.10] * 12 + [0.90] * (n - 12)
    # fade
    out = []
    for i in range(n):
        p = i / (n - 1)
        active = 0.2 <= p <= 0.8
        if not active:
            out.append(0.10 if p < 0.2 else 0.90)
        else:
            t = (p - 0.2) / 0.6
            out.append(0.10 + 0.80 * t)
    return out


def _self_test() -> int:
    fps = 30.0
    # Coarse by design: certify the FAMILY + onset ORDER + band, NOT exact frame
    # timing. The synthetic fade ramps 0.10->0.90 across the middle 60% of 30
    # frames; classify's 0.15-amplitude onset gate fires once the ramp is
    # underway and its 0.85 settle gate near the ramp end. Asserts the band,
    # not exact ms (the honest contract — sim noise precludes tighter).
    k, on, se, d = classify(_synth("fade"), fps)
    assert k == "fade", k
    assert on is not None and se is not None and se > on, (on, se)
    assert 0.0 < on < 0.5, on          # onset somewhere in the first half
    assert se > 0.4, se                # settle in the second half
    assert d > 0                       # rose
    # pop: flat-then-instant step -> onset & settle within pop_frames (a step,
    # not a gradual fade)
    k, on, se, d = classify(_synth("pop"), fps)
    assert k == "pop", k
    assert on is not None and se is not None and (se - on) * fps <= 2
    assert d > 0
    # none: no change above threshold
    k, on, se, d = classify(_synth("none"), fps)
    assert k == "none"
    assert on is None and se is None
    # short series guard
    assert classify([0.1, 0.1], fps)[0] == "none"
    print("ios_entrance self-test OK (fade/pop/none classification)")
    return 0


# ---------------- CLI --------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--udid", default=None, help="target sim (default: the booted one)")
    ap.add_argument("--bundle", default=None,
                    help="bundle id to cold-launch THEN record (records the launch entrance)")
    ap.add_argument("--no-launch", action="store_true",
                    help="do NOT launch; record the currently-running app (route entrance)")
    ap.add_argument("--seconds", type=float, default=6.0, help="record window")
    ap.add_argument("--fps", type=float, default=30.0)
    ap.add_argument("--select", default=None,
                    help="comma list of 'label:Foo' to track (default: all non-degenerate frames)")
    ap.add_argument("--regions", default=None,
                    help="literal device-px rects 'x,y,w,h:x,y,w,h' (bypasses the AX tree)")
    ap.add_argument("--pre-roll", type=float, default=0.5,
                    help="seconds to wait AFTER launch / BEFORE record-start settle")
    ap.add_argument("--out", default=None)
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        return _self_test()

    if not args.no_launch:
        if not args.bundle:
            die("--bundle is required (or pass --no-launch to record the running app)")

    udid = _booted_udid(args.udid)
    tmp = Path(tempfile.mkdtemp(prefix="ios-ent-"))

    # resolve regions BEFORE launching (the tree is the at-rest contract; for a
    # launch entrance the post-launch tree equals the settled target). When
    # --no-launch, the running app's tree is read as-is.
    if args.regions:
        regions = parse_regions(args.regions)
        dpr = 1.0
    else:
        if not args.no_launch:
            # launch first so the at-rest tree reflects the target screen
            subprocess.run(["xcrun", "simctl", "terminate", udid, args.bundle],
                           capture_output=True)
            time.sleep(1)
            subprocess.run(["xcrun", "simctl", "launch", udid, args.bundle],
                           capture_output=True)
            time.sleep(args.pre_roll)
        tree = _describe_all(udid)
        root_w = _root_point_width(tree)
        if root_w < 100:
            die("no foreground app in the accessibility tree (root width %.0fpt); "
                "launch the app first" % root_w)
        dpr = derive_dpr(_screenshot_px_width(udid, tmp), root_w)
        select = ([p.split("label:", 1)[1] for p in args.select.split(",")
                   if p.startswith("label:")]
                  if args.select else None)
        regions = regions_from_tree(tree, dpr, select=select)

    if not regions:
        die("no trackable regions resolved (pass --select / --regions, or check the AX tree)")

    out = Path(args.out) if args.out else out_path("ios-entrance", "mp4")
    # cold-launch entrance: start the record, THEN relaunch so the cascade is
    # captured from t0 (the --no-launch path records an already-settled app, so
    # the operator drives the route transition themselves).
    proc = _record_start(udid, out)
    if not args.no_launch:
        time.sleep(args.pre_roll)
        subprocess.run(["xcrun", "simctl", "terminate", udid, args.bundle],
                       capture_output=True)
        time.sleep(0.5)
        subprocess.run(["xcrun", "simctl", "launch", udid, args.bundle],
                       capture_output=True)
    time.sleep(args.seconds)
    _record_stop(proc)

    from _frames import extract  # noqa: E402
    frames_dir = str(tmp / "frames")
    frames = extract(str(out), frames_dir, args.fps)
    frame_paths = [f["path"] for f in frames]
    if len(frame_paths) < 3:
        die(f"need >=3 frames, got {len(frame_paths)} (raise --fps or lengthen --seconds)")

    observed = recover_observed(frame_paths, regions, args.fps)

    emit_json({"engine": "ios", "udid": udid, "bundle": args.bundle,
               "video": str(out), "dpr": dpr, "fps": args.fps,
               "frames_used": len(frame_paths),
               "regions": [{"label": r["label"], "x": r["x"], "y": r["y"],
                            "w": r["w"], "h": r["h"]} for r in regions],
               "observed": observed,
               # honest ceiling: per-element FAMILY + onset ORDER + band only;
               # NOT easing/delay certification (sim noise + opacity-dominance).
               "certifies": ["family", "onset_order", "band"],
               "does_not_certify": ["easing", "exact_delay_ms"]})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
