# Crawl-discovery yield de-risk harness — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `§C9-R-CRAWL` de-risk harness that measures whether one-hop crawl-discovery surfaces content templates structurally novel vs the user-enumerated seed routes, against a pre-registered bar.

**Architecture:** A pure, unit-tested scoring core (`_crawl_yield.py`: content-region fingerprint, bag-Jaccard, frontier extraction, novelty count, discrimination matrix) reusing existing content-free primitives (`_shape_key._node_key`, `_nav.classify_chrome`/`normalize_url`/`build_route_map`), wrapped by a **non-collected** manual harness (`derisk_crawl_yield.py`) that launches headless Chrome, drives `web_skeleton.py` per URL, honors robots.txt + a rate limit, and prints a per-site + aggregate verdict. URLs are used transiently; only counts/stats are persisted.

**Tech Stack:** Python 3, pytest (pure core only), headless Chrome via CDP (existing `web_skeleton.py` subprocess), `urllib.robotparser`.

**Spec:** `docs/plans/crawl-discovery-yield-derisk.md`. Memory: `[[falsify-detection-signal-on-real-neg-controls-before-code]]`, `[[validate-real-artifact-not-keys-proxy]]`, `[[derisk-must-record-capture-regime]]`, `[[live-cdp-capture-is-manual-harness-not-pytest]]`, `[[cdp-capture-needs-open-tab]]`.

---

## File Structure

- **Create `scripts/_crawl_yield.py`** — pure scoring core. No I/O, no network. Imports `_shape_key`, `_nav`, `collections.Counter`. Responsibility: turn raw skeleton node-lists into a novelty count + discrimination matrix.
- **Create `scripts/test_crawl_yield.py`** — collected pytest for the pure core only (synthetic node-lists, no network). Adds to the existing suite (530 → 530+N).
- **Create `scripts/derisk_crawl_yield.py`** — non-collected manual harness (name starts `derisk_`, not `test_`, so pytest never collects it; mirrors `derisk_pseudo_geometry.py`). I/O shell: Chrome launch, `web_skeleton.py` subprocess, robots, rate-limit, verdict print.
- **Modify `docs/plans/probe-runner-engine-capture-gaps.md`** — final task appends the `§C9-R-CRAWL` results section + repoints the roadmap footer.

**Why split:** the scoring logic is the only part with correctness risk and is fully testable offline; the capture/network shell is inherently manual (live Chrome, ~minutes/site) and must not enter CI. Keeping them in separate files lets the core be TDD'd green while the shell stays a hand-run harness.

---

### Task 1: `bag_jaccard` (pure similarity)

**Files:**
- Create: `scripts/_crawl_yield.py`
- Test: `scripts/test_crawl_yield.py`

- [ ] **Step 1: Write the failing test**

```python
# scripts/test_crawl_yield.py
from collections import Counter
import _crawl_yield as cy


def test_bag_jaccard_identical_is_one():
    a = Counter({"x": 2, "y": 1})
    assert cy.bag_jaccard(a, Counter({"x": 2, "y": 1})) == 1.0


def test_bag_jaccard_disjoint_is_zero():
    assert cy.bag_jaccard(Counter({"x": 1}), Counter({"y": 1})) == 0.0


def test_bag_jaccard_partial_overlap():
    # min: x->1, y->0, z->0 => 1 ; max: x->2, y->1, z->1 => 4 ; 1/4
    a = Counter({"x": 1, "y": 1})
    b = Counter({"x": 2, "z": 1})
    assert cy.bag_jaccard(a, b) == 0.25


def test_bag_jaccard_both_empty_is_one():
    assert cy.bag_jaccard(Counter(), Counter()) == 1.0


def test_bag_jaccard_one_empty_is_zero():
    assert cy.bag_jaccard(Counter({"x": 1}), Counter()) == 0.0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scripts && python3 -m pytest test_crawl_yield.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named '_crawl_yield'`

- [ ] **Step 3: Write minimal implementation**

```python
# scripts/_crawl_yield.py
"""Pure scoring core for the §C9-R-CRAWL crawl-discovery yield de-risk.
No I/O, no network. Spec: docs/plans/crawl-discovery-yield-derisk.md."""
from collections import Counter

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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd scripts && python3 -m pytest test_crawl_yield.py -q`
Expected: PASS (5 passed)

