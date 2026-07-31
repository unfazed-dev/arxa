# Fixed-width `@container` capture — design spec

**Status:** approved 2026-06-01. Closes the Regime-3c ceiling §C9-R-P11 ("fixed-width @container NOT captured").
**Regime:** ladder rung after form-state (P14). Sibling to Regime-3c responsive multi-viewport.
**Grounding probe:** `research/capture-gap-probes/probe_container_query.py` (committed `b320ed1`).

---

## §0 — Probe facts (CQ-series, the empirical floor)

Run on host Chrome (CDP `:9222`) against a synthetic owned page. Forks resolved BEFORE design:

- **CQ1 DISCOVERY = OK.** `container-type` is present in the DOMSnapshot `computedStyles` whitelist. Query
  containers are findable by computed style (`inline-size` / `size` / `normal`). `container-name` also
  exposed (`'none'` when unnamed).
- **CQ2 JOIN = OK (the kill-shot).** A non-navigate inline-style width mutation that reflows the page caused
  **zero `backendNodeId` churn** (base-backends=19, cond-backends=19, added=[], dropped=[]). The base↔condition
  join survives mutation. R2's stability-across-viewport-override does not automatically transfer to mutation;
  this is the empirical proof it holds for mutation too.
- **CQ3 RE-EVAL = OK.** After narrowing the fixed-width container, the child's CAPTURED computed style reflected
  the `@container` rule (`display: block→flex`, `font-size: 20→11`, `color` moved). The query re-evaluates in
  the captured styles, not merely the live render.
- **CQ4 PROPS-THAT-MOVED** = `display, font-size, color` (+ `width` = induced artifact). CQ rules restyle the
  same discrete-layout + type vocab as `@media`.
- **CQ5 ARTIFACT / NESTING.** A `%`-sized descendant (`#cqi-pct`) and the container's own box show induced
  `width` deltas (layout artifacts of our mutation, NOT authored CQ restyle). A NESTED container's child
  (`#cqi2-child`, `font-size 16→8`) re-evaluated **transitively** when its ancestor shrank, and the delta
  landed on the nested descendant's own backendNodeId (joins correctly).
- **CQ6 REVERT = OK.** Clearing the inline width restored the base exactly (empty delta) → a per-container
  sweep is reusable on ONE navigate.
- **CQ7 SIZE-2D.** `container-type: size` fired on a height mutation but dragged HTML/BODY page-root height
  artifacts. → **inline-size only; `size` is a documented ceiling.**

**Probe label caveat:** the probe's `tag#id` helper printed `?`/`None` because `parse_snapshot` records carry no
author `id` — cosmetic only; the backend SETS and deltas (the actual results) are authoritative.

---

## §1 — Scope & intent

**Intent (user-confirmed): component-adaptive sweep.** A fixed-width query container renders at exactly ONE
width on the page, so capturing the rendered state alone adds nothing (base already has it). The signal is the
restyle a container's descendants take **across a sweep of representative absolute widths** — how this card /
sidebar / grid-track would adapt. We deliberately surface OFF-render states. This is the only framing where the
rung carries signal; page-render-fidelity-only would be a near-empty no-op rung (rejected).

**The gap.** Regime-3c (`capture_with_breakpoints`) re-evaluates `@container` ONLY for viewport-TRACKING
containers (a full-width block whose inline-size = the viewport, so `setDeviceMetricsOverride` resizes it). A
FIXED-WIDTH container's size is independent of the viewport, so its rules never fire under R3c.

**The mechanism divergence.** There is NO CDP primitive to emulate CONTAINER size (unlike
`setDeviceMetricsOverride` for the viewport, `forcePseudoState` for pseudo-classes). The only content-free way
to fire a fixed-width container's rules is to MUTATE the container element's own width and reflow. Reading the
authored `@container` rule text would be the BLOCKED regime-4b. This is the first rung to mutate the DOM; the
probe (CQ2/CQ6) proved the join survives it and revert restores cleanly.

---

## §2 — Mechanism: `capture_with_container_queries(ev, engine, url, widths, max_wait)`

