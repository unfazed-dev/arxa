"""Frame-based motion recovery ("flipbook") core.

Content-independent, platform-universal: derive an animation's motion law
(translate / scale / rotate / opacity over scroll or time) from a sequence of
screenshots by measuring how the moving region SHIFTS between frames -- not what
it shows. Works anywhere a screenshot exists (web, iOS, Android, Flutter).

Baseline deps: numpy + Pillow only (phase correlation + log-polar FFT =
Fourier-Mellin). cv2 is an optional enhancement (ORB + affine), lazily imported.
Recovered trajectories feed the existing _anim_core.fit_easing for the curve.
"""
from __future__ import annotations

import numpy as np
from PIL import Image

from _anim_core import fit_easing, EASINGS


def _bez_t_for_coord(target, c1, c2):
    """Bisect param t in [0,1] where the 1D cubic-bezier (endpoints 0,1, controls
    c1,c2) equals `target`. The coord is monotonic for ease curves."""
    lo, hi = 0.0, 1.0
    for _ in range(48):
        m = (lo + hi) / 2
        v = 3 * (1 - m) ** 2 * m * c1 + 3 * (1 - m) * m * m * c2 + m ** 3
        if v < target:
            lo = m
        else:
            hi = m
    return (lo + hi) / 2


def _bez_x_at_y(yv, x1, y1, x2, y2):
    """Inverse of a CSS cubic-bezier easing: the normalized time x at which the
    easing output reaches y."""
    t = _bez_t_for_coord(min(1.0, max(0.0, yv)), y1, y2)
    return 3 * (1 - t) ** 2 * t * x1 + 3 * (1 - t) * t * t * x2 + t ** 3


def _bez_y_progress(x, x1, y1, x2, y2):
    """y(x) for a CSS cubic-bezier easing (x clamped to [0,1])."""
    x = min(1.0, max(0.0, x))
    t = _bez_t_for_coord(x, x1, x2)
    return 3 * (1 - t) ** 2 * t * y1 + 3 * (1 - t) * t * t * y2 + t ** 3


def fit_easing_aligned(xs, ys):
    """Easing fit invariant to time-origin (t0) and duration (D).

    Realtime/video capture knows position vs *capture* time, but not the exact
    animation t0/D, and easeOutCubic's steep onset aliases to easeOutQuad under
    a small misalignment. For the true easing E, x = E^{-1}(y) is an AFFINE
    function of capture time (x = (t - t0)/D), so we pick the easing whose
    inverse maps the data most LINEARLY against capture time -- t0 (intercept)
    and D (slope) drop out. Returns {name, nearest, bezier, rms}.
    """
    n = len(ys)
    y0, yN = ys[0], ys[-1]
    span = yN - y0
    if n < 3 or abs(span) < 1e-9:
        return {"name": None, "bezier": "-", "rms": 9.0}
    yn = [(v - y0) / span for v in ys]
    xnorm = _norm_axis(list(xs))
    # near-saturated points (y~0/1) are uninformative for E^{-1} and cluster on
    # clamped lead/settle frames -> exclude them from the regression.
    core = [i for i in range(n) if 0.04 < yn[i] < 0.96]
    if len(core) < 3:
        core = list(range(n))
    # Degenerate guard: a step/plateau trajectory (e.g. an undersampled capture
    # where the source rendered only a few frames) collapses to a near-constant
    # y, which the t0/D regression fits with slope 0 and zero residual -> EVERY
    # easing scores rms 0 and a junk curve passes as a confident match. Require
    # enough distinct progress levels for the inverse-linearity test to mean
    # something; otherwise refuse to certify.
    if len({round(yn[i], 2) for i in core}) < 4:
        return {"name": None, "nearest": None, "bezier": "-", "rms": None,
                "note": "degenerate: too few distinct progress levels "
                        "(capture undersampled the motion)"}
    best, best_rms = None, 1e9
    for name, (x1, y1, x2, y2) in EASINGS.items():
        xs_c = [xnorm[i] for i in core]
        tp = [_bez_x_at_y(yn[i], x1, y1, x2, y2) for i in core]
        m = len(tp)
        sx = sum(xs_c); sy = sum(tp)
        sxx = sum(v * v for v in xs_c); sxy = sum(xs_c[k] * tp[k] for k in range(m))
        denom = (m * sxx - sx * sx) or 1e-12
        a = (m * sxy - sx * sy) / denom
        b = (sy - a * sx) / m
        res = 0.0
        for k in range(m):
            y_pred = _bez_y_progress(a * xs_c[k] + b, x1, y1, x2, y2)
            res += (y_pred - yn[core[k]]) ** 2
        rms = (res / m) ** 0.5
        if rms < best_rms:
            best_rms, best = rms, name
    bz = EASINGS[best]
    return {"name": best if best_rms <= 0.1 else "custom", "nearest": best,
            "bezier": "cubic-bezier(%s,%s,%s,%s)" % bz, "rms": round(best_rms, 4)}


