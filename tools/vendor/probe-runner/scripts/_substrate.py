#!/usr/bin/env python3
"""_substrate — pure core for P2 substrate-honesty (G5/G9/G11). No browser/IO.

`classify_substrate`: map an element TAG (+ for iframes, whether its document was
captured in the snapshot) to the kind of UN-REPRODUCIBLE render substrate it is,
or None. `collect_substrate`: build the content-free substrate manifest from
skeleton nodes that carry a `substrate` marker. Both deterministic + unit-tested;
web_skeleton sets the per-node marker, bundle_writer derives the manifest.

WHY (honesty, not a DOM "fix"): a <canvas>/WebGL surface (G5), a <video> (G9), and
a cross-SITE out-of-process iframe (G11) paint pixels that are NOT in the DOM.
DOMSnapshot captures their BOX but never their content, and the firewall blocks the
pixels by construction (third-party IP). The honest output LABELS these regions so
a consumer knows they are un-reproducible from the bundle, instead of silently
emitting an empty box that looks reproducible.

G11 discriminator (empirically grounded 2026-05-30): whether the iframe's document
was CAPTURED (contentDocumentIndex present), NOT origin. Same-site cross-origin
iframes share the renderer process and ARE captured (reproducible); only cross-SITE
iframes go out-of-process (OOPIF) and are opaque. (127.0.0.1:A parent + 127.0.0.1:B
child = same-site cross-origin -> captured; localhost:B child = cross-site -> NOT
captured.) 2D-vs-WebGL canvas is intentionally NOT distinguished: the only probe
(getContext) is destructive and does not change the verdict — both are un-reproducible."""
from __future__ import annotations

_FRAME_TAGS = {"IFRAME", "FRAME"}


def classify_substrate(tag, captured=None):
    """Return the un-reproducible substrate kind for an element, or None.

    tag: the element's tag name (any case).
    captured: for frame tags, True/None when the frame's document WAS captured in
      the snapshot (reproducible -> not flagged), False when it was NOT captured
      (out-of-process / cross-site -> opaque). Ignored for non-frame tags.

    Kinds: 'canvas' (G5), 'video' (G9), 'iframe_uncaptured' (G11). Fires ONLY on
    CANVAS / VIDEO / un-captured IFRAME|FRAME — never IMG/PICTURE/SOURCE/SVG, which
    are ordinary swappable image slots reproducible from a slot."""
    t = (tag or "").upper()
    if t == "CANVAS":
        return "canvas"
    if t == "VIDEO":
        return "video"
    if t in _FRAME_TAGS:
        if captured is False:
            return "iframe_uncaptured"
        return None
    return None


def collect_substrate(nodes, url=None):
    """Build the content-free substrate manifest from skeleton nodes. Each node
    carrying a truthy `substrate` marker becomes one region descriptor
    (node_id/kind/role/bbox/z — geometry + mechanism only, no content). Returns
    {schema, url, regions, n_regions, kinds}; `kinds` is a per-kind count. Always
    well-formed (empty regions list when there is no substrate)."""
    regions = []
    for n in (nodes or []):
        kind = n.get("substrate")
        if not kind:
            continue
        regions.append({"node_id": n.get("id"), "kind": kind,
                        "role": n.get("role"), "bbox": n.get("bbox"),
                        "z": n.get("z", 0)})
    kinds = {}
    for r in regions:
        kinds[r["kind"]] = kinds.get(r["kind"], 0) + 1
    return {"schema": "probe-substrate/1", "url": url,
            "regions": regions, "n_regions": len(regions), "kinds": kinds}
