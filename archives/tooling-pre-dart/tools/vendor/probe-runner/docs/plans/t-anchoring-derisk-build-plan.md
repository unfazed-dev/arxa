# T-anchoring de-risk Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the measurement harness that anchors the same-template HIGH side of the content-fingerprint bag-Jaccard, so T=0.5 is validated/re-anchored/falsified before any multi-hop BFS build.

**Architecture:** Two pure, offline-tested cores — `_url_template.py` (URL-structural same-template grouping, independent of the metric → non-circular) and `_t_anchor.py` (distribution stats + the §3 pre-registered verdict) — plus a non-collected live harness `derisk_t_anchor.py` that reuses the shipped `_crawl` primitives and the existing `derisk_crawl_yield` Chrome/fetch helpers. Measurement-only: nothing is captured to disk, no URL is ever printed (firewall §5). Verdict emitted only; multi-hop is NOT built here.

**Tech Stack:** Python 3, stdlib only (`re`, `urllib.parse`, `itertools`), pytest. Reuses `_crawl.bag_jaccard` / `content_fingerprint` / `frontier_urls`, `_nav`, and `derisk_crawl_yield._launch` / `_capture_nodes` / `_robots` / `_origin` / `COHORT`.

**Spec:** `docs/plans/t-anchoring-derisk.md` (§C9-R-T-ANCHOR). Key spec points the implementer MUST honor:
- **LOW-primary = re-measured seed-seed pairs** (clean, hand-picked-distinct different-template set), drives the bar. Across-group frontier LOW is secondary/reported only.
- **Bar asymmetry (strict, no bending):** HIGH uses the **median**, LOW uses the **max**.
- **Conclusive site = ≥3 Tier-1 pagination pairs**; verdict needs **≥2 conclusive sites**.
- **Firewall:** URLs in-memory only, never persisted/printed; output is counts + bag-Jaccard scalars. Harness is non-collected (name `derisk_*` → pytest skips it).

**Test command (run from repo root):** `python -m pytest scripts/ -q` (567 tests today; each task adds to this).

---

## File Structure

- **Create** `scripts/_url_template.py` — pure URL-structural grouping. Functions: `paginate_key`, `sibling_key`, `group_by_template`, `within_group_pairs`, `across_group_pairs`. No I/O, no network.
- **Create** `scripts/test_url_template.py` — offline unit tests (synthetic `example.test` URLs only).
- **Create** `scripts/_t_anchor.py` — pure stats + verdict. Functions: `summarize`, `verdict`. No I/O.
- **Create** `scripts/test_t_anchor.py` — offline unit tests (injected per-site stats).
- **Create** `scripts/derisk_t_anchor.py` — non-collected live harness. Reuses `_crawl` + `derisk_crawl_yield` helpers + the two new cores. No unit test (manual/live, per the existing `derisk_*` pattern); validated by the Task 6 live run.
- **Modify (Task 6, after the run)** `docs/plans/probe-runner-engine-capture-gaps.md` — append the `§C9-R-T-ANCHOR` verdict block + roadmap footer.

---

### Task 1: `_url_template.paginate_key` — pagination template detection

**Files:**
- Create: `scripts/_url_template.py`
- Test: `scripts/test_url_template.py`

- [ ] **Step 1: Write the failing test**

```python
# scripts/test_url_template.py
import _url_template as ut


def test_query_page_param_same_template_distinct_index():
    a = ut.paginate_key("https://x.test/blog/?page=2")
    b = ut.paginate_key("https://x.test/blog/?page=3")
    assert a is not None and b is not None
    assert a[0] == b[0]          # same template
    assert (a[1], b[1]) == (2, 3)


def test_query_p_param_and_other_params_preserved():
    a = ut.paginate_key("https://x.test/list?p=1&sort=asc")
    b = ut.paginate_key("https://x.test/list?p=2&sort=asc")
    assert a is not None and a[0] == b[0]
    assert "sort=asc" in a[0]    # non-page params kept in the template


def test_path_page_segment():
    a = ut.paginate_key("https://x.test/news/page/4")
    b = ut.paginate_key("https://x.test/news/page/5")
    assert a is not None and a[0] == b[0] and (a[1], b[1]) == (4, 5)


def test_trailing_numeric_segment():
    a = ut.paginate_key("https://x.test/archive/10")
    b = ut.paginate_key("https://x.test/archive/11")
    assert a is not None and a[0] == b[0] and (a[1], b[1]) == (10, 11)


def test_host_canonicalized_www_stripped():
    a = ut.paginate_key("https://www.x.test/b/?page=2")
    b = ut.paginate_key("https://x.test/b/?page=3")
    assert a is not None and a[0] == b[0]


def test_non_paginated_returns_none():
    assert ut.paginate_key("https://x.test/about/") is None
    assert ut.paginate_key("https://x.test/") is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest scripts/test_url_template.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named '_url_template'`.