# ---------- image io ----------

def load_gray(path):
    """Load an image as a float32 grayscale array in [0,1]."""
    im = Image.open(path).convert("L")
    return np.asarray(im, dtype=np.float32) / 255.0


def _hann(shape):
    """2D Hann window to suppress FFT edge/periodicity artifacts."""
    wy = np.hanning(shape[0])
    wx = np.hanning(shape[1])
    return np.outer(wy, wx).astype(np.float32)


def _crop(a, region):
    """region = (x, y, w, h) in pixels, or None for the whole frame."""
    if region is None:
        return a
    x, y, w, h = region
    return a[y:y + h, x:x + w]


# ---------- phase correlation (translation, sub-pixel) ----------

def _parabolic(c, peak, axis, length):
    """Sub-pixel peak offset via 3-point parabolic fit along one axis."""
    i = peak[axis]
    im1 = (i - 1) % length
    ip1 = (i + 1) % length
    if axis == 0:
        a, b, cc = c[im1, peak[1]], c[i, peak[1]], c[ip1, peak[1]]
    else:
        a, b, cc = c[peak[0], im1], c[peak[0], i], c[peak[0], ip1]
    denom = (a - 2 * b + cc)
    return 0.0 if abs(denom) < 1e-12 else 0.5 * (a - cc) / denom


def phase_corr(a, b, window=True):
    """Translation that maps a -> b (b is a shifted by (dx, dy)), sub-pixel.

    Content-robust: normalizes the cross-power spectrum, so it locks onto the
    dominant shift regardless of absolute pixel values.
    """
    if a.shape != b.shape:
        h = min(a.shape[0], b.shape[0])
        w = min(a.shape[1], b.shape[1])
        a, b = a[:h, :w], b[:h, :w]
    if window:
        win = _hann(a.shape)
        a = a * win
        b = b * win
    A = np.fft.fft2(a)
    B = np.fft.fft2(b)
    R = A * np.conj(B)
    mag = np.abs(R)
    R = R / (mag + 1e-12)
    r = np.fft.ifft2(R).real
    peak = np.unravel_index(int(np.argmax(r)), r.shape)
    H, W = a.shape
    dy = peak[0] + _parabolic(r, peak, 0, H)
    dx = peak[1] + _parabolic(r, peak, 1, W)
    # wrap to signed shift
    if dy > H / 2:
        dy -= H
    if dx > W / 2:
        dx -= W
    # peak position of conj-corr is the shift a->b negated; flip to a->b
    return -dx, -dy


# ---------- log-polar (scale + rotation, content-robust) ----------

