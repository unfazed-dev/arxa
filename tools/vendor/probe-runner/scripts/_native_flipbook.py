#!/usr/bin/env python3
"""Platform-agnostic flipbook recovery from a screen-recorded VIDEO.

Every native target (Flutter / iOS / Android app) lacks the web's DOM + WAAPI,
so the only universal input is a screen recording. This is the shared core the
native verbs orchestrate: video -> uniform-fps lossless frames -> motion law.

  recover_from_video(video, fps[, region]) -> analyze_frames-shape dict

Region is optional: pass the element's frame-0 bbox when introspection provides
one (Flutter VM `getTransformTo`, UI-tree bounds) for a precise template;
otherwise the mover is auto-located coordinate-free from the pixels themselves.
Video timing is a capture-time axis with unknown t0/duration, so the recovery
always uses the t0/D-invariant aligned fit (`analyze_frames(align=True)`).
"""
from __future__ import annotations

import tempfile
from pathlib import Path

from _frames import extract
from _flipbook import analyze_frames, locate_mover, active_segment


def recover_from_video(video_path, fps=30, region=None, dpr=1.0, do_scale=False,
                       trim=True, conf_min=0.5, start=None, end=None,
                       workdir=None):
    """Recover an animation's motion law from `video_path`.

    `region` = (x, y, w, h) image-px template bbox, or None to auto-locate.
    `trim` drops the static record-spin-up / settle frames that bracket a real
    recording. Returns the `analyze_frames` dict plus a `video` block.
    """
    workdir = workdir or tempfile.mkdtemp(prefix="natfb-")
    frames = extract(video_path, workdir, fps, start, end)
    paths = [f["path"] for f in frames]
    xs = [f["t"] for f in frames]
    if len(paths) < 3:
        raise SystemExit(f"need >=3 frames, got {len(paths)} "
                         f"(raise --fps or lengthen the recording)")

    if region is None:
        region = locate_mover(paths)
        if region is None:
            raise SystemExit("could not auto-locate a moving object; pass --region")
    region = tuple(int(v) for v in region)

    if trim:
        idx, _locs = active_segment(paths, region)
        paths = [paths[i] for i in idx]
        xs = [xs[i] for i in idx]

    res = analyze_frames(paths, region, dpr=dpr, x=xs, do_scale=do_scale,
                         conf_min=conf_min, align=True)
    res["video"] = {"path": str(video_path), "fps": fps, "region": list(region),
                    "dpr": dpr, "frames_extracted": len(frames),
                    "frames_used": len(paths), "workdir": workdir}
    return res


def _main():
    import argparse
    import json
    p = argparse.ArgumentParser(description="recover motion law from a video")
    p.add_argument("--video", required=True)
    p.add_argument("--fps", type=float, default=30)
    p.add_argument("--region", help="x,y,w,h image-px template (else auto-locate)")
    p.add_argument("--dpr", type=float, default=1.0)
    p.add_argument("--scale", action="store_true")
    p.add_argument("--no-trim", action="store_true")
    p.add_argument("--start", type=float, default=None)
    p.add_argument("--end", type=float, default=None)
    args = p.parse_args()
    region = tuple(int(v) for v in args.region.split(",")) if args.region else None
    res = recover_from_video(args.video, fps=args.fps, region=region, dpr=args.dpr,
                             do_scale=args.scale, trim=not args.no_trim,
                             start=args.start, end=args.end)
    print(json.dumps(res, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
