# G2 virtualization — DE-RISK pre-registration (bar locked BEFORE data)

> **For agentic workers:** This is a DE-RISK rung, not a BUILD. Step 1 is a measurement probe
> against a pre-registered bar. No scroll-sweep/merge engine is built here. If the bar passes, a
> separately-specified BUILD follows; if it fails, G2 DEFERs with the honest reason recorded in
> `docs/plans/probe-runner-engine-capture-gaps.md`.

**Goal:** Decide whether a bounded scroll-settle sweep recovers materially more *content-free
structure* than the engine's single REST DOMSnapshot, on virtualized-class sites — and whether that
gain is capturable on a content-free identity basis. Pure measurement.

**Status:** BAR PRE-REGISTERED (2026-06-02) → **CAPTURED: BUILD-JUSTIFIED** (2/2 in-class pass-sites:
youtube home + append demo; neg discriminates; firewall-clean), scoped to APPEND-class virtualization.
The append-class gap is robust across 3 runs (youtube 51–76 new shapes, demo 27); the live
discriminator is cross-load **reproducibility** — the Reddit feed fails it (repro 0.60; live feeds vary
load-to-load), and youtube.com home is intermittently consent-locked (`sh==ih`) under the default
pre-consent basis. Results in `research/capture-gap-probes/out/g2_virt.json`; verdict recorded in
`docs/plans/probe-runner-engine-capture-gaps.md` §C9-R-G2. **Gate re-validated 2026-06-02 against the
recorded data — locked bar MET, but the "≥2 *stable real-world*" reading is thinner than "2/2 in-class";
see the Gate re-validation section at the end.**

---

## Premise (CITED, not re-derived)

