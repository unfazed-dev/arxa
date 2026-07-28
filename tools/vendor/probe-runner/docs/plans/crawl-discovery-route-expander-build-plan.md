# Crawl-discovery route-expander Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in `--crawl` one-hop route-expander to `site_capture` that discovers same-origin un-enumerated pages, captures only the structurally-novel/deduped ones, and extends `nav_edges` — keeping every discovered URL off disk.

**Architecture:** A new pure `scripts/_crawl.py` owns frontier shaping + the per-page capture decision (relocating the 5 general primitives out of the de-risk harness `_crawl_yield.py`, which now imports them back). `scripts/site_capture.py` stays the thin fetch shell: it gains a `--crawl` path that derives the frontier from the seed captures, runs the expander loop behind injectable network callables, and re-resolves `nav_edges` against the combined route_map. The existing default (non-crawl) path is byte-for-byte unchanged.

**Tech Stack:** Python 3 (stdlib only: `argparse`, `subprocess`, `tempfile`, `urllib.robotparser`, `collections.Counter`), pytest. Reuses `_nav`, `_shape_key`, `content_firewall`, `web_skeleton`/`web_tokens`/`bundle_writer`.

**Spec:** `docs/plans/crawl-discovery-route-expander.md` (§C9-R-CRAWL-BUILD).

**Conventions (this repo):** tests live in `scripts/test_*.py`; run from repo root with `python3 -m pytest scripts/`. Modules import bare (`import _nav`) and run with `cwd=scripts/`. Commits are single-line, NO `Co-Authored-By` trailer. Baseline suite = **543 passing**; every task must keep it green.

**Firewall (ADR-0001) — non-negotiable:** discovered URLs are content. They live in-memory only, are NEVER written to disk or printed; discovered `site.json` rows carry NO `url` field (only `discovered`+`via` route_id provenance). `content_firewall.audit_bundle` re-runs over the whole tree as the backstop.

---

## File Structure

| File | Responsibility | Change |
|------|----------------|--------|
| `scripts/_crawl.py` | Pure ship core: relocated primitives + `frontier_targets`, `cap_frontier`, `reject_reason`, `accept` | **Create** |
| `scripts/_crawl_yield.py` | De-risk harness core: keeps `count_novel_templates`, `discrimination_matrix`; imports primitives from `_crawl` | Modify |
| `scripts/site_capture.py` | Fetch shell: `capture_route` returns raw nodes; new `_skeleton_nodes`, `crawl_expand`, `_resolve_combined_edges`, `_make_robots_allow`; `capture_site` + `main` `--crawl` wiring | Modify |
| `scripts/test_crawl.py` | Unit tests for `_crawl` | **Create** |
| `scripts/test_crawl_expand.py` | Offline tests for the expander loop + combined edges + firewall row schema | **Create** |
| `scripts/test_crawl_yield.py` | Existing 13 de-risk tests — must stay green (import redirect) | Unchanged (gate) |
| `scripts/crawl_expander_smoke.py` | Non-collected manual real-site smoke | **Create** |
| `docs/plans/probe-runner-engine-capture-gaps.md` | §C9-R-CRAWL-BUILD status | Modify |

---

## Task 1: `_crawl.py` — relocate primitives + add frontier_targets / cap_frontier / reject_reason / accept

**Files:**
- Create: `scripts/_crawl.py`
- Modify: `scripts/_crawl_yield.py`
- Create: `scripts/test_crawl.py`
- Gate: `scripts/test_crawl_yield.py` (must stay green, do NOT edit)

- [ ] **Step 1: Write the failing tests** — `scripts/test_crawl.py`:

```python
from collections import Counter
import _crawl as cw


def _node(nid, parent=None, aria_role=None, role="generic", href=None, text_len=0):
    n = {"id": nid, "parent": parent, "role": role, "text_len": text_len}
    if aria_role is not None:
        n["aria_role"] = aria_role
    if href is not None:
        n["href"] = href
    return n


# --- cap_frontier ---
def test_cap_frontier_under_cap_unchanged():
    f = [("a", "ha", 0), ("b", "hb", 0)]
    capped, n_over = cw.cap_frontier(f, 5)
    assert capped == f and n_over == 0


def test_cap_frontier_over_cap_truncates_and_counts():
    f = [("a", "1", 0), ("b", "2", 0), ("c", "3", 1)]
    capped, n_over = cw.cap_frontier(f, 2)
    assert capped == [("a", "1", 0), ("b", "2", 0)] and n_over == 1


def test_cap_frontier_empty():
    assert cw.cap_frontier([], 10) == ([], 0)


# --- reject_reason / accept ---
def test_reject_reason_subfloor():
    assert cw.reject_reason(Counter({"k": 5}), [], [], 0.5, 20) == "subfloor"


def test_reject_reason_not_novel_when_matches_seed():
    seed = Counter({"a": 20})
    assert cw.reject_reason(Counter({"a": 20}), [seed], [], 0.5, 20) == "not_novel"


def test_reject_reason_dup_of_kept():
    seed = Counter({"a": 20})
    kept = Counter({"z": 20})
    assert cw.reject_reason(Counter({"z": 20}), [seed], [kept], 0.5, 20) == "dup"


def test_reject_reason_none_means_capture():
    seed = Counter({"a": 20})
    kept = Counter({"z": 20})
    assert cw.reject_reason(Counter({"q": 21}), [seed], [kept], 0.5, 20) is None


def test_accept_wraps_reject_reason():
    seed = Counter({"a": 20})
    assert cw.accept(Counter({"q": 21}), [seed], [], 0.5, 20) is True
    assert cw.accept(Counter({"a": 20}), [seed], [], 0.5, 20) is False


def test_accept_no_seeds_is_vacuously_novel():
    assert cw.accept(Counter({"q": 20}), [], [], 0.5, 20) is True


def test_accept_kept_set_statefulness():
    seed = [Counter({"a": 20})]
    fp = Counter({"z": 20})
    kept = []
    assert cw.accept(fp, seed, kept, 0.5, 20) is True
    kept.append(fp)
    assert cw.accept(fp, seed, kept, 0.5, 20) is False


# --- frontier_targets provenance ---
def test_frontier_targets_records_src_idx():
    seed_urls = ["https://ex.com/", "https://ex.com/docs"]
    route0 = [_node(0, aria_role="main"),
              _node(1, parent=0, role="link", href="https://ex.com/blog/x")]   # from seed 0
    route1 = [_node(0, aria_role="main"),
              _node(1, parent=0, role="link", href="https://ex.com/guide")]    # from seed 1
    targets, n_cross = cw.frontier_targets([route0, route1], seed_urls)
    by_norm = {norm: src for norm, _href, src in targets}
    assert by_norm["ex.com/blog/x"] == 0
    assert by_norm["ex.com/guide"] == 1
    assert n_cross == 0


def test_frontier_targets_first_seed_wins_on_collision():
    seed_urls = ["https://ex.com/", "https://ex.com/docs"]
    link = "https://ex.com/shared"
    route0 = [_node(0, aria_role="main"), _node(1, parent=0, role="link", href=link)]
    route1 = [_node(0, aria_role="main"), _node(1, parent=0, role="link", href=link)]
    targets, _ = cw.frontier_targets([route0, route1], seed_urls)
    src = {norm: s for norm, _h, s in targets}["ex.com/shared"]
    assert src == 0


def test_frontier_targets_drops_cross_origin_and_chrome():
    seed_urls = ["https://ex.com/"]
    nodes = [
        _node(0, aria_role="navigation"),
        _node(1, parent=0, role="link", href="https://ex.com/chrome-link"),    # chrome -> drop
        _node(2, aria_role="main"),
        _node(3, parent=2, role="link", href="https://other.com/x"),           # cross-origin -> drop+count
        _node(4, parent=2, role="link", href="https://ex.com/keep"),           # content same-origin -> keep
    ]
    targets, n_cross = cw.frontier_targets([nodes], seed_urls)
    norms = {n for n, _h, _s in targets}
    assert norms == {"ex.com/keep"} and n_cross == 1


def test_frontier_urls_wrapper_matches_legacy_shape():
    seed_urls = ["https://ex.com/"]
    nodes = [_node(0, aria_role="main"), _node(1, parent=0, role="link", href="https://ex.com/p")]
    targets, n_cross = cw.frontier_urls([nodes], seed_urls)
    assert targets == [("ex.com/p", "https://ex.com/p")] and n_cross == 0
```

- [ ] **Step 2: Run, verify it fails**

Run: `cd <repo> && python3 -m pytest scripts/test_crawl.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named '_crawl'` (collection error).

- [ ] **Step 3: Create `scripts/_crawl.py`** (relocate the 5 primitives verbatim from `_crawl_yield.py`, then add the four new functions):

```python
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
```

- [ ] **Step 4: Redirect `_crawl_yield.py` imports** — replace the whole file with:

```python
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
```

- [ ] **Step 5: Run both test files, verify green**

Run: `cd <repo> && python3 -m pytest scripts/test_crawl.py scripts/test_crawl_yield.py -q`
Expected: PASS — all new `_crawl` tests pass AND the 13 existing `test_crawl_yield.py` tests still pass (import redirect, behavior unchanged).

- [ ] **Step 6: Run the full suite (no regression)**

Run: `cd <repo> && python3 -m pytest scripts/ -q`
Expected: PASS — baseline 543 + the new `_crawl` tests; 0 failures.

- [ ] **Step 7: Commit**

```bash
git add scripts/_crawl.py scripts/_crawl_yield.py scripts/test_crawl.py
git commit -m "feat: add pure _crawl ship core (frontier_targets/cap_frontier/reject_reason/accept); relocate content-region primitives out of de-risk harness (_crawl_yield imports them back)"
```

---

## Task 2: `capture_route` returns the raw seed node-list

The crawl path needs each seed's raw (pre-redaction) node-list — to fingerprint seeds and to derive the frontier. `capture_route` already reads it in-memory for edge resolution; expose it as a 5th return element. The default (non-crawl) path ignores it.

**Files:**
- Modify: `scripts/site_capture.py` (`capture_route` return tuples + the one `capture_site` unpack)
- Modify: `scripts/test_crawl_expand.py` (created in Task 3; the failure-path arity test below can also live in a new `scripts/test_site_capture_crawl.py` — keep it with the other crawl tests)

> **Note:** `capture_route` is the network boundary; the existing suite does NOT unit-test its success path (no CDP in CI), and this plan preserves that. The arity change is locked by an offline failure-path test (below) plus the combined `crawl_expand` tests (Task 3); the real success path is exercised by the live smoke (Task 5).

- [ ] **Step 1: Write the failing test** — add to `scripts/test_crawl_expand.py`:

```python
def test_capture_route_failure_returns_five_tuple(tmp_path, monkeypatch):
    import site_capture as SC

    class _R:
        returncode = 1
    monkeypatch.setattr(SC, "_run", lambda cmd: _R())
    res = SC.capture_route("https://x.com/", tmp_path / "r00", transport=[])
    assert res == (False, None, "skeleton_failed", [], [])
```

- [ ] **Step 2: Run, verify it fails**

Run: `cd <repo> && python3 -m pytest scripts/test_crawl_expand.py::test_capture_route_failure_returns_five_tuple -q`
Expected: FAIL — `capture_route` currently returns a 4-tuple `(False, None, "skeleton_failed", [])`.