def logpolar_scale_rot(a, b):
    """Recover (scale, rotation_deg) mapping a -> b via Fourier-Mellin.

    FFT magnitude (translation-invariant) -> log-polar -> phase correlation:
    angular shift = rotation, radial shift = log(scale).
    """
    if a.shape != b.shape:
        h = min(a.shape[0], b.shape[0])
        w = min(a.shape[1], b.shape[1])
        a, b = a[:h, :w], b[:h, :w]
    win = _hann(a.shape)
    # log-compress the magnitude so the DC / low-freq spike doesn't dominate
    FA = np.log1p(np.abs(np.fft.fftshift(np.fft.fft2(a * win))))
    FB = np.log1p(np.abs(np.fft.fftshift(np.fft.fft2(b * win))))
    H, W = a.shape
    cy, cx = H / 2.0, W / 2.0
    maxr = min(cy, cx)
    nrad, nang = 256, 256
    log_base = np.log(maxr) / nrad
    radii = np.exp(np.arange(nrad) * log_base)
    angles = np.linspace(0, np.pi, nang, endpoint=False)  # FFT mag is symmetric -> [0,pi)
    ang_g, rad_g = np.meshgrid(angles, radii)
    xs = cx + rad_g * np.cos(ang_g)
    ys = cy + rad_g * np.sin(ang_g)
    xi = np.clip(np.round(xs).astype(int), 0, W - 1)
    yi = np.clip(np.round(ys).astype(int), 0, H - 1)
    lpa = FA[yi, xi]
    lpb = FB[yi, xi]
    # radial high-pass: down-weight low-radius (near-DC) rows that pin the peak at 0
    hp = (np.arange(nrad) / nrad)[:, None]
    lpa = lpa * hp
    lpb = lpb * hp
    # phase_corr returns shift a->b; rows=radius(log scale), cols=angle.
    # Spatial scale is the inverse of the frequency-domain radial shift.
    d_ang, d_rad = phase_corr(lpa, lpb, window=False)
    scale = float(np.exp(-d_rad * log_base))
    rot = float(d_ang * (180.0 / nang))
    return scale, rot


# ---------- trajectory recovery ----------

def recover_translation(frame_paths, region=None, dpr=1.0):
    """Per-frame (dx, dy) of `region` relative to frame 0, in CSS px (after DPR)."""
    base = _crop(load_gray(frame_paths[0]), region)
    out = [(0.0, 0.0)]
    for p in frame_paths[1:]:
        cur = _crop(load_gray(p), region)
        dx, dy = phase_corr(base, cur)
        out.append((dx / dpr, dy / dpr))
    return out


def locate_mover(frame_paths, thresh=0.06, min_area=50):
    """Coordinate-free auto-localization of the moving object's frame-0 bbox.

    Native screenshots have no DOM to read a bbox from, so find it from pixels:
    |frame0 - frameLast| has two blobs (object's start + end positions); the
    START blob is the one where frame0 itself is textured (the object), so pick
    the connected component with the highest frame-0 variance. Returns (x,y,w,h)
    in image px, or None.
    """
    cv2 = _cv2()
    f0 = (load_gray(frame_paths[0]) * 255).astype(np.uint8)
    fl = (load_gray(frame_paths[-1]) * 255).astype(np.uint8)
    if f0.shape != fl.shape:
        h = min(f0.shape[0], fl.shape[0])
        w = min(f0.shape[1], fl.shape[1])
        f0, fl = f0[:h, :w], fl[:h, :w]
    diff = cv2.absdiff(f0, fl)
    _, mask = cv2.threshold(diff, int(thresh * 255), 255, cv2.THRESH_BINARY)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    n, _lab, stats, _cent = cv2.connectedComponentsWithStats(mask, 8)
    best, best_var = None, -1.0
    for i in range(1, n):
        x, y, w, h, area = stats[i]
        if area < min_area:
            continue
        v = float(f0[y:y + h, x:x + w].astype(np.float32).var())
        if v > best_var:
            best_var, best = v, (int(x), int(y), int(w), int(h))
    return best


def active_segment(frame_paths, region, settle_frac=0.02, tmpl_idx=0):
    """Trim a realtime-captured sequence to the active-motion window.

    Realtime video has static lead-in/settle frames that would corrupt the fit.
    Track the object, then keep [first frame that departs the start, last frame
    that reaches the end], padded by one settle frame each side. Returns
    (indices, locs_trimmed).
    """
    locs = track_object(frame_paths, region, tmpl_idx=tmpl_idx)
    xs = [l[0] for l in locs]
    ys = [l[1] for l in locs]
    span = max(abs(xs[-1] - xs[0]), abs(ys[-1] - ys[0]), 1.0)
    tol = span * settle_frac
    n = len(locs)
    start = 0
    for i in range(n):
        if abs(xs[i] - xs[0]) > tol or abs(ys[i] - ys[0]) > tol:
            start = max(0, i - 1)
            break
    end = n - 1
    for i in range(n - 1, -1, -1):
        if abs(xs[i] - xs[-1]) > tol or abs(ys[i] - ys[-1]) > tol:
            end = min(n - 1, i + 1)
            break
    if end <= start:
        return list(range(n)), locs
    idx = list(range(start, end + 1))
    return idx, [locs[i] for i in idx]


