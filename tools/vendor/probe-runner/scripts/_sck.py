#!/usr/bin/env python3
"""ScreenCaptureKit bridge — zero-copy GPU frame capture on macOS 12.3+ via
pyobjc-framework-ScreenCaptureKit.

This is the modern, low-latency successor to the legacy CLI `screencapture`
path used by `shot.py`/`record.py`. ScreenCaptureKit delivers frames straight
off the compositor surface (no per-frame PNG encode to disk mid-capture), with
per-window content filters — materially lower latency than shelling to
`screencapture -V`. Reference: Apple ScreenCaptureKit docs
(https://developer.apple.com/documentation/screencapturekit/) and the working
PyObjC SCStream example (https://github.com/ronaldoussoren/pyobjc/issues/590).

The verbs (`shot`/`record`/`multishot`) route here ONLY when
`_platform.has_screencapturekit()` is True (macOS 12.3+ AND the binding
installed); otherwise they fall back to the legacy CLI path unchanged. So this
module is OPTIONAL — lazy-imported, never breaks a non-macOS or pre-12.3 run.

Entry point: capture_window_still(window_id, out_path) — one PNG frame of a
window. (Video capture via SCStreamConfiguration.setURL_ is a future route;
record.py stays on the legacy screencapture CLI for now.)

TCC: ScreenCaptureKit still requires the Screen Recording permission; callers
run `tcc_check("screen_recording")` first (unchanged from the legacy path).
"""
from __future__ import annotations

import io
import time
from pathlib import Path
from typing import Any


def _import_sck():
    """Lazy import; raises ImportError with a clear message if unavailable."""
    try:
        import ScreenCaptureKit  # type: ignore
        import Quartz  # type: ignore
        return ScreenCaptureKit, Quartz
    except ImportError as e:
        raise ImportError(
            "ScreenCaptureKit bridge unavailable: %s. Install the optional dep: "
            "pip3 install pyobjc-framework-ScreenCaptureKit (macOS 12.3+). "
            "probe-runner falls back to the legacy `screencapture` CLI path "
            "without it." % e)


def _resolve_window_filter(window_id: int):
    """Build an SCContentFilter for a single window (by CGWindowID), excluding
    the desktop. Returns the filter or raises."""
    ScreenCaptureKit, Quartz = _import_sck()
    # SCShareableContent.excludingDesktopWindows:onScreenWindowsOnly: is async
    # (a completion handler). PyObjC exposes the sync helper
    # shareableContentExcludingDesktopWindows:onScreenWindowsOnly:completionHandler:
    # — we pass a Python block that captures the result.
    content = _sync_shareable_content(ScreenCaptureKit)
    target = None
    for win in content.windows():
        if win.windowID() == window_id:
            target = win
            break
    if target is None:
        raise RuntimeError(
            f"window id {window_id} not found in SCShareableContent "
            f"(is it on-screen? screen recording granted?)")
    # Single-window filter: the most precise (no other windows composited in).
    return ScreenCaptureKit.SCContentFilter.alloc().initWithDesktopIndependentWindow_(target)


def _sync_shareable_content(ScreenCaptureKit):
    """Call the async SCShareableContent getter synchronously via a completion
    block. Returns the SCShareableContent object or raises on error."""
    result: dict[str, Any] = {"content": None, "error": None}

    def _handler(_content, _error):
        result["content"] = _content
        result["error"] = _error

    ScreenCaptureKit.SCShareableContent.shareableContentExcludingDesktopWindows_onScreenWindowsOnly_completionHandler_(
        True, True, _handler)
    # Spin the runloop until the completion handler fires (PyObjC pattern).
    from CoreFoundation import CFRunLoopRunInMode, kCFRunLoopDefaultMode  # type: ignore
    deadline = time.monotonic() + 5.0
    while result["content"] is None and result["error"] is None and time.monotonic() < deadline:
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, False)
    if result["error"] is not None:
        raise RuntimeError("SCShareableContent fetch failed: %s" % result["error"])
    if result["content"] is None:
        raise RuntimeError("SCShareableContent fetch timed out (screen recording permission?)")
    return result["content"]