The engine takes ONE `DOMSnapshot.captureSnapshot` after forcing REST (`web_skeleton.py:_REST_JS`
scrolls to 0). DOMSnapshot captures the **full current DOM**, not the viewport — so a tall page that
renders everything is captured whole (`kasane rendered its whole long page`; awwwards sweep
`virt_delta=0` on all 7, incl. Razorpay 22117px — §C3/§B). Therefore any node growth observed on
scroll is **real lazy mounting**, not snapshot clipping. The open gap (§B #2, MAJOR): feed /
infinite-scroll apps (YouTube: comments + most recommendations absent until scrolled, `+6766 nodes`)
mount content below the fold that the single REST snapshot never sees.

## G2-vs-G7a boundary (decides site-class — fixed FIRST)

`web_anim.py:_wait_scrollable` already splits the two:
- **G2 (this rung):** natively scrollable, `scrollHeight > innerHeight`, content lazy-mounts as the
  document scrolls. In-class sites must satisfy `sh > ih` at REST or grow to it.
- **G7a (separate, deferred):** wrapper-virtualized — `sh <= ih forever`; a fixed-height inner
  container scrolls internally, document never grows. OUT of scope here.

Site-class gate: a candidate site counts as G2-in-class only if `sh > ih` (natively scrollable). Log
and EXCLUDE any wrapper-virtualized (`sh <= ih`) candidate — it's a G7a case, not evidence here.

## The crux: content-free cross-snapshot IDENTITY (de-risked directly, not deferred to BUILD)

A per-step union needs to answer "is this node NEW vs what I've already seen?" across snapshots whose
absolute `bbox.y` shifts with scroll. Two facts make raw instance-identity un-content-free:
1. `bbox.y` moves under scroll, so it cannot be in the key.
2. Without position, a virtualized feed is *by construction* a list of structurally-identical items
   (50 comments → one content-free shape). Distinguishing item #5 from item #50 requires their text —
   a firewall violation. So **counting individual recovered items is not content-free-measurable, and
   a content-free engine should dedup identical shapes anyway** (cf. G3d).

**Resolution (on-basis with what a content-free BUILD would ship):** measure recovery on the project's
existing content-free **shape-key** — the structural key already used by the cross-route dedup work
(`research/capture-gap-probes/probe_g3d_dedup.py:_node_key` over `_KEY_FIELDS`, positional fields
dropped). The honest question becomes:

> Does the scroll sweep reveal distinct content-free **shapes** (structure/role/sizing/token_ref/
> text_len-bucket) that are ABSENT from the REST snapshot — i.e. genuinely new below-fold *structure*,
> not just more instances of already-seen structure?

This is exactly what a content-free skeleton could faithfully add (new shapes + repeat counts), and it
sidesteps the unsolvable "identify each identical item" problem by not pretending to solve it.

## Metrics (per site)

Reusing `_node_key` (content-free shape-key; positional `id/parent/z/confidence/bbox` dropped):

- `rest_nodes` — raw node count at REST (the naive "+6766" framing's denominator).
- `rest_shapes` — `|{shape_key(n) : n in REST}|`.
- `sweep_peak_nodes` — max raw node count at any single sweep step (append-virtualization signal).
- `union_shapes` — `|{shape_key(n) : n in (REST ∪ all sweep steps)}|`.
- **`new_shapes = union_shapes − rest_shapes`** — the load-bearing number: distinct content-free
  structure the sweep adds that REST missed.
- `new_shape_frac = new_shapes / rest_shapes`.
- Reproducibility: re-run the bounded sweep once; record `new_shapes_rerun` and
  `repro_delta = |new_shapes − new_shapes_rerun| / max(1, new_shapes)`.
- Firewall: every per-step skeleton through `content_firewall.audit_bundle` → must be 0 violations.

Report BOTH `new_shapes` (content-free-honest) AND `sweep_peak_nodes / rest_nodes` (the raw growth, for
contrast/honesty) — never let the raw number stand alone.

## PRE-REGISTERED BAR (locked — no post-hoc tuning)

Bar shape: **existence-proof for capturability + reproducibility gate + negative-control discrimination.**
Rationale: with a windowed/recycling-heavy class, a prevalence-on-peak bar would false-DEFER (advisor),
so the bar is on the union-basis `new_shapes` and needs only a strong existence proof to justify
building the union engine.

**G2 de-risk PASSES (BUILD justified) iff ALL of:**
1. **Real new structure (union basis):** on ≥2 G2-in-class sites, `new_shape_frac ≥ 0.30` AND
   `new_shapes ≥ 25` (absolute floor so we don't pass on key-split noise).
2. **Reproducible:** on each passing site, `repro_delta ≤ 0.20` (a fixed-step sweep recovers a stable
   structure set → an honest shippable contract exists).
3. **Metric discriminates:** the static-render negative control (full-page, non-virtualized) shows
   `new_shape_frac < 0.10` — proving `new_shapes` measures mounting, not snapshot jitter.
4. **Content-free:** 0 firewall violations across all per-step skeletons.

**G2 DEFERS (with the specific finding recorded) if:**
- `new_shapes ≈ 0` even where raw `sweep_peak_nodes` grows large ⇒ the sweep only multiplies
  already-seen shapes; a content-free engine gains nothing faithful ⇒ **content-free identity verdict:
  no new structure recoverable** (the real blocker, named). OR
- non-reproducible (`repro_delta > 0.20`) ⇒ no honest fixed-step contract. OR
- gain appears only as raw node count with `new_shapes` collapsing ⇒ scope note: append-instances
  only, not new structure.

The BUILD bar (sweep-merge engine: realized faithful-skeleton gain net of merge cost) is a SEPARATE
pre-registration if this passes — it does not carry over.

## Sites (PRE-REGISTERED + fallbacks; log every load outcome, NO silent drops)

In-class (virtualized): pick the first that loads per slot; log skips.
- **S1 YouTube** — `https://www.youtube.com` (home feed) — canonical append-virtualization, doc-cited.
  Fallback: a YouTube watch URL (comments + recommendations rail).
- **S2 Reddit** — `https://www.reddit.com/r/popular` — feed virtualization (windowed/recycling stress —
  the react-window-class case peak would miss). Fallback: `old.reddit.com` is NOT in-class (static) —
  skip if new Reddit won't load; substitute `https://news.ycombinator.com/news` is static (negative,
  not a substitute). True fallback: `https://nitter`-style public feed if reachable, else log S2 absent.
- **S3 Infinite-scroll demo** — `https://infinite-scroll.com/demo/full-page/` (Metafizzy, public, real
  page-append) — controlled positive, no login wall.

Negative control (must show `new_shape_frac < 0.10`):
- **N1** — `https://en.wikipedia.org/wiki/Cat` (long, fully server-rendered MPA; §A reference). Fallback:
  `https://en.wikipedia.org/wiki/Photosynthesis`.

Load-failure policy: any site that fails to load / times out / firewall-trips is LOGGED with the reason
and EXCLUDED; it does not silently shrink the cohort. A pass needs the absolute counts above met by
sites that actually loaded.

## Probe spec — `research/capture-gap-probes/probe_g2_virtualization.py`

Runs on HOST Bash (CDP :9222, `dangerouslyDisableSandbox`), like the other probes. Per site:
1. Navigate; `_wait_scrollable` to settle hydration + confirm `sh > ih` (else log G7a-exclude).
2. REST snapshot → skeleton records (reuse `web_skeleton` capture path / subprocess `--url`).
3. Bounded scroll-settle sweep: `K = 8` steps from 0 → `min(scrollHeight, K*innerH)` (re-read
   scrollHeight each step — it grows). At each step: `_set_scroll` + settle (scrollY converged AND
   DOM-node-count stable between consecutive reads, reusing the `_read_settled` convergence pattern
   adapted to node-count), then capture a DOMSnapshot → skeleton records.
4. Compute the metrics above (shape-key union via `probe_g3d_dedup._node_key`).
5. Re-run the sweep once for `repro_delta`.
6. `content_firewall.audit_bundle` every per-step skeleton; assert 0 violations.
7. Emit one JSON row per site; print a compact table + the pass/defer verdict against the bar.

De-risk ONLY: do not modify `web_skeleton.py`/`site_capture.py`; do not build the merge. Measure, then
record BUILD-justified or DEFER in the roadmap with the numbers.

## Provenance / reuse
- Snapshot: `web_skeleton.py:_snapshot_skeleton` / `_snapshot_recs`.
- Scroll-settle: `web_anim.py:_set_scroll` / `_wait_scrollable` / `_read_settled` (node-count-stable
  variant of the convergence gate).
- Shape-key: `research/capture-gap-probes/probe_g3d_dedup.py:_node_key` (+ `_KEY_FIELDS`).
- Firewall: `scripts/content_firewall.py:audit_bundle`.
- CDP: `scripts/_web.py` (`cdp_target`, `cdp_session`). Memory: CDP :9222 needs an open tab first
  (`cdp-capture-needs-open-tab`).

## Gate re-validation (2026-06-02) — locked bar MET; real-world stability is THIN

Re-checked the recorded `out/g2_virt.json` against the **locked** pre-registered bar above (no re-run —
re-running a pre-locked, met bar is post-hoc goalpost-moving + manufactured work). Recorded rows:

| site | class | in-class `sh>ih` | `new_shape_frac` ≥0.30 | `new_shapes` ≥25 | `repro_delta` ≤0.20 | firewall | verdict |
|---|---|---|---|---|---|---|---|
| S1 `youtube.com` (home) | virt | ✓ 4601>913 | 0.34 ✓ | 51 ✓ | 0.137 ✓ | 0 | **PASS** |
| S3 infinite-scroll demo (Metafizzy) | virt | ✓ 3420>913 | 0.474 ✓ | 27 ✓ | 0.0 ✓ | 0 | **PASS** |
| S2 `reddit.com/r/popular` | virt | ✓ 3014>913 | 0.709 | 90 | **0.60 ✗** | 0 | FAIL (repro) |
| N1 `wikipedia/Cat` (neg) | neg | — | 0.009 **<0.10 ✓** | 5 | 0.0 | 0 | discriminates |

**Verdict holds: 2 in-class pass-sites meet all four locked conditions → BUILD-JUSTIFIED stands.** Reddit
is correctly excluded (fails the reproducibility condition, not silently dropped); the neg control
discriminates; firewall is 0 across every per-step skeleton.

**Honest caveat — the locked-bar pass is NOT a real-world-stability claim (do not conflate):**
- `repro_delta` measures **within-capture** variance (sweep vs immediate re-sweep), NOT the
  consent-lockout failure mode. So the json's youtube-home PASS is **one favorable run**; the memory
  (`g2-virtualization-append-vs-windowed`) records youtube home as `sh==ih` consent-locked (out-of-class)
  in 2 of 3 runs. The json pass and the cross-run instability are **both true** — different claims.
- The only clean, repeatable **real** pass is the **Metafizzy infinite-scroll demo** — a *controlled
  positive* (deterministic, `repro_delta 0.0`), not a stress test of organic load-to-load variance.
- **Reddit** — the obvious organic 2nd feed — **fails** reproducibility (0.60; feeds vary load-to-load).
- ⇒ "≥2 *stable real-world* append sites" is **thin**: cleanly met only as the locked "≥2 *in-class*"
  bar. A real BUILD must scope **consent-lockout** and **organic-feed load-variance** as *out-of-contract*
  (no honest fixed-step sweep contract exists for them), not pretend they're covered.

**Data-of-record caveat:** `out/g2_virt.json` is gitignored/local-only (uncommitted). Its numbers
(youtube `new_shapes` 51, demo 27, reddit 90→36) cross-check exactly against the committed §C9-R-G2
verdict and the memory figures — consistent, so it is the genuine data behind the verdict, but it is not
itself in version control.

**Next rung is NOT another de-risk run — it is the SEPARATE BUILD pre-registration** the bar calls for
("does not carry over"). That pre-reg must confront the two problems this de-risk deliberately
*sidestepped*, which do NOT ride in as solved:
1. **Cross-snapshot node identity under scroll-shift** — `bbox.y` moves with scroll, so it can't be in
   the merge key; the de-risk measured a content-free *shape-key UNION* (which sidesteps per-item
   identity), but a shipping merge engine must decide node identity across snapshots for real.
2. **Merge cost** — realized faithful-skeleton gain must be NET of the sweep+merge runtime/complexity.
Plus: scope to APPEND-class only; document consent-flakiness + feed load-variance as out-of-contract.
