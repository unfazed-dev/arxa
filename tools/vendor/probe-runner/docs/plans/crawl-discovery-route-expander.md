# Crawl-discovery route-expander (§C9-R-CRAWL-BUILD)

**Status:** SPEC — design approved 2026-06-04, not yet planned/built.
**Builds:** the §C9-R-CRAWL **BUILD** verdict (`crawl-discovery-yield-derisk.md`,
`probe-runner-engine-capture-gaps.md:2320`). The yield gate proved one-hop same-origin escape
surfaces novel content templates (python 2 / django 10 / mui 5 / vercel 10, repro-confirmed).
**Sibling:** `crawl-discovery-yield-derisk.md` (the gate this ships).
Memory: `[[nav-graph-shipped-as-nav-annotation]]`, `[[subagent-review-code-vs-spec-not-just-plan]]`,
`[[derisk-must-record-capture-regime]]`, `[[validate-real-artifact-not-keys-proxy]]`.

---

## §0 — Scope, locked to the evidence boundary

The de-risk gate validated **one-hop** escape **only**. This build ships **exactly that** — no
extrapolation:

- **One-hop expander.** From the seed `--urls`, follow same-origin content links **one hop**, capture
  the pages that add new structure, extend `nav_edges`. No multi-hop BFS, no recursion.
- **No saturation stop / no control loop.** Because depth is one-hop, the novelty threshold `T` is **not**
  a stop signal — it only filters and dedups a bounded, pre-enumerated frontier. (Multi-hop BFS — where
  `T` would define "novel" → "dry" → the stop condition — is explicitly OUT; it is not de-risked.)
- **Capture policy: novel + deduped.** Capture a discovered page iff its content-region fingerprint is
  **novel vs every seed** AND **not a duplicate of an already-kept** discovered template. Ship one
  representative per template. Rationale (§C9-R-CRAWL background): route-expansion's only added value is
  **new content structure** — chrome is already deduped (G3d), tokens already merged across routes (G3b);
  near-seed-duplicate pages add no structure.

**Why this equals the measured yield.** The per-page `accept` predicate (§2) is algorithmically identical
to the gate's `count_novel_templates` (novel-vs-seed `max bag_jaccard < T`, then dedup-vs-kept
`all bag_jaccard < T`) — streamed per page instead of batch-counted. Expected ship output therefore equals
the measured yield. Step-4 edge resolution (§1) is **zero-fetch**, so the crawl stays genuinely one-hop.

---

## §1 — Architecture & data flow

### Module layout

- **`scripts/_crawl.py` (NEW — pure, no I/O, no network, CI-testable).** Ship-path selection:
  - `cap_frontier(frontier, max_pages) -> (capped, n_over_cap)`
  - `reject_reason(fp, seed_fps, kept_fps, T, floor) -> None | "subfloor"|"not_novel"|"dup"` — the
    single-source-of-truth per-page decision (§2). `accept(...) -> bool` wraps it (`reject_reason(...) is
    None`). Stateful per-page decision kept pure: the caller threads `kept_fps`. The orchestrator calls
    `reject_reason` to attribute each drop to the ledger (§5).
  - `frontier_targets(seed_node_lists, seed_urls) -> ([(norm, href, src_idx)], n_cross_origin)` — like
    `frontier_urls` but also records the **first seed index** a norm was discovered from (the `via`
    provenance, §4). `frontier_urls` becomes a thin wrapper that drops `src_idx`, so its behavior and the
    13 de-risk tests are unchanged.
  - **Hosts the 5 general primitives** relocated from `_crawl_yield.py`: `bag_jaccard`,
    `content_fingerprint`, `_host`, `frontier_urls`, `passes_floor`.
- **`scripts/_crawl_yield.py` (MODIFIED).** The de-risk harness core keeps only `count_novel_templates`
  and `discrimination_matrix`; it **imports the 5 primitives back from `_crawl`**. This fixes the
  dependency direction — **ship code must not depend on a de-risk harness**. The 13 existing
  `test_crawl_yield.py` tests are behavior tests; imports redirect and they MUST stay green (a build gate).
- **`scripts/site_capture.py` (MODIFIED).** Thin fetch shell. Adds the `--crawl` path; owns
  network / rate-limit / robots / IO. Captures nothing itself (every page-derived byte still comes from
  the already-gated `web_*`/`bundle_writer` tools).

### Data flow when `--crawl` is on

1. **Seed capture** (existing path). When `--crawl`, `capture_route` ALSO returns the raw node-list it
   already reads in-memory for edge resolution — handed back, **never written to disk**.