New function in `web_skeleton.py`, sibling to `capture_with_breakpoints`. CDP-only (guards on
`hasattr(ev, "sess")`; the `elif args.container_queries:` branch `die()`s on a non-CDP transport).

1. **Base.** `_capture_one(ev, engine, url, width=CONTAINER_BASE_VIEWPORT)` at a FIXED wide viewport
   (`CONTAINER_BASE_VIEWPORT = 1440`) → `(sk, _layout, _page, node_backend)`. Then snapshot ONCE over the
   discovery-augmented prop list: `base = _theme.styles_by_backend(_snapshot_recs(ev, SNAPSHOT_PROPS))` where
   `SNAPSHOT_PROPS = CONTAINER_PROPS + ["container-type"]`. The viewport stays fixed for the whole sweep so a
   container's size is governed by our forced inline width, NOT the viewport (phantom-diff discipline, §2 of the
   R3c design). `node_backend = {node_id: backendNodeId}`; build `backend→node_id` reverse for labels.
2. **Discover containers.** From `base`, collect element backends whose computed
   `container-type == "inline-size"` (`base[backend].get("container-type")`). (`size` → SKIP, documented ceiling
   CQ7. `normal`/absent → not a container.) For each, read its base width from the node's bbox (`bbox.w`).
3. **Per container, per width** (`W` in `widths`, clamped to `W < base_w` to skip no-op widenings):
   - `pushed = DOM.pushNodesByBackendIdsToFrontend({backendNodeIds: [container_backend]})` → frontend `nodeId`
     (R3b plumbing precedent). If it fails to resolve, skip that container (drop-on-miss).
   - `obj = DOM.resolveNode({nodeId})` → `objectId`.
   - **Set** via `Runtime.callFunctionOn(objectId, fn, [Wpx])` where `fn` SAVES the original width
     (`this.style.getPropertyValue('width')` + `getPropertyPriority`) and then
     `this.style.setProperty('width', Wpx, 'important')`; returns the saved `value|priority` string.
   - `time.sleep(0.25)` to let reflow + CQ re-eval settle; `cond = _theme.styles_by_backend(_snapshot_recs(ev, SNAPSHOT_PROPS))`
     (SAME snapshot prop list as base — phantom-diff discipline).
   - `delta = _theme.diff_theme(base, cond, CONTAINER_PROPS)` → `rekey_by_node_id(delta, node_backend)`. The diff
     universe is CONTAINER_PROPS only, so `container-type` (constant) never lands in a delta.
   - Store under composite label `f"{container_node_id}@{int(W)}"` (container's node_id — bundle-internal,
     content-safe — per advisor; NOT the backendNodeId).
   - **Revert** via `callFunctionOn` with the saved string: if saved value was empty → `removeProperty('width')`,
     else `setProperty('width', savedValue, savedPriority)`. **NEVER `removeAttribute('style')`** — real elements
     carry author inline styles that must survive (advisor correctness blocker; the probe's `removeAttribute`
     masked this because the synthetic element had no prior inline style).
4. **Transpose.** `node_cq = _theme.build_node_theme(per_condition)` → `{node_id: {composite_label: delta}}`.
   `sk["_node_container"] = {str(k): v for k, v in node_cq.items()}`. Transitive nested deltas are recorded
   faithfully under the OUTER container's sweep (CQ5) — no containment-tree logic (YAGNI).
5. **`finally`.** Best-effort revert of any container still carrying a forced inline width (track the set), so
   the operator's tab is left unpolluted.

**Composite-label rationale.** A descendant under nested containers can receive deltas from BOTH its own
container's sweep and an ancestor's sweep; both are real adaptive behaviors. Keying by `(container_node_id, W)`
keeps them distinct without collision. node_id is bundle-internal (not backendNodeId), so it is content-safe to
emit.

---

## §3 — Bundle integration (`bundle_writer.py`)

- `apply_node_container(nodes, node_cq)` after `apply_node_form_state`, mirroring `apply_node_responsive`:
  `if not node_cq: return`; for each node carrying a delta, `n["container"] = _style.redact_container(cv)`.
