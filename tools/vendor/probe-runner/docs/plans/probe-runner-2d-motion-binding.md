# Probe-runner full-axis motion binding — capture motion in any direction (X, Y, Z)

**Goal:** the scanner must capture and correctly bind motion regardless of direction or
co-location — left/right, up/down, **toward/away (depth)**, and multiple movers sharing a
position. Two gaps, both measured 2026-05-29 (task #33):

1. **Binding is x-blind.** `web_anim`'s `P.meta` records only `absY` (web_anim.py:64);
   `bundle_writer.match_motion` binds by **y-distance only**; `node.anim_ref` is a single
   overwriting string. Side-by-side mirror elements (kasane's diverging hero words)
   collapse onto one node and lose their element→motion assignment.
2. **Motion is 2D-only.** Channels are `["tx","ty","sx","sy","rot","op"]`. The decoder
   `P.dec` even reads a `matrix3d(...)` but discards the depth terms (`a[14]`=translateZ
   dropped; only flat 2D spin `atan2(a[1],a[0])`, no 3D tilt). A 3D flip is recorded as a
   squashed 2D shadow.

See `kasane-motion-rebaseline-results.md` §4 and memory `bundle-motion-fidelity-layers`.

## Real-data resolutions (checked against the saved kasane fixture, NOT synthetic)

- **Separable nodes EXIST.** Hero band y=1061.5 has 7 distinct `role=text` word-nodes at
  distinct center-x (955, 1082, 1262, 1468, 1594, 1757, 1937), each its own id/parent/z.
  So x-aware binding *can* split movers to real nodes.
- **Use CENTER-x distance, not left-edge.** The wide hero container (id229, x=600 w=1680)
  has a left edge (600) nearest the left word — left-edge distance would mis-bind both
  movers to the container. Center-x separates them.
- **Coordinates MUST be REST-frame.** `rect.left`/`rect.top` include the live `tx`/`ty`
  transform — the very channels being animated — so naive absX/absY are *maximally* wrong
  mid-animation (this is the same transient-anchor bug found for y: absY swung 365/1991/1098).
  Measure rects at scroll=0 with transforms neutralized (snap base BEFORE scrolling, read
  geometry there), or join mover→node via the `data-pa` tag the producer already sets.

## Contract change

- **Motion channels 6 → 9:** add `tz` (translateZ, depth move), `rotX`, `rotY` (3D tilt).
  Exact-transform path only (web_anim / computed transform / WAAPI) — these read precisely.
  **Flipbook depth stays best-effort:** screen-space can't disambiguate "move away" from
  "shrink", so flipbook does NOT emit tz/rotX/rotY (documented limit, not silent).
- **Motion row gains `anchor_x`** (float, REST page-x CENTER), alongside `anchor` (REST y).
- **`anim_ref` becomes a LIST** of row names (one node legitimately carries several
  channels / movers). This is a **breaking** reader migration — every `anim_ref` consumer
  in all 3 copies + the crate plan must be updated (T4).
- **Amplitude is signed** (`to − from`, no `abs()`) — already the contract (engine-plan
  example `-720`, `bundle_writer` test `-218.5`); the adapter's `abs()` is the deviation.
- `anchor_x`-less rows fall back to y-only binding (back-compat for old captures).
- **axis map** gains `tz→translate-z`, `rotX→rotate-x`, `rotY→rotate-y`.

## Task ordering rationale

The **mirror-binding fix (X/Y) is the only slice provable on live kasane** and is the bug
that started this + the user's stated interest. It ships FIRST as a complete, real-data-
validated slice (Phase 1). **Z motion is synthetic-only on kasane** (no live depth motion to
validate against) — it goes SECOND (Phase 2) so the unprovable part isn't front-loaded.

## Phase 1 — Mirror binding (X/Y), provable on live kasane

### T0 — Live de-risk BEFORE coding the binder (blocks the approach, not just "done")
Relaunch debug Chrome → kasane. For EACH of the two h1 movers: dump its live rect + the
current decoded transform, compute `restX/restY`, and **resolve which skeleton node id it
maps to**. Acceptance: the two movers resolve to **two distinct, correct** nodes (not 7
unrelated spans; "Handcrafted"/"With Urushi" is 2 phrases). If they don't, center-x binding
won't save it and the metric must change. This is the check skipped last time → synthetic-
green while kasane stayed broken.

### T1 — Producer captures REST-frame x/y (`web_anim.py` `P.meta`)
- `P.meta` emits `absX` (REST page-x CENTER) AND a REST-frame `absY`. CRITICAL: `rect.left/top`
  carry the live tx/ty (the animated channels) — naive absX/absY are transient (absY swung
  365/1991/1098). Recover the layout origin engine-agnostically by subtracting the decoded
  transform P.dec already computes: `restX = rect.left + scrollX − tx_now + width/2`,
  `restY = rect.top + scrollY − ty_now`. Exact for translate; approximate under scale/rot
  (fine for ±band binding) — document it.
- Verify live (T0 harness): two hero movers report distinct, STABLE absX (one < center, one
  > center) that do NOT drift across scroll steps, and absY ≈ skeleton REST (≈1061), not 365.

### T2 — Adapter: REST x + signed amp + unique names (`motion_adapter.py`)
- `adapt_web_anim`: `anchor_x = float(mover["absX"])` when present; `anchor` from absY;
  `amplitude = to − from` **signed** (no abs()); `name = f"{sel}#{rank}#{ch}"` (rank unique
  per scan → mirror movers no longer collide as "h1#tx").
- `assert_contract`: `anchor_x` if present must be numeric (stays optional/back-compat).
- Tests: signed amp incl. negative, unique names for two same-sel movers, `anchor_x` carried,
  contract passes, `anchor_x`-less row still valid.

### T3 — bundle_writer: 2D bind + anim_ref list (`bundle_writer.py`)
- `match_motion`: y-band gate as today; among in-band candidates, minimize distance using
  **center-x when the row has `anchor_x`** (Euclidean x+y), else y-only (back-compat). Pass
  `anchor_x` through to the output row.
- `anim_ref`: append to a LIST, never overwrite. `derive_slots`/`assemble` unchanged.
- Tests: two co-located rows (same y, different center-x, opposite-sign amp) → two DIFFERENT
  nodes; a node with N channels → N-element `anim_ref`; single-mover y-only path still passes.

### T4 — Migrate anim_ref readers + existing tests (all 3 copies + crate plan)
`anim_ref` scalar→list is a **breaking** reader change. `test_bundle_writer.py` scalar
assertions → list. Grep all 3 copies + the crate consumer plan for scalar `anim_ref`; update.

### T5 — Live re-validate the MIRROR on kasane + rebuild bundle (Phase-1 ship gate)
Re-capture hero with REST x. Acceptance is the **SPECIFIC assignment**, not just "two
distinct": the Handcrafted-mover binds to its node with **tx<0**, the With-Urushi-mover to a
**different** node with **tx>0**. Rebuild bundle, re-assess, update results doc + memory.
**Phase 1 is shippable here** (commit + propagate can happen now or after Phase 2).

## Phase 2 — Z / depth motion (synthetic-validated, bounded claim)

### T6 — Decoder + core gain Z channels (`web_anim.py` `P.dec`, `_anim_core.py`)
- **APPEND** (never reorder — `flutter_anim._decompose` emits a fixed 6-vec `[tx,ty,sx,sy,
  rot,op]` at those indices; reordering corrupts it): `CHANNELS = ["tx","ty","sx","sy","rot",
  "op","tz","rotX","rotY"]`.
- ADD keys for tz/rotX/rotY to `VARY_THR`, `STABLE_THR`, `REPRO_THR`, `_DOM_W` (else KeyError).
- Extend the short-vector fallback `[0,0,1,1,0,1]` → `[0,0,1,1,0,1,0,0,0]`; guard `vec[ci]`/
  `va[ci]` in `analyze_movers`/`vecs_close` for vectors shorter than CHANNELS (flutter's 6).
- `P.dec`: matrix3d → `tz=a[14]`; `rotX/rotY` from the matrix3d rotation sub-block. 2D
  `matrix()` → tz=0,rotX=0,rotY=0. `P.accum` delta extended to indices 6–8.
- **Bounded claim (documented):** translateZ has NO visual effect without an ancestor
  `perspective`, and under perspective projects partly into sx/sy; rotX/rotY Euler extraction
  is ambiguous for COMBINED rotations. Certify Z reliably only for SINGLE-AXIS depth motion;
  flag combined-3D as low-confidence.
- TDD: synthetic test feeds a *varying* tz/rotX/rotY ACROSS steps (not one static matrix3d —
  that's the synthetic-green trap one level up) and asserts the channel certifies; existing
  2D fixtures still pass with the new channels inert.

### T7 — Adapter Z axis map (`motion_adapter.py`)
`_AXIS_MAP` += `tz→translate-z`, `rotX→rotate-x`, `rotY→rotate-y`. Tests: tz/rotX/rotY rows
map to correct axes + pass contract.

### T8 — Propagate to the 3 copies
`web_anim.py`, `_anim_core.py`, `motion_adapter.py`, `bundle_writer.py` + tests →
engineering-pack + brainiac (per `probe-runner-distribution`; don't clobber diverged
SKILL.md/docs). Commit canonical first, single-line message, explicit staging, no push.

## T9 — skeleton_diff px gates after the ÷dpr fix (RESOLVED 2026-05-29: gates kept)

Built the deterministic fixture the recalibration needed (`fixtures/skdiff-calib/fixture.html`
+ `harness2.py`, content-independent) and measured the CSS-px floor on real retina (dpr=2).
Results doc: `docs/skeleton-diff-css-px-calibration.md` (in probe-runner).

- **T0b verified correct (live path).** Real-retina raw DOMSnapshot bounds = `2560` for a
  1280-CSS page (= CSS × real dpr → device px); the live ÷dpr gives `2560÷2 = 1280` CSS,
  matching JS `getBoundingClientRect`. The earlier "1 CSS-px clone" worry below was directionally
  real but its magnitude guess was wrong.
- **Measured same-dpr floor = ~0 px** (deterministic fixture, dpr2 vs dpr2: pos 0.0 / size 0.0
  / iou 1.0, 26/26). Coordinates are now uniformly CSS px → gates are dpr-independent in value.
- **The plan's "MUST recalibrate / halve to 0.5, radius 12" premise is corrected — the value
  was never forced.** Same-dpr floor ≈0 means `pos=1.0` produces no false-fails, but neither
  would `0.5`. **Gates kept unchanged** (`pos=1.0`, `size=1.0`, `iou=0.98`, `radius=24`) as a
  judgment call (continuity with the pre-÷dpr value; a sub-1-px shift is imperceptible) — `0.5`
  would be equally defensible. Only docstring + SKILL prose updated to pin the CSS-px +
  **same-dpr** contract; no code/gate change.
- **Cross-dpr is excluded by contract, not tolerated.** The certified contract is
  same-page-same-viewport-**same-dpr** (already implied by SKILL "same viewport"). The cross-dpr
  numbers (pos 0.75 / size 1.5 / iou 0.944, an upper bound conflating dpr-grid + headless/headed)
  are the *reason same-dpr is required* — not an argument for any gate value (a cross-dpr capture
  is rejected on `size` regardless of `pos`).
- **Spawned T10 (#56) — RESOLVED 2026-05-29.** The `--viewports` path set `deviceScaleFactor:1`
  and divided by JS `dpr=1`, but on a **headed retina** display the override drops JS
  `devicePixelRatio` to 1 while DOMSnapshot bounds stay at the real backing scale (raw `2560`,
  survives re-nav+settle) → ÷1 left coords **2× too large**. **Fix:** `_capture_one`'s
  `--viewports` branch now divides by `_backing_scale(ev)` = `Page.getLayoutMetrics`
  `layoutViewport.clientWidth ÷ cssLayoutViewport.clientWidth` (snapped ±0.06 to standard
  display scales {1,1.25,1.5,1.75,2,2.5,3}), which —
  unlike JS dpr — keeps the true scale under the override. **Empirically chosen, not guessed:**
  a signal probe on the headed-retina rig showed getLayoutMetrics reads `2.0` under the override
  while js dpr reads `1`; an end-to-end gate ran the real width path and got widest bbox `1280`
  CSS (old ÷1 would be `2560`). 5 TDD unit tests + 152-test canonical suite green; propagated to
  all 3 copies. Repro: `fixtures/skdiff-calib/t10_measure.py` + `t10_gate.py`. Unaffected: the
  **live** path and any **headless**/non-retina capture. T9's gate decision is independent of T10.

## Non-goals / documented limits
- **Flipbook depth:** screen-space can't disambiguate translateZ from scale, so the flipbook
  path stays 2D — does NOT emit tz/rotX/rotY. Logged, not silent.
- **Combined-3D rotation:** Euler extraction ambiguous; only single-axis depth is certified.
- **klass=time stagger field** (kasane menu 0–300ms) — separate contract addition, deferred.
- Existing scale/2D-rot already flow as axes; binding is axis-agnostic so all 9 channels
  benefit from the position fix automatically.
