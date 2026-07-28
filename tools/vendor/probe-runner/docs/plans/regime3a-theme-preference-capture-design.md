# Regime 3a — theme / preference capture (design spec)

**Status:** approved design, pre-plan. Next: `writing-plans` → `docs/plans/regime3a-theme-preference-capture.md`.

**Goal:** Capture, as an additive per-node sidecar, the **resolved style delta** each
element takes under three emulated-media preference conditions —
`prefers-color-scheme: dark`, `forced-colors: active`, `prefers-contrast: more` —
relative to a pinned default-media base. Content-free, additive, no reproduction-side
parser.

**Where it fits (regime ladder):** Regime 1 (single-snapshot computed-style coverage,
LANDED P6/P7) → Regime 2 (pseudo-elements, LANDED P8) → **Regime 3** (responsive /
theme / interactive), of which this is sub-axis **3a (theme/preference)**. 3b
(interactive `:hover`/`:focus` via `forcePseudoState`) and 3c (responsive multi-viewport)
are separate spec→plan→impl cycles.

---

## 1. Premise (de-risked before design)

A throwaway host CDP probe (synthetic page; deleted after) verified the three
load-bearing facts the whole diff core rests on:

- `DOMSnapshot.captureSnapshot` returns **`backendNodeId`** per node — **present**, a
  **dense array parallel** to `nodeName`/`parentIndex` (len equal).
- The `backendNodeId` set is **identical across a base→dark recapture** of the same page
  (no navigate, only `setEmulatedMedia` between) — 0 nodes appeared/disappeared from the
  *node list*.
- A node toggled **`display:none` by a dark `@media` rule LEFT the layout set** (laid-out
  count dropped) **but persisted in the node list** (its `backendNodeId` remained) — so a
  visibility toggle does not corrupt the join.

**Therefore the join key is `backendNodeId`, NOT the positional skeleton `id`.** Skeleton
`id = len(emitted)` is emission-ordinal and is NOT stable across two captures (the existing
`_states.diff_skeletons` matches geometrically for exactly this reason). An id-keyed theme
diff would silently mis-key on any node-set shift. `backendNodeId` is the correct,
verified, stable join.

---

## 2. Scope (locked)

- **Conditions (3, user-chosen):** `prefers-color-scheme: dark`, `forced-colors: active`,
  `prefers-contrast: more`. The recapture loop takes a list; adding/removing conditions is
  a data change, not a code change.
