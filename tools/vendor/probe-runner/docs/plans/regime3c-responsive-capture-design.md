# Regime-3c — responsive multi-viewport capture (design spec)

**Status:** approved design, pre-plan. Next: `writing-plans` → `docs/plans/regime3c-responsive-capture.md`.

**Goal:** Capture, as an additive per-node sidecar, the **resolved-CSS reflow delta**
each element takes at narrower viewport widths relative to a widest-width base —
the responsive *design decision* (reflow / stack / retype) authored via `@media`,
`@container` (viewport-tracking only), and `clamp()`. Content-free, additive, no
reproduction-side parser.

**Where it fits (regime ladder):** Regime 1 (single-snapshot computed-style, LANDED
P6/P7) → Regime 2 (pseudo-elements, LANDED P8) → **Regime 3** (responsive / theme /
interactive): 3a theme/preference (LANDED P9), 3b interactive pseudo-states (LANDED
P10), **3c responsive multi-viewport (THIS spec)**. Remaining after 3c: Regime-4
authored-rule/keyframe parse; pseudo-element GEOMETRY; reduced-motion; form-state
pseudo-classes.

**Architecture in one line:** structural clone of 3a/3b on the **viewport-width** axis —
navigate once → `Emulation.setDeviceMetricsOverride(width)` per breakpoint with NO
re-navigate → recapture DOMSnapshot → diff resolved styles over `RESPONSIVE_PROPS` →
join base↔width by the stable `backendNodeId` → emit a per-node `responsive` field.

---

## §1 — Probe premise (the load-bearing facts, all verified)

A throwaway host probe (served a synthetic `@media`/`clamp()`/`@container` page via a
local `ThreadingHTTPServer`, drove host Chrome CDP at `:9222`, deleted after) established
the 7 facts the clone-framing depends on. All PASS:

- **R1 — `@media` STYLE re-eval:** a post-navigate `setDeviceMetricsOverride(width)` +
  fresh `DOMSnapshot.captureSnapshot` re-evaluates `@media` STYLE props (not just bbox):
  on the `@media (max-width:600px)` node, `display` flex→block, `flex-direction`
  row→column, `font-size` 24px→12px, `color` and `gap` 20px→4px all re-resolved. **This
  is the make-or-break fact — it holds.**
- **R2 — `backendNodeId` stable across repeated overrides on ONE navigate:** the same
  `backendNodeId` for every target node appeared in all 5 captures (1200 / 400-immediate /
  400-settled / 280 / restore-1200). The existing `--viewports` re-navigates per width and
  never tested this; 3c relies on it for the join.
- **R3 — `clamp()` re-resolves:** a `clamp(10px, 5vw, 40px)` font-size resolved 40px@1200 →
  20px@400 — the fluid type curve is recoverable by recapturing at multiple widths.
- **R4 — style re-eval is synchronous:** immediate (no settle) == settled capture for the
  `@media` props. A small settle tick is STILL kept in production (real-site JS resize
  listeners / async reflow), but CSS style re-eval itself does not require it.
- **R5 — isolation:** a node with NO `@media` rule had an identical resolved style at both
  widths → it gets no delta (sparse output, like 3a/3b).
- **R6 — restore:** re-widening the override returns the node to its base style.
- **R7 — `@container` under viewport resize:** an `inline-size` container whose width
  tracks the viewport re-evaluated its `@container (max-width:300px)` rule when the
  viewport shrank to 280px (`#cq` color flipped). → viewport-sized containers ride free;
  containers with fixed/intrinsic width do not (deferred, §6).

---

## §2 — Scope

**In:** per-node resolved-style deltas over a curated discrete-layout prop universe, at N
author-supplied viewport widths, joined by `backendNodeId`, emitted as an additive
per-node `responsive` sidecar. `@media`, `clamp()`, and viewport-tracking `@container`
ride for free through the same machinery.

**Out (deferred, documented ceilings — §6):** fixed/intrinsic-width `@container`;
continuous px (`width`/`height`/`margin`/`padding`/`inset` — bbox already carries rendered
size and they delta on nearly every node in fluid layouts); authored breakpoint conditions
/ the literal `clamp()` expression (Regime-4 parse); JS-resize-listener DOM mutations
(drop-on-miss, style-only ceiling).

### §2.1 — Prop universe (`RESPONSIVE_PROPS`)

```
display, flex-direction, flex-wrap,
grid-template-columns, grid-template-rows,
gap, column-gap, row-gap,
position, font-size, text-align
```