- `assemble(...)` signature gains trailing `node_container=None`; call `apply_node_container(nodes, node_container)`
  after the existing `apply_node_*` calls.
- `main`: `raw_container = skeleton.pop("_node_container", {}); node_container = {int(k): v for k, v in raw_container.items()}`;
  thread `node_container=node_container` into the `assemble(...)` call. Popped BEFORE `_node_backend` is stripped.

---

## §4 — Redactor (`_style.py`)

The per-node delta is the flat `{composite_label: {prop: value}}` theme shape (labels are
`"<node_id>@<W>"`), so its redactor is the SAME walker — an alias, identical to
`redact_responsive`/`redact_reduced_motion`/`redact_form_state`:

```python
redact_container = redact_theme
```

The alias is a PASSTHROUGH (returns input unchanged), so the firewall is the SOLE backstop for the delta values.

---

## §5 — Content-free & firewall

- **Props are layout keywords + px + grid templates** (CONTAINER_PROPS = RESPONSIVE_PROPS, §6) — no URLs, no
  color values, no prose. The composite label embeds a node_id + integer width: both content-free.
- **`backendNodeId` (and transient CDP `nodeId`) stay INTERNAL** — never on disk. `_node_container`/`_node_backend`
  are popped by `bundle_writer.main` before write.
- **Firewall — VERIFY, do not assume.** CONTAINER_PROPS == RESPONSIVE_PROPS, and R3c already proved
  `grid-template-columns` with author-named lines (`[sidebar] 1fr`) flows through `audit_bundle` caught-not-silent.
  So no firewall change is EXPECTED. But the form-state rung taught that the "firewall unchanged" premise must be
  proven by a canary, not asserted: T3 adds a canary feeding unredacted prose through a `container` delta and
  asserting `audit_bundle` trips (`kind=="prose"`). If the canary fails, fix the firewall in its own commit.

---

## §6 — Props

```python
CONTAINER_PROPS = RESPONSIVE_PROPS   # same breakpoint-restyle class as @media, different axis
```

