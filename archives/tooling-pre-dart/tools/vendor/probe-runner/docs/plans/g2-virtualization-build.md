# G2 virtualization — BUILD pre-registration (ship bar locked BEFORE engine code)

> **For agentic workers:** This LOCKS the ship-acceptance bar for the scroll-sweep + merge engine
> BEFORE any engine code is written — same discipline as the de-risk pre-reg (no post-hoc tuning).
> It is NOT yet a TDD task plan. The implementation plan (bite-sized TDD tasks via
> `superpowers:writing-plans` → `subagent-driven-development`) is produced ONLY after this bar is
> approved. If the bar is not met during implementation, G2 DEFERs with the specific finding recorded
> in `docs/plans/probe-runner-engine-capture-gaps.md` §C9-R-G2 — the engine does not ship.

**Goal:** Ship a content-free engine that recovers below-fold structure a single REST `DOMSnapshot`
misses on APPEND-class virtualized pages, by a bounded scroll-settle **sweep** + a **merge** that adds
the new structure to the skeleton — *realized faithful-skeleton gain NET of merge cost*, never raw node
count, never per-instance content.

**Status:** BAR PRE-REGISTERED (2026-06-02). **NO ENGINE CODE WRITTEN YET.** Awaiting approval of this
locked bar before the implementation plan is authored.

**Premise (CITED, not re-derived):** the de-risk PASSED its locked bar — `docs/plans/g2-virtualization-derisk.md`
(2 in-class pass-sites: youtube home `new_shape_frac 0.34`/`new_shapes 51`/`repro 0.137`; infinite-scroll
demo `0.474`/`27`/`0.0`; Reddit excluded on `repro 0.60`; neg control discriminates `0.009`; firewall 0).
Verdict `§C9-R-G2`. The de-risk measured the gain on a per-step **shape-key UNION** (`probe_g3d_dedup._node_key`)
— exactly the basis this BUILD must ship. **Real-world stability is thin** (de-risk "Gate re-validation"
section): only the controlled Metafizzy demo passes cleanly+repeatably; youtube home is consent-flaky;
organic feeds (Reddit) fail reproducibility. The BUILD therefore SCOPES those out-of-contract (below) —
it does not pretend to cover them.

---

## What ships (design — the artifact, fixed before the bar)

The engine adds an **opt-in** capture mode; the default stays the single REST snapshot (unchanged
contract). When `--sweep` is set AND the page is G2-in-class (`scrollHeight > innerHeight`):

1. **REST snapshot** — the existing `web_skeleton._snapshot_skeleton` positioned skeleton (above-fold,
   full `bbox`). Unchanged.
2. **Bounded scroll-settle sweep** — `K = 8` steps, `0 → min(scrollHeight, K*innerH)`, re-reading
   `scrollHeight` each step (it grows); per step `_set_scroll` + node-count-stable settle (the
   `_read_settled` convergence pattern adapted to DOM-node-count), then a DOMSnapshot → skeleton records.
3. **Merge** → the emitted skeleton = REST nodes (positioned, unchanged) **+ a `below_fold` addendum**:
   the **SET of distinct content-free shape-keys** present across the sweep but ABSENT from REST — one
   record per distinct new shape, carrying its shape fields only (`sizing.{w,h}` etc. are already in the
   key, content-free). **No per-shape instance count is shipped** (see the contract note below).

**What the addendum does NOT contain (the content-free contract):**
- **No per-instance `bbox.y`** — position is volatile under scroll and cannot be a faithful identity.
- **No per-instance nodes for already-seen shapes** — a feed of 50 identical items collapses to ONE
  shape record (distinguishing item #5 from #50 needs their text = firewall violation; a content-free
  engine dedups instances anyway — cf. G3d).
- **No per-shape `repeat_count` / instance tally** — DELIBERATELY OMITTED. The de-risk's reproducibility
  gate (`repro_delta ≤ 0.20`) measured **`new_shapes`** = the cardinality of the distinct-shape SET ONLY;
  it never measured per-shape instance counts. Feed instance tallies vary load-to-load — the *same*
  variance that failed Reddit — so a `repeat_count` field would ship a value whose cross-load stability
  is UN-de-risked, reintroducing the locked-bar-pass-vs-real-stability conflation one level down. A count
  signal (raw / bucketed / boolean `repeats`) is a **SEPARATE future de-risk** with its own pre-registered
  reproducibility bar — NOT shipped by this BUILD.
- **No text, src, href, or any `CONTENT_KEYS`** — `redact_node` + `audit_bundle` apply to the addendum
  exactly as to every other artifact.

So the BUILD's below-fold contribution is honest and strictly on the de-risked basis: *"these N new
distinct shapes (structure/role/sizing/token_ref/font/text_len-bucket) exist below the fold"* — a SET, no
counts, no order. The maximal faithful claim a content-free engine can make about virtualized content
that the de-risk actually validated as reproducible.

