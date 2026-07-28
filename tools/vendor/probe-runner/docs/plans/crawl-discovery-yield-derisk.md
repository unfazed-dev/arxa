# Crawl-discovery yield de-risk (§C9-R-CRAWL)

**Status:** SPEC — pre-registered, not yet run. Date: 2026-06-03; **revised 2026-06-04 (still pre-data)**.
**Decision being de-risked:** whether to BUILD a crawl-discovery route-expander, or DEFER it.
**Sibling discipline:** `pseudo-element-geometry-derisk.md`, `form-state-validity-family-derisk.md`.
Memory: `[[falsify-detection-signal-on-real-neg-controls-before-code]]`,
`[[validate-real-artifact-not-keys-proxy]]`, `[[derisk-must-record-capture-regime]]`,
`[[g2-static-flag-anticorrelated-defer]]` (measure-before-spec),
`[[subagent-review-code-vs-spec-not-just-plan]]` (the 2026-06-04 revision below).

> **2026-06-04 pre-data revision** (no data collected yet — these TIGHTEN the test, removing sources of
> *false* novelty, so they make BUILD strictly harder, not easier; licensed by
> `[[subagent-review-code-vs-spec-not-just-plan]]`). A holistic cross-file review found three paths that
> would push the verdict toward a **false BUILD**: (C1) the frontier was not restricted to same-origin, so
> external hosts — near-guaranteed structurally novel — would inflate the count; (C2) degenerate captures
> (404 / consent wall / JS-blank) produce tiny fingerprints that score novel against rich seeds; (I3) a
> site running on <4 valid seeds had no baseline for some templates → false novelty. The fixes — pinned
> here before any run — are the **same-origin host-set rule (§2)**, the **min-node validity floor F (§2/§3)**,
> and the **conclusive-site denominator rule (§1)**.

---

## Background — why a gate, not a build

§C9-R-NG (`probe-runner-engine-capture-gaps.md:2149`) shipped nav-link → `route_id` annotation
*within* the user-supplied `--urls` set, and measured that the **content-level** cross-link graph is
**sparse by construction** (~0.5 resolved content-edges per route; the content site map is empty because
users pick `--urls` = the nav destinations, so nav links resolve circularly while content cross-links
point to un-enumerated pages and drop as external). NG explicitly scoped crawl-discovery OUT: a real
content map needs following links to pages the user did NOT enumerate, and **discovered URLs are content**
— they collide with the content-free firewall (ADR-0001).

The selected deliverable is a **route-set expander** (not a URL sitemap, not a topology graph): crawl to
DISCOVER pages the user didn't list, feed them into the existing content-free multi-route capture, ship
**more per-route skeletons + extended `nav_edges`**. URLs are used transiently to fetch and are **never
written to disk**.

The only thing route-expansion can add over the status quo is **new content STRUCTURE** — chrome is
already deduped (G3d `_chrome_dedup`), tokens already merged across routes (G3b). NG's sparse-content-link
finding directly predicts the yield may be ~0. G2 / G3c / G4 / validity were all DEFERRED after de-risk.
Therefore: **measure the yield behind a pre-registered bar before building anything.**

---

## §1 — Objective & pre-registered bar

**Question:** does one-hop crawl-discovery surface content templates that are structurally novel relative
to the user-enumerated seed routes (i.e. NOT already represented by a captured route)?

**Pre-registered bar (pinned BEFORE any data — not bendable):**

A site is **CONCLUSIVE** iff (a) all 4 seed routes captured as **valid** (each ≥ floor F content-region
nodes, §3) AND (b) it passes the discrimination control (intra-seed spread ≥ 0.10, §3). A conclusive site
**CLEARS** iff it yields **≥2 distinct content-templates novel-vs-seed** (T=0.5, §3).

> **BUILD** iff **≥2 conclusive sites CLEAR.**

