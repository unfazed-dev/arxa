# T-anchoring de-risk — anchor the same-template HIGH side (gate for multi-hop BFS)

**Section ID:** §C9-R-T-ANCHOR
**Status:** spec (de-risk gate, measurement-only — NOT a build)
**Date:** 2026-06-04
**Gates:** multi-hop BFS crawler (DEFERRED — T becomes the load-bearing saturation stop-signal there)

---

## §0 — Purpose & scope

§C9-R-CRAWL shipped the one-hop route-expander and recorded **caveat 1**: the crawl-yield
de-risk validated the discrimination *spread* (different-template seed pairs scored 0.015–0.472,
all < T=0.5) but **never anchored the HIGH side** the spec asked for ("same templates score
HIGH"). No known-same-template pair was ever measured. So **T=0.5 is a pre-guess the data only
partially audits.**

For the **shipped one-hop** expander this does not matter — the one-hop depth choice made T
non-load-bearing (it only over/under-includes within the max-page cap, never a stop signal).

For **multi-hop BFS** it matters fully: there T is the **saturation stop-signal** ("stop
expanding when newly discovered pages are all near-dupes of pages already seen"). A multi-hop
crawler with an unanchored T either over-crawls (T too high → never saturates) or stops early
(T too low → drops novel content). So multi-hop is BUILD-blocked until T is anchored.

**This de-risk emits a VERDICT ONLY.** It does not build anything. It answers: *does
bag-Jaccard on the content-region fingerprint cleanly separate same-template pages from
different-template pages, and is T=0.5 inside the separating band?*

- **In scope:** measure bag-Jaccard on URL-structurally-labeled same-template pairs (HIGH) vs.
  different-template pairs (LOW); apply a pre-registered bar; record verdict.
- **Out of scope:** building multi-hop BFS; changing the shipped one-hop expander; any new
  capture path. PASS/RE-ANCHOR → multi-hop becomes BUILD-justified (separate brainstorm). FAIL →
  multi-hop stays DEFERRED with recorded evidence.

---

## §1 — Ground-truth labeling (URL-structural, non-circular)

**The circularity trap (rejected):** the shipped crawler's `dup` reject flag is assigned *at
T=0.5* (a page is `dup` iff bag-Jaccard ≥ T against a kept page). Feeding dup-rejects back to
"validate" T=0.5 is tautological — it can describe, not anchor. **Do NOT use the dup flag as the
HIGH-side label.**

**The non-circular form (adopted):** label same-template pairs by **URL path-structure**, which
is independent of the bag-Jaccard `_node_key` multiset — so labeling and measurement cannot
contaminate each other. From the discovered same-origin frontier (transient in-memory URLs, as
in the existing de-risk harness), group into two confidence tiers:

- **Tier 1 — pagination (highest confidence; THE multi-hop saturation case).** URLs that differ
  only by a paging index on an otherwise-shared path: `/page/N`, `?page=N`, `/p/N`, a trailing
  numeric path segment on a shared prefix, `?p=N` / `&page=N` query forms. Near-certainly the
  same template, different content. **The verdict rides on this tier.**
- **Tier 2 — same-parent siblings (medium confidence; corroborative only).** Identical parent
  path, differing leaf segment (`/blog/foo` vs `/blog/bar`). Carries label noise (index-vs-detail
  under a shared parent), but being URL-derived it adds no circular bias. **Informs but cannot
  flip a Tier-1 verdict.**

The crawler's `dup`-rejected set is retained ONLY as a **descriptive cross-check** ("does the
live metric's dup decision agree with the structural label?") — never as the validating ground
truth.

---

## §2 — Measurement

Per **site**, per **tier**, enumerate all within-group page pairs and report the bag-Jaccard
distribution: **`min / median / max / n_pairs`**.

Three distributions:
- **HIGH-T1** — within-pagination-group similarity (saturation case).
- **HIGH-T2** — within-sibling-group similarity (corroborative).
- **LOW (primary, drives the bar)** — re-measured **seed-seed** pairs this draw. The seeds are
  hand-picked-distinct (different-template by construction — exactly what §C9-R-CRAWL measured at
  0.015–0.472), so they are the CLEAN "different template" ground truth, directly comparable to
  that reference.
- **LOW (secondary, reported only)** — across-different-template-group **frontier** pairs (same
  page population as HIGH, but carries grouping label-noise). Reported as a same-population
  cross-check; NOT in the pass arithmetic.

bag-Jaccard, `content_fingerprint`, the same-origin frontier discovery, robots gate, and the
F=20 content floor are reused unchanged from the shipped `_crawl` core / existing de-risk
harness. No new metric.

---

## §3 — Pre-registered bar (LOCKED before any number is seen)

Let **conclusive site** = a site yielding **≥3 Tier-1 pagination pairs** (the thin-sample floor;
§C9-R-CRAWL had ~2 dup pairs on python.org, ~1 on mui — too thin to anchor). Verdict requires
**≥2 conclusive sites**.

- **PASS — T=0.5 validated.** A clean gap exists with **0.5 inside the separating band**:
  `min(HIGH-T1 medians over conclusive sites) > 0.5` **AND** `max(LOW) < 0.5`, with no
  median-level overlap. Here `max(LOW)` is computed over the **re-measured seed-seed pairs from
  this draw** (the primary, clean LOW per §2/§8.3); the across-group frontier LOW and the
  §C9-R-CRAWL 0.015–0.472 reference are corroborating, NOT part of the pass arithmetic. Note the
  deliberate asymmetry — HIGH uses the **median** (must be robustly high) while LOW uses the
  **max** (must lie entirely below): a strict, no-bending bar. → Multi-hop becomes BUILD-justified
  at T=0.5.
- **RE-ANCHOR — T=X.** A clean separation exists (`max(LOW) < min(HIGH-T1 medians)`) but 0.5 is
  NOT strictly inside the gap (e.g. HIGH-T1 medians cluster ≥0.7 while LOW tops out at ~0.6 → the
  separating band (0.6, 0.7) lies entirely above 0.5). Recommend `T=X` = gap midpoint
  `(max(LOW) + min(HIGH-T1 medians)) / 2`. → Multi-hop becomes BUILD-justified at the re-anchored T.
- **FAIL — no separation at any T.** `max(LOW) ≥ min(HIGH-T1 medians)` over the conclusive
  sites (the cross-site aggregate — strictly stronger than any single per-site overlap, so it
  fails more readily: no bar-bending) → bag-Jaccard cannot reliably distinguish same-template
  from novel → the saturation stop-signal is unreliable. → Multi-hop stays **DEFERRED**; record
  that a different novelty signal is required (do NOT build one here).

Tier-2 (siblings) is corroborative only: noisier labels, so it informs interpretation but cannot
flip a PASS/FAIL that Tier-1 decides.

**No bar-bending:** any pre-data correction (e.g. tightening the conclusive floor, fixing a
grouping bug) must make the verdict STRICTER, never looser — per [[subagent-review-code-vs-spec-not-just-plan]].

---

## §4 — Cohort, regime, reproducibility

**Cohort:** reuse the §C9-R-CRAWL four (python.org, djangoproject.com, mui.com, vercel.com) so
the LOW reference is directly comparable. Pagination may be sparse on these (docs/marketing, not
feeds) — Phase 0 measures actual `n_pairs` first. If Tier-1 is thin across the cohort, **add 1–2
pagination-rich sites** (a blog/news/docs index with clear `/page/N`), selected for *structural
pagination presence*, NOT cherry-picked for a favorable score (record the selection reason).

**Regime (per [[derisk-must-record-capture-regime]]):** identical to §C9-R-CRAWL — headless
Chrome 1440×900, robots honored, 2s rate-limit, content floor F=20. Record headed-vs-headless
explicitly. **Single draw + one repro draw** — the gate must reproduce; a favorable single draw
does not count (the G2 single-draw fragility scar).

---

## §5 — Firewall (ADR-0001, content-free)

Non-collected de-risk harness, same contract as `derisk_crawl_yield.py`:
- Discovered / frontier URLs live **in-memory only** — never persisted, never printed.
- The URL-structural grouping (path templates, pagination patterns) happens transiently
  in-process; the patterns/paths themselves never enter logs.
- Output is **counts + bag-Jaccard scalars only** (`min/median/max/n_pairs`).
- No `site.json` or any bundle is written — measurement-only; nothing ships.
- `audit_bundle` is not invoked (nothing is captured to audit); the firewall guarantee is
  structural (no write path exists in the harness).

---

## §6 — Architecture & deliverables

**Pure core (CI-tested, offline):** a small module — provisionally `scripts/_url_template.py`
— holding the URL-structural logic:
- `paginate_key(url) -> (template, page_index | None)` — normalizes a URL to its pagination
  template + extracted index (None if no pagination form matches). Tier-1 grouping = equal
  `template` with differing `page_index`.
- `sibling_key(url) -> parent_path` — parent path for Tier-2 grouping.
- `group_by_template(urls) -> {tier1_groups, tier2_groups, ungrouped}` — pure, deterministic.
- `within_group_pairs(groups)` / `across_group_pairs(groups)` — pair enumerators.

Unit tests (`scripts/test_url_template.py`) feed **injected fake frontier URL lists** and assert
groupings/pairs — fully offline, no network, mirroring `_crawl_yield.py`'s test pattern. (Test
fixtures use synthetic example.test URLs only — never real content URLs.)

**Analysis core (CI-tested, offline):** `scripts/_t_anchor.py` — the stats + verdict logic,
separated from URL parsing (single responsibility):
- `summarize(values) -> (min, median, max, n) | None` — distribution of a list of bag-Jaccard
  scalars (None if empty).
- `verdict(per_site) -> (decision, t_reco)` — applies the §3 pre-registered bar to per-site
  `{high_t1_median, low_max, n_t1_pairs}` records: `decision ∈ {PASS, RE-ANCHOR, FAIL,
  INCONCLUSIVE}`, `t_reco` = 0.5 (PASS) / gap-midpoint (RE-ANCHOR) / None.
Unit tests (`scripts/test_t_anchor.py`) cover the PASS / RE-ANCHOR / FAIL / INCONCLUSIVE branches
+ the conclusive-site floor (≥3 Tier-1 pairs, ≥2 conclusive sites) with injected per-site stats.

**Live harness (non-collected):** extend `scripts/derisk_crawl_yield.py` (or a sibling
`derisk_t_anchor.py` that imports the same core) — discovers the frontier per regime, groups via
the pure core, measures bag-Jaccard per tier, prints the distribution table + counts. Non-collected
(skipped under pytest collection), like the existing live de-risk harness.

**Verdict record:** append `§C9-R-T-ANCHOR` to `docs/plans/probe-runner-engine-capture-gaps.md` —
the distribution table + the pre-registered verdict (PASS / RE-ANCHOR=T=X / FAIL), regime line,
and the multi-hop consequence. Update the roadmap footer.

---

## §7 — Staging (falsify-cheap first)

Per [[falsify-detection-signal-on-real-neg-controls-before-code]] — falsify on real pos+neg
before formalizing:

- **Phase 0 — falsify-cheap.** Extend the existing harness; measure `n_pairs` + the three
  distributions on the 4-site cohort (single draw). Two gate questions:
  1. **Separation visible?** Do Tier-1 pairs score clearly above the LOW spread (0.015–0.472)?
  2. **Tier-1 non-sparse?** Are there ≥3 pagination pairs on ≥2 sites?
  - No separation → **DEFER** (record FAIL evidence), stop — found for ~nothing.
  - Sparse → add pagination-rich site(s), re-read Phase 0.
- **Phase 1 — formalize (only if Phase 0 survives).** Repro draw (same regime), apply the §3
  pre-registered bar, write the §C9-R-T-ANCHOR verdict. Build the pure core + offline tests here
  (Phase 0 may prototype the grouper inline; Phase 1 hardens it into the tested module).

---

## §8 — Caveats carried forward

1. **Tier-2 label noise** — same-parent siblings can mix index-vs-detail templates; that's why
   Tier-2 is corroborative-only and the verdict rides on Tier-1 pagination.
2. **Pagination ≠ every same-template case** — pagination is the cleanest, highest-confidence,
   and most decision-relevant (it IS the saturation case) same-template signal, but a multi-hop
   crawler also re-encounters non-paginated same-template pages (e.g. many detail pages of one
   type). Tier-1 anchors the threshold; Tier-2 sanity-checks that it generalizes. A PASS means
   "T separates the clean case"; real multi-hop saturation on messier same-template families is a
   known residual the multi-hop spec must still treat carefully.
3. **Cohort drift** — live sites change between the §C9-R-CRAWL draw and this one; the LOW
   reference (0.015–0.472) is the recorded prior, re-measured LOW from this draw is the primary.
4. **Verdict is about the SIGNAL, not the crawler** — a FAIL defers multi-hop on the *bag-Jaccard
   saturation signal*; it does not condemn multi-hop in principle (a different novelty signal
   could revive it, out of scope here).

---

## §9 — Out of scope (explicit)

- Multi-hop BFS implementation (this de-risk gates it; does not build it).
- Any change to the shipped one-hop `--crawl` expander.
- A replacement novelty signal if bag-Jaccard FAILs (recorded as future work, not built).
- Persisting or shipping any discovered URL (firewall; §5).
