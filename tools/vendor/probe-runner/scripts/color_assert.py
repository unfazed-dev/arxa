#!/usr/bin/env python3
"""Sample a screen region's colour and assert it matches a target hex within ΔE.

The colour-fidelity verifier. This closes the loop that pixel-level design bugs
(button colour wrong, icon tint wrong) slip through: instead of eyeballing a
screenshot, sample the rendered pixels and assert the mean colour is within a
perceptual tolerance (CIEDE2000 ΔE) of the design's token hex.

Two ways to specify the region:
  --rect X,Y,W,H           SCREENSHOT (physical) pixels on --image PATH.
                           Use this only when you measured the rect off the
                           screenshot yourself — NOT a rect from flutter_inspect
                           (those are logical/CSS px; see --locate).
  --locate type=AdaptiveButton,text="Send code"
                           resolve the widget's rect at runtime via the VM
                           (localToGlobal + size, in LOGICAL px) and SCALE by the
                           device's devicePixelRatio to land in screenshot space.
                           This is the coordinate-space-safe path — flutter_inspect
                           reports logical px while screenshots are physical px,
                           and without the DPR scale a sampled region misses its
                           target. Inset dodges border anti-alias / rounded corners.

The mean is taken over the region (optionally --inset N px to dodge edges /
anti-aliasing / rounded corners). ΔE is CIEDE2000 (perceptually uniform — the
same metric design tools use); a tolerance of ~5 reads as "the same colour to a
human", ~2-3 as "near-exact". Defaults to 5.0 (GLM-5.2's proving-case value).

Emits JSON: {mean_rgb, mean_hex, target_hex, delta_e, tolerance, pass, rect}.
Exit 0 on pass, 2 on fail (the probe-runner die convention) so a CI gate can
chain it.

Usage:
  # assert a screenshot region is the accent orange (#D2522B):
  color_assert.py --image shot.png --rect 30,500,300,52 --hex D2522B

  # locate the Send-code button on the live device + assert its fill:
  color_assert.py --target ios --locate 'type=AdaptiveButton,text=Send code' --hex D2522B
  color_assert.py --target ios --locate 'type=AdaptiveButton,text=Send code' --hex DDD3C0 --state disabled
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json


# ─── colour math (sRGB → Lab → CIEDE2000), pure python, no scipy ───────────────

def _srgb_to_linear(c: float) -> float:
    # c in 0..1. Standard sRGB gamma expansion.
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _rgb_to_lab(r: int, g: int, b: int) -> tuple[float, float, float]:
    # sRGB (0..255) → CIE Lab (D65). Pure-python, no numpy needed for a single
    # colour (the region mean is reduced to one RGB triple before this).
    rl = _srgb_to_linear(r / 255.0)
    gl = _srgb_to_linear(g / 255.0)
    bl = _srgb_to_linear(b / 255.0)
    # linear sRGB → XYZ (D65 matrices, Bruce Lindbloom)
    x = rl * 0.4124564 + gl * 0.3575761 + bl * 0.1804375
    y = rl * 0.2126729 + gl * 0.7151522 + bl * 0.0721750
    z = rl * 0.0193339 + gl * 0.1191920 + bl * 0.9503041
    # XYZ → Lab (D65 reference white)
    xn, yn, zn = 0.95047, 1.0, 1.08883
    fx = (x / xn) ** (1 / 3) if (x / xn) > 0.008856 else (7.787 * (x / xn) + 16 / 116)
    fy = (y / yn) ** (1 / 3) if (y / yn) > 0.008856 else (7.787 * (y / yn) + 16 / 116)
    fz = (z / zn) ** (1 / 3) if (z / zn) > 0.008856 else (7.787 * (z / zn) + 16 / 116)
    L = 116 * fy - 16
    a = 500 * (fx - fy)
    bb = 200 * (fy - fz)
    return L, a, bb


def _delta_e_2000(lab1: tuple[float, float, float],
                  lab2: tuple[float, float, float]) -> float:
    """CIEDE2000 colour difference (perceptually uniform). Pure-python port of the
    Sharma et al. reference formulation (DOI 10.1002/col.20070). Returns a single
    ΔE value (~1 = just noticeable, ~5 = clearly different colour). Verified against
    the reference test set: (50,2.6772,-79.7751) vs (50,0,-82.7485) → 2.0425."""
    import math
    L1, a1, b1 = lab1
    L2, a2, b2 = lab2
    # step 1: Lab → L'C'h' (chroma + hue adaptation)
    C1 = math.hypot(a1, b1)
    C2 = math.hypot(a2, b2)
    Cbar = (C1 + C2) / 2
    Cbar7 = Cbar ** 7
    G = 0.5 * (1 - math.sqrt(Cbar7 / (Cbar7 + 25 ** 7)))
    a1p = (1 + G) * a1
    a2p = (1 + G) * a2
    C1p = math.hypot(a1p, b1)
    C2p = math.hypot(a2p, b2)
    h1p = math.degrees(math.atan2(b1, a1p)) % 360
    h2p = math.degrees(math.atan2(b2, a2p)) % 360
    # treat atan2(0,0) hue as 0 (the spec's convention for achromatic)
    if C1p == 0:
        h1p = 0.0
    if C2p == 0:
        h2p = 0.0
    # step 2: the deltas
    dLp = L2 - L1
    dCp = C2p - C1p
    # Δh': the hue-angle difference, folded into [0,180] magnitude
    if C1p * C2p == 0:
        dhp = 0.0
    else:
        diff = h2p - h1p
        if abs(diff) <= 180:
            dhp = diff
        elif diff > 180:
            dhp = diff - 360
        else:  # diff < -180
            dhp = diff + 360
    # ΔH' = 2·√(C1'C2')·sin(Δh'/2) — Δh' in degrees → radians for sin
    dHp = 2 * math.sqrt(C1p * C2p) * math.sin(math.radians(dhp) / 2)
    # step 3: the weighting functions
    Lbarp = (L1 + L2) / 2
    Cbarp = (C1p + C2p) / 2
    # mean hue h̄'
    if C1p * C2p == 0:
        hbarp = h1p + h2p
    elif abs(h1p - h2p) <= 180:
        hbarp = (h1p + h2p) / 2
    elif (h1p + h2p) < 360:
        hbarp = (h1p + h2p + 360) / 2
    else:
        hbarp = (h1p + h2p - 360) / 2
    T = (1 - 0.17 * math.cos(math.radians(hbarp - 30))
         + 0.24 * math.cos(math.radians(2 * hbarp))
         + 0.32 * math.cos(math.radians(3 * hbarp + 6))
         - 0.20 * math.cos(math.radians(4 * hbarp - 63)))
    dtheta = 30 * math.exp(-(((hbarp - 275) / 25) ** 2))
    Cbarp7 = Cbarp ** 7
    RC = 2 * math.sqrt(Cbarp7 / (Cbarp7 + 25 ** 7))
    SL = 1 + (0.015 * (Lbarp - 50) ** 2) / math.sqrt(20 + (Lbarp - 50) ** 2)
    SC = 1 + 0.045 * Cbarp
    SH = 1 + 0.015 * Cbarp * T
    RT = -math.sin(math.radians(2 * dtheta)) * RC
    kL = kC = kH = 1
    term_L = dLp / (kL * SL)
    term_C = dCp / (kC * SC)
    term_H = dHp / (kH * SH)
    dE = math.sqrt(term_L ** 2 + term_C ** 2 + term_H ** 2
                   + RT * term_C * term_H)
    return dE


def _hex_to_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    if len(h) != 6:
        die(f"--hex expects a 6-digit (or 3-digit) RGB hex, got {h!r}")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def _mean_rgb(image_path: str, rect: tuple[int, int, int, int],
              inset: int = 0) -> tuple[int, int, int]:
    """Mean RGB over a rect of a PNG, with optional inset to dodge edges."""
    try:
        from PIL import Image  # type: ignore
    except ImportError:
        die("missing Pillow. install: pip3 install Pillow")
        return 0, 0, 0  # unreachable
    img = Image.open(image_path).convert("RGB")
    x, y, w, h = rect
    # clamp to image bounds
    x = max(0, min(x, img.width - 1))
    y = max(0, min(y, img.height - 1))
    w = max(1, min(w, img.width - x))
    h = max(1, min(h, img.height - y))
    if inset:
        x += inset; y += inset; w -= 2 * inset; h -= 2 * inset
        w = max(1, w); h = max(1, h)
    crop = img.crop((x, y, x + w, y + h))
    # tiny region → a few px; large → mean is the right summary (the design token
    # is a flat fill, so the centroid IS the token colour; texture/aliasing washes out).
    # Use numpy if available (fast + no deprecation); fall back to band iteration.
    try:
        import numpy as np  # type: ignore
        arr = np.asarray(crop, dtype="float64")
        mr, mg, mb = (int(v) for v in arr.reshape(-1, 3).mean(axis=0))
    except ImportError:
        bands = crop.split()  # (R, G, B)
        px = list(zip(bands[0].getdata(), bands[1].getdata(), bands[2].getdata()))
        if not px:
            die(f"empty crop at {rect} (inset {inset}?) on {image_path} ({img.size})")
            return 0, 0, 0
        mr = sum(p[0] for p in px) // len(px)
        mg = sum(p[1] for p in px) // len(px)
        mb = sum(p[2] for p in px) // len(px)
    return mr, mg, mb


# ─── widget rect resolution (reuse flutter_inspect's VM walk) ──────────────────

def _device_pixel_ratio() -> float:
    """The running app's devicePixelRatio, read from the VM (the single source of
    truth for the CSS-px → screenshot-px scale). Flutter's localToGlobal + size are
    in LOGICAL px (CSS); screenshots (ios_shot/adb_shot) are in PHYSICAL px. Without
    this scale, a rect from flutter_inspect (logical) samples the wrong region of a
    screenshot (physical) — the coordinate-space bug that made the Send-code button
    sample its background instead of its fill. Cached after first read."""
    from _flutter import VMLib
    try:
        raw = VMLib().ev(
            'WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio.toString()')
        return float(raw)
    except Exception:
        # fallback: 3.0 covers all modern iPhones; Android emulators vary (2.625/3.0/3.5)
        # but a mis-scale here only shifts the sample region, and --inset + a sensible
        # default still lands on the element for the common iPhone case.
        return 3.0


def _locate_rect(spec: str, dpr: float | None = None) -> tuple[int, int, int, int] | None:
    """Resolve a widget's screen rect from a 'type=...,text=...' spec via the VM.

    Returns (x, y, w, h) in SCREENSHOT px (physical), by scaling the widget's
    logical-px rect (localToGlobal + size) by the device's devicePixelRatio. This
    is the coordinate-space fix: flutter_inspect's rects are logical px, screenshots
    are physical px — without the DPR scale, --locate would sample the wrong region.

    Pass dpr to skip the VM read (when the caller already has it)."""
    fields = {}
    for part in spec.split(","):
        if "=" in part:
            k, v = part.split("=", 1)
            fields[k.strip()] = v.strip()
    type_pred = ""
    if "type" in fields:
        type_pred = "||".join('rt=="%s"' % t.strip() for t in fields["type"].split("|"))
    text_pred = ""
    if "text" in fields:
        text_pred = 'lbl.contains("%s")' % fields["text"]
    preds = [p for p in (type_pred, text_pred) if p]
    pred = "&&".join("(%s)" % p for p in preds) if preds else "true"
    expr = (
        '(() {'
        ' var hit="";'
        ' void w(Element e) {'
        '  if(hit.isNotEmpty) return;'
        '  var rt=e.widget.runtimeType.toString();'
        '  var lbl="";'
        '  try{lbl=(e.widget as dynamic).label.toString();}catch(_){}'
        '  try{ if(lbl.isEmpty) lbl=(e.widget as dynamic).data.toString(); }catch(_){}'
        '  if(%(pred)s) {' % {"pred": pred}
        + '   var ro=e.renderObject;'
        '   if(ro is RenderBox){'
        '    var o=ro.localToGlobal(Offset.zero); var s=ro.size;'
        '    hit=o.dx.toString()+"\\x1f"+o.dy.toString()+"\\x1f"+s.width.toString()+"\\x1f"+s.height.toString();'
        '    return;'
        '   }'
        '  }'
        '  e.visitChildren((c)=>w(c));'
        ' }'
        ' var r=WidgetsBinding.instance.rootElement;'
        ' if(r!=null) w(r);'
        ' return hit;'
        '})()'
    )
    from _flutter import VMLib
    try:
        raw = VMLib().ev(expr)
    except Exception as e:
        die(f"VM eval failed locating {spec!r}: {e}")
        return None
    if not raw:
        return None
    f = raw.split("\x1f")
    if len(f) != 4:
        return None
    try:
        x, y, w, h = (float(p) for p in f)
    except ValueError:
        return None
    if dpr is None:
        dpr = _device_pixel_ratio()
    # logical px → physical px (screenshot space)
    return (int(round(x * dpr)), int(round(y * dpr)),
            int(round(w * dpr)), int(round(h * dpr)))


def _shot(target: str, outdir: str) -> tuple[str | None, str | None]:
    """Capture a device screenshot; return (path, error).

    On failure the child's stderr/stdout is returned in `error` — otherwise the
    caller dies with 'could not capture' and no reason (the swallowed-stderr bug)."""
    script = Path(__file__).with_name("ios_shot.py" if target == "ios" else "adb_shot.py")
    try:
        r = subprocess.run(["python3", str(script)], capture_output=True, text=True, timeout=30)
    except Exception as e:
        return None, f"{script.name} failed to run: {e}"
    if r.returncode != 0:
        err = (r.stderr or r.stdout or "").strip()
        return None, f"{script.name} rc={r.returncode}: {err or '(no output)'}"
    import re
    m = re.search(r"(/[^\s\"]+\.png)", r.stdout + r.stderr)
    if not m:
        return None, f"{script.name} rc=0 but no .png path in output"
    return m.group(1), None


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--image", help="screenshot PNG to sample (skip if --target)")
    p.add_argument("--rect", help="X,Y,W,H pixels in the screenshot (required with --image)")
    p.add_argument("--target", choices=["ios", "adb"], help="live device to screenshot")
    p.add_argument("--locate", help="'type=AdaptiveButton,text=Send code' — resolve rect via VM")
    p.add_argument("--hex", required=True, help="target colour as RRGGBB (with or without #)")
    p.add_argument("--tolerance", type=float, default=5.0,
                   help="max CIEDE2000 ΔE to pass (default 5.0 — 'same colour to a human')")
    p.add_argument("--inset", type=int, default=4,
                   help="px to inset the rect before sampling (dodges border alias / radius; default 4)")
    args = p.parse_args()

    image = args.image
    rect = None
    if args.rect:
        try:
            rect = tuple(int(v) for v in args.rect.split(","))  # type: ignore
        except ValueError:
            die("--rect expects X,Y,W,H ints")
    if args.target:
        import os
        outdir = os.environ.get("PROBE_RUNNER_OUTDIR", "/tmp/probe-runner")
        if not image:
            image, shot_err = _shot(args.target, outdir)
            if not image:
                die("could not capture a screenshot from target %s: %s" % (args.target, shot_err))
    # When --target is given, attach to THAT device's VM for the whole locate+sample
    # pass (the global cache may hold a DIFFERENT device's URL — sampling iOS's widget
    # tree against an Android screenshot produces nonsense that looks like a render bug).
    from _flutter import with_target_url
    with with_target_url(args.target):
        if args.locate:
            rect = _locate_rect(args.locate)
            if not rect:
                die("could not locate a widget matching %r" % args.locate)
    if not image:
        die("need --image PATH or --target {ios,adb}")
    if not rect:
        die("need --rect X,Y,W,H or --locate 'type=…,text=…'")

    mean = _mean_rgb(image, rect, inset=args.inset)
    mr, mg, mb = mean
    mean_hex = "%02X%02X%02X" % (mr, mg, mb)
    tr, tg, tb = _hex_to_rgb(args.hex)
    de = _delta_e_2000(_rgb_to_lab(mr, mg, mb), _rgb_to_lab(tr, tg, tb))
    passed = de <= args.tolerance
    emit_json({
        "mean_rgb": [mr, mg, mb], "mean_hex": mean_hex,
        "target_hex": args.hex.lstrip("#").upper(),
        "delta_e": round(de, 3), "tolerance": args.tolerance,
        "pass": passed, "rect": list(rect), "image": image,
    })
    return 0 if passed else 2


if __name__ == "__main__":
    sys.exit(main())