- **≥2 conclusive sites clear → BUILD.** Open a separate brainstorm → spec for the crawler proper (BFS
  frontier, template-saturation stop with K-consecutive-misses, robots.txt, rate-limit, `site_capture`
  pipeline wiring — the Q2/Q4 answers below become its params).
- **≥2 conclusive sites exist but <2 clear → DEFER** with measured evidence, exactly as NG / validity
  recorded their DEFERs.
- **<2 conclusive sites exist → INCONCLUSIVE** (not BUILD, not DEFER): a site that fails 4/4-valid or the
  discrimination control is excluded from BOTH the numerator and the denominator (an unpinned denominator
  is itself a verdict-integrity hole — advisor 2026-06-04). The de-risk does not render a verdict; expand
  / repair the cohort (fix the failing captures, or add diverse sites) and re-run. Record the inconclusive
  outcome honestly; do NOT round it to DEFER.

**Reopen criteria (if DEFER):** a real site population where one-hop **same-origin** content links routinely
reach un-enumerated pages carrying a valid (≥F) content-region shape not present in the seed set, clearing
the bar above.

---

## §2 — Harness

`scripts/derisk_crawl_yield.py` — **non-collected** (manual headless, not a pytest; mirrors
`scripts/derisk_pseudo_geometry.py`). Reuses, does not reimplement:

| Need | Reused module | Content-free guarantee |
|------|---------------|------------------------|
| per-node fingerprint | `_shape_key._node_key` | volatile/positional fields excluded by construction (`_shape_key.py:7`) |
| chrome vs content split | `_nav.classify_chrome` + `_chrome_dedup.CHROME` | landmark-role based |
| same-origin URL resolution | `_nav.normalize_url`, `_nav.build_route_map` | **NEVER emits an href** (`_nav.py:1,43`) |
| headless skeleton capture | `web_skeleton` / `site_capture` | existing content-free pipeline |

**Steps:**

1. Headless-capture each **seed route** skeleton (the routes a user would naturally enumerate per site).
   A seed is **valid** only if its content-region fingerprint has **≥ F nodes** (floor, §3); a sub-floor
   seed is a degenerate capture and makes the site INCONCLUSIVE (§1), it is not silently dropped.
2. From each seed route, extract **content anchors only** (`classify_chrome` → non-chrome). Keep an anchor
   as a frontier target iff (a) its **parsed host equals a seed host** (www-stripped, lowercased — a
   set-membership test on the *host alone*, NOT a prefix-match on the glued `host+path` norm, which would
   admit `python.org.evil.com`), AND (b) its normalized URL is NOT already in the seed set. Same-origin is
   the core of the NG finding (content links to OTHER same-site pages); cross-host links are external and
   **must be dropped** — and their count **logged** (§5). The kept set = the **one-hop frontier** (NG
   predicts it is small, ~0.5/route).
