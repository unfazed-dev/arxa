#!/usr/bin/env python3
"""flutter_flipbook -- frame-based motion recovery for a Flutter app's
time/event animation (tap-triggered translate, entrance), the native sibling of
web_flipbook.

Flutter has no DOM/WAAPI, so the certification input is a screen RECORDING. But
unlike a raw screenshot pipeline, Flutter exposes an EXACT cross-check over the
VM service (the same primitive flutter_anim uses): `getTransformTo(null)` reads
the moving widget's transform-to-root. So this verb:

  1. resolves the tracked widget's at-rest screen rect (localToGlobal + size +
     devicePixelRatio) -> a precise template region in device px;
  2. screen-records while firing a REAL input tap on the trigger widget;
  3. recovers the motion law from the video (_native_flipbook, content-
     independent, t0/D-invariant fit);
  4. reads the widget's start/end transform over the VM as a ground-truth
     displacement cross-check.

Recording + tap are platform verbs: --target adb (emulator, default) or ios
(simulator). Run `flutter_attach.py` first so the VM service URL is cached.

Usage:
  flutter_attach.py --url http://127.0.0.1:<PORT>/
  flutter_flipbook.py --type AnimatedPositioned --tap-type FloatingActionButton
  flutter_flipbook.py --key box --tap-key trigger --target adb --seconds 2.5
  flutter_flipbook.py --key box --tap-key trigger --target ios --udid <UDID>
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json, out_path
from _flutter import VMLib
from _native_flipbook import recover_from_video


def _predicate(key, type_, text) -> str:
    parts = []
    for val, tmpl in (
        (key, "(e.widget.key?.toString() ?? \"\").contains('%s')"),
        (type_, "e.widget.runtimeType.toString().contains('%s')"),
        (text, "e.widget.toString().contains('%s')"),
    ):
        if val:
            if "'" in val or "\\" in val:
                die("selector may not contain quotes or backslashes: %r" % val)
            parts.append(tmpl % val)
    if not parts:
        die("pass --type, --key, or --text to locate a widget")
    return " && ".join(parts)


def _rect_expr(pred: str) -> str:
    """Walk to the first element matching `pred` with a RenderBox; return its
    at-rest screen rect + devicePixelRatio as "x,y,w,h,dpr" (logical px).
    "NO_TARGET" if none."""
    return ("(() { RenderObject? ro; "
            "void rec(Element e){ if(ro!=null) return; "
            "if((" + pred + ") && e.renderObject is RenderBox){ ro = e.renderObject; return; } "
            "e.visitChildren(rec); } "
            "rec(WidgetsBinding.instance.rootElement!); "
            "if(ro==null) return \"NO_TARGET\"; "
            "final b = ro as RenderBox; final o = b.localToGlobal(Offset.zero); "
            "final dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio; "
            "return \"${o.dx},${o.dy},${b.size.width},${b.size.height},${dpr}\"; })()")


def _xform_expr(pred: str) -> str:
    return ("(() { RenderObject? ro; "
            "void rec(Element e){ if(ro!=null) return; "
            "if((" + pred + ") && e.renderObject!=null){ ro = e.renderObject; return; } "
            "e.visitChildren(rec); } "
            "rec(WidgetsBinding.instance.rootElement!); "
            "if(ro==null) return \"NO_TARGET\"; "
            "final m = ro!.getTransformTo(null).storage; "
            "return \"${m[12]},${m[13]}\"; })()")


def _resolve_rect(lib, pred):
    raw = lib.ev(_rect_expr(pred))
    if raw is None or raw == "NO_TARGET":
        die("tracked widget not found in the tree (check --key/--type/--text). "
            "Run flutter_attach.py first.")
    x, y, w, h, dpr = (float(v) for v in raw.split(","))
    return x, y, w, h, dpr


def _read_tx(lib, pred):
    raw = lib.ev(_xform_expr(pred))
    if raw is None or raw == "NO_TARGET":
        return None
    tx, ty = (float(v) for v in raw.split(","))
    return tx, ty


# ---------------- platform recorder + tap ----------------
#
# Two backends share one interface (record_start/record_finish/tap) so the
# motion-recovery + VM-crosscheck tail is identical for --target adb|ios. The
# displacement oracle stays the Flutter VM getTransformTo in BOTH cases (read
# via _read_tx above); only the recorder + tap transport differs.
#   adb : `adb shell screenrecord` + `adb shell input tap` (device px throughout)
#   ios : `xcrun simctl io recordVideo --codec=h264` + `idb ui tap` (logical pts,
#         so the device-px tap coord from _resolve_rect is divided by dpr). This
#         reuses the PROVEN ios_flipbook orchestration (ios_flipbook.py:142-158).

class _AdbBackend:
    """Android-emulator record + tap. adb input tap takes DEVICE px."""
    name = "adb"

    def __init__(self):
        from _adb import adb_bin, serial  # noqa: F401 (import-time check)
        self._adb_base = self._base()

    @staticmethod
    def _base():
        from _adb import adb_bin, serial
        base = [adb_bin()]
        s = serial()
        if s:
            base += ["-s", s]
        return base

    def record_start(self, seconds, out, remote="/sdcard/pr-flipbook.mp4"):
        from _adb import adb_cmd
        adb_cmd(["shell", "rm", "-f", remote], check=False)
        proc = subprocess.Popen(self._adb_base + ["shell", "screenrecord",
                                "--time-limit", str(int(seconds) + 1), remote])
        return proc, remote

    def record_finish(self, proc, remote, out):
        from _adb import adb_cmd
        proc.wait()
        adb_cmd(["pull", remote, str(out)], stderr=subprocess.DEVNULL)
        adb_cmd(["shell", "rm", "-f", remote], check=False)
        return out

    def tap(self, cx_devpx, cy_devpx):
        from _adb import adb_cmd
        adb_cmd(["shell", "input", "tap", str(int(cx_devpx)), str(int(cy_devpx))])


class _IosBackend:
    """iOS-simulator record + tap. idb ui tap takes LOGICAL points, so the
    device-px tap coord is divided by dpr before dispatch. Recording uses h264
    so ffmpeg can split frames (default simctl codec is HEVC)."""
    name = "ios"

    def __init__(self, udid=None):
        self.udid = udid or _booted_udid()

    def record_start(self, seconds, out, remote=None):
        cmd = ["xcrun", "simctl", "io", self.udid, "recordVideo",
               "--codec=h264", "--force", str(out)]
        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL)
        return proc, None

    def record_finish(self, proc, remote, out):
        import signal
        proc.send_signal(signal.SIGINT)
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            proc.kill()
        return out

    def tap(self, cx_devpx, cy_devpx, dpr=1.0):
        # idb ui tap takes logical points; _resolve_rect gives device px.
        from _ios import idb_run
        idb_run(["ui", "tap", str(int(cx_devpx / dpr)), str(int(cy_devpx / dpr)),
                 "--udid", self.udid], capture=True)


def _booted_udid():
    """First booted iOS sim UDID (mirrors ios_flipbook._booted_udid)."""
    r = subprocess.run(["xcrun", "simctl", "list", "devices", "booted"],
                       capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if "Booted" in line and "(" in line:
            parts = [p for p in line.split("(") if ")" in p]
            for p in parts:
                cand = p.split(")")[0].strip()
                if len(cand) >= 32 and "-" in cand:
                    return cand
    die("no booted iOS simulator (boot one: ios_boot.py / xcrun simctl boot)")


_BACKENDS = {"adb": _AdbBackend, "ios": _IosBackend}


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--target", choices=["adb", "ios"], default="adb",
                   help="recorder/tap backend: adb = Android emulator (default), "
                        "ios = iOS simulator (simctl recordVideo + idb ui tap). "
                        "The displacement oracle is the Flutter VM in BOTH cases.")
    p.add_argument("--udid", default=None, help="iOS sim UDID (--target ios only)")
    p.add_argument("--key"); p.add_argument("--type"); p.add_argument("--text")
    p.add_argument("--tap-key"); p.add_argument("--tap-type"); p.add_argument("--tap-text")
    p.add_argument("--seconds", type=float, default=2.5, help="record window")
    p.add_argument("--fps", type=float, default=30, help="frame extraction rate")
    p.add_argument("--lead", type=float, default=0.8, help="record spin-up before the tap")
    p.add_argument("--settle", type=float, default=0.8, help="post-tap settle before reading end transform")
    p.add_argument("--scale", action="store_true")
    p.add_argument("--no-trim", action="store_true")
    p.add_argument("--out", default=None)
    args = p.parse_args()

    try:
        lib = VMLib()
    except Exception as e:
        die("no Flutter VM service. run flutter_attach.py first. (%s)" % e)

    backend = _BACKENDS[args.target]()

    pred = _predicate(args.key, args.type, args.text)
    x, y, w, h, dpr = _resolve_rect(lib, pred)
    region = (max(0, int(x * dpr)), max(0, int(y * dpr)),
              max(1, int(w * dpr)), max(1, int(h * dpr)))
    tx0 = _read_tx(lib, pred)

    tap_pred = None
    if args.tap_key or args.tap_type or args.tap_text:
        tap_pred = _predicate(args.tap_key, args.tap_type, args.tap_text)
        tx_, ty_, tw_, th_, _ = _resolve_rect(lib, tap_pred)
        tap_cx, tap_cy = (tx_ + tw_ / 2) * dpr, (ty_ + th_ / 2) * dpr

    out = Path(args.out) if args.out else out_path("flutter-flipbook", "mp4")
    proc, remote = backend.record_start(args.seconds, out)
    time.sleep(args.lead)
    if tap_pred:
        if args.target == "ios":
            backend.tap(tap_cx, tap_cy, dpr=dpr)
        else:
            backend.tap(tap_cx, tap_cy)
    backend.record_finish(proc, remote, out)

    time.sleep(args.settle)
    tx1 = _read_tx(lib, pred)
    vm_disp = None
    if tx0 and tx1:
        vm_disp = {"tx": round(tx1[0] - tx0[0], 2), "ty": round(tx1[1] - tx0[1], 2)}

    rec = recover_from_video(str(out), fps=args.fps, region=region, dpr=dpr,
                             do_scale=args.scale, trim=not args.no_trim)

    cross = None
    if vm_disp:
        rtx = rec["channels"]["tx"].get("amp") or 0.0
        rty = rec["channels"]["ty"].get("amp") or 0.0
        cross = {"vm_displacement": vm_disp,
                 "recovered": {"tx": rtx, "ty": rty},
                 "tx_match_px": round(abs(rtx - vm_disp["tx"]), 2),
                 "ty_match_px": round(abs(rty - vm_disp["ty"]), 2)}

    from motion_adapter import motion_summary
    emit_json({"engine": "flutter", "target": args.target, "video": str(out),
               "dpr": dpr, "region_devpx": list(region), "tracked": pred,
               "trigger": tap_pred, "recovery": rec, "vm_crosscheck": cross,
               "motion_summary": motion_summary({"recovery": rec}, "time")})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
