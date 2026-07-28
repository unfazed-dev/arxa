#!/usr/bin/env python3
"""Video -> lossless PNG frames at an exact fps, plus a dependency preflight.

Capture layer for the flipbook motion-recovery pipeline. Unlike a token-budget
video reader, this extracts LOSSLESS, full-resolution PNG at an exact uniform
fps -- sub-pixel phase correlation needs every pixel and a known, uniform dt
(JPEG block artifacts and frame-budget caps would destroy the recovery).

Time-axis convention: with `-vf fps=F` the output is uniformly spaced, so
frame i is at t = start + i / F seconds.

Modes:
  _frames.py --check                 silent preflight; exit 0 ready, 2 missing
  _frames.py --json                  machine-readable dependency status
  _frames.py --extract V --fps F ...  extract frames (debug / standalone use)

Preflight mirrors claude-video's setup.py UX (binary check + per-OS install
hints, never sudo) but for our deps: ffmpeg/ffprobe required, numpy/Pillow
required, cv2 (opencv-python) optional enhancement.
"""
from __future__ import annotations

import importlib.util
import json
import shutil
import subprocess
import sys
from pathlib import Path

REQUIRED_BIN = ["ffmpeg", "ffprobe"]
REQUIRED_PY = ["numpy", "PIL"]
OPTIONAL_PY = ["cv2"]  # opencv-python: enables ORB+affine / optical-flow path


# ---------- time helpers ----------

def parse_time(value):
    """Parse SS, MM:SS, or HH:MM:SS (optional .ms) into seconds."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    s = str(value).strip()
    if not s:
        return None
    parts = s.split(":")
    try:
        if len(parts) == 1:
            return float(parts[0])
        if len(parts) == 2:
            return int(parts[0]) * 60 + float(parts[1])
        if len(parts) == 3:
            return int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])
    except ValueError:
        pass
    raise SystemExit(f"cannot parse time: {value!r} (expected SS, MM:SS, HH:MM:SS)")


def format_time(seconds):
    total = int(round(seconds))
    h, rem = divmod(total, 3600)
    m, s = divmod(rem, 60)
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"


# ---------- metadata ----------

def get_metadata(video_path) -> dict:
    if shutil.which("ffprobe") is None:
        raise SystemExit("ffprobe not installed (brew install ffmpeg)")
    r = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "json",
         "-show_format", "-show_streams", str(Path(video_path).resolve())],
        capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"ffprobe failed: {r.stderr.strip()}")
    data = json.loads(r.stdout or "{}")
    streams = data.get("streams", [])
    fmt = data.get("format", {})
    v = next((s for s in streams if s.get("codec_type") == "video"), {})
    return {
        "duration_seconds": float(fmt.get("duration") or v.get("duration") or 0),
        "width": v.get("width"),
        "height": v.get("height"),
        "fps": _fps_ratio(v.get("avg_frame_rate") or v.get("r_frame_rate") or "0/0"),
        "codec": v.get("codec_name"),
    }


def _fps_ratio(s):
    try:
        num, _, den = str(s).partition("/")
        den = float(den) if den else 1.0
        return float(num) / den if den else 0.0
    except (ValueError, ZeroDivisionError):
        return 0.0


# ---------- extraction (lossless PNG, exact fps, no budget cap) ----------

def extract(video_path, out_dir, fps, start_seconds=None, end_seconds=None,
            accurate=True) -> list[dict]:
    """Extract uniform-fps lossless PNG frames. Returns [{path, t}] in order."""
    if shutil.which("ffmpeg") is None:
        raise SystemExit("ffmpeg not installed (brew install ffmpeg)")
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    src = str(Path(video_path).resolve())
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"]
    if accurate:
        # decode-from-zero seek = frame-accurate (-ss AFTER -i); -t avoids the
        # -to/-ss relativity footgun. Precision matters for motion timing.
        cmd += ["-i", src]
        if start_seconds is not None:
            cmd += ["-ss", f"{start_seconds:.3f}"]
        if end_seconds is not None:
            dur = end_seconds - (start_seconds or 0.0)
            cmd += ["-t", f"{max(0.0, dur):.3f}"]
    else:
        # fast keyframe-snap seek (-ss BEFORE -i)
        if start_seconds is not None:
            cmd += ["-ss", f"{start_seconds:.3f}"]
        cmd += ["-i", src]
        if end_seconds is not None:
            dur = end_seconds - (start_seconds or 0.0)
            cmd += ["-t", f"{max(0.0, dur):.3f}"]
    pattern = str(out_dir / "f%05d.png")
    cmd += ["-vf", f"fps={fps}", "-start_number", "0", pattern]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"ffmpeg extract failed: {r.stderr.strip()}")
    base = start_seconds or 0.0
    frames = sorted(out_dir.glob("f*.png"))
    return [{"path": str(p), "t": base + i / fps} for i, p in enumerate(frames)]


# ---------- dependency preflight ----------

def _bin_missing():
    return [b for b in REQUIRED_BIN if shutil.which(b) is None]


def _py_missing(mods):
    return [m for m in mods if importlib.util.find_spec(m) is None]


def status() -> dict:
    bm = _bin_missing()
    pm = _py_missing(REQUIRED_PY)
    opt = _py_missing(OPTIONAL_PY)
    return {
        "status": "ready" if not bm and not pm else "missing",
        "binaries_missing": bm,
        "python_missing": pm,
        "optional_missing": opt,
        "cv2": "cv2" not in opt,
    }


def install_hints(s) -> list[str]:
    import platform
    osn = platform.system()
    hints = []
    if s["binaries_missing"]:
        if osn == "Darwin":
            hints.append("ffmpeg: `brew install ffmpeg`")
        elif osn == "Linux":
            hints.append("ffmpeg: `sudo apt install ffmpeg` or `sudo dnf install ffmpeg`")
        else:
            hints.append("ffmpeg: `winget install Gyan.FFmpeg`")
    if s["python_missing"]:
        hints.append("python deps: `pip install " +
                     " ".join("Pillow" if m == "PIL" else m for m in s["python_missing"]) + "`")
    if s["optional_missing"]:
        hints.append("optional (richer scale/rotation via ORB+affine): "
                     "`pip install opencv-python`")
    return hints


def _main():
    args = sys.argv[1:]
    if "--json" in args:
        print(json.dumps({**status(), "hints": install_hints(status())}, indent=2))
        return 0
    if "--check" in args:
        s = status()
        if s["status"] == "ready":
            return 0
        for h in install_hints(s):
            sys.stderr.write(f"[flipbook] missing — {h}\n")
        return 2
    if "--extract" in args:
        i = args.index("--extract")
        video = args[i + 1]
        def opt(flag, default=None):
            return args[args.index(flag) + 1] if flag in args else default
        fps = float(opt("--fps", "30"))
        start = parse_time(opt("--start"))
        end = parse_time(opt("--end"))
        out = opt("--out-dir", "/tmp/flipbook-frames")
        frames = extract(video, out, fps, start, end)
        print(json.dumps({"count": len(frames), "out_dir": out,
                          "first": frames[0] if frames else None,
                          "last": frames[-1] if frames else None}, indent=2))
        return 0
    print(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(_main())