Rationale: these are the **discrete** props that flip at author breakpoints (the
responsive decision), not the continuous px that resize on every node. `display` /
`flex-*` / `grid-template-*` / `gap` delta only where an author wrote a responsive rule →
sparse (isolation). `font-size` is the densest by design — it carries the wanted `clamp()`
fluid curve. Excluded continuous px is the explicit anti-chimera choice from brainstorming.

`RESPONSIVE_PROPS` is requested in the `DOMSnapshot.captureSnapshot` `computedStyles` list
for each breakpoint capture and is the `universe` passed to `_theme.diff_theme`. It is a
NEW constant in `web_skeleton.py` (distinct from `WANT_STYLES` and `THEME_PROPS`); a
prop in `RESPONSIVE_PROPS` need not be in `WANT_STYLES` (the breakpoint captures request
their own list).

### §2.2 — Sidecar shape

Per-node `responsive` field: `{width_label: {prop: resolved_value}}`, e.g.
`{"768": {"display": "block", "flex-direction": "column"}, "390": {"font-size": "12px"}}`.
`width_label` is the breakpoint width as a string. Identical `{label: {prop: value}}`
shape as 3a's `theme` and 3b's `pseudo_state` — so the entire 3a redaction + bundle +
firewall machinery applies by alias.

---

## §3 — Capture flow (`capture_with_breakpoints`)

New CDP-orchestration function in `web_skeleton.py`, mirroring `capture_with_themes` /
`capture_with_pseudo_states`:

1. Parse `--breakpoints` into widths; sort **descending**; `base_w = widths[0]` (widest),
   `delta_ws = widths[1:]`.
2. **Base skeleton** (the emitted reference bundle, at the widest width): `_capture_one(ev,
   engine, url, width=base_w)` — this navigates ONCE, applies
   `setDeviceMetricsOverride(width=base_w)`, settles, forces REST, and snapshots over
   `WANT_STYLES`, returning `(sk, layout, page, node_backend)`. The bundle's widest-width
   skeleton is exactly the normal output — no new skeleton path. The override is left at
   `base_w` (CDP does not auto-revert until session close), so the next step reads at the
   same width with no re-navigate.
3. **Base diff-styles** (`RESPONSIVE_PROPS` ⊄ `WANT_STYLES`, so a separate read is
   required): with the override still at `base_w` and no navigate, take a
   `DOMSnapshot.captureSnapshot(computedStyles=RESPONSIVE_PROPS)`, parse via
   `parse_snapshot(snap, RESPONSIVE_PROPS, dpr=eff_dpr)`, and build
   `base_styles = _theme.styles_by_backend(recs)`. A small helper generalizes 3b's
   `_snapshot_recs` to take the prop list (`_snapshot_recs(ev, props=RESPONSIVE_PROPS)`),
   so base and every width share one capture-and-parse routine over the SAME prop list
   (the phantom-diff guard). `node_backend` (from step 2) is the join map; its keys are the
   base skeleton's positional node ids.
4. For each `w` in `delta_ws`: `setDeviceMetricsOverride(width=w)`, settle tick,
   `cond_styles = _theme.styles_by_backend(_snapshot_recs(ev, RESPONSIVE_PROPS))`,
   `delta = _theme.diff_theme(base_styles, cond_styles, RESPONSIVE_PROPS)`,
   `per_width[str(w)] = _theme.rekey_by_node_id(delta, node_backend)`. (No navigate inside
   the loop — R2 guarantees `backendNodeId` is stable across the overrides.)
5. After the loop: `node_resp = _theme.build_node_theme(per_width)` (transpose
   {label:{node:delta}} → {node:{label:delta}}); attach
   `sk["_node_responsive"] = {str(k): v for k, v in node_resp.items()}`.
6. `finally`: clear the device-metrics override (`Emulation.clearDeviceMetricsOverride`)
   so the operator's tab is left unpolluted — the 3a/3b cleanup discipline.

Identical capture params across base + every width (same `RESPONSIVE_PROPS` `computedStyles`
list, same `dpr` handling, same REST) = the 3a **phantom-diff guard**: a plain
`base[prop] != cond[prop]` fires on a real reflow, not on serialization noise, and catches
both directions (a reset is a value change). The base skeleton (step 2) uses `WANT_STYLES`
for the normal bundle; the diff (steps 3–4) uses `RESPONSIVE_PROPS` consistently on both
sides — the two prop lists never cross. The dpr handling reuses the existing `--viewports`
`eff_dpr` logic (`_backing_scale` under a width override — see `_snapshot_skeleton`), since
3c also forces `deviceScaleFactor:1`.