`@container` and `@media` are the same KIND of rule (conditional restyle at a size threshold). Reuse the proven
vocab: `display, flex-direction, flex-wrap, grid-template-columns, grid-template-rows, gap, column-gap, row-gap,
position, font-size, text-align`. `width`/`height`/`margin`/`padding`/`inset` are deliberately EXCLUDED — bbox
carries rendered size and they delta on nearly every node under a resize (anti-chimera, R3c §2.1). This
exclusion ALSO removes the induced-mutation artifacts (CQ5: container's own width + %-sized descendants), so the
captured delta is genuine CQ-rule restyle, not geometry we forced. `color`/`background-color` are an inherited
ceiling (R3c omits them; CQ rules are layout-dominant; the probe's color move was a synthetic test rule).
`container-type` is read for DISCOVERY but is constant, so it never appears in a diff.

Discovery folds `container-type` into the snapshot prop list: `SNAPSHOT_PROPS = CONTAINER_PROPS +
["container-type"]` is the `_snapshot_recs` whitelist for BOTH base and every swept condition (one snapshot
shape throughout — phantom-diff). The diff universe passed to `diff_theme` is CONTAINER_PROPS only (no
`container-type`), so `container-type` is read for discovery yet never lands in a delta (it cannot change under
a width mutation anyway).

**Default sweep widths:** `DEFAULT_CONTAINER_WIDTHS = "240,480,720"` — representative narrow/medium component
widths (containers are sub-viewport). Absolute, per advisor: CQ breakpoints are authored in absolute px, so
absolute widths hit them; relative fractions would miss large-container breakpoints and overshoot small ones.

---

## §7 — Ceilings (documented, not silently dropped)

- **`container-type: size` (2D) SKIPPED** — fires on height but drags page-root (HTML/BODY) height artifacts and
  risks auto-dimension collapse (CQ7). inline-size only.
- **Viewport-tracking inline-size containers are ALSO swept** → their `@container` rules OVERLAP what R3c already
  captures. We cannot distinguish viewport-tracking from fixed-width by computed style alone, so we do NOT build
  detect-and-exclude (advisor); the overlap is documented. (The two sidecars are separate keys; a consumer sees
  both.)
- **Off-render states by design** — the swept widths are states the page never actually renders (the sweep
  intent). Not a fidelity bug.
- **`DOM.querySelectorAll`/discovery does NOT pierce shadow DOM / iframes** — containers inside web components or
  cross-frame get no delta.
- **Authored thresholds NOT recovered** — we sweep representative widths and capture whatever restyles; the
  `@container (max-width:Npx)` expression itself is regime-4b (blocked).
- **`width`/`height`/`color`/`bg`/continuous-px excluded** (§6).
- **Box-model metric mismatch (documented, not fixed).** `base_w` is read via
  `getBoundingClientRect().width` (border-box), but `style.setProperty('width', Wpx)` sets the CONTENT width on a
  content-box element. The two differ by padding+border on a content-box container, so the effective container
  size at a swept `W` is slightly larger there. The `W < base_w` clamp stays directionally correct (skips
  widenings) and the gate page is `box-sizing: border-box` so the gate is exact; on a content-box site the swept
  widths are approximate — acceptable for a representative sweep (we are not reproducing authored thresholds).

---

## §8 — Code surface

- `scripts/web_skeleton.py`: `CONTAINER_PROPS`, `DEFAULT_CONTAINER_WIDTHS`, `CONTAINER_BASE_VIEWPORT`,
  `capture_with_container_queries(...)`, `--container-queries` flag (`dest="container_queries"`,
  `nargs="?"` const default), `elif args.container_queries:` main branch.
- `scripts/_style.py`: `redact_container = redact_theme`.
- `scripts/bundle_writer.py`: `apply_node_container`, `assemble` param, `main` pop+thread.
- `scripts/content_firewall.py`: NO change expected (verified by canary, not asserted).
- `fixtures/container-query/run_container_query.py`: host CDP gate — the first real test of the
  discover→push→resolve→mutate→revert path.
- `fixtures/container-query/validate_realsite.py`: content-free real-site harness.
- `.gitignore`: `fixtures/container-query/_sk.json`, `_tokens.json`, `_bundle/`.
- Tests: `test_style.py` (alias), `test_bundle_writer.py` (apply + none-safe), `test_web_skeleton.py`
  (discovery filter, composite label, save/restore, `w<base` clamp, prop-list discipline),
  `test_content_firewall.py` (prose canary through a `container` delta).

---

## §9 — Test plan (TDD, host gate run by controller)

**Unit (sandbox-safe, fake CDP session):**
- discovery selects only `container-type=="inline-size"` (skips `size`/`normal`).
- composite label `"<node_id>@<W>"`; `build_node_theme` transpose correct.
- save/restore: revert calls `removeProperty` when no prior inline width, `setProperty(saved)` otherwise; never
  `removeAttribute`.
- `W < base_w` clamp drops no-op widenings.
- diff universe is CONTAINER_PROPS (no `container-type`, no width/height).
- error path clears all forced widths in `finally`.

**Host gate (`run_container_query.py`, controller-run, `dangerouslyDisableSandbox`):** synthetic page —
fixed-width inline-size container with a child `@container` rule; nested container (transitive); a `size`
container (must be SKIPPED — its child absent from the sidecar); a plain div (no delta); `* { box-sizing:
border-box }` for stable bbox IDs. Asserts: child restyles at a swept width; nested child carries a transitive
delta on its own node; `size` container's child absent; plain div absent; NO `_node_container`/`_node_backend`/
node `backend` on disk; `bundle_writer.write_bundle` audit CLEAN (raises on leak).

**Real-site harness (`validate_realsite.py`, content-free):** prints host netloc, total nodes, nodes-with-
`container`, per-(container,width) counts, changed-prop NAMES (sorted), delta-size distribution, on-disk gate,
audit result. Failure paths print returncode only, never subprocess stderr.