- [ ] **Step 3: Write minimal implementation**

```python
# scripts/_url_template.py
"""Pure URL-structural same-template grouping for the §C9-R-T-ANCHOR de-risk.
No I/O, no network. Labels same-template pairs by URL SHAPE (pagination / siblings),
independent of the bag-Jaccard content fingerprint -> the HIGH-side anchor is non-circular
(spec §1). URLs are handled transiently; this module neither persists nor logs them."""
import re
from itertools import combinations
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode

_PAGE_QS = {"page", "p"}
_PATH_PAGE = re.compile(r"/(?:page|p)/(\d+)(?=/|$)")
_TRAIL_NUM = re.compile(r"/(\d+)/?$")


def _canon_host(netloc):
    h = netloc.lower()
    return h[4:] if h.startswith("www.") else h


def _rebuild(scheme, host, path, query_pairs):
    return urlunsplit((scheme, host, path, urlencode(sorted(query_pairs)), ""))


def paginate_key(url):
    """If `url` matches a pagination form, return (template, index): `template` is the URL
    with the page index replaced by a placeholder / removed, `index` the int page number.
    Else None. Forms (high-confidence same-template, different content): ?page=N / ?p=N (query);
    /page/N or /p/N (path); a trailing pure-integer path segment. Host is lowercased + www-
    stripped so the same list paginated under either host collapses to one template."""
    parts = urlsplit(url)
    host = _canon_host(parts.netloc)
    q = parse_qsl(parts.query, keep_blank_values=True)
    idx, rest = None, []
    for k, v in q:
        if k.lower() in _PAGE_QS and idx is None and v.isdigit():
            idx = int(v)
        else:
            rest.append((k, v))
    if idx is not None:
        return (_rebuild(parts.scheme, host, parts.path, rest), idx)
    m = _PATH_PAGE.search(parts.path)
    if m:
        tmpl_path = parts.path[:m.start()] + "/page/{}" + parts.path[m.end():]
        return (_rebuild(parts.scheme, host, tmpl_path, q), int(m.group(1)))
    m = _TRAIL_NUM.search(parts.path)
    if m:
        tmpl_path = parts.path[:m.start()] + "/{}"
        return (_rebuild(parts.scheme, host, tmpl_path, q), int(m.group(1)))
    return None
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest scripts/test_url_template.py -q`
Expected: PASS (6 passed).

- [ ] **Step 5: Commit**

```bash
git add scripts/_url_template.py scripts/test_url_template.py
git commit -m "feat: _url_template.paginate_key — URL-structural pagination template detection (§C9-R-T-ANCHOR)"
```

---

### Task 2: `_url_template.sibling_key` + `group_by_template`

**Files:**
- Modify: `scripts/_url_template.py`
- Test: `scripts/test_url_template.py`

- [ ] **Step 1: Write the failing test**

