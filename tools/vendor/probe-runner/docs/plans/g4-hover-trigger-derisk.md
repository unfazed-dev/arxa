# G4 hover / non-ARIA trigger — DE-RISK pre-registration (bar locked BEFORE data)

> **For agentic workers:** This is a DE-RISK rung, not a BUILD. Step 1 is a measurement probe
> against a pre-registered bar. No `web_states` engine change is built here. If the bar passes, a
> separately-specified BUILD follows; if it fails, G4-hover DEFERs with the honest reason recorded in
> `docs/plans/probe-runner-engine-capture-gaps.md`.

**Goal:** Decide whether extending the G4 interaction-state trigger scan beyond explicit-ARIA — to
(a) **hover-revealed** menus and (b) **JS-custom, no-ARIA click** triggers — recovers materially more
*content-free revealed structure* than the current ARIA-click scan, on **real sites**, AND whether the
extra triggers are findable on a **content-free** basis with enough precision to ship. Pure measurement.

**Status:** BAR PRE-REGISTERED (2026-06-02) → **CAPTURED: DEFER** (0 of MIN_REAL_PASS_SITES=2 real
pass-sites). All 3 real sites read "ARIA-covered or empty": MDN already ARIA-covered (9 triggers / 472
appeared), Bootstrap already ARIA-covered (50 + 21 ARIA triggers, all caught by `_AFFORD_JS`), HN has no
interaction state at all. The two pre-registered crux risks BOTH fired: (a) **prevalence** (a11y adoption
put real triggers behind ARIA, which the existing scan already captures); (b) **content-free findability +
cost** (event delegation + href-nav defeat the precise per-node `getEventListeners` detector — ~1–4% of
non-ARIA `cursor:pointer` candidates have any direct listener — and the brute hover-all fallback found 0
new reveals on every real site AND did not scale: Bootstrap's 531 cursor:pointer candidates → 900s
timeout). Detectors fire on the fixture; negative control discriminates; firewall clean. Verdict +
numbers: `docs/plans/probe-runner-engine-capture-gaps.md` §C9-R-G4. Results: `out/g4_hover.json`.

---

## Premise (CITED, not re-derived)

`web_states.py` (G4, LANDED §C9-R) scans ONLY explicit-ARIA affordances —
`_AFFORD_JS` selector = `'[aria-haspopup],[aria-expanded],summary,[role=menu]'` — `classify_trigger`s
them, drives each with `el.click()` (`_CLICK_JS`), and diffs APPEARED nodes via `_states.diff_skeletons`
(content-free: role/bbox/z only; same-corner reflow excluded). §C9-R named the honest limit verbatim:

> Trigger scan is **explicit-affordance only**… Hover-only menus and JS-custom triggers with no ARIA are
> NOT scanned (follow-up: a hover/Input-dispatch path + heuristic affordance detection).

Two classes are therefore invisible to the current engine:
1. **Hover-only menus** — desktop nav dropdowns revealed by CSS `:hover` / a JS `mouseenter` listener,
   with no `aria-haspopup`/`aria-expanded`. `el.click()` does nothing for the CSS case.
2. **JS-custom no-ARIA click triggers** — `<div onclick>` / listener-driven togglers with no ARIA. The
   scan selector never finds them, so they are never driven. (The *drive* — click — already works; only
   **detection** is missing for this class.)

## The load-bearing crux: is this gap still REAL on real sites, and CONTENT-FREE-findable?

Mirror the G2 de-risk discipline. Two crux risks, de-risked DIRECTLY (not deferred to BUILD):

1. **Prevalence (the dominant risk).** ARIA+click adoption (a11y pressure) has shrunk hover-only/no-ARIA
   triggers on modern real sites. The gap may be largely covered already by the ARIA scan. So **PASS
   requires reveals on REAL sites; fixtures are an existence-proof only and do NOT count toward the bar.**
   (Apply the G2 real-world-breadth lesson *harder* — the prior is worse here.)
