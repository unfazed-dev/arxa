"""Pure scoring core for the §C9-R-CRAWL crawl-discovery yield de-risk.
No I/O, no network. Spec: docs/plans/crawl-discovery-yield-derisk.md.

The general content-region primitives now live in _crawl.py (the SHIP core); this
de-risk harness core imports them so ship code never depends on a de-risk module."""
from _crawl import (  # noqa: F401  (re-exported for the de-risk harness + its tests)
    bag_jaccard,
    content_fingerprint,
    passes_floor,
    frontier_urls,
)


def count_novel_templates(frontier_fps, seed_fps, T):
    """A frontier fingerprint is NOVEL iff its best bag_jaccard to ALL seed fingerprints
    is < T. Novel fingerprints are then collapsed against each other (>= T => same
    template) so K identical novel pages count as ONE template. Returns the count of
    distinct novel templates. T is pre-registered (0.5); see spec. The collapse is greedy/order-dependent (appropriate for a de-risk threshold, not a precise census)."""
    novel = [fp for fp in frontier_fps
             if max((bag_jaccard(fp, s) for s in seed_fps), default=0.0) < T]
    templates = []
    for fp in novel:
        if all(bag_jaccard(fp, t) < T for t in templates):
            templates.append(fp)
    return len(templates)


def discrimination_matrix(seed_fps):
    """Pairwise bag_jaccard among the seed routes (the §3 discrimination control).
    NxN list-of-lists. The fingerprint must score known-different seed templates LOW and
    identical ones HIGH, else the novelty signal is vacuous and the de-risk aborts."""
    return [[bag_jaccard(a, b) for b in seed_fps] for a in seed_fps]