---

## §4 — The join

`backendNodeId` — DOMSnapshot-stable across base→width recapture with no navigate (R2),
already threaded by 3a/3b through `parse_snapshot` → `to_skeleton` → `node_backend`.
`diff_theme` joins base↔width by `backendNodeId`; `rekey_by_node_id` maps back to the
positional skeleton `node_id` for emission. `backendNodeId` (and any transient CDP
`nodeId`) are INTERNAL — never written to disk (`main` pops `_node_responsive` only; no
per-node `backend` is emitted — gate-asserted, §7).

Unlike 3b, 3c needs **no** `pushNodesByBackendIdsToFrontend` map — the width override is
global (`setDeviceMetricsOverride`), not a per-node command, so there is no
`backendNodeId → nodeId` round-trip to issue.

---

## §5 — `_theme` reuse (unchanged)

`styles_by_backend` / `diff_theme` / `rekey_by_node_id` / `build_node_theme` are
condition-agnostic (they took 3a's media conditions and 3b's pseudo-states unmodified) —
they drive 3c's width conditions unmodified too. **No new pure module.** The only new
pure-ish constant is `RESPONSIVE_PROPS`.

---

## §6 — Ceilings (honest)

- **Fixed/intrinsic-width `@container` deferred.** Viewport-tracking containers ride free
  (R7). A container whose width is fixed or intrinsic does not change when the viewport
  resizes, so its `@container` rule never fires under this mechanism. Capturing it would
  need per-element resize (DOM mutation or per-element metrics — no clean content-free CDP
  primitive) → deferred to a follow-on / Regime-4. Documented, not silently dropped.
- **Drop-on-miss.** A node present in base but absent at a width (`display:none` under a
  width-media rule, or a JS-resize-triggered DOM mutation) is DROPPED for that width, never
  reattached — the documented style-only ceiling (same as 3a). `diff_theme` already does
  this (a node missing from `cond_by_backend` is skipped).
- **`grid-template-columns/rows` author-named lines — firewall watch-item.** The computed
  value of these props *may* include author-named grid lines (`[sidebar-start]`), which are
  CSS structural identifiers (not page content) but contain letters. The host gate (§7)
  MUST include a named-grid node and confirm the firewall behavior is **caught-not-silent**:
  either the redactor/firewall passes it as mechanism, or `audit_bundle` RAISES (a caught
  leak), never a silent pass of author text. If the gate shows a real leak risk, the
  fallback is to drop `grid-template-*` from `RESPONSIVE_PROPS` (track sizes are lower-value
  than the display/flex flips). Decide empirically at the gate.
- **JS-resize layout ≠ fresh-navigate-at-width.** A site that builds responsive layout in a
  JS `resize` listener may land in a different state under live override vs a fresh
  navigate at that width. 3c captures the live-override state (consistent with the no-
  navigate design); the fresh-navigate-per-width state is the landed `--viewports` path's
  domain. Style-only ceiling, same class as 3a's DOM-mutation note.
- **No co-occurrence chimera.** Width override is global, so all nodes are measured under
  the same single condition per capture — unlike 3b's force-all (which co-forced a pseudo
  on every node simultaneously). 3c is cleaner on this axis.

---

## §7 — Bundle integration + firewall

- `bundle_writer.apply_node_responsive(nodes, node_resp)` mirrors `apply_node_theme`:
  `if not node_resp: return`; per node `rv = node_resp.get(n["id"])`; `if rv:
  n["responsive"] = _style.redact_responsive(rv)`. Runs BEFORE `cf.redact_node`.
- `assemble(..., node_responsive=None)` gains the trailing param (existing `states`,
  `node_style`, `node_pseudo`, `node_theme` params UNTOUCHED), calls
  `apply_node_responsive` after `apply_node_theme`, before `cf.redact_node`.
- `main` adds `raw_resp = skeleton.pop("_node_responsive", {})`,
  `node_responsive = {int(k): v for k, v in raw_resp.items()}`, passes to `assemble`.
- `_style.redact_responsive = redact_theme` (alias — identical `{label:{prop:value}}`
  shape; values are CSS keywords/lengths/track-lists with no URLs/content, so the redactor
  is a near-no-op, but the alias keeps the firewall recursion + canary symmetry).