- **Delta storage (user-chosen):** **raw resolved values inline** per node (colors as
  resolved `rgb()`, mirroring `_collect_pseudo`'s inline fg/bg/border). A palette-token
  model for theme colors is an explicit deferred follow-on.
- **Style-only:** per-node *style* deltas for nodes laid-out under BOTH base and the
  condition. Visibility/structural deltas are a documented ceiling (§9).
- **No new content vector** — theme deltas are resolved style values, redacted by the
  Regime-1 `redact_style_value` (the one `content`-shaped edge is routed through
  `redact_content_value`; see §6).

---

## 3. Capture flow & base-media pinning

`web_skeleton.py` gains a `--themes` flag (e.g. `--themes dark,forced-colors,contrast`,
default off), consistent with the existing `--viewports`. On a CDP transport only (theme
emulation needs `Emulation.setEmulatedMedia`; no-op / error on non-CDP, mirroring
`--viewports`).

Sequence (single open tab, NO navigate between captures — reuses
`_snapshot_skeleton(ev, url, width=None)`):

1. **Pin base to explicit default media** before the base capture — do NOT rely on ambient
   OS/headless defaults (otherwise the delta is environment-dependent):
   `setEmulatedMedia({features: [
   {name:"prefers-color-scheme", value:"light"},
   {name:"forced-colors", value:"none"},
   {name:"prefers-contrast", value:"no-preference"}]})`.
   Capture base → this is the bundle's primary skeleton.
2. For each requested condition, flip **exactly one** feature off the pinned base (single
   axis isolated), e.g. dark = base features with `prefers-color-scheme: dark`:
   `setEmulatedMedia(...)` → `_snapshot_skeleton` → parse → condition raw styles.
3. **`finally`: clear emulation** (`setEmulatedMedia({features: []})`) so the operator's
   tab is left unpolluted even on error.

**Phantom-diff guard:** base and every condition use **identical capture params** — same
`WANT_STYLES`, same dpr (live; `width=None` for all theme captures, no viewport override),
same REST/settle. Resolved values therefore serialize byte-identically across captures
(single Chrome engine, same call), so a `base[prop] != cond[prop]` comparison fires on a
*real* value change, never on formatting. (Same rgb-serialization invariant already relied
on by the Regime-2 color parent-diff.)

---

## 4. Join: `backendNodeId` threaded through parse → skeleton

- **`parse_snapshot`** reads the dense `nodes["backendNodeId"]` array and stamps
  `"backend": backend_by_index[dom_i]` on each record (alongside the existing `dom_index`).
- **`to_skeleton`** returns a **5th value** `node_backend = {node_id: backendNodeId}`
  (parallels the `node_colors`/`node_style`/`node_pseudo` sidecar pattern). Built from the
  same `emitted` list, so it is exact. The 4→5-tuple change churns call sites: production
  `_snapshot_skeleton` (migrate) + the `to_skeleton` unit-test unpack sites (migrate to
  5-value or arity-tolerant `*_`). `fixtures/skdiff-calib/harness2.py` already uses
  `sk, *_ =` (P8 fix) — unaffected.
- `backendNodeId` is **internal only** — used to join captures in-process; it is NEVER
  written to disk (session-scoped; also a mild fingerprint). The on-disk sidecar is keyed
  by skeleton `node_id`.

---

## 5. `_theme.py` — pure diff core (new module, no browser, no I/O)

Mirrors `_states.py` / `_style.py`: deterministic, unit-tested; `web_skeleton` wraps it
with the CDP recapture I/O.

```
THEME_PROPS = STYLE_PROPS ∪ {"color", "background-color", "border-top-color"}
```
(the Regime-1 visual prop set + the three colors the `_node_colors` model holds; a subset
of `WANT_STYLES`, so every value is present in a record's raw `style` map. Pure-geometry /
sizing props — `width`/`height`/`display`/`box-sizing` — are excluded: theme conditions
don't visually restyle via those, and a `display:none` toggle is handled by drop-on-miss,
not by diffing `display`.)

```
diff_theme(base_raw_by_backend, cond_raw_by_backend, universe) -> {backendNodeId: {prop: cond_value}}
```
- For each `backendNodeId` present in `base_raw_by_backend`:
  - if absent from `cond_raw_by_backend` → **drop** (node not laid out under the condition;
    §9 ceiling). Never reattach.
  - else for each `prop` in `universe`: `computedStyles` always resolves every requested
    prop for a laid-out node, so both raw maps carry every `THEME_PROP` — the compare is a
    plain `base[prop] != cond[prop]`; emit `prop: cond_value` **only when they differ**.
    This catches changes in BOTH directions because a "reset" is just a value change (e.g.
    `box-shadow` `"rgb(...) ..."` → `"none"`, or `"none"` → a real shadow).
- Emits nothing for a node with no changed prop (sparse).

`rekey_by_node_id(delta_by_backend, node_backend) -> {node_id: {prop: val}}` inverts
`node_backend` ({node_id→backend} → {backend→node_id}) and re-keys; a backend with no
matching node_id is dropped (defensive; shouldn't happen since base drives both).

The `web_skeleton` orchestrator assembles
`_node_theme = {node_id: {condition_label: {prop: raw_value}}}` across the conditions.

---

## 6. Redaction (`_style.py`)

`redact_theme(themes)` mirrors `redact_pseudo` — for each condition's `{prop: value}`:
`content` → `redact_content_value`; every other prop → `redact_style_value`
(external/data `url()` → `url("<asset>")`; same-doc `url(#frag)`, gradients, shapes, raw
`rgb()` colors kept). None/empty-safe. Idempotent.

`content` is included in the routing only as a safety belt: theme deltas are computed on
**element** nodes (pseudo-elements are not emitted as standalone nodes), where `content`
resolves to `normal` and never produces a delta — but routing it correctly costs nothing
and prevents a future regression. **No new content vector is introduced** beyond Regime-2's
already-handled `content`.

---

## 7. Bundle integration (`bundle_writer.py`)

- `apply_node_theme(nodes, node_theme)` mirrors `apply_node_pseudo`: for each int node id,
  `n["theme"] = _style.redact_theme(tv)`. Runs **before** `cf.redact_node` (so the already-
  redacted nested map survives — `theme` is not a `CONTENT_KEYS` entry).
- `assemble(..., node_theme=None)` calls `apply_node_theme` after `apply_node_pseudo`.
- `main` pops `_node_theme`, int-keys it (str→int, JSON has no int keys), passes
  `node_theme=...`. `web_skeleton._snapshot_skeleton`/orchestrator sets
  `sk["_node_theme"] = {str(k): v for k, v in node_theme.items()}`.

## 8. Firewall (`content_firewall.py`) — UNCHANGED

`theme` is not added to `CONTENT_KEYS`, so `redact_node` keeps the nested (already-redacted)
map; `audit_bundle` `_walk_strings` recurses into `node.theme[condition][prop]` as the
independent backstop. A new canary test asserts an un-redacted external `url()` in a theme
delta trips `ContentLeak`.

---

## 9. Ceilings (documented, honest)

- **Visibility / structural theme deltas NOT captured.** Any node absent from a condition's
  layout — whether by `display:none` from an `@media` rule, OR by theme-triggered JS that
  mutates the DOM (re-created node → different `backendNodeId`) — is **dropped on miss**
  (style-only first cut). The node persists in the base skeleton; only its per-condition
  style delta is omitted. (Parallels the Regime-2 show/hide ceiling.)
- **`forced-colors: active` deltas are DENSE, not sparse.** `active` remaps nearly every
  color to a resolved system keyword (`Canvas`/`CanvasText`/`LinkText` → rgb) and sets
  `forced-color-adjust` — so most laid-out nodes carry a non-empty delta. This is expected;
  the bundle grows accordingly. Real-site validation (§10) MUST measure forced-colors
  sidecar volume (node-count + total prop-count) so the size impact is known, not silent.
- **Pseudo-element theme deltas NOT captured** (theme diff is element-node-scoped; a dark
  `::before` color change is out of scope for 3a).
- **Palette-token model deferred** — colors stored inline raw (§2).
- **`prefers-reduced-motion` deferred** — a motion concern (gates animations), not a static
  computed-style delta; belongs with motion capture, not 3a.
- Resolved colors are Chrome's single-engine serialization (same as Regime 1/2).

---

## 10. Testing strategy

**Pure-core unit (`test_theme.py`):**
- `diff_theme`: changed prop emitted; unchanged prop NOT emitted; prop default-in-base /
  set-in-cond (appeared) emitted; set-in-base / reset-in-cond (disappeared) emitted;
  node-absent-in-cond dropped; empty delta → node omitted.
- `rekey_by_node_id`: correct backend→node_id mapping; drop unmatched backend.
- `THEME_PROPS` membership (colors present; geometry props excluded).

**Redaction unit (`test_style.py`):** `redact_theme` — external url in a theme delta →
`url("<asset>")`; same-doc `url(#frag)` kept; raw rgb kept; `content` routed through
`redact_content_value`; None/empty safe; idempotent.

**`parse_snapshot` unit (`test_web_skeleton.py`):** `backendNodeId` parsed onto records
(dense parallel); `to_skeleton` returns the 5-tuple with a correct `node_backend` map.

**Bundle unit (`test_bundle_writer.py`):** `apply_node_theme` round-trips a redacted theme
delta to disk under `node.theme`; runs before `redact_node`; survives.

**Firewall unit (`test_content_firewall.py`):** audit passes a skeleton with a redacted
theme delta; canary — un-redacted external url in a theme delta trips `ContentLeak`.

**Synthetic host gate (`fixtures/theme/run_theme.py`, host CDP, `dangerouslyDisableSandbox`):**
a local page with all three `@media` rules. Assertions PROVE JOIN CORRECTNESS, not merely
"deltas appear":
- a node whose color changes under dark gets the **right** delta (expected resolved rgb)
  keyed to the **right** node;
- a node with NO dark rule gets **no** dark delta;
- forced-colors produces deltas on the forced nodes;
- the raw authored color strings do not leak (on-disk values are redacted/rgb-only);
- `write_bundle`'s firewall audit does not raise → **GATE PASS**.

**Real-site validation (one-off, content-free):** a dark-mode-capable public page. Print
ONLY content-free signal: per-condition node-count with a delta + total changed-prop count
(esp. **forced-colors volume**); never a resolved value, selector content, or url. Confirm
`write_bundle` audit CLEAN at scale.

---

## 11. File structure

- **Create:** `scripts/_theme.py` (pure diff core), `scripts/test_theme.py`,
  `fixtures/theme/run_theme.py` (host gate).
- **Modify:** `scripts/web_skeleton.py` (`parse_snapshot` backendNodeId; `to_skeleton`
  5-tuple + `node_backend`; `_snapshot_skeleton`/orchestrator multi-condition recapture +
  base-media pin + `finally`-clear + `_node_theme` sidecar; `--themes` flag);
  `scripts/_style.py` (`redact_theme`); `scripts/bundle_writer.py` (`apply_node_theme` +
  thread through `assemble`/`main`); `scripts/test_web_skeleton.py`,
  `scripts/test_style.py`, `scripts/test_bundle_writer.py`,
  `scripts/test_content_firewall.py` (tests + 5-tuple unpack migration).
- **Docs:** record landing in `docs/plans/probe-runner-engine-capture-gaps.md` (§C9-R-P9)
  and correct `docs/research/css-capture-completeness.md` Regime-3 theme rows.

## 12. Out of scope (explicit)

3b interactive states; 3c responsive viewports; reproduction-side theme application;
palette-token theme colors; pseudo-element theme deltas; visibility/structural deltas;
`prefers-reduced-motion`.