- [ ] **Step 3: Edit `capture_route`** in `scripts/site_capture.py`. Change **every** failure return from a 4-tuple to a 5-tuple (append `, []`), and rebuild the success return to also yield `raw_nodes`. The five failure returns become:

```python
        r = _run([sys.executable, "web_skeleton.py", "--url", url, "--out", str(sk)] + transport + sweep)
        if r.returncode != 0:
            shutil.rmtree(route_dir, ignore_errors=True)
            return (False, None, "skeleton_failed", [], [])

        r = _run([sys.executable, "web_tokens.py", "--url", url, "--out", str(tok)] + transport)
        if r.returncode != 0:
            shutil.rmtree(route_dir, ignore_errors=True)
            return (False, None, "tokens_failed", [], [])

        r = _run([sys.executable, "bundle_writer.py",
                  "--skeleton", str(sk), "--tokens", str(tok), "--out", str(route_dir)])
        if r.returncode == 3:
            shutil.rmtree(route_dir, ignore_errors=True)
            return (False, None, "bundle_audit_failed", [], [])
        if r.returncode != 0:
            shutil.rmtree(route_dir, ignore_errors=True)
            return (False, None, "bundle_failed", [], [])

        try:
            skel = json.loads((route_dir / "skeleton.json").read_text())
        except (OSError, ValueError):
            shutil.rmtree(route_dir, ignore_errors=True)
            return (False, None, "skeleton_unreadable", [], [])
```

And replace the success tail (the `edges = []` block through `return`) with:

```python
        edges, raw_nodes = [], []
        try:
            raw = json.loads(sk.read_text())          # raw _sk.json (pre-redaction, has href)
            raw_nodes = raw.get("nodes", [])
            if route_map is not None and src_id is not None:
                edges = _edges_from_skeleton(raw_nodes, route_map, src_id)
        except (OSError, ValueError, KeyError, TypeError):
            edges, raw_nodes = [], []
        return (True, len(skel.get("nodes", [])), None, edges, raw_nodes)
```

Update the docstring's return description to `(ok, node_count, error_kind, edges, raw_nodes)` and note `raw_nodes` is the in-memory pre-redaction node-list (hrefs intact, never persisted), `[]` on failure or unreadable.

- [ ] **Step 4: Update the `capture_site` unpack.** In `capture_site`, change:

```python
        ok, node_count, error_kind, edges = capture_route(
            url, out / "routes" / rid, transport, sweep, route_map=route_map, src_id=src_id)
```
to:
```python
        ok, node_count, error_kind, edges, _raw = capture_route(
            url, out / "routes" / rid, transport, sweep, route_map=route_map, src_id=src_id)
```
(The default path ignores `_raw`; Task 4 rewires the crawl branch to use it.)

- [ ] **Step 5: Run the failing test + full suite**

