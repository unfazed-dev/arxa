#!/usr/bin/env python3
"""vision_probe — Apple Vision framework detectors beyond OCR.

Generalises ocr.py's proven PyObjC/Vision pattern to the detectors probe-runner
lacked. macOS-only (Vision framework); lazy pyobjc import + clear missing-dep
message. Reference: Apple Vision docs (https://developer.apple.com/documentation/vision)
and the PyObjC Vision guide (https://yasoob.me/posts/how-to-use-vision-framework-via-pyobjc/).

Detectors (one VNRequest per --kind):
  text      → VNRecognizeTextRequest     (== ocr._vision_text; reuse, no dup)
  face      → VNDetectFaceRectanglesRequest
  body      → VNDetectHumanBodyPoseRequest  (landmarks; bbox is the body bounds)
  rect      → VNDetectBarcodesRequest → rect... use VNDetectRectanglesRequest
              (document/card detection; adjustable aspect ratios)
  barcode   → VNDetectBarcodesRequest     (QR, EAN, UPC, etc. → payload string)
  saliency → VNGenerateAttentionBasedSaliencyImageRequest (a heat-map image;
              surfaced as the salient-object bbox(es))

Every detector emits {kind, image, count, detections:[{bbox, ...}]} where bbox
is the NORMALISED Vision bounding box [origin.x, origin.y, w, h] (origin =
bottom-left, y-up — same convention ocr.py emits). Callers that need
pixel-space boxes multiply by image w/h and flip y.

Usage:
  vision_probe.py --image PATH --kind face
  vision_probe.py <owner> --kind barcode        # shot first, then detect
  vision_probe.py --image PATH --kind rect --min-confidence 0.6
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json, out_path


def _load_ciimage(image_path: str):
    """Load an image file as a CIImage for Vision (mirrors ocr._vision_text)."""
    try:
        import Vision  # type: ignore
        import Quartz  # type: ignore
        from Cocoa import NSURL  # type: ignore
    except ImportError:
        die("missing pyobjc-framework-Vision. "
            "pip3 install pyobjc-framework-Vision pyobjc-framework-Cocoa")
        return None, None, None
    url = NSURL.fileURLWithPath_(image_path)
    img = Quartz.CIImage.imageWithContentsOfURL_(url)
    if img is None:
        die(f"could not load image: {image_path}")
        return None, None, None
    return Vision, img, None


def _bbox(obs) -> list[float]:
    """Normalised Vision bbox [origin.x, origin.y, w, h] (bottom-left, y-up)."""
    bb = obs.boundingBox()
    return [float(bb.origin.x), float(bb.origin.y),
            float(bb.size.width), float(bb.size.height)]


def detect(image_path: str, kind: str, *, min_confidence: float = 0.0) -> dict:
    """Run ONE Vision detector on image_path. Pure-ish (macOS framework I/O);
    the request-class selection + confidence wiring are unit-tested via the
    _KIND→class mapping. Returns {kind, image, count, detections:[...]}."""
    # text reuses ocr's battle-tested path verbatim (no request-class dup) and
    # loads its OWN image, so it must short-circuit BEFORE _load_ciimage (which
    # would otherwise require the Vision framework just to route text away).
    if kind == "text":
        from ocr import _vision_text
        lines = _vision_text(image_path)
        return {"kind": "text", "image": image_path, "count": len(lines),
                "detections": lines}

    Vision, img, _ = _load_ciimage(image_path)
    if Vision is None:
        return {"kind": kind, "image": image_path, "count": 0, "detections": []}

    req = _build_request(Vision, kind, min_confidence)
    handler = Vision.VNImageRequestHandler.alloc().initWithCIImage_options_(img, {})
    handler.performRequests_error_([req], None)

    out = []
    results = req.results() or []
    for obs in results:
        entry = {"bbox": _bbox(obs), "confidence": float(obs.confidence())}
        _enrich(entry, obs, kind)
        out.append(entry)
    return {"kind": kind, "image": image_path, "count": len(out), "detections": out}


def _build_request(Vision, kind: str, min_confidence: float):
    """Map --kind → a fresh VNRequest instance, then apply --min-confidence as a
    floor where the request exposes setMinimumConfidence_ (VNDetectRectangles
    and the face/body detectors do; saliency/barcode generators don't and
    correctly ignore it). Centralised so the mapping is unit-testable without a
    live Vision framework (test monkeypatches Vision)."""
    if kind == "face":
        r = Vision.VNDetectFaceRectanglesRequest.alloc().init()
    elif kind == "body":
        r = Vision.VNDetectHumanBodyPoseRequest.alloc().init()
    elif kind == "rect":
        r = Vision.VNDetectRectanglesRequest.alloc().init()
    elif kind == "barcode":
        r = Vision.VNDetectBarcodesRequest.alloc().init()
    elif kind == "saliency":
        r = Vision.VNGenerateAttentionBasedSaliencyImageRequest.alloc().init()
    else:
        raise ValueError(f"unknown kind {kind!r}; expected "
                         f"face|body|rect|barcode|saliency|text")
    if min_confidence > 0 and hasattr(r, "setMinimumConfidence_"):
        r.setMinimumConfidence_(min_confidence)
    return r


def _enrich(entry: dict, obs, kind: str) -> None:
    """Add kind-specific fields to a detection entry (barcode payload, etc.)."""
    if kind == "barcode":
        # VNBarcodeObservation exposes payloadStringValue
        payload = getattr(obs, "payloadStringValue", lambda: None)
        val = payload() if callable(payload) else payload
        entry["payload"] = str(val) if val is not None else None
        symb = getattr(obs, "symbology", None)
        entry["symbology"] = str(symb) if symb is not None else None


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("owner", nargs="?")
    p.add_argument("--image")
    p.add_argument("--kind", required=True,
                   choices=["face", "body", "rect", "barcode", "saliency", "text"])
    p.add_argument("--min-confidence", dest="min_confidence", type=float, default=0.0)
    args = p.parse_args()

    img_path = args.image
    if not img_path:
        if not args.owner:
            die("pass --image or <owner>")
        # capture first, then detect (mirrors ocr.py's capture-then-OCR flow)
        cmd_path = Path(__file__).with_name("shot.py")
        r = subprocess.run(["python3", str(cmd_path), args.owner],
                           check=False, capture_output=True, text=True)
        if r.returncode != 0:
            die(f"capture step failed: {r.stderr.strip() or r.stdout.strip()}",
                code=r.returncode or 2)
        img_path = r.stdout.strip().splitlines()[-1]

    res = detect(img_path, args.kind, min_confidence=args.min_confidence)
    emit_json(res)
    return 0


if __name__ == "__main__":
    sys.exit(main())