def _cv2():
    try:
        import cv2
        return cv2
    except ImportError:
        raise SystemExit("object tracking needs OpenCV: "
                         "pip install opencv-python-headless")


def _subpix_peak(res, loc):
    """Sub-pixel refine a correlation-map peak via 3-point parabolic fit."""
    x, y = loc
    H, W = res.shape

    def parab(a, b, c):
        d = a - 2 * b + c
        return 0.0 if abs(d) < 1e-9 else 0.5 * (a - c) / d

    sx = parab(res[y, x - 1], res[y, x], res[y, x + 1]) if 0 < x < W - 1 else 0.0
    sy = parab(res[y - 1, x], res[y, x], res[y + 1, x]) if 0 < y < H - 1 else 0.0
    return float(x + sx), float(y + sy)


def track_object(frame_paths, region, shrink=0.2, tmpl_idx=0):
    """Track a template across frames by normalized cross-correlation. The
    robust engine for an object moving against a background -- the common UI
    case, where global phase correlation fails.

    `region` = (x, y, w, h) in IMAGE px (the element's bbox in frame `tmpl_idx`,
    obtained free from DOM getBoundingClientRect on web / UI-tree bounds native).
    `tmpl_idx` = which frame to crop the template from: 0 for a persistent
    object, -1 for an ENTERING element (absent in frame 0, settled at the end).
    Returns absolute [(x, y, confidence)] per frame, in IMAGE px.
    """
    cv2 = _cv2()
    tf = (load_gray(frame_paths[tmpl_idx]) * 255).astype(np.uint8)
    x, y, w, h = region
    mx, my = int(w * shrink), int(h * shrink)
    templ = tf[y + my:y + h - my, x + mx:x + w - mx]
    locs = []
    for p in frame_paths:
        f = (load_gray(p) * 255).astype(np.uint8)
        res = cv2.matchTemplate(f, templ, cv2.TM_CCOEFF_NORMED)
        _, maxv, _, maxloc = cv2.minMaxLoc(res)
        px, py = _subpix_peak(res, maxloc)
        locs.append((px, py, float(maxv)))
    return locs


def _pf_xy(xs, vals):
    """Like to_pf but with an explicit (possibly non-uniform) x-axis."""
    if len(vals) < 3:
        return None
    v0, vN = vals[0], vals[-1]
    span = vN - v0
    if abs(span) < 1e-9:
        return None
    return [(xs[i], (vals[i] - v0) / span) for i in range(len(vals))]


def _norm_axis(x):
    x0, xN = x[0], x[-1]
    span = (xN - x0) or 1.0
    return [(v - x0) / span for v in x]