## The two problems the de-risk SIDESTEPPED — confronted here (not assumed solved)

The de-risk explicitly deferred these to BUILD; they do NOT ride in as solved.

**1. Cross-snapshot node identity under scroll-shift.**
A per-step union must answer "is this node NEW vs what I've seen?" across snapshots whose absolute
`bbox.y` shifts with scroll. **Resolution:** identity is decided ONLY by the bbox-free **shape-key**
(`_node_key`, which already excludes `id/parent/bbox/z/sizing.confidence`). The engine performs a
**set-union over shape-keys**, NOT per-instance matching. It does not attempt to identify "which item is
which" — that problem is *declined*, not pretended-solved. Consequence accepted honestly: the engine
cannot report below-fold layout/order or instance counts, only **shape presence** (set membership) —
which is exactly what the de-risk validated as reproducible.

**2. Merge cost.**
The sweep adds K snapshots + settle waits; the merge adds compute + artifact bytes. **Resolution:** the
ship bar (below) requires the realized gain to clear a floor AND the cost to be bounded — runtime within
a pre-registered budget over REST-only, and artifact growth proportional to `new_shapes` (NOT raw node
count: if the addendum grew with raw nodes, the shape-dedup isn't actually happening).

## PRE-REGISTERED SHIP BAR (locked — no post-hoc tuning)

The engine SHIPS iff **ALL** of the following hold on the produced, on-disk artifact (not a probe):

1. **Realized gain (not just measured):** on the 2 reproducible in-class pass-sites — the Metafizzy
   infinite-scroll demo AND a YouTube **`/watch`** URL (the non-consent-gated deep link, NOT the home
   feed) — the emitted skeleton's `below_fold` addendum carries **`new_shapes ≥ 25`** distinct shapes
   ABSENT from the same run's REST-only skeleton. The de-risk's measured gain must survive into the
   shipped bytes. (A consent-locked YouTube **home** at ship-test is a TEST-ENVIRONMENT skip — out-of-class
   `sh==ih` → REST-only by condition 6 — NOT a bar failure, since the lockout is no fault of the engine.)
2. **Content-free identity is honest:** the addendum stores **only** the distinct shape-key fields
   (which already include `sizing.{w,h}`) — **no `bbox.y`, no instance count, no per-instance duplication
   of seen shapes, no `CONTENT_KEYS`**.
   `content_firewall.audit_bundle(bundle)` **== 0** across the FULL produced bundle including the addendum,
   on every pass-site AND on a deliberately-seeded canary (a `url(https://…)`/text value injected into a
   below-fold shape MUST trip the audit — proving the addendum is gated, not exempt).
3. **Deterministic / idempotent merge:** `merge(rest, sweep_snapshots)` is a pure function of its inputs;
   re-merging the same captured snapshot set yields **byte-identical** output (stable shape ordering, no
   set-iteration nondeterminism). Verified deterministically with fixtures — NO live capture needed.
4. **Cost bounded:** sweep+merge runtime ≤ a pre-registered budget over REST-only capture (`≤ K` settle
   intervals, `K=8`, documented per-step max-wait), AND addendum byte-size grows with `new_shapes`, not
   with `sweep_peak_nodes` (assert `addendum_nodes == new_shapes`, i.e. one record per distinct new shape).
5. **Negative control unchanged:** on a static fully-rendered page (`wikipedia/Cat`), the merged skeleton
   ≈ REST skeleton — `new_shapes < 0.10 * rest_shapes`. The sweep must not fabricate structure.
6. **Default contract untouched:** without `--sweep`, `web_skeleton`/`site_capture` output is
   byte-identical to today; the full existing unit suite (497) stays green; `--sweep` on an out-of-class
   page (`sh <= ih`, G7a / consent-locked) falls back to REST-only and logs the exclusion.

**The engine DEFERS (does not ship; record the finding) if:**
- Realized gain collapses — the addendum does NOT carry the de-risked `new_shapes` (e.g. the merge
  dedups them away or the shape-key parity with the probe breaks). ⇒ "measured gain not realizable."
- The merge is non-idempotent (condition 3 fails). ⇒ "no stable shippable contract."
- Cost is disproportionate (condition 4 fails). ⇒ "gain not NET-positive."
- Firewall trips on the addendum or the canary does NOT trip (condition 2 fails). ⇒ content-leak / unguarded field.

## Out-of-contract scope (honest labeling, NOT silent gaps)

- **Wrapper-virtualized (G7a, `sh <= ih` forever):** out of class; `--sweep` falls back to REST-only,
  logged. Separate deferred rung.
- **Consent-locked homes (`sh == ih` under the pre-consent basis):** the default path does not dismiss
  overlays (`_consent` is `web_states`-only). A consent-locked page is out-of-class at capture time →
  REST-only + logged. Realizing G2 on consent-gated feed homes is gated on G6 consent being wired first
  (memory `g2-virtualization-append-vs-windowed`).
- **Organic high-variance feeds (Reddit-class, `repro_delta > 0.20`):** the sweep is non-deterministic
  load-to-load; the engine still emits the addendum but it carries NO per-load reproducibility claim — it
  is labeled `sweep-discovered` (best-effort), and such sites are NOT counted toward the ship bar's
  pass-sites. The de-risk already established which classes are reproducible; the BUILD ships the
  mechanism and labels honestly rather than overclaiming a stable contract.

## Implementation surface (files / functions — for the later TDD plan)

- **New pure core `scripts/_sweep.py`:**
  - `merge_skeletons(rest_sk, sweep_sks) -> merged_sk` — the load-bearing PURE function (no I/O, no CDP):
    set-union over shape-keys, emits `below_fold` addendum (distinct new shapes only — NO instance
    count). Fully unit-testable from fixtures; this is where conditions 1/3/4/5 are proven deterministically.
  - Own the shape-key in `scripts/` (lift `_node_key` + `_KEY_FIELDS` out of `research/probe_g3d_dedup.py`
    into a shipped module, e.g. `scripts/_shape_key.py`, and have BOTH the probe and `_sweep` import it —
    parity is then guaranteed, not coincidental).
- **`scripts/web_skeleton.py`:** add opt-in `--sweep` (default OFF). When set + in-class, run the
  scroll-settle sweep (reusing `web_anim._set_scroll`/`_wait_scrollable`/`_read_settled`) and call
  `_sweep.merge_skeletons`; else unchanged `_snapshot_skeleton`.
- **`scripts/bundle_writer.py`:** surface the `below_fold` addendum into `skeleton.json` as an additive
  key (precedent: `substrate`/`states`); `audit_bundle` already covers it (content-based).
- **`scripts/site_capture.py`:** forward `--sweep` to each per-route `web_skeleton` subprocess.
- **Tests:** `scripts/test_sweep.py` — pure `merge_skeletons` fixtures (union/count/no-bbox.y/idempotence/
  canary-trips/neg-control). Live leg = extend the manual harness `scripts/livesmoke_web_capture.py`
  (or a `livesmoke_g2.py`) — manual, not pytest (same slow/shared-Chrome reasons as the consolidation
  live-smoke; memory `live-cdp-capture-is-manual-harness-not-pytest`).

## Acceptance measurement (how each locked condition is checked)

| Cond | Check | Live CDP? |
|---|---|---|
| 1 realized gain | manual harness on 2 pass-sites: `new_shapes(addendum) ≥ 25` vs same-run REST | yes (manual) |
| 2 content-free | `audit_bundle == 0` on produced bundle + a fixture canary that MUST trip | no (canary fixture) + yes (live bundle) |
| 3 idempotent | fixture: `merge(...) == merge(...)` byte-identical | no |
| 4 cost | runtime delta logged ≤ budget; `addendum_nodes == new_shapes` (fixture + live) | partial |
| 5 neg control | wikipedia: `new_shapes < 0.10*rest_shapes` | yes (manual) |
| 6 default contract | suite 497 green; no-`--sweep` byte-identical; out-of-class → REST+log | no |

Conditions 2(canary)/3/4(size)/5(logic)/6 are **deterministic** (fixtures + suite) — the bulk of the bar
is provable WITHOUT the flaky live path. Only conditions 1 and 5's live legs need real CDP, via the
manual harness.

## Provenance / reuse
- De-risk pass + thinness: `docs/plans/g2-virtualization-derisk.md` (Gate re-validation section);
  verdict `docs/plans/probe-runner-engine-capture-gaps.md` §C9-R-G2.
- Snapshot/skeleton: `web_skeleton.py:_snapshot_skeleton` / `to_skeleton` / node schema `:564`.
- Scroll-settle: `web_anim.py:_set_scroll` / `_wait_scrollable` / `_read_settled`.
- Shape-key: `research/capture-gap-probes/probe_g3d_dedup.py:_node_key` (+ `_KEY_FIELDS`) — to be lifted
  into `scripts/`.
- Firewall: `scripts/content_firewall.py:audit_bundle` (content-based; covers new fields by construction).
- Per-route flow + opt-in forwarding: `scripts/site_capture.py:capture_route`.
- Manual live-smoke precedent + one-clean-tab prereq: `scripts/livesmoke_web_capture.py`; memories
  `live-cdp-capture-is-manual-harness-not-pytest`, `cdp-capture-needs-open-tab`.

## Next step
Approve / adjust this locked bar → THEN author the TDD implementation plan
(`superpowers:writing-plans`) and execute via `subagent-driven-development`. Do NOT write engine code
before the bar is approved (pre-registration discipline).
