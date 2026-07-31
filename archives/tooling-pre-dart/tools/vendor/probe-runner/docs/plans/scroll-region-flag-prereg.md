# Scroll-Region Flag — Pre-Registration (the static reframe of G2)

**Status:** **DEFER** — pre-registered, then REFUTED on real data at build-step-1 falsification (BEFORE
any code), 2026-06-03. See "Falsification result" at the bottom. Reframe of the DEFERRED G2 sweep-merge
(`docs/plans/g2-virtualization-build.md`; ship-test DEFER §C9-R-G2). Date: 2026-06-03.
**The prescribed retry (sharpened composed-item ∧ homogeneity discriminator + broader cohort) was attempted
2026-06-03 and ALSO DEFERRED — §C9-R-G2b: composed-by-role is defeated by the sparse role vocab, and the
only surviving separator (homogeneity) is ANTI-CORRELATED with the target (highest on static uniform
catalogs with no below-fold gap, lowest on real feeds). Root cause: a single static snapshot cannot observe
a dynamic below-fold property. The static reframe is closed on both attempts.**

## Why this reframe

The G2 sweep tried to **enumerate** below-fold shapes by scrolling. It DEFERRED because the count is
regime-fragile: the demo gave `new_shapes=17`/`repro_delta=0.452` headless vs the de-risk's `27`/`0.0`
(regime undocumented). The engine was proven faithful — the *gain itself* is unstable load-to-load, and
windowed feeds (Reddit) recover instances, not new structure (memory `g2-virtualization-append-vs-windowed`).

**Reframe:** stop counting below-fold contents. Instead emit ONE stable, content-free structural fact —
*"this node is a scroll/feed region"* — derived from the SINGLE REST snapshot we already capture. The
container exists at load and its identity does not depend on scroll depth/timing → the variance that
DEFERRED G2 cannot arise.

**Honest fidelity trade (not a free win):** a region flag is COARSER than the sweep's goal. YouTube's
de-risk found 51 *distinct* below-fold shape-keys — real heterogeneity, not one template. A flag collapses
that to "feed region + item template," losing the fine tail. For a content-free *structural* skeleton this
stable-coarse beats noisy-fine — but it is a deliberate trade, recorded, NOT "G2 revived."

## Verification of record (the decisive static-vs-eval question — ANSWERED)

`DOMSnapshot.captureSnapshot(includeDOMRects=True)` — the call the engine ALREADY makes — populates
per-node `scrollRects` AND `clientRects`. Live check (`/tmp/g2_scrollrects_probe.py`, headless `:9222`,
infinite-scroll demo, 2026-06-03):

```
LAYOUT KEYS: bounds, clientRects, offsetRects, paintOrders, scrollRects, stackingContexts, styles, text
scrollRects  present=True len=278 nonempty=117
clientRects  present=True len=278 nonempty=117
OVERFLOW node: scrollH=2907 clientH=469 ratio=6.2   (correctly = the scroll region)
```

So per-element `scrollHeight`/`clientHeight` is **already in the captured bytes** — `parse_snapshot`
(`web_skeleton.py:270`) reads only `layout["bounds"]` and DISCARDS `scrollRects`/`clientRects`. Detection
needs NO new capture, NO JS eval, NO sweep. `overflow-x`/`overflow-y` are also already in `WANT_STYLES`
(`web_skeleton.py:48`). **Fully static & deterministic.**

## Signal (LOCKED)

`parse_snapshot` is extended to carry, per node, `scroll_h`/`client_h` from `scrollRects`/`clientRects`
(CSS px, ÷dpr like bounds). A pure classifier then flags a node as a scroll-region iff ALL hold:

1. **Scrollable:** `overflow-y ∈ {auto, scroll}` (computed style, already captured) OR the node is the
   document scroller (root).
2. **Has overflow content:** `scroll_h > 1.5 · client_h` (from the already-captured rects).
3. **Repeated children (the FEED discriminator):** among the node's direct children, ≥ `M=3` share one
   identical content-free shape-key (`_shape_key._node_key`). This separates a feed/list from a merely
   tall article (heterogeneous children → not flagged). **`M=3` is LOCKED** (≥3 identical siblings = a list;
   2 could be a nav pair / hero duo). If the negative control (cond 2) false-positives at `M=3`, that is a
   DEFER finding ("signal not specific") — NOT a license to raise `M` until wikipedia passes (post-hoc tuning).