2. `seed_fps = [content_fingerprint(n) for n in seed_node_lists]`;
   `frontier, n_cross = frontier_urls(seed_node_lists, seed_urls)`;
   `frontier, n_over = cap_frontier(frontier, crawl_max)`.
3. **Per frontier page** (rate-limited, robots-checked) — skeleton-first to save the polite budget:
   - fetch **skeleton only** (`web_skeleton` → in-memory raw nodes) → `fp = content_fingerprint(nodes)`.
   - `accept(fp, seed_fps, kept_fps, T, F)`?
     - **reject** (subfloor / not-novel / dup-of-kept): drop the scratch, **NO tokens fetch**, bump the
       matching drop counter, continue.
     - **accept**: capture the page via the **untouched `capture_route`** (re-fetches skeleton + fetches
       tokens, builds the bundle into a real `rNN` route dir, returns its raw nodes); append `fp` to
       `kept_fps`; record `via` = the seed route_id the link came from.
4. **Edge resolution** for ALL captured routes (seed + discovered) against the **final combined**
   route_map (seeds + discovered) — enriches `nav_edges` with **zero extra fetches** (still one-hop).
5. **Backstop:** the existing `content_firewall.audit_bundle` re-runs over the whole site tree. Unchanged.

**Fetch cost.** Rejected pages cost **1** request (selection skeleton only). Accepted pages re-capture
through the unmodified `capture_route` → 1 (selection) + 2 (skeleton + tokens) = **3** requests. The
re-fetch is a deliberate tradeoff: it keeps `capture_route` — the network boundary the existing suite does
**not** unit-test in CI — **byte-for-byte unchanged**, so the proven default path and the e2e nav tests carry
zero regression risk. The extra request lands only on accepted (novel, minority) pages, is rate-limited, and
hits a page just fetched (cached). All bounded by `--crawl-max`. (Reusing the selection skeleton for the
bundle — splitting `capture_route` to let the scratch survive the `accept` decision — is a later
optimization, OUT of scope for this first ship.)

---

## §2 — Selection (`_crawl.reject_reason` / `accept`)

`reject_reason` is the single source of truth; `accept` is a thin wrapper. The orchestrator calls
`reject_reason` so it can attribute each drop to the ledger (§5) — a single bool could not.

```
reject_reason(fp, seed_fps, kept_fps, T, floor) -> None | str:
    if not passes_floor(fp, floor):                                   return "subfloor"   # degenerate
    if max((bag_jaccard(fp, s) for s in seed_fps), default=0.0) >= T: return "not_novel"  # a seed template
    if any(bag_jaccard(fp, k) >= T for k in kept_fps):               return "dup"        # dup of one kept
    return None                                                                          # -> capture

accept(fp, seed_fps, kept_fps, T, floor) -> bool:
    return reject_reason(fp, seed_fps, kept_fps, T, floor) is None
```

- `bag_jaccard` = multiset `Σmin/Σmax` over `_node_key` Counters (repetition is structural signal).
- `content_fingerprint` = Counter of `_node_key` over NON-chrome nodes (`_nav.classify_chrome`).
- Default `T = 0.5`, `floor F = 20` (both de-risk repro-confirmed; §3).

---

## §3 — Parameters / CLI

New flags on `site_capture.py`, all opt-in, mirroring `--sweep`:

| Flag | Default | Meaning |
|------|---------|---------|
| `--crawl` | off | Enable one-hop discovery. Off by default. |
| `--crawl-max N` | **40** | Cap on frontier pages **attempted** (skeleton fetches). Over-cap dropped + counted. Matches the de-risk `MAX_FRONTIER`. |
| `--crawl-threshold T` | **0.5** | Novelty/dedup threshold. De-risk repro-confirmed value. |
| `--crawl-delay S` | **2.0** | Inter-fetch rate-limit (politeness). |

