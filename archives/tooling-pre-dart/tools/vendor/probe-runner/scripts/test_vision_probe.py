#!/usr/bin/env python3
"""Tests for vision_probe — the Vision request-class mapping + bbox/enrich logic.

Hermetic: the request-builder + enricher are pure and unit-testable without a
live Vision framework (we inject a fake Vision module). The end-to-end detect()
path (which needs macOS Vision + a real image) lives in derisk_*.py.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pytest

import vision_probe as vp


# ─── _build_request: kind → VNRequest mapping ────────────────────────────────

class _FakeReq:
    """Minimal stand-in for a VN*Request: records its class name."""
    def __init__(self, cls):
        self.cls = cls
        self._results = []
    def results(self):
        return self._results


class _FakeReqClass:
    """A fake *Request Objective-C-style class: .alloc().init() → _FakeReq."""
    def __init__(self, name):
        self.name = name
    def alloc(self):
        return self
    def init(self):
        return _FakeReq(self.name)


class _FakeVision:
    """A fake Vision module: each *Request class builds a _FakeReq tagged with
    its name, so the mapping is verifiable without the real framework."""
    VNDetectFaceRectanglesRequest = _FakeReqClass("Face")
    VNDetectHumanBodyPoseRequest = _FakeReqClass("Body")
    VNDetectRectanglesRequest = _FakeReqClass("Rect")
    VNDetectBarcodesRequest = _FakeReqClass("Barcode")
    VNGenerateAttentionBasedSaliencyImageRequest = _FakeReqClass("Saliency")
    # detect() uses VNImageRequestHandler (mocked per-test via monkeypatch)


def test_build_request_face():
    r = vp._build_request(_FakeVision, "face", 0.0)
    assert r.cls == "Face"


def test_build_request_body():
    r = vp._build_request(_FakeVision, "body", 0.0)
    assert r.cls == "Body"


def test_build_request_rect():
    r = vp._build_request(_FakeVision, "rect", 0.0)
    assert r.cls == "Rect"


def test_build_request_barcode():
    r = vp._build_request(_FakeVision, "barcode", 0.0)
    assert r.cls == "Barcode"


def test_build_request_saliency():
    r = vp._build_request(_FakeVision, "saliency", 0.0)
    assert r.cls == "Saliency"


def test_build_request_unknown_raises():
    with pytest.raises(ValueError) as ei:
        vp._build_request(_FakeVision, "nonsense", 0.0)
    assert "unknown kind" in str(ei.value)


def test_build_request_applies_min_confidence_when_supported():
    """min_confidence > 0 is forwarded to setMinimumConfidence_ when the request
    exposes it (rect/face/body). Proves the knob is wired, not a no-op."""
    class _ConfReqClass:
        def __init__(self, name):
            self.name = name
        def alloc(self):
            return self
        def init(self):
            return _ConfReq(self.name)

    class _ConfReq:
        def __init__(self, name):
            self.cls = name
            self.applied = None
        def setMinimumConfidence_(self, c):
            self.applied = c

    class _V:
        VNDetectRectanglesRequest = _ConfReqClass("Rect")
    r = vp._build_request(_V, "rect", 0.6)
    assert r.cls == "Rect"
    assert r.applied == 0.6          # forwarded


def test_build_request_skips_min_confidence_for_kinds_without_it():
    """saliency/barcode generators have no setMinimumConfidence_ — min_confidence
    must be silently ignored (not raise), so the flag stays harmless there."""
    r = vp._build_request(_FakeVision, "saliency", 0.5)
    assert r.cls == "Saliency"       # built; no confidence applied (none to set)


def test_build_request_zero_min_confidence_never_calls_setter():
    """min_confidence == 0 (the default) never touches the request's setter,
    even when the request supports it."""
    class _ConfReq:
        def __init__(self):
            self.cls = "Rect"
            self.applied = "UNTOUCHED"
        def setMinimumConfidence_(self, c):
            self.applied = c

    class _ConfReqClass:
        def alloc(self):
            return self
        def init(self):
            return _ConfReq()

    class _V:
        VNDetectRectanglesRequest = _ConfReqClass()
    r = vp._build_request(_V, "rect", 0.0)
    assert r.applied == "UNTOUCHED"  # default 0 → setter never called


def test_build_request_text_not_routed_here():
    """text reuses ocr._vision_text; _build_request is never called for it.
    Calling it with text should raise (no text request class here)."""
    with pytest.raises(ValueError):
        vp._build_request(_FakeVision, "text", 0.0)


# ─── _bbox + _enrich ──────────────────────────────────────────────────────────

class _FakeBox:
    def __init__(self, x, y, w, h):
        self.origin = type("O", (), {"x": x, "y": y})()
        self.size = type("S", (), {"width": w, "height": h})()


class _FakeObs:
    """Stand-in for a VNObservation: has a bbox + confidence (+ barcode fields)."""
    def __init__(self, bbox, confidence=0.9, payload=None, symbology=None):
        self._bbox = _FakeBox(*bbox)
        self._conf = confidence
        self._payload = payload
        self.symbology = symbology  # exposed as attribute (real VNBarcodeObservation does)
    def boundingBox(self):
        return self._bbox
    def confidence(self):
        return self._conf
    def payloadStringValue(self):
        return self._payload


def test_bbox_normalised_origin_bottomleft():
    obs = _FakeObs((0.1, 0.2, 0.5, 0.3))
    assert vp._bbox(obs) == [0.1, 0.2, 0.5, 0.3]


def test_enrich_barcode_adds_payload_and_symbology():
    obs = _FakeObs((0, 0, 0.1, 0.1), payload="https://x.com", symbology="QR")
    entry = {"bbox": vp._bbox(obs), "confidence": 0.9}
    vp._enrich(entry, obs, "barcode")
    assert entry["payload"] == "https://x.com"
    assert entry["symbology"] == "QR"


def test_enrich_barcode_null_payload():
    obs = _FakeObs((0, 0, 0.1, 0.1), payload=None)
    entry = {"bbox": vp._bbox(obs), "confidence": 0.9}
    vp._enrich(entry, obs, "barcode")
    assert entry["payload"] is None


def test_enrich_face_adds_nothing_extra():
    """Non-barcode kinds get only the base bbox+confidence (no payload field)."""
    obs = _FakeObs((0.1, 0.1, 0.4, 0.4))
    entry = {"bbox": vp._bbox(obs), "confidence": 0.95}
    vp._enrich(entry, obs, "face")
    assert set(entry) == {"bbox", "confidence"}


# ─── detect() with a fully mocked Vision (proves the orchestration) ───────────

def test_detect_returns_empty_when_no_results(monkeypatch):
    """detect() on a kind with no detections returns count 0, empty list.
    Mocks _load_ciimage to avoid needing a real image/Vision."""
    class _Req:
        def results(self):
            return []
    monkeypatch.setattr(vp, "_load_ciimage",
                        lambda p: (_FakeVision, object(), None))
    # override _build_request to return the empty-results req
    monkeypatch.setattr(vp, "_build_request", lambda V, k, c: _Req())
    # _FakeVision.VNImageRequestHandler needs to exist for the handler call
    class _Handler:
        def __init__(self, *a, **k): pass
        def initWithCIImage_options_(self, *a, **k): return self
        def performRequests_error_(self, *a, **k): return True
    _FakeVision.VNImageRequestHandler = type(
        "VNImageRequestHandler", (), {"alloc": classmethod(
            lambda cls: type("A", (), {"initWithCIImage_options_": lambda self, *a, **k: _Handler(),
                                       "performRequests_error_": lambda *a, **k: True}))})
    res = vp.detect("/fake.png", "face")
    assert res["count"] == 0 and res["detections"] == []
    assert res["kind"] == "face"


def test_detect_text_routes_to_ocr(monkeypatch):
    """kind=text must call ocr._vision_text, NOT _build_request (no dup)."""
    import ocr
    called = {"n": 0}
    def fake_vision_text(path):
        called["n"] += 1
        return [{"text": "hi", "bbox": [0, 0, 0.1, 0.1]}]
    monkeypatch.setattr(ocr, "_vision_text", fake_vision_text)
    res = vp.detect("/fake.png", "text")
    assert called["n"] == 1
    assert res["kind"] == "text" and res["count"] == 1
    assert res["detections"][0]["text"] == "hi"