Emit a sparse content-free field on the qualifying node (like `substrate`/`aria_role` — present only where
it applies, absent elsewhere):

```
"scroll_region": {"repeated": true, "item_key": "<the repeated child's _node_key>"}
```

`item_key` is a content-free shape-key string. NOTE `_node_key` includes `text_len` (an INTEGER character
count — mechanism, not content) and excludes bbox/id/parent/z by construction; the firewall canary (cond 3)
must exercise the `scroll_region.item_key` path SPECIFICALLY (verify, don't assume the G2 below_fold canary
covers it). NO counts, NO bbox, NO content. The item template's full shape is already in `nodes[]` (the
mounted child).

## Pre-registered accept bar (LOCKED — do not tune post-hoc)

The feature SHIPS (as a normal additive skeleton field) iff ALL hold on the produced on-disk skeleton:

1. **Detection — positive:** flags the scroll/feed region on 2 PRE-NAMED in-class sites, BOTH LOCKED now:
   (i) `infinite-scroll.com/demo/full-page/` (document scroller) AND (ii) **`reddit.com/r/popular`** — the
   de-risk's own real-world WINDOWED feed (S2) — proving both the root-scroller and nested/windowed cases.
   The flagged node's `item_key` matches a shape recurring ≥3× among its children. If (ii)'s recorded snapshot
   does not carry the signal, that is a recorded sensitivity DEFER finding — NOT a license to swap in a
   friendlier site (the selection bias the DEFERRED G2 spent two turns avoiding).
2. **Detection — negative control (discrimination):** a tall static article (`wikipedia/Cat`) is NOT flagged
   as a feed region — it may be scrollable (signal 1+2) but FAILS signal 3 (heterogeneous children, no
   ≥3-repeat shape). `scroll_region` absent on every wikipedia node. (Distinguishes feed from long prose —
   the exact false-positive the `scrollH≫clientH`-alone signal would hit.)
