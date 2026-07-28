# Regime 3b — interactive states capture (design spec)

**Status:** approved design, pre-plan. Next: `writing-plans` → `docs/plans/regime3b-interactive-states-capture.md`.

**Goal:** Capture, as an additive per-node sidecar, the **resolved style delta** each
element takes under three forced interactive **pseudo-class** states — `:hover`,
`:focus`, `:active` — relative to a default-state base. Content-free, additive, no
reproduction-side parser. Structurally a sibling of Regime-3a: same `backendNodeId`
join, same pure diff core, same redaction/firewall path; the only new axis is the
**per-node forcing mechanism** (`CSS.forcePseudoState`).

**Naming — distinct from G4.** The per-node field is `pseudo_state` (NOT `states`).
A bundle-level `states.json` / `bundle["states"]` artifact ALREADY exists — it is the
**G4 interaction-state** capture (`web_states.py`: click an affordance, diff the
revealed component subtree; fixtures in `fixtures/interaction-state/`). That is a
different concept (JS-event-driven component reveals) at a different level (bundle
artifact, not per-node). 3b captures declarative CSS **pseudo-class** restyle deltas
per node and names them `pseudo_state` (mirrors `forcePseudoState`/`forcedPseudoClasses`,
the exact CDP terms) to keep the two unambiguous. Do not "simplify" `pseudo_state`
back to `states`.

**Where it fits (regime ladder):** Regime 1 (single-snapshot computed-style coverage,
LANDED P6/P7) → Regime 2 (pseudo-elements, LANDED P8) → **Regime 3** (responsive /
theme / interactive): 3a theme/preference LANDED P9; **this is 3b (interactive
pseudo-class states)**. 3c (responsive multi-viewport / `@container`) and Regime-4
(authored-rule / keyframe parse) are separate spec→plan→impl cycles.

---

## 1. Premise (de-risked before design)

A throwaway host CDP probe (`scripts/_probe_forcestate.py`, synthetic local-server
page; deleted after) verified every load-bearing fact the force-all-then-recapture
architecture rests on:

- **F1 — the load-bearing fact: a `CSS.forcePseudoState` flag SURVIVES a fresh
  `DOMSnapshot.captureSnapshot`.** Forcing `["hover"]` on a node with a `:hover` rule,
  then taking a brand-new snapshot, recaptured its `color` as the hover value
  (`rgb(10,20,30)` → `rgb(0,128,0)`; deltas `color`/`background-color`/`outline-color`).
  Without this, force-all-then-recapture collapses; it holds, so the architecture is
  viable.
- **F2 — `DOM.pushNodesByBackendIdsToFrontend` round-trips `backendNodeId` → `nodeId`**
  (6/6 element backends, no zeros). The DOMSnapshot join key maps to the CDP `nodeId`
  that `forcePseudoState` requires.
- **F3 — descendant-combinator restyle works.** Forcing `:hover` on a *parent*
  (`#menu`) restyled a *child* via `#menu:hover .child` in the recapture (child `color`
  → `rgb(123,45,67)`). Force-all therefore captures ancestor-hover-chain patterns a
  leaf-only "interactive nodes" set would miss.
- **F4 — isolation: a node with NO interactive rule gets NO delta** (`#plain`
  unchanged under force-all). Forcing the state on every element does not smear
  deltas across the tree.
- **F1b — `:focus` rings are captured.** Forcing `:focus` produced
  `outline-style`/`outline-width`/`outline-color` deltas — `THEME_PROPS` already
  carries the outline props, so no prop-universe change is needed.