def _pixel_buffer_to_png(buffer, out_path: str) -> None:
    """Write a CVPixelBuffer (BGRA) to a PNG file via Pillow. ScreenCaptureKit
    delivers BGRA frames; Pillow has no direct CVBuffer reader, so we read the
    raw bytes via CoreVideo and reshape."""
    from CoreVideo import (  # type: ignore
        CVPixelBufferLockBaseAddress, CVPixelBufferUnlockBaseAddress,
        CVPixelBufferGetBaseAddress, CVPixelBufferGetWidth,
        CVPixelBufferGetHeight, CVPixelBufferGetBytesPerRow,
        kCVPixelFormatType_32BGRA,  # noqa: F401 (format constant)
    )
    import ctypes
    import numpy as np
    from PIL import Image

    CVPixelBufferLockBaseAddress(buffer, 0)
    try:
        base = CVPixelBufferGetBaseAddress(buffer)
        width = CVPixelBufferGetWidth(buffer)
        height = CVPixelBufferGetHeight(buffer)
        bpr = CVPixelBufferGetBytesPerRow(buffer)
        # BGRA → RGB. bpr may exceed width*4 (row padding); slice per row.
        # PyObjC returns a raw pointer (int/void*); wrap with ctypes for numpy.
        buf = (ctypes.c_ubyte * (bpr * height)).from_address(int(base))
        arr = np.frombuffer(buf, dtype=np.uint8).reshape((height, bpr))
        arr = arr[:, :width * 4].reshape((height, width, 4))  # BGRA
        rgb = arr[:, :, [2, 1, 0]]  # → RGB (drop alpha)
        Image.fromarray(rgb).save(out_path)
    finally:
        CVPixelBufferUnlockBaseAddress(buffer, 0)


# CoreVideo helpers (CVPixelBufferGet*) are imported inline in
# _pixel_buffer_to_png above — pyobjc-framework-CoreVideo re-exports them
# directly, so no module-level re-export shims are needed here.


def capture_window_still(window_id: int, out_path: str) -> str:
    """Capture a single PNG frame of a window via ScreenCaptureKit.

    Spins an SCStream for one frame, writes it to out_path, returns out_path.
    Higher fidelity + lower latency than `screencapture -l <wid>`."""
    ScreenCaptureKit, Quartz = _import_sck()
    filt = _resolve_window_filter(window_id)
    config = ScreenCaptureKit.SCStreamConfiguration.alloc().init()
    # one-shot: capture a single frame via SCScreenshotManager (the still-image
    # API), which is simpler + more reliable than streaming for one frame.
    mgr = ScreenCaptureKit.SCScreenshotManager.alloc().init()
    result: dict[str, Any] = {"buffer": None, "error": None}

    def _handler(_buf, _err):
        result["buffer"] = _buf
        result["error"] = _err

    # captureImageWithFilter:configuration:completionHandler: (macOS 14+). On
    # 12.3–13 the SCStream path is the fallback; detect availability.
    if hasattr(mgr, "captureImageWithFilter_configuration_completionHandler_"):
        mgr.captureImageWithFilter_configuration_completionHandler_(filt, config, _handler)
    else:
        return _capture_still_via_stream(ScreenCaptureKit, filt, config, out_path)

    from CoreFoundation import CFRunLoopRunInMode, kCFRunLoopDefaultMode  # type: ignore
    deadline = time.monotonic() + 5.0
    while result["buffer"] is None and result["error"] is None and time.monotonic() < deadline:
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, False)
    if result["error"] is not None:
        raise RuntimeError("ScreenCaptureKit still capture failed: %s" % result["error"])
    if result["buffer"] is None:
        raise RuntimeError("ScreenCaptureKit still capture timed out")
    _pixel_buffer_to_png(result["buffer"], out_path)
    return out_path


def _capture_still_via_stream(ScreenCaptureKit, filt, config, out_path):
    """macOS 12.3–13 fallback: open an SCStream, grab the first delivered frame,
    stop the stream. Used when SCScreenshotManager.captureImage... is absent."""
    result: dict[str, Any] = {"buffer": None, "done": False}

    class _Output:
        def stream_didOutputSampleBuffer_ofType_(self, stream, sample_buffer, stype):
            if result["buffer"] is None and str(stype) == "screen":
                from CoreVideo import CVBufferGetImageBuffer  # type: ignore
                ib = CVBufferGetImageBuffer(sample_buffer)
                if ib is not None:
                    result["buffer"] = ib
                    result["done"] = True

    stream = ScreenCaptureKit.SCStream.alloc().initWithFilter_configuration_delegate_(
        filt, config, _Output())
    stream.startCaptureWithCompletionHandler_(lambda _e: None)
    from CoreFoundation import CFRunLoopRunInMode, kCFRunLoopDefaultMode  # type: ignore
    deadline = time.monotonic() + 5.0
    while not result["done"] and time.monotonic() < deadline:
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, False)
    stream.stopCaptureWithCompletionHandler_(lambda: None)
    if result["buffer"] is None:
        raise RuntimeError("ScreenCaptureKit stream capture timed out")
    _pixel_buffer_to_png(result["buffer"], out_path)
    return out_path
