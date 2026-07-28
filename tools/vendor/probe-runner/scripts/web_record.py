#!/usr/bin/env python3
"""Record a video of the active web target.

Chrome path: CDP Page.screencastFrame stream → mjpeg → ffmpeg → mp4.
Safari path: macOS screencapture of the Safari window for N seconds.

Usage:
  web_record.py --seconds N
  web_record.py --seconds N --out /tmp/clip.mp4
  web_record.py --seconds N --browser=safari --out /tmp/clip.mov
"""

from __future__ import annotations

import argparse
import base64
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import OUTDIR, die, emit_path, out_path, ts
from _web import ensure_browser


def _chrome_record(handle: dict, seconds: int, out: Path | None = None,
                   scroll: bool = False) -> Path:
    try:
        from websocket import (  # type: ignore
            create_connection,
            WebSocketTimeoutException,
            WebSocketConnectionClosedException,
        )
    except ImportError:
        die("missing websocket-client: pip3 install websocket-client")

    ws = create_connection(handle["webSocketDebuggerUrl"], timeout=10)
    nid = 0

    def send(method: str, params: dict | None = None) -> int:
        nonlocal nid
        nid += 1
        ws.send(json.dumps({"id": nid, "method": method, "params": params or {}}))
        return nid

    # --scroll: own the motion on THIS connection (no separate process, no
    # race). Kick a single in-page rAF sweep top→bottom over the capture
    # window — fire-and-forget so the loop below stays free to drain frames at
    # full rate. Driving scroll per-iteration instead floods recv with command
    # responses and starves the ACK-gated screencast (drops ~40fps → ~2fps).
    if scroll:
        dur_ms = max(1, int(seconds * 0.9 * 1000))
        # scrollBehavior='auto' defeats CSS `scroll-behavior:smooth`; without it
        # each per-frame scrollTo restarts an eased animation toward a moving
        # target and the page never traverses (verified on scroll-jacked sites).
        send("Runtime.evaluate", {"expression": (
            "(()=>{const de=document.documentElement;"
            "de.style.scrollBehavior='auto';document.body.style.scrollBehavior='auto';"
            "const tot=de.scrollHeight-innerHeight;const t0=performance.now();"
            "function s(){const k=Math.min((performance.now()-t0)/%d,1);"
            "window.scrollTo(0,k*tot);if(k<1)requestAnimationFrame(s);}"
            "window.scrollTo(0,0);requestAnimationFrame(s);})()" % dur_ms
        )})

    send("Page.startScreencast", {
        "format": "jpeg", "quality": 70, "everyNthFrame": 1,
    })
    ws.settimeout(0.5)

    frames_dir = OUTDIR / f"web-{ts()}-frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    end = time.monotonic() + seconds
    i = 0
    while time.monotonic() < end:
        try:
            raw = ws.recv()
        except WebSocketTimeoutException:
            continue  # no frame this tick (static page) — keep recording
        except (WebSocketConnectionClosedException, OSError):
            break  # tab/connection gone — stop
        if not raw:
            continue
        msg = json.loads(raw)
        if msg.get("method") == "Page.screencastFrame":
            data = base64.b64decode(msg["params"]["data"])
            (frames_dir / f"f_{i:06d}.jpg").write_bytes(data)
            send("Page.screencastFrameAck",
                 {"sessionId": msg["params"]["sessionId"]})
            i += 1
    send("Page.stopScreencast")
    ws.close()

    if i == 0:
        die(f"no screencast frames captured over {seconds}s; is the tab visible?")
        return Path()

    out = out if out is not None else out_path("web", "mp4")
    ff = shutil.which("ffmpeg")
    if not ff:
        die(f"frames captured at {frames_dir}; install ffmpeg to encode (brew install ffmpeg)")
        return Path()
    # Match playback duration to capture: fps = frames / wall-clock seconds.
    fps = max(1, round(i / seconds)) if seconds else 10
    subprocess.run(
        [ff, "-y", "-framerate", str(fps), "-i", str(frames_dir / "f_%06d.jpg"),
         "-c:v", "libx264", "-pix_fmt", "yuv420p", str(out)],
        check=True, capture_output=True,
    )
    return out


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--seconds", type=int, required=True)
    p.add_argument("--browser", default="auto", choices=["chrome", "safari", "auto"])
    p.add_argument("--out", help="output file path (default: auto-named in PROBE_RUNNER_OUTDIR)")
    p.add_argument("--scroll", action="store_true",
                   help="sweep the page top→bottom during capture (chrome only)")
    args = p.parse_args()

    try:
        engine, handle = ensure_browser(args.browser)
    except Exception as e:
        die(str(e))

    out_override = Path(args.out) if args.out else None

    if engine == "chrome":
        emit_path(_chrome_record(handle, args.seconds, out_override, scroll=args.scroll))
        return 0

    # Safari: macOS screencapture of the Safari app window.
    o = out_override if out_override is not None else out_path("web", "mov")
    win_id_proc = subprocess.run(
        ["osascript", "-e",
         'tell application "System Events" to id of window 1 of (first process whose frontmost is true)'],
        capture_output=True, text=True, check=False,
    )
    subprocess.run(["screencapture", "-V", str(args.seconds), str(o)], check=True)
    handle.quit()
    emit_path(o)
    return 0


if __name__ == "__main__":
    sys.exit(main())