Run: `cd <repo> && python3 -m pytest scripts/test_crawl_expand.py::test_capture_route_failure_returns_five_tuple scripts/ -q`
Expected: PASS — the arity test passes and the full suite stays green (543 + Task 1's new tests). The non-crawl path behavior is unchanged.

- [ ] **Step 6: Commit**

```bash
git add scripts/site_capture.py scripts/test_crawl_expand.py
git commit -m "refactor: capture_route returns raw seed node-list (5th elt) for the crawl path; default path unchanged"
```

---

## Task 3: `crawl_expand` — the one-hop expander loop (offline-injectable)

The loop lives in `site_capture` but all network is behind two injectable callables so it is fully CI-testable: `skeleton_nodes(href, transport)` (selection fetch) and `capture_page(href, route_dir)` (full capture of an accepted page). Real defaults wrap the existing tools.

**Files:**
- Modify: `scripts/site_capture.py` (add `import time`, `_skeleton_nodes`, `crawl_expand`)
- Modify: `scripts/test_crawl_expand.py`

- [ ] **Step 1: Write the failing tests** — `scripts/test_crawl_expand.py` (header + loop tests; the Task-2 arity test already lives here):

```python
import json
from pathlib import Path

import site_capture as SC
import _crawl as cw


def _content(n_items, item_role="listitem"):
    """A raw node-list: one `main` landmark + n_items identical content children.
    content_fingerprint counts main + all children (main is a non-chrome landmark)."""
    nodes = [{"id": 0, "parent": None, "role": "region", "aria_role": "main"}]
    for i in range(n_items):
        nodes.append({"id": i + 1, "parent": 0, "role": item_role,
                      "aria_role": None, "text_len": 5})
    return nodes


def test_crawl_expand_keeps_only_novel_deduped(tmp_path):
    routes = tmp_path / "routes"
    routes.mkdir()
    seed_nodes = _content(25, "listitem")               # seed template
    seed_fp = cw.content_fingerprint(seed_nodes)
    novel_nodes = _content(25, "article")               # different role -> novel
    frontier = [
        ("ex.com/same", "https://ex.com/same", 0),      # == seed -> not_novel
        ("ex.com/n1", "https://ex.com/n1", 0),          # novel -> kept r01
        ("ex.com/n2", "https://ex.com/n2", 1),          # dup of n1
        ("ex.com/tiny", "https://ex.com/tiny", 0),      # 6 nodes -> subfloor
    ]
    fake_nodes = {
        "https://ex.com/same": seed_nodes,
        "https://ex.com/n1": novel_nodes,
        "https://ex.com/n2": novel_nodes,
        "https://ex.com/tiny": _content(5, "listitem"),
    }

    def fake_skel(href, transport):
        return fake_nodes[href]

    def fake_capture(href, route_dir):
        route_dir = Path(route_dir)
        route_dir.mkdir(parents=True, exist_ok=True)
        (route_dir / "skeleton.json").write_text(json.dumps({"nodes": fake_nodes[href]}))
        return True, len(fake_nodes[href]), fake_nodes[href]

    rows, raw_by_rid, norm_by_rid, ledger, nxt = SC.crawl_expand(
        frontier, [seed_fp], routes, start_idx=1, transport=[],
        T=0.5, floor=20, robots_allow=lambda h: True,
        skeleton_nodes=fake_skel, capture_page=fake_capture,
        sleep=lambda s: None, delay=0.0)

    assert [r["route_id"] for r in rows] == ["r01"]
    assert rows[0]["discovered"] is True and "url" not in rows[0]
    assert rows[0]["via"] == "r00"
    assert rows[0]["bundle"] == "routes/r01" and rows[0]["ok"] is True
    assert ledger == {"subfloor": 1, "not_novel": 1, "dup": 1,
                      "robots_blocked": 0, "failed": 0}
    assert nxt == 2
    assert norm_by_rid == {"r01": "ex.com/n1"} and "r01" in raw_by_rid


def test_crawl_expand_robots_blocked_counts(tmp_path):
    routes = tmp_path / "routes"
    routes.mkdir()
    seed_fp = cw.content_fingerprint(_content(25))
    frontier = [("ex.com/x", "https://ex.com/x", 0)]
    rows, _r, _n, ledger, nxt = SC.crawl_expand(
        frontier, [seed_fp], routes, 1, [], T=0.5, floor=20,
        robots_allow=lambda h: False,
        skeleton_nodes=lambda h, t: _content(25),
        capture_page=lambda h, d: (True, 26, _content(25)),
        sleep=lambda s: None, delay=0.0)
    assert rows == [] and ledger["robots_blocked"] == 1 and nxt == 1


def test_crawl_expand_zero_yield_is_graceful_noop(tmp_path):
    routes = tmp_path / "routes"
    routes.mkdir()
    seed_nodes = _content(25)
    seed_fp = cw.content_fingerprint(seed_nodes)
    frontier = [("ex.com/same", "https://ex.com/same", 0)]
    rows, _r, _n, ledger, nxt = SC.crawl_expand(
        frontier, [seed_fp], routes, 1, [], T=0.5, floor=20,
        robots_allow=lambda h: True,
        skeleton_nodes=lambda h, t: seed_nodes,
        capture_page=lambda h, d: (True, 26, seed_nodes),
        sleep=lambda s: None, delay=0.0)
    assert rows == [] and ledger["not_novel"] == 1 and nxt == 1


def test_crawl_expand_capture_failure_counts_failed(tmp_path):
    routes = tmp_path / "routes"
    routes.mkdir()
    seed_fp = cw.content_fingerprint(_content(25))
    frontier = [("ex.com/n1", "https://ex.com/n1", 0)]
    rows, _r, _n, ledger, nxt = SC.crawl_expand(
        frontier, [seed_fp], routes, 1, [], T=0.5, floor=20,
        robots_allow=lambda h: True,
        skeleton_nodes=lambda h, t: _content(25, "article"),   # novel -> accepted...
        capture_page=lambda h, d: (False, None, []),           # ...but full capture fails
        sleep=lambda s: None, delay=0.0)
    assert rows == [] and ledger["failed"] == 1 and nxt == 1
```

- [ ] **Step 2: Run, verify it fails**

Run: `cd <repo> && python3 -m pytest scripts/test_crawl_expand.py -q`
Expected: FAIL — `AttributeError: module 'site_capture' has no attribute 'crawl_expand'`.

- [ ] **Step 3: Implement** — add `import time` to the imports of `scripts/site_capture.py`, then add these two functions (place after `capture_route`):

```python
def _skeleton_nodes(url, transport):
    """Selection fetch: run web_skeleton ONLY and return its raw node-list (pre-redaction,
    href intact, IN-MEMORY) or None on any failure. The scratch lives OUTSIDE any audited
    tree and is discarded; no bundle is written. The hrefs are used transiently for one-hop
    discovery and are NEVER persisted."""
    with tempfile.TemporaryDirectory() as scratch:
        sk = Path(scratch) / "_sk.json"
        r = _run([sys.executable, "web_skeleton.py", "--url", url, "--out", str(sk)] + transport)
        if r.returncode != 0 or not sk.exists():
            return None
        try:
            return json.loads(sk.read_text()).get("nodes", [])
        except (OSError, ValueError):
            return None


def crawl_expand(frontier, seed_fps, routes_dir, start_idx, transport, *,
                 T, floor, robots_allow, skeleton_nodes=_skeleton_nodes,
                 capture_page=None, sleep=time.sleep, delay=2.0):
    """One-hop expander loop (spec §1 step 3). `frontier` is a list of (norm, href, src_idx)
    already same-origin-filtered and capped. For each: robots-check -> selection skeleton ->
    fingerprint -> reject_reason? On capture (reason is None) fully capture the page via
    `capture_page` into routes_dir/rNN and keep it. All network is behind the injected
    `skeleton_nodes(href, transport)` / `capture_page(href, route_dir)` callables (real
    defaults below; tests inject fakes).

    Returns (discovered_rows, raw_by_rid, norm_by_rid, ledger, next_idx):
      discovered_rows: content-free site.json rows -- NO url; carry discovered=True + via.
      raw_by_rid:      {rid: raw node-list} for the combined edge-resolution pass (in-memory).
      norm_by_rid:     {rid: normalized_url} for the combined route_map (in-memory, transient).
      ledger:          drop counts (no URLs): subfloor/not_novel/dup/robots_blocked/failed.
      next_idx:        the next free route index (== start_idx + number kept).
    """
    routes_dir = Path(routes_dir)
    if capture_page is None:
        def capture_page(href, route_dir):
            ok, node_count, _ek, _edges, raw = capture_route(href, route_dir, transport)
            return ok, node_count, raw
    import _crawl as cw
    kept_fps = []
    rows, raw_by_rid, norm_by_rid = [], {}, {}
    ledger = {"subfloor": 0, "not_novel": 0, "dup": 0, "robots_blocked": 0, "failed": 0}
    idx = start_idx
    for norm, href, src_idx in frontier:
        if not robots_allow(href):
            ledger["robots_blocked"] += 1
            continue
        nodes = skeleton_nodes(href, transport)
        sleep(delay)
        if nodes is None:
            ledger["failed"] += 1
            continue
        fp = cw.content_fingerprint(nodes)
        reason = cw.reject_reason(fp, seed_fps, kept_fps, T, floor)
        if reason is not None:
            ledger[reason] += 1
            continue
        rid = "r%02d" % idx
        ok, node_count, raw = capture_page(href, routes_dir / rid)
        sleep(delay)
        if not ok:
            ledger["failed"] += 1
            continue
        kept_fps.append(fp)
        rows.append({"route_id": rid, "bundle": "routes/" + rid, "ok": True,
                     "node_count": node_count, "discovered": True,
                     "via": "r%02d" % src_idx})
        raw_by_rid[rid] = raw
        norm_by_rid[rid] = norm
        idx += 1
    return rows, raw_by_rid, norm_by_rid, ledger, idx
```

- [ ] **Step 4: Run the crawl tests + full suite**

Run: `cd <repo> && python3 -m pytest scripts/test_crawl_expand.py scripts/ -q`
Expected: PASS — all four loop tests + the arity test pass; full suite green.

- [ ] **Step 5: Commit**

```bash
git add scripts/site_capture.py scripts/test_crawl_expand.py
git commit -m "feat: crawl_expand one-hop loop (injectable fetchers) — novel+deduped capture, content-free discovered rows (no url, via provenance), drop ledger"
```

---

## Task 4: Combined edge resolution + `capture_site`/`main` `--crawl` wiring + robots

Wire the expander into `capture_site` (crawl branch only — default path untouched), re-resolve `nav_edges` against the combined route_map, add the real robots gate, and expose the CLI flags.

**Files:**
- Modify: `scripts/site_capture.py` (`_resolve_combined_edges`, `_make_robots_allow`, `CRAWL_FLOOR`, `capture_site` crawl branch, `main` flags)
- Modify: `scripts/test_crawl_expand.py`

- [ ] **Step 1: Write the failing tests** — add to `scripts/test_crawl_expand.py`:

```python
def test_resolve_combined_edges_links_seed_and_discovered():
    urls = ["https://ex.com/", "https://ex.com/docs"]
    seed0 = [{"id": 0, "parent": None, "role": "region", "aria_role": "main"},
             {"id": 1, "parent": 0, "role": "link", "aria_role": None,
              "href": "https://ex.com/blog"}]               # seed -> discovered
    seed1 = [{"id": 0, "parent": None, "role": "region", "aria_role": "main"}]
    disc = [{"id": 0, "parent": None, "role": "region", "aria_role": "main"},
            {"id": 1, "parent": 0, "role": "link", "aria_role": None,
             "href": "https://ex.com/docs"}]                # discovered -> seed
    routes_raw = {0: seed0, 1: seed1, 2: disc}
    norm_by_rid = {"r02": "ex.com/blog"}
    edges = SC._resolve_combined_edges(routes_raw, urls, norm_by_rid)
    assert {"src": "r00", "dst": "r02", "src_node": 1, "chrome": False} in edges
    assert {"src": "r02", "dst": "r01", "src_node": 1, "chrome": False} in edges


def test_capture_site_crawl_branch_offline(tmp_path, monkeypatch):
    """End-to-end crawl branch with capture stubbed: a seed links to one novel discovered
    page; assert the discovered row has no url, carries via, nav_edges connect them, and the
    firewall backstop is clean. Injectables are passed via the `crawl` dict (no reliance on
    default-arg binding); seed captures go through a monkeypatched capture_route."""
    import content_firewall as cf

    def _redacted(nodes):
        # mimic bundle_writer: hrefs are stripped before skeleton.json is written to disk
        return [{k: v for k, v in n.items() if k != "href"} for n in nodes]

    seed_nodes = [{"id": 0, "parent": None, "role": "region", "aria_role": "main"},
                  {"id": 1, "parent": 0, "role": "link", "aria_role": None,
                   "href": "https://ex.com/blog"}] + \
                 [{"id": i + 2, "parent": 0, "role": "listitem", "aria_role": None,
                   "text_len": 5} for i in range(22)]
    disc_nodes = [{"id": 0, "parent": None, "role": "region", "aria_role": "main"}] + \
                 [{"id": i + 1, "parent": 0, "role": "article", "aria_role": None,
                   "text_len": 9} for i in range(24)]
    by_url = {"https://ex.com/": seed_nodes, "https://ex.com/blog": disc_nodes}

    def _write_bundle(route_dir, nodes):
        route_dir = Path(route_dir)
        route_dir.mkdir(parents=True, exist_ok=True)
        (route_dir / "skeleton.json").write_text(json.dumps({"nodes": _redacted(nodes)}))
        (route_dir / "tokens.json").write_text(
            json.dumps({"palette": {}, "type_scale": [], "spacing": []}))

    def fake_capture_route(url, route_dir, transport, sweep=None, route_map=None, src_id=None):
        nodes = by_url[url]
        _write_bundle(route_dir, nodes)
        return (True, len(nodes), None, [], nodes)       # raw nodes (href intact) in-memory

    def fake_capture_page(href, route_dir):
        nodes = by_url[href]
        _write_bundle(route_dir, nodes)
        return (True, len(nodes), nodes)

    monkeypatch.setattr(SC, "capture_route", fake_capture_route)   # seed captures

    out = tmp_path / "site_out"
    crawl = {"T": 0.5, "floor": 20, "max": 40, "delay": 0.0, "ua": "probe-runner/1.0",
             "sleep": (lambda s: None), "robots_allow": (lambda h: True),
             "skeleton_nodes": (lambda href, transport: by_url[href]),
             "capture_page": fake_capture_page}
    manifest = SC.capture_site(["https://ex.com/"], str(out), transport=[], crawl=crawl)

    discovered = [r for r in manifest["routes"] if r.get("discovered")]
    assert len(discovered) == 1
    assert "url" not in discovered[0] and discovered[0]["via"] == "r00"
    assert any(e["src"] == "r00" and e["dst"] == "r01" for e in manifest["nav_edges"])
    assert manifest["crawl"]["kept"] == 1 and manifest["crawl"]["cross_origin_dropped"] == 0
    site_text = (out / "site.json").read_text()
    assert "blog" not in site_text                       # discovered href never persisted
    assert cf.audit_bundle(out) == []                    # firewall backstop clean
```

> If `audit_bundle` rejects the minimal stub bundles, enrich the stub `skeleton.json`/`tokens.json` to the smallest shape it accepts (mirror `_build_site`/`_tokens` in `test_site_capture_post.py`) — do NOT weaken the audit.

- [ ] **Step 2: Run, verify it fails**

Run: `cd <repo> && python3 -m pytest scripts/test_crawl_expand.py -k "combined or crawl_branch" -q`
Expected: FAIL — `_resolve_combined_edges` / the `crawl=` kwarg don't exist yet.

- [ ] **Step 3: Implement.** In `scripts/site_capture.py`, add a module constant near the top (after `SCRIPTS = ...`):

```python
CRAWL_FLOOR = 20   # min content-region nodes for a discovered capture to be VALID (spec §3, pinned)
```

Add `import urllib.robotparser` to the imports. Add the combined-edge resolver and the robots gate:

```python
def _resolve_combined_edges(routes_raw, urls, norm_by_rid):
    """Resolve nav-edges for EVERY captured route (seed + discovered) against the COMBINED
    route_map (seed urls + discovered norms), so seed->discovered and discovered->seed links
    both resolve (spec §1 step 4). routes_raw: {route_index:int -> raw node-list}.
    norm_by_rid: {'rNN' -> normalized_url} for discovered routes. Returns formatted edges
    ({src,dst,src_node,chrome} with rNN ids). Content-free; never an href."""
    route_map = dict(_nav.build_route_map(urls))
    for rid, norm in norm_by_rid.items():
        route_map[norm] = int(rid[1:])
    all_edges = []
    for idx, raw in sorted(routes_raw.items()):
        for e in _edges_from_skeleton(raw, route_map, idx):
            all_edges.append({"src": "r%02d" % e["src"], "dst": "r%02d" % e["dst"],
                              "src_node": e["src_node"], "chrome": e["chrome"]})
    return all_edges


def _make_robots_allow(ua):
    """Per-origin robots.txt gate (fetched/cached once per host). UA is the crawler's
    declared name. Fail-CLOSED: an unreadable robots.txt -> skip that origin (stricter than
    the de-risk's fail-open, because this ships)."""
    cache = {}

    def allow(href):
        p = urlparse(href)
        origin = "%s://%s" % (p.scheme, p.netloc)
        rp = cache.get(origin)
        if rp is None:
            rp = urllib.robotparser.RobotFileParser()
            rp.set_url(origin + "/robots.txt")
            try:
                rp.read()
            except Exception:
                cache[origin] = False    # fail-closed sentinel
                return False
            cache[origin] = rp
        if rp is False:
            return False
        return rp.can_fetch(ua, href)

    return allow
```

> `urlparse` must be importable in `site_capture`. Add `from urllib.parse import urlparse` to the imports if not already present.

- [ ] **Step 4: Rewire `capture_site`** to accept `crawl=None` and branch. Replace the current `capture_site` body so the **non-crawl path is identical** and the crawl path runs after seeds:

```python
def capture_site(urls, out_dir, transport, sweep=None, crawl=None):
    """Capture every seed route, optionally expand one-hop (crawl), write site.json, and run
    the site-root firewall backstop. Returns the manifest dict. dies (nonzero) if the audit
    trips.

    crawl: None -> default behavior (unchanged). Else a params dict:
      {T, floor, max, delay, ua, robots_allow?, sleep?} — one-hop route-expander (spec §1)."""
    if sweep is None:
        sweep = []
    out = Path(out_dir)
    (out / "routes").mkdir(parents=True, exist_ok=True)
    route_map = _nav.build_route_map(urls)
    rows, all_edges = [], []
    seed_raw = {}     # src_id -> raw node-list (crawl only)
    for src_id, url in enumerate(urls):
        rid = "r%02d" % src_id
        # In crawl mode, defer edge resolution to the combined pass (route_map=None here).
        rm = None if crawl else route_map
        ok, node_count, error_kind, edges, raw = capture_route(
            url, out / "routes" / rid, transport, sweep, route_map=rm, src_id=src_id)
        row = {"route_id": rid, "url": url, "bundle": "routes/" + rid, "ok": ok}
        if ok:
            row["node_count"] = node_count
        else:
            row["error_kind"] = error_kind
        rows.append(row)
        if crawl:
            seed_raw[src_id] = raw if ok else []
        else:
            for e in edges:
                all_edges.append({"src": "r%02d" % e["src"], "dst": "r%02d" % e["dst"],
                                  "src_node": e["src_node"], "chrome": e["chrome"]})

    crawl_stats = None
    if crawl:
        import _crawl as cw
        seed_node_lists = [seed_raw.get(i, []) for i in range(len(urls))]
        seed_fps = [cw.content_fingerprint(seed_raw[i]) for i in sorted(seed_raw) if seed_raw[i]]
        frontier, n_cross = cw.frontier_targets(seed_node_lists, urls)
        frontier, n_over = cw.cap_frontier(frontier, crawl.get("max"))
        robots_allow = crawl.get("robots_allow") or _make_robots_allow(crawl.get("ua", "probe-runner/1.0"))
        sleep = crawl.get("sleep", time.sleep)
        disc_rows, raw_by_rid, norm_by_rid, ledger, _nxt = crawl_expand(
            frontier, seed_fps, out / "routes", len(urls), transport,
            T=crawl.get("T", 0.5), floor=crawl.get("floor", CRAWL_FLOOR),
            robots_allow=robots_allow, sleep=sleep, delay=crawl.get("delay", 2.0),
            skeleton_nodes=crawl.get("skeleton_nodes", _skeleton_nodes),
            capture_page=crawl.get("capture_page"))
        rows.extend(disc_rows)
        routes_raw = dict(seed_raw)
        for rid, raw in raw_by_rid.items():
            routes_raw[int(rid[1:])] = raw
        all_edges = _resolve_combined_edges(routes_raw, urls, norm_by_rid)
        crawl_stats = {"frontier": len(frontier), "cross_origin_dropped": n_cross,
                       "over_cap_dropped": n_over, "kept": len(disc_rows), **ledger}

    manifest = _site.build_site_manifest(rows, nav_edges=all_edges)
    if crawl_stats is not None:
        manifest["crawl"] = crawl_stats    # counts only (no URLs) -- spec §5 no-silent-caps
    (out / "site.json").write_text(json.dumps(manifest, indent=2))

    # Backstop: audit_bundle rglobs the whole tree -> covers site.json AND every per-route
    # bundle. Content-free failure: kind+file only, never the `sample`.
    viol = cf.audit_bundle(out)
    if viol:
        safe = [{"kind": v.get("kind"), "file": v.get("file")} for v in viol[:5]]
        die("content leak in site %s: %d violation(s); first %d: %s"
            % (out_dir, len(viol), len(safe), safe), code=3)
    return manifest
```

- [ ] **Step 5: Add the CLI flags + wiring in `main`.** After the `--sweep-steps` argument, add:

```python
    p.add_argument("--crawl", action="store_true", default=False,
                   help="one-hop same-origin discovery: capture novel un-enumerated pages (off by default)")
    p.add_argument("--crawl-max", type=int, default=40, dest="crawl_max",
                   help="hard cap on frontier pages attempted per run (default: 40)")
    p.add_argument("--crawl-threshold", type=float, default=0.5, dest="crawl_threshold",
                   help="novelty/dedup bag-Jaccard threshold T (default: 0.5)")
    p.add_argument("--crawl-delay", type=float, default=2.0, dest="crawl_delay",
                   help="inter-fetch rate-limit seconds (default: 2.0)")
```

Then replace the `capture_site(...)` call in `main` with a crawl-aware version:

```python
    crawl = None
    if args.crawl:
        crawl = {"T": args.crawl_threshold, "floor": CRAWL_FLOOR, "max": args.crawl_max,
                 "delay": args.crawl_delay, "ua": "probe-runner/1.0"}
    manifest = capture_site(urls, str(out_dir), _transport_argv(args), _sweep_argv(args), crawl=crawl)
```

And surface the crawl stats in the payload (counts only):

```python
    payload = {"ok": True, "out": str(out_dir),
               "route_count": manifest["route_count"], "ok_count": manifest["ok_count"]}
    if "crawl" in manifest:
        payload["crawl"] = manifest["crawl"]
```
(Insert the `if "crawl"` block right after `payload = {...}`, before the `--merge/--dedup` block.)

- [ ] **Step 6: Run the new tests + full suite**

Run: `cd <repo> && python3 -m pytest scripts/test_crawl_expand.py scripts/ -q`
Expected: PASS — combined-edges + crawl-branch tests pass; full suite green (default path unchanged).

- [ ] **Step 7: Commit**

```bash
git add scripts/site_capture.py scripts/test_crawl_expand.py
git commit -m "feat: wire --crawl into site_capture (one-hop expander) — combined nav_edges over seeds+discovered, fail-closed robots gate, content-free crawl stats block; default path unchanged"
```

---

## Task 5: Non-collected live smoke harness

A manual real-site check (NOT a pytest — filename must not start with `test_`), mirroring `scripts/derisk_crawl_yield.py`. Launches headless Chrome, runs `site_capture --crawl` against one cohort site into a tempdir, prints counts only.

**Files:**
- Create: `scripts/crawl_expander_smoke.py`

- [ ] **Step 1: Create `scripts/crawl_expander_smoke.py`:**

```python
#!/usr/bin/env python3
"""LIVE smoke (NOT a pytest; manual, headless real-site). §C9-R-CRAWL-BUILD route-expander.

Runs site_capture --crawl against a real cohort site and prints the manifest's content-free
counts (route_count, ok_count, crawl stats). NOTHING but counts is printed; no URLs, no hrefs.
Mirrors derisk_crawl_yield.py. Run: python3 scripts/crawl_expander_smoke.py
(needs Chrome). This is the human de-risk gate before declaring the feature validated
([[live-cdp-capture-is-manual-harness-not-pytest]]); it never runs in CI."""
from __future__ import annotations
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))
from _web import chrome_binary  # noqa: E402

# One cohort seed set (4 routes, mirrors the de-risk COHORT).
SEED_URLS = [
    "https://www.djangoproject.com/",
    "https://www.djangoproject.com/start/",
    "https://www.djangoproject.com/download/",
    "https://www.djangoproject.com/weblog/",
]


def _launch(udd):
    bin_ = chrome_binary()
    if not bin_:
        print("FATAL no-chrome"); sys.exit(2)
    p = subprocess.Popen(
        [bin_, "--headless=new", "--remote-debugging-port=0", "--remote-allow-origins=*",
         "--no-first-run", "--no-default-browser-check", "--user-data-dir=" + udd, "about:blank"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    pf = Path(udd) / "DevToolsActivePort"
    for _ in range(100):
        if pf.exists():
            t = pf.read_text().splitlines()
            if t:
                return p, int(t[0])
        time.sleep(0.1)
    p.terminate(); print("FATAL no-port"); sys.exit(2)


def main():
    print("§C9-R-CRAWL-BUILD route-expander LIVE smoke | --crawl --crawl-max 40 T=0.5 F=20")
    udd = tempfile.mkdtemp()
    out = tempfile.mkdtemp()
    proc, port = _launch(udd)
    try:
        r = subprocess.run(
            [sys.executable, "site_capture.py", "--urls", ",".join(SEED_URLS),
             "--out", out, "--cdp-port", str(port), "--crawl",
             "--crawl-max", "40", "--crawl-delay", "2.0"],
            cwd=str(SCRIPTS), capture_output=True, text=True)
        if r.returncode != 0:
            print("FAIL site_capture rc=%d" % r.returncode); return 1
        payload = json.loads(r.stdout)
        print("route_count:", payload.get("route_count"))
        print("ok_count:", payload.get("ok_count"))
        print("crawl:", json.dumps(payload.get("crawl", {}), sort_keys=True))
        print("PASS" if payload.get("ok") else "FAIL")
        return 0
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill(); proc.wait()
        shutil.rmtree(udd, ignore_errors=True)
        shutil.rmtree(out, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Confirm pytest does NOT collect it**

Run: `cd <repo> && python3 -m pytest scripts/ -q --co 2>/dev/null | grep -c crawl_expander_smoke`
Expected: `0` (not collected — filename has no `test_` prefix).

- [ ] **Step 3: Commit**

```bash
git add scripts/crawl_expander_smoke.py
git commit -m "test: non-collected live smoke harness for the --crawl route-expander (counts only, never URLs)"
```

---

## Task 6: Document the shipped feature

**Files:**
- Modify: `docs/plans/probe-runner-engine-capture-gaps.md` (the §C9-R-CRAWL-BUILD status)

- [ ] **Step 1: Append a build-completion note** under the existing `## §C9-R-CRAWL` results section (do NOT alter the de-risk verdict above it). Add:

```markdown
### §C9-R-CRAWL-BUILD — SHIPPED (2026-06-04): one-hop route-expander

Built per `docs/plans/crawl-discovery-route-expander.md` + `...-build-plan.md`. Pure
`scripts/_crawl.py` (frontier_targets / cap_frontier / reject_reason / accept; the 5
content-region primitives relocated out of the de-risk harness — `_crawl_yield.py` imports
them back). `site_capture --crawl` (off by default): seeds -> one-hop same-origin frontier ->
selection-skeleton -> novel+deduped capture -> combined `nav_edges` over seeds+discovered.

**Firewall:** discovered rows carry NO `url` (only `discovered`+`via` route_id); discovered
URLs in-memory only; `audit_bundle` backstop unchanged + a real-bytes "no discovered href in
site.json" test. **Fetch cost:** reject = 1 request, accept = 3 (re-fetch via untouched
`capture_route`; the split-scratch optimization is deferred). **T** demoted to a non-load-
bearing knob (`--crawl-threshold`, default 0.5) by the one-hop depth choice; T-anchoring is a
documented refinement, not a gate. Caveats carried (T partially audited; order-dependent
dedup under non-transitive similarity) — see spec §7.

Tests: `test_crawl.py` + `test_crawl_expand.py` (offline, injected fetchers) + non-collected
live smoke `crawl_expander_smoke.py`. Suite green.
```

- [ ] **Step 2: Update the roadmap-status footer** of that file: change the "crawler proper (build cycle, ready to open ...)" line to "**crawler proper one-hop expander SHIPPED (§C9-R-CRAWL-BUILD)**; multi-hop BFS remains DEFERRED (needs a T-anchoring de-risk — T becomes load-bearing)."

- [ ] **Step 3: Run the full suite one final time**

Run: `cd <repo> && python3 -m pytest scripts/ -q`
Expected: PASS — full suite green (543 baseline + new crawl tests).

- [ ] **Step 4: Commit**

```bash
git add docs/plans/probe-runner-engine-capture-gaps.md
git commit -m "docs: record §C9-R-CRAWL-BUILD one-hop route-expander SHIPPED; multi-hop BFS stays deferred (T-anchoring gate)"
```

---

## Post-plan: review + memory + finish

- After Task 6, dispatch the final whole-implementation code review (subagent-driven-development's terminal step), then use **superpowers:finishing-a-development-branch**.
- **Memory:** update `[[nav-graph-shipped-as-nav-annotation]]` to note the one-hop expander is now SHIPPED (was "next: build cycle"). Optionally add a memory if a non-obvious decision recurs (e.g., re-fetch-over-split tradeoff). Do NOT duplicate what the §C9-R-CRAWL-BUILD doc already records.
- **Firewall self-audit before finishing:** grep the new code + a sample `site.json` from the live smoke for any persisted href; confirm `audit_bundle` is unchanged and still the backstop.
```