- **F5 — cost.** `forcePseudoState` is **0.21 ms/call** → forcing every node on a
  ~2000-node page costs ~420 ms/state. Force-all is cheap; **no budgeting / node
  subset is needed** (the recapture, one per state, dominates — identical cost
  structure to 3a's O(conditions) recaptures).
- **F6 — pseudo-string support.** This Chrome accepts `hover`, `focus`, `active`, and
  `focus-visible` (the last is a documented future extension; out of 3b scope).
- **F7 — clean teardown.** Clearing (`forcedPseudoClasses: []`) restores the base
  computed style exactly.

**Therefore force every ELEMENT node with the pseudo-class, take ONE recapture per
state, and diff by `backendNodeId`** — the same shape as 3a, with `forcePseudoState`
substituted for `Emulation.setEmulatedMedia`.

---

## 2. Scope (locked)

- **States:** `hover`, `focus`, `active` (user-locked; minimal triad). `focus-visible`
  / form states (`checked`/`disabled`) are deferred (probe confirms `focus-visible` is
  forcible — a clean future add — but YAGNI for this cut).
- **Prop universe:** the diff uses `THEME_PROPS` **verbatim** (the Regime-1 visual prop
  set + `color`/`background-color`/`border-top-color`). No separate `STATE_PROPS`
  constant — it would just equal `THEME_PROPS`. `cursor` is intentionally **deferred**
  (the one relevant prop absent from `WANT_STYLES`; adding it is an append-only future
  change). Reusing `THEME_PROPS` required zero `WANT_STYLES` change (probe F1/F1b
  confirmed outline + color + box-shadow coverage).
- **Sidecar:** additive per-node `pseudo_state` field `{state_label: {prop: raw_value}}`,
  parallel to (and independent of) the 3a `theme` sidecar. Internal carrier key
  `_node_pseudo_state`. Sparse: a node with no delta under any state carries no
  `pseudo_state`.
- **Content-free:** deltas are resolved styles → redacted by the SAME redactor as
  theme before disk; `content_firewall.py` is **UNCHANGED** (no new content vector).
- **No reproduction-side parser.** The sidecar is consumed as-is.

---

## 3. Capture flow & forcing mechanism (the one true difference from 3a)

3a flipped a single GLOBAL `Emulation.setEmulatedMedia`. 3b forces a **per-element**
`CSS.forcePseudoState`, so it needs a `backendNodeId → nodeId` map first.

`capture_with_pseudo_states(ev, engine, url, labels)` (in `web_skeleton.py`, sibling of
`capture_with_themes`):

1. **Base.** `_capture_one(ev, engine, url)` → skeleton + `node_backend`
   ({node_id: backendNodeId}). Then capture ONE base snapshot recs (`_snapshot_recs`,
   §5) and derive both `base_styles = _theme.styles_by_backend(recs)` and the element
   force-set `elem_backends = element_backends(recs)`. No media pinning — states are
   media-independent.
2. **Setup the force map.** `DOM.enable`, `CSS.enable`, `DOM.getDocument({depth:-1,
   pierce:true})` (populates the frontend). `DOM.pushNodesByBackendIdsToFrontend(
   {backendNodeIds: elem_backends})` → build `b2n = {backendNodeId: nodeId}` (skip any
   zero/falsy nodeId defensively).
3. **Per state label** (`forcedPseudoClasses` uses the bare name, no colon):
   - force on **every** element node: `CSS.forcePseudoState({nodeId: nid,
     forcedPseudoClasses: [label]})` for each `nid` in `b2n.values()`;
   - `time.sleep(0.2)` (settle), `cond_styles = _styles_by_backend(ev)` — **identical
     capture params to base** (phantom-diff guard, design §3 of 3a);
   - `delta = _theme.diff_theme(base_styles, cond_styles, THEME_PROPS)`;
   - `per_condition[label] = _theme.rekey_by_node_id(delta, node_backend)`;
   - **clear**: `forcePseudoState({nodeId, forcedPseudoClasses: []})` on every node
     (so the next label starts from a clean base; probe F7).
4. `node_ps = _theme.build_node_theme(per_condition)`; `sk["_node_pseudo_state"] =
   {str(k): v for k, v in node_ps.items()}`.
5. **`finally`:** clear forced state on every element node (leave the operator's tab
   unpolluted — the analogue of 3a's `setEmulatedMedia({features: []})`).

A node that goes `display:none` under a state is **dropped on miss** by `diff_theme`
(absent from `cond_styles`) and never reattached — the same style-only ceiling as 3a.

---

## 4. Join: `backendNodeId` (reused) + element `nodeId` mapping

The cross-capture join key is **`backendNodeId`** — DOMSnapshot-stable across a
base→forced recapture (no navigate; same property 3a relies on), already threaded
through `parse_snapshot` → `to_skeleton` → `node_backend` by 3a (Tasks 1–2, LANDED).
3b adds ONE thing on top: a `backendNodeId → nodeId` map (CDP frontend id), needed
only transiently to issue `forcePseudoState` calls. `backendNodeId` remains INTERNAL
(never written to disk; gate-asserted, §10); the transient `nodeId` is never persisted
either.

---

## 5. Diff core — `_theme.py` REUSED unchanged (no new pure module)

The probe drove `_theme.diff_theme`, `_theme.rekey_by_node_id`, and
`_theme.build_node_theme` **unmodified** to compute the interactive deltas — they are
condition-agnostic (they diff two `{backendNodeId: style}` maps over a prop universe;
they do not care whether the second map came from media emulation or pseudo-forcing).
3b therefore introduces **no new pure-diff module**; `capture_with_pseudo_states` calls
the existing `_theme` functions. `build_node_theme` already produces the exact
`{node_id: {label: delta}}` shape the `pseudo_state` sidecar needs; it is reused
verbatim (its name is historical — it is the generic transpose).

Two small `web_skeleton`-level helpers (snapshot-`tag`-aware, so they belong with the
I/O orchestrator, not in the pure `_theme`):

- `element_backends(recs)` → list of `backendNodeId` for ELEMENT records only (`tag`
  present and not starting with `#`, not a pseudo record, `backend` present).
  `styles_by_backend` keeps text/doc nodes, and `forcePseudoState` rejects
  non-elements with `"Node is not an Element"` — so this element filter is **mandatory**
  for the force set (probe confirmed). Pure over records → unit-testable.
- `_snapshot_recs(ev)` → REST + `DOMSnapshot.captureSnapshot` + `parse_snapshot` → recs
  (factored so the base pass can derive both `base_styles` and `elem_backends` from one
  snapshot). `_styles_by_backend` is refactored to `return
  _theme.styles_by_backend(_snapshot_recs(ev))` — behavior-identical (existing theme
  path + host gate still pass), DRY.

---

## 6. Redaction (`_style.py`) — reuse the theme redactor

The pseudo-state-delta map shape (`{label: {prop: raw_value}}`) is **byte-identical**
to the theme-delta map. Redaction is therefore the same function. To keep
`bundle_writer` call sites self-documenting, add a thin alias:

```python
redact_pseudo_state = redact_theme   # identical {label: {prop: value}} shape;
#                                      # content prop → redact_content_value, else
#                                      # redact_style_value (external/data url() → marker)
```

No new redaction logic, no new content vector. `content` never appears on element
nodes (resolves to `normal`), but is routed through `redact_content_value` as the same
safety belt 3a documents.

---

## 7. Bundle integration (`bundle_writer.py`)

Mirrors `apply_node_theme` exactly (added directly after it):

```python
def apply_node_pseudo_state(nodes, node_ps):
    if not node_ps:
        return
    for n in nodes:
        pv = node_ps.get(n["id"])
        if pv:
            n["pseudo_state"] = _style.redact_pseudo_state(pv)
```

- `assemble` gains a trailing `node_pseudo_state=None` param (the existing `states=None`
  param is the unrelated G4 artifact — do NOT reuse it); calls
  `apply_node_pseudo_state(nodes, node_pseudo_state)` directly after
  `apply_node_theme(...)` and **before** `cf.redact_node`. (`cf.redact_node` filters
  only top-level CONTENT_KEYS; `pseudo_state` is not a CONTENT_KEYS entry, so the nested
  redacted map survives — same as `theme`/`pseudo`.)
- `main`: `raw_ps = skeleton.pop("_node_pseudo_state", {})`; `node_pseudo_state = {int(k):
  v for k, v in raw_ps.items()}` (JSON keys are strings; `n["id"]` is int — the same
  int-cast 3a needs); pass `node_pseudo_state=node_pseudo_state` to `assemble`.
- `_node_backend` is already popped/discarded by 3a's `main`; 3b adds nothing on disk
  but the new per-node `pseudo_state` field.

---

## 8. Firewall (`content_firewall.py`) — UNCHANGED

Pseudo-state deltas are resolved CSS values, redacted by `redact_pseudo_state`
(= `redact_theme`) before the audit, exactly like theme deltas. `CONTENT_KEYS` /
`_PROSE_EXEMPT_KEYS` need no `pseudo_state` entry for the same reason they needed no
`theme` entry: the redactor runs first and the per-prop walk assigns the CSS prop name
as the nearest key. No new content surface → no firewall change. The packaging audit
remains the independent backstop.

---

## 9. Ceilings (documented, honest)

- **Force-all co-occurrence (the chimera ceiling).** Forcing a state on EVERY element
  simultaneously is correct for reading each node's OWN state delta (probe F4
  isolation), but a **multi-node combinator** selector — `.a:hover .b:hover`, or
  `:focus-within` matching an ancestor of a force-focused node — can yield a computed
  style that no single real interaction (one hovered/focused element at a time) would
  produce. Low-frequency; documented, not corrected (correcting it needs per-node
  force+recapture, O(N) recaptures — infeasible). This is the §9 analogue of 3a's
  forced-colors-density note.
- **currentColor ride-along.** Changing `color` under a state cascades to props that
  resolve to `currentColor` (border-\*-color, outline-color) — these appear as extra
  deltas (probe F3). Faithful and benign; not filtered.
- **Drop-on-miss.** A node not laid out under a state (`display:none` toggled by
  `:active`, etc.) is dropped from that state's delta and never reattached
  (style-only; geometry/visibility toggles are out of scope).
- **Single-engine.** Resolved values are Chrome's strings (same ceiling as all
  regimes).