- [ ] **Step 5: Commit**

```bash
git add scripts/_crawl_yield.py scripts/test_crawl_yield.py
git commit -m "feat: bag-Jaccard similarity for crawl-yield de-risk core (§C9-R-CRAWL)"
```

---

### Task 2: `content_fingerprint` (non-chrome `_node_key` multiset)

**Files:**
- Modify: `scripts/_crawl_yield.py`
- Test: `scripts/test_crawl_yield.py`

- [ ] **Step 1: Write the failing test**

```python
# append to scripts/test_crawl_yield.py
def _node(nid, parent=None, aria_role=None, role="generic", href=None, text_len=0):
    n = {"id": nid, "parent": parent, "role": role, "text_len": text_len}
    if aria_role is not None:
        n["aria_role"] = aria_role
    if href is not None:
        n["href"] = href
    return n


def test_content_fingerprint_excludes_chrome():
    # node 1 lives under a navigation landmark (chrome) -> excluded;
    # node 3 lives under main (content) -> included.
    nodes = [
        _node(0, aria_role="navigation"),
        _node(1, parent=0, role="link"),          # chrome -> excluded
        _node(2, aria_role="main"),
        _node(3, parent=2, role="link"),          # content -> included
    ]
    fp = cy.content_fingerprint(nodes)
    # only node 2 (main landmark) and node 3 are content; node 2 itself is a landmark
    # but NOT a chrome landmark, so it is included too.
    assert sum(fp.values()) == 2


def test_content_fingerprint_counts_multiset():
    # two structurally identical content nodes -> one key with count 2
    nodes = [
        _node(0, aria_role="main"),
        _node(1, parent=0, role="listitem", text_len=5),
        _node(2, parent=0, role="listitem", text_len=5),
    ]
    fp = cy.content_fingerprint(nodes)
    listitem_keys = [k for k, c in fp.items() if c == 2]
    assert len(listitem_keys) == 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scripts && python3 -m pytest test_crawl_yield.py -q`
Expected: FAIL — `AttributeError: module '_crawl_yield' has no attribute 'content_fingerprint'`

- [ ] **Step 3: Write minimal implementation**

```python
# append to scripts/_crawl_yield.py
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd scripts && python3 -m pytest test_crawl_yield.py -q`
Expected: PASS (7 passed)

- [ ] **Step 5: Commit**

```bash
git add scripts/_crawl_yield.py scripts/test_crawl_yield.py
git commit -m "feat: content-region fingerprint (non-chrome _node_key multiset) for crawl de-risk"
```

---

### Task 3: `frontier_urls` (content anchors minus the seed set)

**Files:**
- Modify: `scripts/_crawl_yield.py`
- Test: `scripts/test_crawl_yield.py`

- [ ] **Step 1: Write the failing test**

```python
# append to scripts/test_crawl_yield.py
def test_frontier_urls_keeps_content_links_to_unenumerated_pages():
    seed_urls = ["https://ex.com/", "https://ex.com/about"]
    # one seed route's nodes:
    nodes = [
        _node(0, aria_role="navigation"),
        _node(1, parent=0, role="link", href="https://ex.com/about"),   # chrome -> dropped
        _node(2, aria_role="main"),
        _node(3, parent=2, role="link", href="https://ex.com/blog/x"),  # content, NOT seed -> KEEP
        _node(4, parent=2, role="link", href="https://ex.com/about"),   # content but IS seed -> drop
        _node(5, parent=2, role="link", href="https://other.com/z"),    # different origin but still resolves; kept only if not seed
        _node(6, parent=2, role="link", href="mailto:a@b.c"),           # non-http -> drop
        _node(7, parent=2, role="link", href="https://ex.com/blog/x#h"),# dup of node 3 after normalize -> collapse
    ]
    out = cy.frontier_urls([nodes], seed_urls)
    norms = {n for n, _ in out}
    assert "ex.com/blog/x" in norms
    assert "ex.com/about" not in norms          # seed route excluded
    assert all(not k.startswith("mailto") for k in norms)
    # blog/x appears once despite the #fragment duplicate
    assert sum(1 for n, _ in out if n == "ex.com/blog/x") == 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scripts && python3 -m pytest test_crawl_yield.py -q`