- **Robots:** honored per-origin (fetched/cached once per host). UA `probe-runner/1.0`. Note: Chrome's
  actual fetch UA differs from the robots-check UA — standard practice (you declare your crawler's name);
  documented, not hidden.
- **Robots unreadable → fail-CLOSED** (skip the origin). Stricter than the de-risk's fail-open, because
  this ships.

**T-anchoring (the first-class spec question) — resolved by the depth choice.** One-hop + novel-deduped
takes `T` out of any control loop: a mis-set `T` only over/under-includes pages **within the cap** —
bounded, non-recursive, never a stop signal. So T-anchoring is **downgraded from a blocking prerequisite
to a documented knob**: default 0.5 (repro-confirmed), exposed as `--crawl-threshold`. No separate
calibration gate is required for this (one-hop) build. Multi-hop BFS — where `T` WOULD be load-bearing —
is out of scope and would require a T-anchoring de-risk first.

---

## §4 — Firewall (load-bearing)

ADR-0001 treats **captured page content** as content. Two URL classes:

- **Seed URLs** = user input (not discovered). Existing `site.json` rows persist `"url"`. Unchanged.
- **Discovered URLs** = extracted from captured DOM hrefs → **content**. NEVER persisted or printed.

**Discovered route rows carry NO `url` field:**
```
{route_id, bundle, ok, node_count, discovered: true, via: <src seed route_id>}
```
`via` is a route_id (content-free provenance), not a URL. `nav_edges` stay content-free
(`src`/`dst` route_id + `src_node` + `chrome`). The transient `norm -> rNN` map used to build edges lives
**in-memory only** and is discarded after the run.

Guards:
- `frontier_urls` returns hrefs ONLY for transient fetch (contract preserved verbatim from `_crawl_yield`
  into `_crawl`).
- `audit_bundle` re-runs over the whole tree (incl. `site.json`) — catches any accidental URL leak, fails
  loud.
- **Spec invariant + test:** no discovered row has a `url` key, AND `site.json` contains no discovered-href
  substring. Per `[[validate-real-artifact-not-keys-proxy]]`, assert on the real written `site.json` bytes,
  not a proxy.

---

## §5 — Error handling, drop ledger, edge cases

- Per-page capture failure → rmtree scratch, count `failed`, continue. One bad page never aborts the run
  (existing isolation pattern).
- **Drop ledger (counts only, never URLs):** `cross_origin / over_cap / subfloor / not_novel / dup /
  robots_blocked / failed`. **No silent caps** — every bounded/dropped category is logged so a low yield is
  distinguishable from over-filtering.
- **Zero-novel yield is a VALID graceful no-op**, not an error: the ledger reads all `not_novel`/`dup`, the
  run succeeds, and the site tree is exactly the seed capture. (A site whose one-hop links are all
  seed-templated legitimately expands by zero.)

---

## §6 — Testing

Pure core fully unit-tested offline (CI-safe):

- **`_crawl.py`** (`scripts/test_crawl.py`):
  - `cap_frontier`: under-cap (unchanged, n_over=0), over-cap (truncated, n_over correct), empty.
  - `accept`: floor reject; not-novel reject (≥T to a seed); dup-of-kept reject (≥T to a kept fp);
    accept (novel + distinct); **no-seeds → novel vacuously True**; kept-set statefulness (same fp accepted
    first, rejected second).
  - relocated-primitive smoke (imported into `_crawl`) — and the **13 existing `test_crawl_yield.py` tests
    stay green** (import redirect) as a gate.
- **`site_capture.py`** (`--crawl` integration, capture **stubbed**, no network):
  - discovered rows have **no `url`** key; `via` provenance present.
  - `nav_edges` resolve against the **combined** route_map (a discovered→seed and a seed→discovered edge).
  - drop-ledger counts correct for a mixed frontier (one novel, one dup, one subfloor, one cross-origin).
  - firewall `audit_bundle` clean; `site.json` carries no discovered href.
- **Non-collected live harness** (`scripts/derisk_*`-style, NOT a pytest): manual real-site smoke on the
  §C9-R-CRAWL cohort, prints counts only — for human de-risk before declaring the feature validated, never
  in CI (`[[live-cdp-capture-is-manual-harness-not-pytest]]`).

---

## §7 — Recorded caveats (carried from the gate; do NOT re-engineer)

1. **T only partially audited (caveat 1, §C9-R-CRAWL).** The discrimination control validated *spread* but
   never anchored the same-template HIGH side. `T=0.5` is a pre-guess the data only partially audits.
   Mitigated here because depth made `T` non-load-bearing (§3); exposed as a knob.
2. **Order-dependent dedup under non-transitive similarity.** The shared novel+dedup metric can yield a
   kept-count that depends on fetch order when `A~B, B~C, A≁C` (`~` = bag_jaccard ≥ T). Inherited from the
   de-risk metric; **deterministic in practice** (fixed `frontier_urls` iteration order) but latent. Record;
   do NOT re-engineer the metric.

---

## §8 — Out of scope (explicit)

- Multi-hop / unbounded BFS, template-saturation stop (`T` load-bearing → needs a T-anchoring de-risk first).
- Persisting any discovered URL, sitemap, or content-level topology.
- Cross-origin discovery (same-origin host-set gate only).