3. **Content-free:** `content_firewall.audit_bundle == 0` on the produced bundle including the new field;
   a seeded `url(https://…)`/text value injected SPECIFICALLY into a `scroll_region.item_key` value (the new
   field's own path, NOT a generic node field) trips the audit (canary) — proving the new field is gated, not exempt.
4. **Deterministic / regime-free:** the classifier is a pure function of the captured snapshot — re-running
   it on the SAME captured snapshot yields byte-identical output. Because it reads load-time rects (no
   scroll), cross-load `repro` is structural, not a sampled count. Proven on recorded real-snapshot fixtures
   (NO live sweep) — the variance that DEFERRED G2 is structurally absent.
5. **Cost:** zero new capture (`scrollRects`/`clientRects` already requested via `includeDOMRects`); the only
   added work is reading two rects already in the payload + one pure children-grouping pass.

## Scope cuts (explicit — do NOT re-import variance)

- **Append-vs-windowed sub-classification is OUT.** Distinguishing append (DOM grows on scroll) from windowed
  (recycles a fixed pool) needs a mounted-count-under-scroll signal = a live probe = the regime/variance risk
  that DEFERRED G2. This pre-reg ships only the stable `repeated` flag. A sub-class is a SEPARATE future
  pre-reg with its own repro bar, if ever pursued.
- **No instance count.** `scroll_region` carries no child tally (same reason `repeat_count` was dropped from
  the G2 build — a count's cross-load reproducibility was never de-risked).
- **Fidelity:** this does NOT recover the 51 distinct below-fold shapes the sweep targeted. Recorded trade.

## DEFER conditions (record finding, do not ship) if:

- Negative control fails — wikipedia (or another long article) gets flagged as a feed region ⇒ the
  repeated-child discriminator is too weak (false positives) ⇒ "signal not specific."
- Positive detection misses a real nested-feed container that is visibly a virtualized list ⇒ "signal not
  sensitive" — record which signal (overflow / rect-ratio / repeat threshold) failed.

## Build shape (if bar pursued)

Mostly DETERMINISTIC, fixture-based (honors `validate-real-artifact-not-keys-proxy` WITHOUT live variance):
1. **First (cheap, falsification BEFORE code):** cross-check the signal against the de-risk's
   ALREADY-RECORDED youtube/reddit/demo snapshots (`research/capture-gap-probes/out/`, if retained) — does a
   node in reddit's (windowed) recorded snapshot satisfy signals 1+2+3? If NOT, the sensitivity concern is
   real before any code is written — record it. If not retained, re-capture the 3 bar sites ONCE → fixtures
   (real bytes).
2. Extend `parse_snapshot` to carry `scroll_h`/`client_h` (additive; keeps the parallel-index contract).
3. Pure `scroll_region` classifier in a new module + unit tests proving bar conditions 1–5 on the fixtures.
4. Firewall canary (condition 3) like the G2 below_fold canary.
5. One tiny live smoke (manual harness) re-confirming detection on the demo — NOT a pytest (per
   `live-cdp-capture-is-manual-harness-not-pytest`).
6. Record SHIP/DEFER in §C9-R-G2b with real fixture numbers.

## Falsification result — DEFER (signal not specific; zero confirmed real-world positive) (2026-06-03)

Build-step-1 falsification (`/tmp/g2_sr_falsify.py`, headless `:9222`, one static DOM read per site, a
COARSE child signature as `_node_key` proxy) ran the candidate signal on all 3 LOCKED bar sites BEFORE any
code. Result REFUTES the signal as pre-registered:

| site | overflow node | ratio | repeated descendants | signal fires | verdict |
|---|---|---|---|---|---|
| demo (infinite-scroll) | HTML root | 6.2 | grand_maxgroup **11** | **True** | sensitive (but items are NESTED, not direct children) |
| `reddit/r/popular` (windowed) | — | — | — | **False** (no overflow candidate at all) | untested headless |
| `wikipedia/Cat` (NEG) | HTML root | 94.5 | grand_maxgroup **13** | **True** | **FALSE POSITIVE — bar cond 2 fails** |

**DEFER, two locked-bar conditions broken:**
1. **Negative control FALSE-POSITIVES (concept failure, not a threshold miss).** Wikipedia loaded fully
   (ratio 94.5, 13 *real* repeated `<p>`/reference rows) and the signal fires CORRECTLY per its own
   definition — "scrollable + ≥3 repeated descendants" describes ANY long structured document, not just a
   feed. Repetition is everywhere in structured HTML. Raising `M` or adding ad-hoc filters now would be
   post-hoc tuning against the locked neg-control — forbidden. This is a signal-DESIGN refutation.
2. **Zero confirmed real-world positive.** Only the SYNTHETIC demo fired; `reddit` (the one locked
   real-world feed) returned no overflow candidate headless — record as **untested headless** (likely a
   login/bot block, or a document-scroller / dynamic-height virtualization that defeats the load-time
   `scrollH>1.5·clientH` read). Do NOT chase it or bank it either way. This is the SAME real-world
   thinness (synthetic demo + one flaky real site) that DEFERRED the G2 sweep — not a fresh problem.

**What SURVIVES (reusable):** the static-rects insight is correct and stands — `scrollRects`/`clientRects`
(hence per-element `scrollHeight`) ARE in the captured snapshot and discarded; a future scrollable/overflow
signal needs no live capture. The failure is specificity of the *feed* discriminator, not the data path.

**A real retry would need a FRESH pre-reg (do not tune this one):** designed BEFORE seeing more data, with
(a) a stronger feed-vs-document discriminator candidate — e.g. homogeneity fraction `maxgroup/total_children`
(a feed is ~homogeneous; an article is heterogeneous), repeated-item SIZE (cards vs text lines), or
bounded-vs-unbounded scroll growth; AND (b) **multiple** negative controls (long article, docs page, search
results) and **multiple** real feeds (not demo+1) — closing the demo+1-real-site thinness that has now
DEFERRED two G2 attempts. Not pursued here.