Expected: FAIL — `AttributeError: module '_crawl_yield' has no attribute 'frontier_urls'`

- [ ] **Step 3: Write minimal implementation**

```python
# append to scripts/_crawl_yield.py
def frontier_urls(seed_node_lists, seed_urls):
    """One-hop discovery frontier: content (non-chrome) anchors across ALL seed routes,
    normalized, minus the seed route set, deduped by normalized URL. Returns
    [(normalized_url, raw_href)] preserving the first raw href seen for each norm.
    The raw href is returned ONLY so the harness can fetch it transiently; it is never
    persisted (the firewall line in the spec)."""
    route_map = _nav.build_route_map(seed_urls)
    seen = {}
    for nodes in seed_node_lists:
        by_id = {n["id"]: n for n in nodes}
        for n in nodes:
            href = n.get("href")
            if not href:
                continue
            if _nav.classify_chrome(n["id"], by_id):     # content links only
                continue
            norm = _nav.normalize_url(href)
            if norm is None or norm in route_map or norm in seen:
                continue
            seen[norm] = href
    return list(seen.items())
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd scripts && python3 -m pytest test_crawl_yield.py -q`
Expected: PASS (8 passed)

- [ ] **Step 5: Commit**

```bash
git add scripts/_crawl_yield.py scripts/test_crawl_yield.py
git commit -m "feat: one-hop frontier extraction (content anchors minus seed set) for crawl de-risk"
```

---

### Task 4: `count_novel_templates` + `discrimination_matrix` (verdict math)

**Files:**
- Modify: `scripts/_crawl_yield.py`
- Test: `scripts/test_crawl_yield.py`

- [ ] **Step 1: Write the failing test**

```python
# append to scripts/test_crawl_yield.py
def test_count_novel_templates_basic():
    seed = [Counter({"a": 3}), Counter({"b": 3})]
    frontier = [
        Counter({"a": 3}),         # identical to a seed -> NOT novel
        Counter({"z": 5}),         # far from all seeds -> novel
        Counter({"z": 5}),         # identical to the prior novel -> collapses, +0
        Counter({"q": 1, "w": 1}), # novel, distinct from {z} -> +1
    ]
    assert cy.count_novel_templates(frontier, seed, T=0.5) == 2


def test_count_novel_templates_threshold_boundary():
    # bag_jaccard = 0.5 exactly is NOT < T, so the page is "same template", not novel.
    seed = [Counter({"x": 1, "y": 1})]
    frontier = [Counter({"x": 1, "z": 1})]   # jaccard = 1/3 < 0.5 -> novel
    assert cy.count_novel_templates(frontier, seed, T=0.5) == 1
    frontier_same = [Counter({"x": 1, "y": 1, "z": 1})]  # 2/3 >= 0.5 -> not novel
    assert cy.count_novel_templates(frontier_same, seed, T=0.5) == 0


def test_discrimination_matrix_diagonal_is_one():
    seed = [Counter({"a": 1}), Counter({"b": 1})]
    m = cy.discrimination_matrix(seed)
    assert m[0][0] == 1.0 and m[1][1] == 1.0
    assert m[0][1] == 0.0    # different templates -> low
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scripts && python3 -m pytest test_crawl_yield.py -q`
Expected: FAIL — `AttributeError: module '_crawl_yield' has no attribute 'count_novel_templates'`

- [ ] **Step 3: Write minimal implementation**