3. One-hop fetch + headless-capture each frontier target. **Rate-limited** (fixed inter-request delay);
   **robots.txt honored per target origin** (fetched/cached once per host — frontier is same-origin, so
   this is the seed host's robots; honoring it is the politeness contract for the site being crawled).
4. Compute the **content-region fingerprint** for every seed route AND every frontier target:
   the multiset of `_node_key` over **non-chrome** nodes (chrome excluded via `classify_chrome`). A
   frontier capture is **valid** only if its fingerprint has **≥ F nodes**; sub-floor frontier captures
   (404 / consent / blank) are **dropped before novelty scoring** and their count **logged** (§5) — they
   never count as novel.
5. A **valid** frontier target is **NOVEL** iff its best **bag-Jaccard** similarity to ALL seed-route content
   fingerprints is `< T`. Bag-Jaccard over the two `_node_key` multisets = `Σ min(count_a, count_b) /
   Σ max(count_a, count_b)` (repetition is structurally meaningful — N identical list items is a real
   template signal, so multiset, not set). Count novel templates per site (dedup novel targets against
   each other by the same bag-Jaccard ≥ T rule, so two identical-template novel pages count as ONE).

---

## §3 — T pinning, min-node floor, discrimination control

**T = 0.5**, pinned before data (best-match Jaccard ≥ 0.5 ⇒ "same template"). The VERDICT uses T=0.5
ONLY. Novel counts at T ∈ {0.4, 0.5, 0.6} are printed as a **diagnostic sensitivity strip** so a
knife-edge result is visible — they do not move the bar.

**Min-node validity floor F = 20** (content-region nodes; i.e. `Σ` fingerprint multiset counts ≥ 20),
pinned before data. Applies to **BOTH seeds and frontier targets**. Rationale: a real content template
has dozens-to-hundreds of non-chrome nodes; a capture below 20 content nodes is a **degenerate page** —
a 404, a consent/anti-bot interstitial, or a JS-blank shell — not a representative template. Without the
floor such a capture produces a near-empty fingerprint that scores `bag_jaccard ≈ 0` against rich seeds
and is counted as **novel**, and two distinct degenerate pages would clear the per-site bar on garbage
(the C2 false-BUILD path). A sub-floor **seed** → that seed is invalid → the site cannot reach 4/4 valid
→ INCONCLUSIVE (§1). A sub-floor **frontier** capture → dropped before scoring, logged (§5).

**Discrimination control (runs and is checked FIRST, per
`[[falsify-detection-signal-on-real-neg-controls-before-code]]`):** print the intra-seed Jaccard matrix.
The fingerprint must score known-**different** seed templates LOW and known-**same** templates HIGH. If
the fingerprint cannot separate same-vs-different templates among the seed routes, novelty counts are
meaningless → **the de-risk aborts before the verdict** (the signal is vacuous). This is the
neg-control that prevents declaring a yield off an instrument that can't discriminate.

---

## §4 — Cohort

4 diverse sites, reusing NG's seed `--urls` sets (so seed route sets already exist and are characterized).
**4 seed routes per site** (NG's cohort size, `probe-runner-engine-capture-gaps.md:2152`):

- **MPA:** `python.org`, `djangoproject.com`
- **SPA:** `mui.com`, `vercel.com`

Record the capture regime (headed/headless, viewport) per `[[derisk-must-record-capture-regime]]` — a
favorable single draw is not a verdict.

---

## §5 — Firewall

- URLs are used **transiently to fetch only**; `_nav` never emits an href (`_nav.py:43`).
- The sole persisted artifact is the **verdict**: novel-template counts + Jaccard similarity stats +
  the discrimination matrix + the **drop ledger** (counts only). **No URLs, no hrefs, no content.**
- **No silent caps** (own discipline): the harness logs, per site, the count of frontier targets dropped
  as **cross-origin**, dropped **sub-floor**, and **capture-failed** — so a low novel count is
  distinguishable from over-filtering. Counts only, never the dropped URLs.
- Harness is **non-collected** → never runs in CI, never variance-fishes a green draw.

---

## §6 — Verdict & recording

Append a `## §C9-R-CRAWL — Results: crawl-discovery yield de-risk` section to
`docs/plans/probe-runner-engine-capture-gaps.md` recording the outcome — **BUILD / DEFER / INCONCLUSIVE**
(§1) — plus the per-site numbers (valid-seed count, discrimination spread, novel count, drop ledger), the
sensitivity strip, and the capture regime. Update the roadmap-status footer accordingly (BUILD-justified /
DEFERRED-with-evidence / INCONCLUSIVE-pending-re-run). An INCONCLUSIVE result is NOT rounded to DEFER.

- **If BUILD:** the finding unlocks a fresh brainstorm → spec → plan cycle for the crawler proper. The
  already-decided build params carry forward: route-set expander deliverable; same-origin BFS frontier;
  **template-saturation stop** (loop-until-dry on structural novelty + hard max-page cap); similarity-
  threshold novelty on the content-region fingerprint; **respect robots.txt + rate-limit + opt-in
  `--crawl` flag** (off by default, like `--sweep`).
- **If DEFER:** the measured evidence IS the deliverable; the web-CDP axis stays at its honest ceiling.