```python
def test_sibling_key_shared_parent():
    assert ut.sibling_key("https://x.test/blog/foo") == ut.sibling_key("https://x.test/blog/bar")
    assert ut.sibling_key("https://x.test/blog/foo") != ut.sibling_key("https://x.test/news/baz")


def test_group_tier1_pagination_only_when_two_or_more():
    urls = ["https://x.test/b/?page=2", "https://x.test/b/?page=3", "https://x.test/solo/?page=9"]
    g = ut.group_by_template(urls)
    assert len(g["tier1"]) == 1                     # the /b/ template (2 members)
    members = next(iter(g["tier1"].values()))
    assert len(members) == 2
    assert g["tier2"] == {}                         # solo singleton dropped


def test_group_tier2_siblings_exclude_paginated():
    urls = ["https://x.test/blog/foo", "https://x.test/blog/bar",
            "https://x.test/blog/page/2", "https://x.test/blog/page/3"]
    g = ut.group_by_template(urls)
    assert len(g["tier1"]) == 1                     # the /blog/page/{} pagination group
    assert len(g["tier2"]) == 1                     # foo+bar siblings, NOT the paginated ones
    assert all("page/2" not in m and "page/3" not in m
               for m in next(iter(g["tier2"].values())))


def test_group_dedups_identical_urls():
    g = ut.group_by_template(["https://x.test/b/?page=2", "https://x.test/b/?page=2"])
    assert g["tier1"] == {} and g["tier2"] == {}    # one distinct url -> no pair
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest scripts/test_url_template.py -q`
Expected: FAIL — `AttributeError: module '_url_template' has no attribute 'sibling_key'`.

- [ ] **Step 3: Write minimal implementation** (append to `scripts/_url_template.py`)

```python
def sibling_key(url):
    """Tier-2 grouping key: scheme://host/<parent-path> (last path segment removed). Two
    distinct URLs sharing a sibling_key are same-parent siblings (medium-confidence same
    template; corroborative only)."""
    parts = urlsplit(url)
    host = _canon_host(parts.netloc)
    segs = [s for s in parts.path.split("/") if s]
    parent = "/".join(segs[:-1])
    return f"{parts.scheme}://{host}/{parent}"


def group_by_template(urls):
    """Partition URLs into same-template groups by URL shape (spec §1). A URL with a
    paginate_key goes to Tier 1 (grouped by template); otherwise to Tier 2 (grouped by
    sibling_key). URLs are deduped first; only groups with >=2 distinct members are kept
    (a singleton forms no pair). Returns {"tier1": {template: [urls]}, "tier2": {parent: [urls]}}."""
    urls = list(dict.fromkeys(urls))
    tier1, t2_pool = {}, []
    for u in urls:
        pk = paginate_key(u)
        if pk is not None:
            tier1.setdefault(pk[0], []).append(u)
        else:
            t2_pool.append(u)
    tier2 = {}
    for u in t2_pool:
        tier2.setdefault(sibling_key(u), []).append(u)
    tier1 = {k: v for k, v in tier1.items() if len(v) >= 2}
    tier2 = {k: v for k, v in tier2.items() if len(v) >= 2}
    return {"tier1": tier1, "tier2": tier2}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest scripts/test_url_template.py -q`
Expected: PASS (10 passed).

- [ ] **Step 5: Commit**

```bash
git add scripts/_url_template.py scripts/test_url_template.py
git commit -m "feat: _url_template sibling_key + group_by_template — two-tier same-template grouping (§C9-R-T-ANCHOR)"
```

---

### Task 3: `_url_template.within_group_pairs` + `across_group_pairs`

**Files:**
- Modify: `scripts/_url_template.py`
- Test: `scripts/test_url_template.py`

- [ ] **Step 1: Write the failing test**

```python
def test_within_group_pairs_combinations():
    g = ut.group_by_template(["https://x.test/b/?page=2", "https://x.test/b/?page=3",
                              "https://x.test/b/?page=4"])
    pairs = ut.within_group_pairs(g["tier1"])
    assert len(pairs) == 3                          # C(3,2)
    for a, b in pairs:
        assert a != b


def test_across_group_pairs_only_cross_template():
    urls = ["https://x.test/b/?page=2", "https://x.test/b/?page=3",   # template A
            "https://x.test/news/foo"]                                # group B
    pairs = ut.across_group_pairs(urls)
    # the two /b/ pages share a template -> excluded; each pairs with /news/foo -> 2 pairs
    assert len(pairs) == 2
    flat = {frozenset(p) for p in pairs}
    assert all("https://x.test/news/foo" in p for p in pairs)
    assert frozenset(("https://x.test/b/?page=2", "https://x.test/b/?page=3")) not in flat
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest scripts/test_url_template.py -q`
Expected: FAIL — `AttributeError: ... 'within_group_pairs'`.

- [ ] **Step 3: Write minimal implementation** (append to `scripts/_url_template.py`)

First add the `combinations` import to the top of the file (Task 1 deliberately omitted it — it is first used here):