2. **Content-free findability.** A detector that keys on class/text/id semantics ("class contains
   `dropdown`") is a firewall violation. The honest detector is **CDP `DOMDebugger.getEventListeners`** —
   it returns listener *type names* (`click`/`mouseover`/`mouseenter`…), no content, per-node. This IS
   content-free and precise (a plain `<a href>` has NO listener → excluded → does not dilute precision).
   The hard tail is **pure-CSS `:hover` menus** (no listener at all): the only content-free signal left
   is a bounded hover-sweep. If reveals exist ONLY in that tail and its detector is imprecise, the
   content-free blocker is named (un-findable without content/visual heuristics — cf. G2 instance-ID).

## Mechanism facts (pin BEFORE measuring — getting these wrong = a G2-style tautology)

- **CSS `:hover` does NOT fire on a JS `dispatchEvent`.** It fires ONLY via CDP
  `Input.dispatchMouseEvent` (`type:"mouseMoved"` to the element-center coords, through `ev.sess` —
  the exact pattern at `web_flipbook.py:60`). A JS-`dispatchEvent` hover probe would reveal 0 on a CSS
  `:hover` fixture → **false DEFER** (the same proxy/tautology trap as the G2 `scrollTo(0)` repro). Use
  CDP Input; it drives CSS `:hover` AND JS `mouseenter` listeners both.
- `el.click()` (`_CLICK_JS`) DOES fire JS `click` listeners — so the no-ARIA **click** class needs only
  new *detection*, not a new drive.
- `getEventListeners` requires an `objectId`: `DOM.resolveNode({nodeId})` → `object.objectId` →
  `DOMDebugger.getEventListeners({objectId})`. Content-free by construction (type names only).

## Detectors (both content-free; measured SEPARATELY)

Candidate set per site = elements with `getComputedStyle().cursor === 'pointer'` MINUS the ARIA-affordance
set, capped at `CANDIDATE_CAP` in DOM order (cursor:pointer is a **bounding pre-filter only**, NOT the
precision detector — it merely caps CDP round-trips; the detectors below decide). LOG if the cap is hit
(no silent truncation).

- **Detector-L (listener):** per candidate, `getEventListeners` → keep those with a
  `click`/`mousedown`/`pointerdown` (→ drive via `_CLICK_JS`) or `mouseover`/`mouseenter`/`pointerover`
  (→ drive via CDP `Input.dispatchMouseEvent` mouseMoved) listener. The content-free-clean detector.
- **Detector-H (CSS-hover sweep):** per candidate, drive a CDP mouseMoved regardless of listener (catches
  pure-CSS `:hover` reveals that Detector-L misses). The hard-tail detector; precision reported separately.

Each driven candidate: re-baseline (`_snapshot_skeleton`) → drive → settle → `_snapshot_skeleton` →
`diff_skeletons`. Selectors are the existing structural content-free `path()` (`tag:nth-of-type(n)`).

## Metrics (per site) — content-free shape-key union, exactly as G2

Reuse `probe_g3d_dedup._node_key` (positional fields dropped) for the shape-key; reuse `diff_skeletons`
for the appeared unit.

- `aria_appeared`, `aria_triggers` — the existing ARIA-click baseline (reuse `_AFFORD_JS` +
  `classify_trigger` + `_CLICK_JS` + `diff_skeletons`), and `aria_shapes` = shape-keys it reveals.
- `cand_total` / `cand_capped` — candidate count and whether `CANDIDATE_CAP` was hit.
- Per detector D ∈ {L, H}: `driven_D` (candidates D drove), `hits_D` (drove ≥ `HIT_MIN` appeared
  nodes), **`new_shapes_D`** = `|reveal_shapes_D − (rest_shapes ∪ aria_shapes)|` (NEW content-free
  structure exclusive of REST and of what ARIA already reveals), **`precision_D = hits_D / driven_D`**.
- Firewall: every per-state skeleton through `content_firewall.redact_node` → `audit_bundle` = 0
  violations (audit the SHIPPED artifact, NOT raw capture — the G2 firewall fix).

## PRE-REGISTERED BAR (locked — no post-hoc tuning)

Constants: `NEW_ABS = 25` · `PRECISION_MIN = 0.20` · `NEG_MAX = 10` · `HIT_MIN = 3` ·
`MIN_REAL_PASS_SITES = 2` · `CANDIDATE_CAP = 400`.

**G4-hover de-risk PASSES (BUILD justified) iff ALL of:**
1. **Real-site recall (prevalence):** on ≥ `MIN_REAL_PASS_SITES` **REAL** sites (NOT fixtures),
   `new_shapes_L ≥ NEW_ABS` (the listener detector — the content-free-clean path — reveals genuinely
   new structure the ARIA scan misses). Detector-H reveals are reported but a Detector-H-only pass is a
   DEFER (hard-tail caveat, below).
2. **Content-free precision:** on each real pass-site, `precision_L ≥ PRECISION_MIN` (the listener
   detector is a usable trigger set, not a flood of empty drives).
3. **Metric discriminates:** the static negative control shows `new_shapes_L < NEG_MAX` AND
   `new_shapes_H < NEG_MAX` (proves the metric measures real reveals, not hover/focus style-jitter).
4. **Content-free:** 0 firewall violations across all per-state skeletons.

**G4-hover DEFERS (with the specific finding recorded) if:**
- `new_shapes_L ≈ 0` on real sites even where listeners exist ⇒ **gap already covered by the ARIA scan /
  shrunk by a11y adoption** — the prevalence finding (the likeliest honest outcome). OR
- `precision_L` near-zero ⇒ content-free listener detector too imprecise to ship. OR
- reveals appear ONLY via Detector-H (CSS-hover tail) and `precision_H` is low ⇒ **named blocker:
  pure-CSS `:hover` menus are not content-free-findable without content/visual heuristics** (cf. G2
  instance-identity). OR
- the negative control does not discriminate ⇒ metric is noise.

The BUILD bar (wire the new detector + hover drive into `web_states`, NET of per-candidate CDP cost) is
a SEPARATE pre-registration if this passes — it does not carry over. It MUST clear on ≥2 **real** sites
(fixtures never count), closing the prevalence risk this de-risk foregrounds.

## Sites (PRE-REGISTERED + fallbacks; log every load outcome, NO silent drops)

REAL (a PASS needs ≥2 of these, fixtures excluded):
- **R1** `https://getbootstrap.com/docs/5.3/components/dropdowns/` — JS dropdown components
  (`data-bs-toggle` click listeners; not all ARIA-expanded at REST). Fallback:
  `https://getbootstrap.com/docs/5.3/components/navbar/`.
- **R2** `https://developer.mozilla.org/en-US/` — JS nav/menu widgets. Fallback:
  `https://www.smashingmagazine.com/`.
- **R3** `https://news.ycombinator.com/` — minimal-JS (honest low-prevalence stress: few listeners).
  Fallback: `https://www.gnu.org/licenses/gpl-3.0.html` (static long doc).

EXISTENCE-PROOF fixtures (existence only — DO NOT count toward the ≥2 real pass-sites):
- **F1** `fixtures/interaction-state/hover-menu.html` — to CREATE: a CSS-`:hover` dropdown (no ARIA, no
  listener) + a JS-`mouseenter` menu + a `<div onclick>` no-ARIA panel. The controlled positive proving
  each detector path fires when the pattern is present.

NEGATIVE control (must show `new_shapes_L < NEG_MAX` AND `new_shapes_H < NEG_MAX`):
- **N1** `fixtures/interaction-state/static-neg.html` — to CREATE: `cursor:pointer` links + text, NO
  listeners, NO `:hover` reveal. (NOT wikipedia — it mounts hovercard DOM on link-hover, §advisor.)

Load-failure policy: any site that fails to load / times out / firewall-trips is LOGGED with the reason
and EXCLUDED; it does not silently shrink the cohort. A pass needs the counts above met by real sites
that actually loaded.

## Probe spec — `research/capture-gap-probes/probe_g4_hover.py`

Runs on HOST Bash (CDP :9222, `dangerouslyDisableSandbox`), like the other probes. Per site:
1. `resolve_web_eval` (auto/CDP) → `navigate`. REST `_snapshot_skeleton` → `rest_shapes`.
2. ARIA baseline: `_AFFORD_JS` + `classify_trigger` + `_CLICK_JS` + `diff_skeletons` → `aria_appeared`,
   `aria_shapes`, `aria_triggers`.
3. Candidate scan: in-page `cursor:pointer` minus ARIA set, capped at `CANDIDATE_CAP` (log if capped),
   each as a structural `path()` selector + a `nodeId` (via `DOM.querySelectorAll`/index).
4. Detector-L: per candidate `DOM.resolveNode` → `DOMDebugger.getEventListeners`; classify by type;
   drive (click via `_CLICK_JS`, hover via CDP `Input.dispatchMouseEvent` mouseMoved to center) with a
   per-trigger re-baseline; `diff_skeletons`. Detector-H: CDP mouseMoved over the SAME candidates.
5. Compute the metrics; `redact_node`→`audit_bundle` every per-state skeleton (assert 0).
6. Emit one JSON row per site; print a compact table + the pass/defer verdict against the LOCKED bar.

De-risk ONLY: do not modify `web_states.py`/`_states.py`; do not wire anything into the engine. Measure,
then record BUILD-justified or DEFER in the roadmap with the numbers.

## Provenance / reuse
- Scan/drive/diff: `web_states.py` (`_AFFORD_JS`, `_CLICK_JS`, `_snapshot_skeleton`), `_states.py`
  (`classify_trigger`, `diff_skeletons`).
- Hover drive: CDP `Input.dispatchMouseEvent` (`web_flipbook.py:60` pattern), `ev.sess.send`.
- Listener detect: CDP `DOM.resolveNode` + `DOMDebugger.getEventListeners`.
- Shape-key: `research/capture-gap-probes/probe_g3d_dedup.py:_node_key`.
- Firewall: `scripts/content_firewall.py` (`redact_node`, `audit_bundle`). CDP :9222 needs an open tab
  first (memory `cdp-capture-needs-open-tab`).