def _scale_channel(frame_paths, region, xs):
    """Best-effort scale recovery via ORB + estimateAffinePartial2D (cv2).

    Features from the frame-0 element region matched into each frame; the
    partial-affine fit yields uniform scale. Flagged low-confidence: returns
    easing None when too few features/matches.
    """
    cv2 = _cv2()
    x, y, w, h = region
    f0 = (load_gray(frame_paths[0]) * 255).astype(np.uint8)
    tmpl = f0[y:y + h, x:x + w]
    orb = cv2.ORB_create(800)
    k0, d0 = orb.detectAndCompute(tmpl, None)
    if d0 is None or len(k0) < 8:
        return {"from": None, "to": None, "amp": None, "samples": 0,
                "reliable": False, "easing": None, "note": "insufficient features for scale"}
    bf = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True)
    scales, valid_x = [], []
    for i, p in enumerate(frame_paths):
        f = (load_gray(p) * 255).astype(np.uint8)
        k1, d1 = orb.detectAndCompute(f, None)
        if d1 is None:
            continue
        m = bf.match(d0, d1)
        if len(m) < 8:
            continue
        src = np.float32([k0[mm.queryIdx].pt for mm in m]).reshape(-1, 1, 2)
        dst = np.float32([k1[mm.trainIdx].pt for mm in m]).reshape(-1, 1, 2)
        M, _ = cv2.estimateAffinePartial2D(src, dst)
        if M is None:
            continue
        scales.append(float((M[0, 0] ** 2 + M[0, 1] ** 2) ** 0.5))
        valid_x.append(xs[i])
    if len(scales) < 3:
        return {"from": None, "to": None, "amp": None, "samples": len(scales),
                "reliable": False, "easing": None, "note": "too few scale samples"}
    pf = _pf_xy(valid_x, scales)
    fit = fit_easing(pf) if pf else {"name": None, "bezier": "-", "rms": 9}
    # Same shape as fit_channel: amp + samples + reliable + easing/bezier/rms.
    # motion_adapter.adapt_flipbook reads `amp` (with a to-from fallback), so
    # every channel — tx/ty/opacity/scale — must carry these keys for the
    # adapter to never silently drop a real scale recovery.
    out = {"from": round(scales[0], 3), "to": round(scales[-1], 3),
           "amp": round(scales[-1] - scales[0], 3),
           "samples": len(scales), "reliable": True}
    if fit["name"] is None:
        out["easing"] = None
    else:
        out.update(easing=fit["name"], bezier=fit["bezier"], rms=fit["rms"])
    return out


def analyze_frames(frame_paths, region, dpr=1.0, x=None, entering=False,
                   do_scale=False, conf_min=0.5, align=False):
    """Engine-agnostic recovery shared by every flipbook verb (web + native).

    Recovers tx / ty (template tracking) + opacity (region luminance) and,
    optionally, scale (ORB+affine). `x` = per-frame axis values (timeline ms or
    scroll px); None -> uniform. `entering`=True for elements absent in frame 0.
    Position channels (tx/ty) are gated by per-frame tracking confidence: frames
    where the object is not reliably visible are excluded, so a fade-in reports
    "no motion" instead of garbage. Returns per-channel easing fits + confidence.
    """
    tmpl_idx = -1 if entering else 0
    locs = track_object(frame_paths, region, tmpl_idx=tmpl_idx)
    ax, ay = (locs[-1][0], locs[-1][1]) if entering else (locs[0][0], locs[0][1])
    tx = [(l[0] - ax) / dpr for l in locs]
    ty = [(l[1] - ay) / dpr for l in locs]
    conf = [l[2] for l in locs]
    lum = region_luminance(frame_paths, region)
    n = len(frame_paths)
    xs = [i / (n - 1) for i in range(n)] if x is None else _norm_axis(x)
    channels = {}

    def fit_channel(series, gate):
        # gate=True -> drop low-confidence frames (position undefined there)
        if gate:
            idx = [i for i in range(n) if conf[i] >= conf_min]
        else:
            idx = list(range(n))
        if len(idx) < 3:
            return {"from": None, "to": None, "amp": None, "easing": None,
                    "reliable": False, "note": "object not reliably visible"}
        gx = [xs[i] for i in idx]
        gv = [series[i] for i in idx]
        out = {"from": round(gv[0], 3), "to": round(gv[-1], 3),
               "amp": round(gv[-1] - gv[0], 3),
               "samples": len(idx), "reliable": True}
        if align:
            # realtime/video: fit invariant to unknown t0/D (avoids the
            # easeOutCubic->easeOutQuad onset-misalignment bias)
            fit = fit_easing_aligned(gx, gv)
            if fit["name"] is None:
                out["easing"] = None
            else:
                out.update(easing=fit["name"], bezier=fit["bezier"], rms=fit["rms"])
        else:
            pf = _pf_xy(gx, gv)  # scrub: exact uniform timeline
            if pf is None:
                out["easing"] = None  # no net motion
            else:
                fit = fit_easing(pf)
                out.update(easing=fit["name"], bezier=fit["bezier"], rms=fit["rms"])
        return out

    channels["tx"] = fit_channel(tx, gate=True)
    channels["ty"] = fit_channel(ty, gate=True)
    channels["opacity"] = fit_channel(lum, gate=False)
    if do_scale:
        channels["scale"] = _scale_channel(frame_paths, region, xs)
    return {"frames": n, "min_confidence": round(min(conf), 3),
            "max_confidence": round(max(conf), 3),
            "entering": entering, "x_uniform": x is None, "channels": channels}