```python
from itertools import combinations
```

Then append:

```python
def within_group_pairs(groups):
    """All unordered within-group pairs for ONE tier's group dict (e.g. groups["tier1"]).
    Each group already has >=2 distinct members (group_by_template). HIGH side of the bar."""
    pairs = []
    for members in groups.values():
        pairs.extend(combinations(members, 2))
    return pairs


def _group_id(url):
    pk = paginate_key(url)
    return ("t1", pk[0]) if pk is not None else ("t2", sibling_key(url))


def across_group_pairs(urls):
    """All unordered pairs of distinct URLs whose template-group differs. Singletons each
    form their own group, so an ungrouped URL pairs across with everything that does not
    share its template key. Secondary (same-population) LOW cross-check; not in the bar."""
    urls = list(dict.fromkeys(urls))
    return [(a, b) for a, b in combinations(urls, 2) if _group_id(a) != _group_id(b)]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest scripts/test_url_template.py -q`
Expected: PASS (12 passed).

- [ ] **Step 5: Commit**

```bash
git add scripts/_url_template.py scripts/test_url_template.py
git commit -m "feat: _url_template pair enumerators — within-group (HIGH) + across-group (LOW) (§C9-R-T-ANCHOR)"
```

---

### Task 4: `_t_anchor.summarize` + `verdict`

**Files:**
- Create: `scripts/_t_anchor.py`
- Test: `scripts/test_t_anchor.py`

- [ ] **Step 1: Write the failing test**

```python
# scripts/test_t_anchor.py
import _t_anchor as ta


def test_summarize_basic():
    assert ta.summarize([0.2, 0.4, 0.9]) == (0.2, 0.4, 0.9, 3)
    assert ta.summarize([0.2, 0.4]) == (0.2, 0.3, 0.4, 2)      # even -> mean of middle two
    assert ta.summarize([]) is None


def _site(high, low, n):
    return {"high_t1_median": high, "low_max": low, "n_t1_pairs": n}


def test_verdict_inconclusive_below_two_conclusive_sites():
    # only one site clears the >=3 Tier-1 pairs floor
    d, t = ta.verdict([_site(0.8, 0.3, 5), _site(0.8, 0.3, 2)])
    assert d == "INCONCLUSIVE" and t is None


def test_verdict_pass_05_in_band():
    d, t = ta.verdict([_site(0.7, 0.3, 5), _site(0.8, 0.45, 4)])
    assert d == "PASS" and t == 0.5


def test_verdict_reanchor_band_excludes_05():
    # clean gap (0.45, 0.7) but 0.5 ... still inside -> craft a gap above 0.5
    d, t = ta.verdict([_site(0.75, 0.55, 5), _site(0.85, 0.6, 4)])
    assert d == "RE-ANCHOR"
    assert t == round((0.6 + 0.75) / 2, 3)        # midpoint of (max_low, min_high)


def test_verdict_fail_on_overlap():
    d, t = ta.verdict([_site(0.5, 0.6, 5), _site(0.8, 0.3, 4)])  # site1 low_max > its high
    assert d == "FAIL" and t is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest scripts/test_t_anchor.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named '_t_anchor'`.

- [ ] **Step 3: Write minimal implementation**

```python
# scripts/_t_anchor.py
"""Pure stats + pre-registered verdict for the §C9-R-T-ANCHOR de-risk (spec §3).
No I/O. Separated from _url_template so URL parsing and the bar are independently testable."""


def summarize(values):
    """(min, median, max, n) of a list of bag-Jaccard scalars, or None if empty.
    median = mean of the middle two for an even count."""
    if not values:
        return None
    s = sorted(values)
    n = len(s)
    median = s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2
    return (s[0], median, s[-1], n)


def verdict(per_site):
    """Apply the §3 pre-registered bar. `per_site` = list of
    {high_t1_median: float|None, low_max: float|None, n_t1_pairs: int}.

    Conclusive site = n_t1_pairs >= 3 with both stats present. Needs >= 2 conclusive sites.
    Bar (strict, asymmetric): HIGH uses the median, LOW uses the max.
      PASS      -> clean gap AND 0.5 strictly inside it     (t_reco = 0.5)
      RE-ANCHOR -> clean gap but 0.5 outside it             (t_reco = gap midpoint)
      FAIL      -> HIGH/LOW overlap (no separating T)       (t_reco = None)
      INCONCLUSIVE -> < 2 conclusive sites                  (t_reco = None)
    Returns (decision, t_reco)."""
    conclusive = [s for s in per_site
                  if s["n_t1_pairs"] >= 3
                  and s["high_t1_median"] is not None
                  and s["low_max"] is not None]
    if len(conclusive) < 2:
        return ("INCONCLUSIVE", None)
    min_high = min(s["high_t1_median"] for s in conclusive)
    max_low = max(s["low_max"] for s in conclusive)
    if max_low >= min_high:                      # overlap -> no clean separating threshold
        return ("FAIL", None)
    if max_low < 0.5 < min_high:                 # 0.5 strictly inside the gap
        return ("PASS", 0.5)
    return ("RE-ANCHOR", round((max_low + min_high) / 2, 3))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest scripts/test_t_anchor.py -q`
