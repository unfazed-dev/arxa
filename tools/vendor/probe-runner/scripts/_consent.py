#!/usr/bin/env python3
"""_consent — pure core for G6 occluding-overlay (consent-class) handling.

A page's load-time occluding overlay (cookie/consent modal + backdrop, splash,
drawer) is a web_states State; dismissing it is a Transition. Detection is
CONTENT-BLIND geometry: position:fixed + viewport coverage + a positive z-index.
We never read text/class/id, and we never click a button (a blind click takes an
unknown real action — accept-tracking / nav-away — violating the honest-ceiling
principle). The only dismiss is an Escape keydown (content-blind, non-committal).

Detection errs toward UNDER-detect (documented, mirrors _states.diff_skeletons):
missing an overlay degrades to current behavior (the page behind is captured
regardless — §C7), whereas over-detect would mislabel a sticky-nav/hero/splash as
an un-cleared consent State. classify_overlay is the single policy gate; the JS
scan in web_states is a broad pre-filter, this is the decision."""
from __future__ import annotations

_OCCLUDING_POSITIONS = {"fixed"}


def classify_overlay(rec, *, min_coverage=0.5):
    """Map one scanned candidate record to an occluding_overlay State dict or None.

    rec keys (from web_states._OVERLAY_JS): position (computed CSS position string),
    z (int stacking, or None), coverage (clamped visible-fraction of the viewport,
    0..1), role (ARIA role or None), bbox ({x,y,w,h} ints). An element qualifies as
    an OCCLUDING overlay iff it is position:fixed AND covers >= min_coverage of the
    viewport AND has a positive z-index (establishes a layer above content)."""
    if rec.get("position") not in _OCCLUDING_POSITIONS:
        return None
    cov = rec.get("coverage") or 0.0
    if cov < min_coverage:
        return None
    z = rec.get("z")
    if z is None or z <= 0:
        return None
    return {"kind": "occluding_overlay", "coverage": cov, "z": z,
            "role": rec.get("role"), "bbox": rec.get("bbox")}


def overlay_dismissed(before, after_overlays, *, radius=24.0):
    """Presence test (the INVERSE of G4's appeared-diff): given the overlay recorded
    pre-dismiss and the classify_overlay results re-scanned post-dismiss (Nones
    filtered out), the overlay is CLEARED iff no post-dismiss overlay sits at the
    same top-left corner (within radius px on both axes). We check the recorded
    overlay is GONE — we do NOT diff for newly-appeared nodes. radius mirrors
    _states.diff_skeletons (24.0)."""
    bb = before["bbox"]
    # bbox is always present on a qualified overlay (coverage is derived from it upstream).
    for o in after_overlays:
        ob = o["bbox"]
        if abs(ob["x"] - bb["x"]) <= radius and abs(ob["y"] - bb["y"]) <= radius:
            return False
    return True


def detect_and_dismiss(scan, dismiss, sleep, *, settle_s=0.3, min_coverage=0.5):
    """Orchestrate G6 with injected I/O (the unit-testable seam, mirroring
    _settle.adaptive_settle). scan() -> raw candidate records (web_states._OVERLAY_JS);
    dismiss() -> fire the content-blind Escape gesture; sleep(seconds) -> wait for it
    to settle. Returns the consent State dict, or None when no occluding overlay is
    detected (the common case — see §C7). The State is content-free: geometry + z +
    role + the dismiss method + the cleared outcome.

    Only ONE overlay is recorded — the first detected (a backdrop covers the
    viewport, so the first qualifying full-bleed layer is the occluder). We attempt
    exactly one Escape; we never click (a blind click takes an unknown real action).
    settle_s seconds is the post-dismiss settle wait passed to sleep()."""
    overlay = _first_overlay(scan(), min_coverage)
    if overlay is None:
        return None
    dismiss()
    sleep(settle_s)
    after = [o for o in (classify_overlay(r, min_coverage=min_coverage)
                         for r in (scan() or [])) if o]
    return {**overlay, "dismiss": "escape",
            "cleared": overlay_dismissed(overlay, after)}


def _first_overlay(cands, min_coverage):
    for r in (cands or []):
        o = classify_overlay(r, min_coverage=min_coverage)
        if o is not None:
            return o
    return None