def region_luminance(frame_paths, region=None):
    """Per-frame mean luminance of `region` (opacity/fade proxy, low-confidence)."""
    return [float(_crop(load_gray(p), region).mean()) for p in frame_paths]


def to_pf(values):
    """Normalize a value series to fit_easing input: [(progress, value01)].

    progress = uniform index in [0,1] (driver samples are taken uniformly);
    value01 = (v - v0) / (vN - v0). Returns None if there is no net motion.
    """
    n = len(values)
    if n < 3:
        return None
    v0, vN = values[0], values[-1]
    span = vN - v0
    if abs(span) < 1e-9:
        return None
    return [(i / (n - 1), (values[i] - v0) / span) for i in range(n)]


# ---------- self-test: recover a KNOWN cubic-bezier from synthetic frames ----------

def _fourier_shift(img, dx, dy):
    """Exact sub-pixel translation via a frequency-domain phase ramp."""
    H, W = img.shape
    fy = np.fft.fftfreq(H)
    fx = np.fft.fftfreq(W)
    ramp = np.exp(-2j * np.pi * (fx[None, :] * dx + fy[:, None] * dy))
    return np.fft.ifft2(np.fft.fft2(img) * ramp).real


def _ease_out_cubic(p):
    return 1.0 - (1.0 - p) ** 3


def _self_test():
    from _anim_core import fit_easing
    rng = np.random.default_rng(0)
    # big texture; crop a centered window and shift it by a known easeOutCubic
    big = rng.random((520, 760)).astype(np.float32)
    H, W = 240, 360
    oy, ox = (big.shape[0] - H) // 2, (big.shape[1] - W) // 2
    amp = 120.0  # px of x-translation
    N = 24
    paths = []
    import tempfile, os
    d = tempfile.mkdtemp(prefix="flipbook-st-")
    truth, recovered = [], []
    base_crop = big[oy:oy + H, ox:ox + W]
    for i in range(N + 1):
        p = i / N
        off = amp * _ease_out_cubic(p)
        truth.append(off)
        shifted = _fourier_shift(big, off, 0.0)[oy:oy + H, ox:ox + W]
        path = os.path.join(d, f"f{i:03d}.png")
        Image.fromarray((np.clip(shifted, 0, 1) * 255).astype(np.uint8)).save(path)
        paths.append(path)
    traj = recover_translation(paths)
    recovered = [dx for dx, dy in traj]
    err = max(abs(r - t) for r, t in zip(recovered, truth))
    pf = to_pf(recovered)
    fit = fit_easing(pf)
    # cleanup
    for p in paths:
        os.remove(p)
    os.rmdir(d)
    ok_px = err < 0.5
    ok_fit = fit["name"] == "easeOutCubic" and fit["rms"] <= 0.05
    print(f"synthetic easeOutCubic amp={amp}px N={N}")
    print(f"  max recovery error : {err:.3f}px  ({'PASS' if ok_px else 'FAIL'} <0.5px)")
    print(f"  recovered tx end   : {recovered[-1]:.2f}px (truth {truth[-1]:.2f})")
    print(f"  easing fit         : {fit['name']} rms={fit['rms']} {fit['bezier']}  "
          f"({'PASS' if ok_fit else 'FAIL'})")
    # scale self-test via log-polar
    sc_truth = 2.0
    a = base_crop
    zoomed = _zoom(base_crop, sc_truth)
    sc, rot = logpolar_scale_rot(a, zoomed)
    ok_sc = abs(sc - sc_truth) / sc_truth < 0.08
    print(f"  scale recover      : {sc:.3f} (truth {sc_truth})  rot={rot:.2f}  "
          f"({'PASS' if ok_sc else 'FAIL'} <8%)")
    ok_obj = _self_test_object()
    ok_al = _self_test_aligned()
    return ok_px and ok_fit and ok_sc and ok_obj and ok_al