Expected: PASS (6 passed).

- [ ] **Step 5: Commit**

```bash
git add scripts/_t_anchor.py scripts/test_t_anchor.py
git commit -m "feat: _t_anchor summarize + verdict — §C9-R-T-ANCHOR pre-registered bar (strict median-vs-max, ≥2 conclusive sites)"
```

---

### Task 5: `derisk_t_anchor.py` — non-collected live harness

**Files:**
- Create: `scripts/derisk_t_anchor.py`
- (No unit test — non-collected manual/live harness, per the existing `derisk_*` pattern; validated by the Task 6 live run. The pure logic it calls is already covered by Tasks 1–4.)

- [ ] **Step 1: Write the harness**

```python
# scripts/derisk_t_anchor.py
"""§C9-R-T-ANCHOR live de-risk harness (NON-COLLECTED — name is derisk_*, pytest skips it).
Anchors the same-template HIGH side: discovers the one-hop same-origin frontier, groups it by
URL structure (_url_template), fetches each page, and reports bag-Jaccard distributions
HIGH-T1 (within pagination) / HIGH-T2 (within siblings) / LOW-primary (seed-seed) /
LOW-secondary (across-group frontier), then the §3 verdict. FIREWALL: URLs live in memory only;
output is counts + bag-Jaccard scalars; nothing is written to disk. Manual run:
  python derisk_t_anchor.py            # from scripts/   (~minutes; live Chrome)
"""
from __future__ import annotations
import shutil
import subprocess
import tempfile
import time
from itertools import combinations

import _t_anchor as ta
import _url_template as ut
from _crawl import bag_jaccard, content_fingerprint, frontier_urls, passes_floor
from derisk_crawl_yield import (COHORT, DELAY_S, F, MAX_FRONTIER, UA,
                                _capture_nodes, _launch, _origin, _robots)

T = 0.5


def _seed_fps(seed_urls, port):
    nodes, fps = [], []
    for u in seed_urls:
        n = _capture_nodes(u, port)
        time.sleep(DELAY_S)
        if n is None:
            continue
        fp = content_fingerprint(n)
        if not passes_floor(fp, F):
            continue
        nodes.append(n)
        fps.append(fp)
    return nodes, fps


def _fetch_frontier_fps(frontier, port):
    """Fetch each frontier page once; return {href: fp} for valid (>=F) captures only.
    robots-gated, rate-limited. URLs stay in memory; never printed."""
    fp_by, robots_cache = {}, {}
    n_robots = n_failed = n_subfloor = 0
    for _norm, href in frontier:
        origin = _origin(href)
        rp = robots_cache.get(origin)
        if rp is None:
            rp = _robots(origin); robots_cache[origin] = rp
        if not rp.can_fetch(UA, href):
            n_robots += 1; continue
        n = _capture_nodes(href, port)
        time.sleep(DELAY_S)
        if n is None:
            n_failed += 1; continue
        fp = content_fingerprint(n)
        if not passes_floor(fp, F):
            n_subfloor += 1; continue
        fp_by[href] = fp
    return fp_by, dict(robots_blocked=n_robots, failed=n_failed, subfloor=n_subfloor)


def _pair_jac(pairs, fp_by):
    return [bag_jaccard(fp_by[a], fp_by[b]) for a, b in pairs if a in fp_by and b in fp_by]


def run_site(site, seed_urls):
    print(f"\n=== {site} ===")
    udd = tempfile.mkdtemp()
    proc, port = _launch(udd)
    try:
        seed_nodes, seed_fps = _seed_fps(seed_urls, port)
        if len(seed_fps) < 2:
            print(f"  INCONCLUSIVE: only {len(seed_fps)} valid seeds")
            return {"high_t1_median": None, "low_max": None, "n_t1_pairs": 0}

        frontier, n_cross = frontier_urls(seed_nodes, seed_urls)
        n_capped = max(0, len(frontier) - MAX_FRONTIER)
        frontier = frontier[:MAX_FRONTIER]
        hrefs = [h for _n, h in frontier]
        groups = ut.group_by_template(hrefs)
        print(f"  frontier={len(frontier)} (cross-origin {n_cross}, over-cap {n_capped}); "
              f"tier1-groups={len(groups['tier1'])} tier2-groups={len(groups['tier2'])}")

        fp_by, drops = _fetch_frontier_fps(frontier, port)
        print(f"  frontier captures valid={len(fp_by)} {drops}")

        high_t1 = _pair_jac(ut.within_group_pairs(groups["tier1"]), fp_by)
        high_t2 = _pair_jac(ut.within_group_pairs(groups["tier2"]), fp_by)
        low_sec = _pair_jac(ut.across_group_pairs(hrefs), fp_by)
        low_pri = [bag_jaccard(a, b) for a, b in combinations(seed_fps, 2)]

        for label, vals in (("HIGH-T1", high_t1), ("HIGH-T2", high_t2),
                            ("LOW-primary(seed-seed)", low_pri), ("LOW-secondary(across)", low_sec)):
            s = ta.summarize(vals)
            print(f"  {label:24} {s}")

        s1 = ta.summarize(high_t1)
        return {"high_t1_median": (s1[1] if s1 else None),
                "low_max": (max(low_pri) if low_pri else None),
                "n_t1_pairs": len(high_t1)}
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill(); proc.wait()
        shutil.rmtree(udd, ignore_errors=True)


def main():
    print(f"§C9-R-T-ANCHOR | T={T} F={F} | bar: HIGH-T1 median>0.5 & seed-seed max<0.5, "
          f">=3 T1 pairs/site, >=2 conclusive sites")
    per_site = [run_site(s, u) for s, u in COHORT.items()]
    decision, t_reco = ta.verdict(per_site)
    print("\n=== VERDICT (provisional; confirm on a repro draw) ===")
    print(f"conclusive sites (>=3 T1 pairs): "
          f"{sum(1 for s in per_site if s['n_t1_pairs'] >= 3)}/{len(per_site)}")
    print(f"{decision}  T_reco={t_reco}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Verify it imports cleanly and is NOT pytest-collected**

Run: `python -c "import sys; sys.path.insert(0,'scripts'); import derisk_t_anchor; print('import OK', derisk_t_anchor.T)"`
Expected: `import OK 0.5` (no network — import only).

Run: `python -m pytest scripts/ -q --collect-only 2>/dev/null | tail -1`
Expected: collected count unchanged from the new test files only (no `derisk_t_anchor` collected — name starts with `derisk_`).

- [ ] **Step 3: Run the full suite (regression guard)**

Run: `python -m pytest scripts/ -q`
Expected: PASS — 567 prior + the new `test_url_template.py` (12) + `test_t_anchor.py` (6) = 585. No failures.

- [ ] **Step 4: Commit**

```bash
git add scripts/derisk_t_anchor.py
git commit -m "feat: derisk_t_anchor.py — non-collected live harness for the §C9-R-T-ANCHOR HIGH-side anchor (firewall: counts/scalars only)"
```

---

### Task 6: Live de-risk run + record verdict (execution, not TDD)

This task is the actual de-risk measurement. It is live (headless Chrome, ~minutes/site) and manual — done by the orchestrator, not a code-writing subagent. **Phase 0 then Phase 1, per spec §7.**

- [ ] **Step 1: Phase 0 — falsify-cheap (single draw)**

Run: `cd scripts && python derisk_t_anchor.py` (from repo root: `python scripts/derisk_t_anchor.py` after `cd scripts`, since the harness uses sibling imports).
Capture ONLY the printed counts + scalar distributions + provisional verdict (NEVER any URL).
Two gate questions:
1. **Separation visible?** Are HIGH-T1 medians clearly above the seed-seed LOW max (and the 0.015–0.472 reference)?
2. **Tier-1 non-sparse?** ≥3 pagination pairs on ≥2 sites?

- If **no separation** → record **FAIL** evidence in the roadmap, STOP (multi-hop stays DEFERRED). Done.
- If **Tier-1 sparse** across the cohort → add 1–2 pagination-rich sites to `COHORT` in `derisk_t_anchor.py` (a blog/news/docs index with clear `/page/N`; chosen for structural pagination, recorded reason — NOT a favorable-score pick), re-run Phase 0.

- [ ] **Step 2: Phase 1 — repro draw (only if Phase 0 survives)**

Re-run the harness a second time, same regime (the [[derisk-must-record-capture-regime]] scar — a favorable single draw does not count). Confirm the conclusive-site set and the decision reproduce.

- [ ] **Step 3: Record the verdict**

Append a `## §C9-R-T-ANCHOR — Results: ...` block to `docs/plans/probe-runner-engine-capture-gaps.md` (mirror the §C9-R-CRAWL block): the per-site distribution table (scalars only), the regime line (headless 1440×900, robots, 2s, F=20, single + repro draw), the pre-registered bar, and the verdict (PASS=T=0.5 validated / RE-ANCHOR=T=X / FAIL=multi-hop stays DEFERRED). Update the roadmap footer. Update memory `nav-graph-shipped-as-nav-annotation.md` with the anchoring outcome.