```python
# append to scripts/_crawl_yield.py
def count_novel_templates(frontier_fps, seed_fps, T):
    """A frontier fingerprint is NOVEL iff its best bag_jaccard to ALL seed fingerprints
    is < T. Novel fingerprints are then collapsed against each other (>= T => same
    template) so K identical novel pages count as ONE template. Returns the count of
    distinct novel templates. T is pre-registered (0.5); see spec."""
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

- [ ] **Step 4: Run test to verify it passes**

Run: `cd scripts && python3 -m pytest test_crawl_yield.py -q`
Expected: PASS (11 passed)

- [ ] **Step 5: Run the FULL suite to confirm zero regressions**

Run: `cd scripts && python3 -m pytest -q`
Expected: PASS — prior total + 11 (e.g. 541 passed), no failures.

- [ ] **Step 6: Commit**

```bash
git add scripts/_crawl_yield.py scripts/test_crawl_yield.py
git commit -m "feat: novelty count + discrimination matrix (verdict math) for crawl de-risk core"
```

---

### Task 5: Assemble the manual harness `derisk_crawl_yield.py`

**Files:**
- Create: `scripts/derisk_crawl_yield.py` (non-collected — name starts `derisk_`)

This task has NO pytest (it is the live-CDP I/O shell, manual by design per `[[live-cdp-capture-is-manual-harness-not-pytest]]`). The verification step is an import/static check, not a network run (the network run is Task 6).

- [ ] **Step 1: Write the harness**

```python
#!/usr/bin/env python3
"""DE-RISK harness (NOT a pytest; manual, headless real-site). §C9-R-CRAWL crawl-discovery yield.

Does one-hop crawl-discovery surface content templates structurally NOVEL vs the seed routes?
Bar (pre-registered, spec docs/plans/crawl-discovery-yield-derisk.md): >=2 novel content-templates
on >=2 of 4 sites, bag-Jaccard T=0.5. Discrimination control runs first; aborts a site if the
fingerprint cannot separate same-vs-different seed templates.

URLs are used transiently to fetch only; NOTHING but counts/stats is printed. Never writes an href.

Run: python3 scripts/derisk_crawl_yield.py   (needs Chrome + websocket-client)
"""
from __future__ import annotations
import json
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.robotparser
from pathlib import Path
from collections import Counter
from urllib.parse import urlparse

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))
import _crawl_yield as cy  # noqa: E402
from _web import chrome_binary  # noqa: E402

T = 0.5                 # pre-registered novelty threshold
T_STRIP = (0.4, 0.5, 0.6)  # diagnostic sensitivity strip (does NOT move the verdict)
DELAY_S = 2.0           # inter-request rate limit (politeness)
UA = "probe-runner-derisk/1.0"
MAX_FRONTIER = 40       # hard safety cap on one-hop fetches per site

# 4 seed routes per site (NG cohort). MPA + SPA mix.
COHORT = {
    "python.org": [
        "https://www.python.org/",
        "https://www.python.org/about/",
        "https://www.python.org/downloads/",
        "https://www.python.org/community/",
    ],
    "djangoproject.com": [
        "https://www.djangoproject.com/",
        "https://www.djangoproject.com/start/",
        "https://www.djangoproject.com/download/",
        "https://www.djangoproject.com/community/",
    ],
    "mui.com": [
        "https://mui.com/",
        "https://mui.com/core/",
        "https://mui.com/pricing/",
        "https://mui.com/blog/",
    ],
    "vercel.com": [
        "https://vercel.com/",
        "https://vercel.com/products/dev",
        "https://vercel.com/pricing",
        "https://vercel.com/templates",
    ],
}