---

## 10. Testing strategy

- **Pure-core unit:** the diff core (`_theme.diff_theme`/`rekey`/`build`) is already
  unit-tested by `test_theme.py` (Regime-3a) and is reused unchanged — no new pure
  module to test. Add focused `test_web_skeleton.py` cases for `element_backends`
  (element tag kept; `#text`/`#document`/pseudo/None-backend filtered) and the
  `--pseudo-states` label validation.
- **Redaction unit:** `test_style.py` — `redact_pseudo_state` is `redact_theme`; add an
  alias-identity assertion (`redact_pseudo_state is redact_theme`) plus one functional
  pass-through (external url → `url("<asset>")`) so the alias can't silently drift.
- **Bundle unit:** `test_bundle_writer.py` — 2 `apply_node_pseudo_state` cases mirroring
  the `apply_node_theme` ones (`pseudo_state` attached for a node with a delta + url
  redacted; absent for a node without; None-safe).
- **Firewall:** `test_content_firewall.py` — one canary that an UNREDACTED prose value
  placed under `node["pseudo_state"]` trips the audit with a prose violation (proves the
  key-aware walk recurses into `pseudo_state`, the genuine structural property — mirrors
  the `theme` prose canary).
- **Host gate (`fixtures/pseudo-state/run_pseudo_state.py`, host CDP):** synthetic
  local-server page; drives `web_skeleton --pseudo-states hover,focus,active` →
  `bundle_writer`. Asserts JOIN CORRECTNESS (the `:hover` node carries the right hover
  color/bg delta; a `:focus` node carries an `outline-*` delta; the `#menu:hover .child`
  descendant carries the combinator delta; a no-rule node carries NO hover/focus/active
  delta — per-state isolation, the analogue of 3a's `#static` check) + the two on-disk
  regression locks (`_node_backend`/`_node_pseudo_state` internal carriers gone; no
  per-node `backend` field — the per-node `pseudo_state` field IS expected). `write_bundle`
  raises on any leak.
- **Real-site validation (`fixtures/pseudo-state/validate_realsite.py`, not in suite):**
  content-free harness — per state, nodes-with-delta count + changed-prop occurrences
  (NAMES + counts only; never values/selectors/urls). Confirms the bundle stays bounded
  and the audit passes on real data.

---

## 11. CLI

`web_skeleton.py --pseudo-states hover,focus,active` (comma-separated; validated against
`PSEUDO_STATES = {"hover","focus","active"}`, parallel to `--themes`/`CONDITION_OVERRIDE`).
Requires a CDP transport (`hasattr(ev, "sess")` guard — `forcePseudoState` is CDP-only;
the WebDriver/Safari path is unsupported, same as `--themes`). The `--pseudo-states`
branch sits beside the `--themes` branch in `main` (an `elif`).