- [ ] **Step 4: Commit**

```bash
git add docs/plans/probe-runner-engine-capture-gaps.md
git commit -m "docs: record §C9-R-T-ANCHOR verdict (<PASS|RE-ANCHOR T=X|FAIL>) — same-template HIGH side anchored; multi-hop BFS <BUILD-justified|stays DEFERRED>"
```

- [ ] **Step 5: Consequence**

- **PASS / RE-ANCHOR** → multi-hop BFS becomes BUILD-justified (at T=0.5 or the re-anchored T). Open a separate brainstorm→spec→plan; do NOT build here.
- **FAIL** → multi-hop stays DEFERRED; record that a different novelty signal is required. Do NOT build a replacement here.

---

## Self-Review

**1. Spec coverage:**
- §1 non-circular URL-structural labeling → Tasks 1–3 (`paginate_key`/`sibling_key`/grouping), independent of bag-Jaccard. ✓
- §2 measurement (HIGH-T1/T2, LOW-primary seed-seed, LOW-secondary across-group) → Task 5 `run_site`. ✓
- §3 pre-registered bar (median-vs-max, ≥3 T1 pairs, ≥2 conclusive sites, PASS/RE-ANCHOR/FAIL) → Task 4 `verdict` + Task 6. ✓
- §4 cohort/regime/repro → Task 5 reuses `COHORT`/`_launch` (1440×900); Task 6 Phase 0/1 repro + pagination-rich fallback. ✓
- §5 firewall (in-memory URLs, counts/scalars only, non-collected, no disk write) → Task 5 harness prints only scalars/counts; `derisk_*` name uncollected; no bundle written. ✓
- §6 `_url_template.py` + `_t_anchor.py` + tests + harness + verdict record → Tasks 1–6. ✓
- §7 falsify-cheap staging → Task 6 Phase 0 before Phase 1. ✓

**2. Placeholder scan:** No TBD/TODO; every code step shows complete code; commands have expected output. The only intentional `<PASS|RE-ANCHOR|FAIL>` placeholders are in Task 6 commit/record text — unavoidable, the verdict is the run's output.

**3. Type consistency:** `paginate_key` → `(template, index)|None`; `group_by_template` → `{"tier1":..,"tier2":..}`; `within_group_pairs(tier_dict)`; `across_group_pairs(urls)`; `summarize` → `(min,med,max,n)|None`; `verdict(list[{high_t1_median,low_max,n_t1_pairs}])` → `(decision, t_reco)`. Harness `run_site` returns exactly the `verdict` per-site dict shape. Consistent across tasks. ✓