def _launch(udd):
    """Headless Chrome on a blank page (so there IS a page target -- see cdp-capture-needs-open-tab).
    Returns (proc, port)."""
    bin_ = chrome_binary()
    if not bin_:
        print("FATAL no-chrome"); sys.exit(2)
    p = subprocess.Popen(
        [bin_, "--headless=new", "--remote-debugging-port=0", "--remote-allow-origins=*",
         "--no-first-run", "--no-default-browser-check", "--hide-scrollbars",
         "--window-size=1440,900", f"--user-data-dir={udd}", "about:blank"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    pf = Path(udd) / "DevToolsActivePort"
    for _ in range(100):
        if pf.exists():
            t = pf.read_text().splitlines()
            if t:
                return p, int(t[0])
        time.sleep(0.1)
    p.terminate(); print("FATAL no-port"); sys.exit(2)


def _capture_nodes(url, port):
    """Drive web_skeleton.py against the launched Chrome; return its RAW node-list
    (pre-redaction, href intact) or None on failure. Scratch lives in a tempdir OUTSIDE
    any audited tree and is discarded."""
    with tempfile.TemporaryDirectory() as scratch:
        sk = Path(scratch) / "sk.json"
        r = subprocess.run(
            [sys.executable, "web_skeleton.py", "--url", url, "--cdp-port", str(port),
             "--out", str(sk)],
            cwd=str(SCRIPTS), capture_output=True, text=True)
        if r.returncode != 0 or not sk.exists():
            return None
        return json.loads(sk.read_text())["nodes"]


def _robots(origin):
    rp = urllib.robotparser.RobotFileParser()
    rp.set_url(origin + "/robots.txt")
    try:
        rp.read()
    except Exception:
        return rp  # fail-open is unsafe; treat unreadable robots as allow-all only for this manual de-risk
    return rp


def _origin(url):
    p = urlparse(url)
    return f"{p.scheme}://{p.netloc}"


def run_site(site, seed_urls):
    print(f"\n=== {site} ===")
    udd_root = tempfile.mkdtemp()
    proc, port = _launch(udd_root)
    try:
        seed_nodes = []
        for u in seed_urls:
            n = _capture_nodes(u, port)
            if n is None:
                print(f"  seed capture FAILED: route#{seed_urls.index(u)}"); continue
            seed_nodes.append(n)
            time.sleep(DELAY_S)
        if len(seed_nodes) < 2:
            print("  ABORT: <2 seed routes captured"); return None
        seed_fps = [cy.content_fingerprint(n) for n in seed_nodes]

        # --- discrimination control (runs FIRST) ---
        m = cy.discrimination_matrix(seed_fps)
        offdiag = [m[i][j] for i in range(len(m)) for j in range(len(m)) if i != j]
        spread = max(offdiag) - min(offdiag) if offdiag else 0.0
        print(f"  discrimination off-diagonal jaccard: min={min(offdiag):.3f} "
              f"max={max(offdiag):.3f} spread={spread:.3f}")
        if spread < 0.10:
            print("  ABORT: fingerprint does not discriminate seed templates (vacuous signal)")
            return None

        # --- one-hop frontier ---
        frontier = cy.frontier_urls(seed_nodes, seed_urls)[:MAX_FRONTIER]
        print(f"  frontier targets (content, un-enumerated, one-hop): {len(frontier)}")
        rp = _robots(_origin(seed_urls[0]))
        frontier_fps = []
        for norm, href in frontier:
            if not rp.can_fetch(UA, href):
                continue
            n = _capture_nodes(href, port)
            time.sleep(DELAY_S)
            if n is None:
                continue
            frontier_fps.append(cy.content_fingerprint(n))

        novel = cy.count_novel_templates(frontier_fps, seed_fps, T)
        strip = {t: cy.count_novel_templates(frontier_fps, seed_fps, t) for t in T_STRIP}
        print(f"  fetched fingerprints: {len(frontier_fps)}")
        print(f"  NOVEL templates @ T={T}: {novel}")
        print(f"  sensitivity strip {strip}  (diagnostic only)")
        return novel
    finally:
        proc.terminate()


def main():
    print(f"§C9-R-CRAWL yield de-risk | T={T} | bar: >=2 novel on >=2/4 sites")
    results = {}
    for site, urls in COHORT.items():
        results[site] = run_site(site, urls)
    cleared = [s for s, v in results.items() if v is not None and v >= 2]
    print(f"\n=== VERDICT === sites clearing >=2 novel: {len(cleared)}/4 -> {cleared}")
    print("BUILD" if len(cleared) >= 2 else "DEFER")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Verify it imports clean and pytest does NOT collect it**

Run: `cd scripts && python3 -c "import importlib.util, sys; spec=importlib.util.spec_from_file_location('d','derisk_crawl_yield.py'); m=importlib.util.module_from_spec(spec); sys.argv=['d']; spec.loader.exec_module" 2>&1 | head; python3 -m pytest --co -q 2>&1 | grep -c derisk_crawl_yield`
Expected: import line errors only if a dependency is missing (acceptable — it is a live harness); the `grep -c` prints `0` (pytest does NOT collect `derisk_crawl_yield.py`).

- [ ] **Step 3: Confirm the full pure suite is still green**

Run: `cd scripts && python3 -m pytest -q`
Expected: PASS, same total as end of Task 4 (the harness adds no collected tests).

- [ ] **Step 4: Commit**

```bash
git add scripts/derisk_crawl_yield.py
git commit -m "feat: §C9-R-CRAWL manual yield de-risk harness (non-collected; robots+rate-limit; URL-transient)"
```

---

### Task 6: Run the gate against the live cohort and record the verdict

**Files:**
- Modify: `docs/plans/probe-runner-engine-capture-gaps.md`

This is the **manual de-risk execution**, not code. It needs a live Chrome and runs ~minutes/site. Per `[[derisk-must-record-capture-regime]]`, record the regime (headless, 1440×900).

- [ ] **Step 1: Run the harness**

Run: `cd scripts && python3 derisk_crawl_yield.py`
Expected: per-site discrimination line + NOVEL count, then a final `VERDICT` line printing `BUILD` or `DEFER`. Capture the full stdout.

- [ ] **Step 2: Append the results section**

Append to `docs/plans/probe-runner-engine-capture-gaps.md` a `## §C9-R-CRAWL — Results: crawl-discovery yield de-risk (<date>)` section recording: the bar (verbatim from spec), the capture regime (headless 1440×900), the per-site discrimination spread + novel counts + sensitivity strip, the aggregate (`N/4` sites cleared), and the VERDICT (BUILD or DEFER). If any site aborted on the discrimination control, say so explicitly.

- [ ] **Step 3: Repoint the roadmap footer**

In the latest roadmap-status footer of `probe-runner-engine-capture-gaps.md`, move "crawl-discovery site map" from "not started" to either "BUILD-justified §C9-R-CRAWL" or "DEFERRED §C9-R-CRAWL (measured: <one-line evidence>)".

- [ ] **Step 4: Commit**

```bash
git add docs/plans/probe-runner-engine-capture-gaps.md
git commit -m "docs: record §C9-R-CRAWL yield de-risk verdict (<BUILD|DEFER>) + repoint roadmap footer"
```

- [ ] **Step 5: Next cycle**

- If **DEFER**: the measured evidence is the deliverable; web-CDP axis stays at its honest ceiling. Write/refresh a memory note capturing the finding.
- If **BUILD**: open a fresh `superpowers:brainstorming` → spec → plan cycle for the crawler proper (BFS frontier, template-saturation stop with K-consecutive-misses, robots, rate-limit, `site_capture` wiring). The Q2/Q4 answers in this session become its params.

---

## Self-Review

**1. Spec coverage:**
- §1 bar (≥2 novel on ≥2/4) → Task 6 verdict logic + `count_novel_templates` (Task 4). ✓
- §2 harness steps (capture / content-anchor frontier / one-hop fetch / fingerprint / novelty) → Tasks 2,3,4 (pure) + Task 5 (`_capture_nodes`, `run_site`). ✓
- §3 T=0.5 pinned + sensitivity strip + discrimination control-aborts-first → `T`, `T_STRIP`, `discrimination_matrix` + the `spread < 0.10` abort in `run_site`. ✓
- §4 cohort (4 sites, 4 seed routes, MPA+SPA) → `COHORT`. ✓
- §5 firewall (URL transient, no href persisted, non-collected) → harness prints counts only; `derisk_` name + Task 5 Step 2 collection check. ✓
- §6 verdict recording → Task 6. ✓

**2. Placeholder scan:** No TBD/TODO; every code step shows complete code; every run step has an expected result. The only date placeholder (`<date>`) in Task 6 is a runtime value (stamped when run), not a plan gap.

**3. Type consistency:** `content_fingerprint`→`Counter`; `bag_jaccard(Counter,Counter)→float`; `frontier_urls`→`[(str,str)]`; `count_novel_templates(list[Counter],list[Counter],float)→int`; `discrimination_matrix(list[Counter])→list[list[float]]`. Harness uses each with matching types: `seed_fps`/`frontier_fps` are `list[Counter]`, fed to `count_novel_templates`/`discrimination_matrix`; `frontier_urls` unpacked as `(norm, href)`. Consistent. ✓

**Note on `_robots` fail-open:** if `robots.txt` is unreadable the harness treats it as allow-all (an empty `RobotFileParser` returns `can_fetch → True`). Acceptable for a 4-site manual de-risk with a 2s rate limit; a production crawler (the gated BUILD) must decide fail-open vs fail-closed deliberately.