def _self_test_aligned():
    """fit_easing_aligned recovers the easing under an unknown time-origin (t0)
    and duration (D) -- the realtime/video case where plain index-fit aliases
    easeOutCubic -> easeOutQuad."""
    results = []
    for truth, (x1, y1, x2, y2) in (("easeOutCubic", (0.33, 1, 0.68, 1)),
                                     ("easeInOutQuart", (0.76, 0, 0.24, 1)),
                                     ("linear", (0, 0, 1, 1))):
        N = 24
        t0, D = 0.13, 0.78  # arbitrary unknown alignment
        cap = [i / (N - 1) for i in range(N)]  # uniform capture axis
        ys = []
        for c in cap:
            p = (c - t0) / D
            p = min(1.0, max(0.0, p))
            ys.append(_bez_y_progress(p, x1, y1, x2, y2))
        got = fit_easing_aligned(cap, ys)["nearest"]
        results.append((truth, got, truth == got))
    ok = all(r[2] for r in results)
    print("  aligned t0/D-inv   : " +
          ", ".join(f"{t}->{g}" for t, g, _ in results) +
          f"  ({'PASS' if ok else 'FAIL'})")
    return ok


def _self_test_object():
    """Object-on-background tracking (cv2 matchTemplate) -> known easeOutCubic.

    The common UI case (a textured object translating over a static background),
    where global phase correlation fails but template tracking succeeds.
    """
    try:
        _cv2()
    except SystemExit:
        print("  object track       : SKIP (cv2 not installed; numpy baseline still valid)")
        return True
    from _anim_core import fit_easing
    import tempfile
    import os
    rng = np.random.default_rng(2)
    H, W = 300, 700
    bg = (rng.random((H, W)) * 0.3 + 0.3).astype(np.float32)   # mid-gray noisy bg
    patch = rng.random((120, 120)).astype(np.float32)           # distinct textured object
    amp = 400.0
    N = 24
    d = tempfile.mkdtemp(prefix="flipbook-obj-")
    paths, truth = [], []
    py0 = 90
    for i in range(N + 1):
        off = amp * _ease_out_cubic(i / N)
        px0 = int(round(50 + off))
        truth.append(float(px0 - 50))
        frame = bg.copy()
        frame[py0:py0 + 120, px0:px0 + 120] = patch
        path = os.path.join(d, f"f{i:03d}.png")
        Image.fromarray((np.clip(frame, 0, 1) * 255).astype(np.uint8)).save(path)
        paths.append(path)
    traj = track_object(paths, (50, py0, 120, 120), shrink=0.15)
    x0 = traj[0][0]
    rec = [(l[0] - x0) for l in traj]
    err = max(abs(r - t) for r, t in zip(rec, truth))
    conf = min(c for _, _, c in traj)
    fit = fit_easing(to_pf(rec))
    for p in paths:
        os.remove(p)
    os.rmdir(d)
    ok = err < 1.0 and fit["name"] == "easeOutCubic" and fit["rms"] <= 0.02
    print(f"  object track       : amp {rec[-1]:.2f}px (truth {truth[-1]:.0f}) err {err:.3f}px "
          f"conf {conf:.3f} {fit['name']} rms={fit['rms']}  ({'PASS' if ok else 'FAIL'})")
    return ok


def _zoom(img, scale):
    """Center-zoom by `scale` (for the scale self-test), same output shape."""
    H, W = img.shape
    yy, xx = np.meshgrid(np.arange(H), np.arange(W), indexing="ij")
    cy, cx = H / 2.0, W / 2.0
    sy = (yy - cy) / scale + cy
    sx = (xx - cx) / scale + cx
    yi = np.clip(np.round(sy).astype(int), 0, H - 1)
    xi = np.clip(np.round(sx).astype(int), 0, W - 1)
    return img[yi, xi]


if __name__ == "__main__":
    import sys
    if "--self-test" in sys.argv:
        ok = _self_test()
        print("SELF-TEST:", "PASS" if ok else "FAIL")
        sys.exit(0 if ok else 1)
    print("usage: _flipbook.py --self-test")
