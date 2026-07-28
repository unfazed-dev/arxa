"""Pure ship-path core for the §C9-R-CRAWL-BUILD crawl-discovery route-expander.
No I/O, no network. Spec: docs/plans/crawl-discovery-route-expander.md.

Hosts the general content-region primitives (relocated here from _crawl_yield.py so
SHIP code never depends on the de-risk harness) plus the one-hop expander's frontier
shaping and per-page capture decision. _crawl_yield.py imports the primitives back."""
from collections import Counter
from urllib.parse import urlparse

import _nav
from _shape_key import _node_key


def bag_jaccard(a, b):
    """Multiset (bag) Jaccard of two Counters: Sum min / Sum max over the key union.
    Both empty -> 1.0 (identical); exactly one empty -> 0.0. Repetition is structurally
    meaningful (N identical list items is a real template signal), so multiset, not set."""
    if not a and not b:
        return 1.0
    keys = set(a) | set(b)
    den = sum(max(a.get(k, 0), b.get(k, 0)) for k in keys)
    if not den:
        return 1.0
    num = sum(min(a.get(k, 0), b.get(k, 0)) for k in keys)
    return num / den


def content_fingerprint(nodes):
    """Multiset (Counter) of _node_key over NON-chrome nodes. `nodes` is a raw skeleton
    node-list ({id, parent, aria_role, ...}). Chrome = node whose nearest landmark
    ancestor is a CHROME_LANDMARK (via _nav.classify_chrome); those are dropped because
    G3d already dedups chrome across routes -- the only yield route-expansion can add is
    NEW CONTENT structure."""
    by_id = {n["id"]: n for n in nodes}
    fp = Counter()
    for n in nodes:
        if not _nav.classify_chrome(n["id"], by_id):
            fp[_node_key(n)] += 1
    return fp


def passes_floor(fp, floor):
    """A content-region fingerprint is VALID iff it has >= floor non-chrome nodes (sum of
    multiset counts). Below the floor the capture is degenerate (404 / consent / JS-blank)
    and must not seed novelty (spec §3, floor F=20)."""
    return sum(fp.values()) >= floor


def _host(url):
    """www-stripped, lowercased host of a URL, or None if unparseable / hostless.
    Mirrors _nav.normalize_url's host canonicalization (netloc.lower(), strip leading
    'www.') so the same-origin set-membership test agrees with route-map normalization."""
    if not url:
        return None
    try:
        h = urlparse(url).netloc.lower()
    except ValueError:
        return None
    if not h:
        return None
    if h.startswith("www."):
        h = h[4:]
    return h


def frontier_targets(seed_node_lists, seed_urls):
    """One-hop discovery frontier WITH provenance. Content (non-chrome) anchors across ALL
    seed routes that point to a SAME-ORIGIN, un-enumerated page, deduped by normalized URL.
    Same-origin = the anchor's www-stripped host is one of the seed hosts (a host-only
    set-membership test, NOT a prefix match on the host+path norm -- 'ex.com.evil.com' must
    NOT match 'ex.com'). Returns (targets, n_cross_origin): targets = [(norm, raw_href,
    src_idx)] preserving the FIRST raw href + FIRST seed index per norm; n_cross_origin =
    count of content anchors dropped for a non-seed host. `src_idx` is the index into
    `seed_node_lists` (== the seed route index when the caller passes one entry per seed,
    empty list for a failed seed -> the `via` provenance, spec §4). The raw href is returned
    ONLY so the caller can fetch it transiently; it is never persisted."""
    route_map = _nav.build_route_map(seed_urls)
    seed_hosts = {h for h in (_host(u) for u in seed_urls) if h is not None}
    seen = {}   # norm -> (href, src_idx)
    n_cross_origin = 0
    for src_idx, nodes in enumerate(seed_node_lists):
        by_id = {n["id"]: n for n in nodes}
        for n in nodes:
            href = n.get("href")
            if not href:
                continue
            if _nav.classify_chrome(n["id"], by_id):     # content links only
                continue
            norm = _nav.normalize_url(href)
            if norm is None:                             # non-http (mailto:, etc.)
                continue
            if _host(href) not in seed_hosts:            # same-origin gate (host-only set membership)
                n_cross_origin += 1
                continue
            if norm in route_map or norm in seen:        # seed route or already-seen
                continue
            seen[norm] = (href, src_idx)
    targets = [(norm, href, src_idx) for norm, (href, src_idx) in seen.items()]
    return targets, n_cross_origin


def frontier_urls(seed_node_lists, seed_urls):
    """Back-compat shape for the de-risk harness/core: drops the src_idx provenance.
    Returns ([(norm, href)], n_cross_origin). Behavior identical to the pre-relocation
    frontier_urls (the 13 test_crawl_yield.py tests gate this)."""
    targets, n_cross = frontier_targets(seed_node_lists, seed_urls)
    return [(norm, href) for norm, href, _ in targets], n_cross


def cap_frontier(frontier, max_pages):
    """Truncate the frontier to a hard safety cap on pages ATTEMPTED. Returns
    (capped, n_over_cap). max_pages None or < 0 -> no cap. The dropped count is logged by
    the caller (no silent caps, spec §5); never the URLs."""
    if max_pages is None or max_pages < 0 or len(frontier) <= max_pages:
        return list(frontier), 0
    return list(frontier[:max_pages]), len(frontier) - max_pages


def reject_reason(fp, seed_fps, kept_fps, T, floor):
    """Single source of truth for the per-page SHIP decision (spec §2). Returns None if the
    page should be CAPTURED, else the drop-ledger reason:
      "subfloor"  -- below the min-node floor (degenerate 404/consent/blank)
      "not_novel" -- best bag_jaccard to a seed >= T (already a seed template)
      "dup"       -- bag_jaccard to an already-kept page >= T (same template as one kept)
    `accept` wraps this. The orchestrator calls this directly so it can attribute each drop
    to the ledger (§5) -- a single bool could not."""
    if not passes_floor(fp, floor):
        return "subfloor"
    if max((bag_jaccard(fp, s) for s in seed_fps), default=0.0) >= T:
        return "not_novel"
    if any(bag_jaccard(fp, k) >= T for k in kept_fps):
        return "dup"
    return None


def accept(fp, seed_fps, kept_fps, T, floor):
    """True iff the discovered page should be captured (spec §2). Thin wrapper over
    reject_reason: capture iff there is no reject reason. Stateful in `kept_fps` -- the
    caller appends fp on accept; kept pure (no I/O)."""
    return reject_reason(fp, seed_fps, kept_fps, T, floor) is None