- **`content_firewall.py` UNCHANGED.** `responsive` is not a `CONTENT_KEYS` entry, so
  `redact_node` (a top-level-key blacklist) preserves the already-redacted nested map, and
  `audit_bundle`'s key-aware walk recurses into `node.responsive[label][prop]` as the
  independent backstop. A prose canary (test, §8) proves the walk actually reaches that
  path.

---

## §8 — Testing

- **Unit (pure core):** `_theme` diff/rekey/transpose already covered (3a/3b) — 3c adds no
  pure logic, so no new `_theme` tests are required, but a 3c-labelled smoke test that
  drives `diff_theme`/`rekey_by_node_id`/`build_node_theme` with width labels documents the
  reuse.
- **`redact_responsive` alias** (`test_style.py`): `redact_responsive is redact_theme`;
  redacts external `url()` / keeps a raw value (inherited behavior).
- **`element` selection:** 3c diffs over `styles_by_backend` (which already skips pseudo /
  no-backend records); no new element filter needed (unlike 3b's `element_backends`, which
  was only needed because `forcePseudoState` rejects non-element nodes).
- **Bundle apply** (`test_bundle_writer.py`): `apply_node_responsive` attaches a redacted
  delta to the right node id; None-safe (no field when `node_resp` empty).
- **Firewall prose canary** (`test_content_firewall.py`): plant prose in
  `node["responsive"]["768"]["display"]`; assert `audit_bundle` flags a `prose` violation
  — proves the key-aware walk reaches `responsive`. `content_firewall.py` unchanged.
- **Host gate** (`fixtures/responsive/run_responsive.py`, controller-run CDP): synthetic
  page served locally with — `#known` (`@media (max-width:600px)` flips
  display/flex-direction/font-size), `#fluid` (`clamp()` font-size), `#static` (no
  responsive rule → isolation), `#grid` (`grid-template-columns` change with an author-
  **named line** to exercise the firewall watch-item), and a viewport-tracking
  `@container` node. Run `web_skeleton --breakpoints` → `bundle_writer`. Assert: `#known`
  carries the right per-width display/flex/font-size deltas joined to the right node;
  `#fluid` font-size steps across widths; `#static` has NO `responsive` field (isolation);
  the named-grid node's firewall outcome is caught-not-silent; `_node_responsive` /
  per-node `backend` NEVER on disk; `bundle_writer` does not raise (audit CLEAN). GATE PASS
  required before real-site.
- **Real-site validation** (`fixtures/responsive/validate_realsite.py`, content-free): a
  public `--url`, `LABELS` = the breakpoint widths; print ONLY host netloc + per-width
  nodes-with-delta + volume % + changed-prop NAMES + counts. No content, no resolved
  values, no full URL. `bundle_writer` raising = firewall caught a leak.

---

## §9 — CLI

`web_skeleton.py` argparse gains `--breakpoints` (comma widths, e.g. `390,768,1440`;
default `390,768,1440`), with help text drawing the distinction from `--viewports`:

> `--breakpoints` — per-node resolved-style reflow deltas across viewport widths
> (`backendNodeId` join, additive `responsive` sidecar). Distinct from `--viewports`
> (coarse fill/fixed sizing inference, positional join, merged skeleton).

Handler branch placed after the `elif args.pseudo_states:` block, before `elif
args.viewports:` — validates widths are positive ints, guards `hasattr(ev, "sess")` (CDP
transport required for `Emulation.setDeviceMetricsOverride`), calls
`capture_with_breakpoints`. `--breakpoints` and the other Regime-3 flags
(`--themes`/`--pseudo-states`) and `--viewports` are mutually exclusive via the existing
`if/elif` chain (consistent with the landed pattern; passing two runs only the first).

---

## §10 — Naming — distinct from the landed `--viewports`

`--viewports` (landed, P-pre): re-navigates per width, joins nodes **positionally**
(y-center, radius 40px), overwrites each node's `sizing` to a coarse `{w/h: fill|fixed,
confidence: low}` inference, emits ONE merged skeleton keyed to the widest viewport. Answers
"does this box grow or stay fixed across breakpoints?"

`--breakpoints` (this spec): navigates once, joins by **`backendNodeId`**, emits a base
widest-width skeleton + a per-node `responsive` delta sidecar over discrete layout props.
Answers "what does this element's layout/type *become* at each breakpoint?"

Different questions, different join keys, different output shapes → kept as separate flags
per the additive rule (every prior regime was additive; consolidation is YAGNI now).
