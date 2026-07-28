# Per-state component capture — design spec

**Date:** 2026-05-30
**Status:** approved (brainstorm) → implementation plan next
**Roadmap slot:** first item beyond the §C9 fix-ladder (P0–P3 all landed). Continues the
G4 / `web_states` line.

## Goal

`web_states` currently records each driven G4 interaction state as only an appeared-node
*count* plus flat `{role, bbox, z}` descriptors — not enough to reproduce the revealed UI.
This feature records each triggered state as a **reproducible, content-free component**: the
revealed subtree re-rooted as a small skeleton (structure + sizing + layout + font + colors),
annotated with where it mounts on the REST page.

CONTEXT.md principle #3: *a component = States + Transitions*. Today a State is a count; after
this, a State carries its component.

## Why this is small / what it reuses

- The `after` (post-trigger) DOMSnapshot is **already captured** by `_snapshot_skeleton` inside
  the existing per-trigger loop — `diff_skeletons` then throws all of it away except the appeared
  count. This feature stops discarding it. **No extra CDP round-trip.**
- The after-skeleton **already carries the data**:
  - `font` is on text nodes (`to_skeleton`).
  - colors live in the sidecar `after["_node_colors"]` = `{str(node_id): {bg, fg, border}}`
    (attached by `_snapshot_skeleton`, consumed by `bundle_writer.apply_token_refs`).
  - `sizing`, `layout`, `bbox`, `z`, `role`, `parent` are on every node.
- So fork B (per-state tokens) is **reuse, not a new clustering pass** — states share the page
  palette; there is no meaningful per-state palette.

## Chosen approach: (a) compact subtree + mount

Rejected alternatives:
- **(b) flat full-field descriptors** — not reproducible (parent links unresolved). Out.
- **(c) whole after-skeleton + appeared-id list per state** — correct-by-construction but stores
  up to `--max` (8) near-duplicate full-page skeletons in the bundle. Content-free, so no IP
  issue, but heavy and redundant with REST (`skeleton.json`). Fights the tool's compact ethos.

**(a)** keeps only the revealed nodes + the chain up to their mount, re-rooted as a self-contained
mini-skeleton. Compact, a true mountable component, fits the small-pure-core pattern
(`_states` / `_consent` / `_substrate` / `_settle`).

### The orphan problem (advisor catch — the reason (a) needs care)

`diff_skeletons` deliberately **under-counts**: its corner-match rule drops an origin-anchored
full-bleed modal *container* (corner-matched to `<body>`) while keeping its children. Build a
component naively from the appeared SET alone → children whose `parent` id dangles (points at an
excluded container). The component-builder must resolve every node's parent to either another
component node or an explicit `mount` anchor — never a dangling id.

### Honest-ceiling mitigation for the modal case

When a full-bleed modal container corner-matches `<body>`, the walk-up treats it as the **mount**
(its children are the component). We lose the modal box as a first-class component node, BUT the
`mount` record carries `colors`, so the modal's own backdrop bg/fg/border is preserved. The
residual loss is "the modal box is recorded as the mount frame rather than a component node" —
the same honest under-capture direction as `diff_skeletons`, narrowed to near-zero by `mount.colors`.

## Components

### `_states.py` (pure core, browser-free, unit-tested) — additions

**1. Refactor the match predicate (no behavior change):**
Extract the per-node REST-match test currently inline in `diff_skeletons` into a private
`_matches_rest(after_node, rest_nodes, radius)` returning bool (same-box OR corner-reflow).
`diff_skeletons` calls it; its behavior is unchanged and pinned by the existing `test_states.py`
diff tests (regression guard — they must still pass untouched).

```python
def _matches_rest(a, rest_nodes, radius):
    """True if after-node `a` corresponds to a REST node (same element, possibly
    reflowed) — i.e. it is NOT revealed content. (same_box OR corner-reflow), role-gated.
    Extracted verbatim from diff_skeletons so both callers share one definition."""
    ab = a["bbox"]; ac = _center(ab)
    for r in rest_nodes:
        if a.get("role") != r.get("role"):
            continue
        rb = r["bbox"]; rc = _center(rb)
        same_box = (abs(ac[0]-rc[0]) <= radius and abs(ac[1]-rc[1]) <= radius
                    and abs(ab["w"]-rb["w"]) <= radius and abs(ab["h"]-rb["h"]) <= radius)
        reflowed = (abs(ab["x"]-rb["x"]) <= radius and abs(ab["y"]-rb["y"]) <= radius)
        if same_box or reflowed:
            return True
    return False
```

**2. `build_component(rest, after, radius=24.0)`** → component dict or `None`.

Returns `None` when nothing is revealed (mirrors `detect_and_dismiss` returning `None`).
Otherwise:

```
{
  "n_nodes": N,
  "nodes": [
    {
      "id": <component-local 0..N-1, in revealed order>,
      "role": ..., "bbox": {...}, "z": ...,
      "sizing": {...}, "layout": {...},
      "font": {...},                      # text nodes only (carried from after-node)
      "colors": {"bg":..,"fg":..,"border":..},   # from after["_node_colors"][str(after_id)]
      "parent": <component-local id> | null,      # null => a component root
      "mount": {"role":.., "bbox":{...}, "colors":{...}} | null   # roots only; the
                                                                  # REST-matching after-parent
    }, ...
  ]
}
```

Algorithm:
1. `after_nodes = after["nodes"]`; `rest_nodes = rest["nodes"]`; `colors = after.get("_node_colors", {})`.
2. `new = [n for n in after_nodes if not _matches_rest(n, rest_nodes, radius)]`. If empty → `None`.
   `new_ids = {n["id"] for n in new}`.
3. Assign component-local ids: `local = {after_id: i for i, n in enumerate(new)}` (revealed order).
4. For each new node build the component node:
   - copy `role, bbox, z, sizing, layout`; copy `font` if present.
   - `colors = colors.get(str(after_id))` (None-safe → `{}` default fields).
   - `after_parent = n["parent"]` (an after-id or None).
     - if `after_parent in new_ids` → `parent = local[after_parent]`, `mount = None`.
     - else → `parent = None` (root); `mount` = descriptor of the after-node whose id ==
       `after_parent` (`{role, bbox, colors}`), or `None` if `after_parent is None` (doc root).
5. Return `{"n_nodes": len(new), "nodes": [...]}`.

**Invariant (free cross-check):** `new` uses the same predicate (`not _matches_rest`) over the
same `after["nodes"]` as `diff_skeletons`, so `component.n_nodes == n_appeared` for every state.
Asserted in tests; a divergence means the extraction broke `diff_skeletons`.

Notes:
- `after["nodes"]` `id` == list index (guaranteed by `to_skeleton`, which assigns `id = len(emitted)`
  sequentially and sets `parent` to those ids). `build_component` does not rely on positional
  identity beyond what `to_skeleton` guarantees; it looks parents up by id.
- Content-free by construction: every field is geometry / enum / count / design-token color —
  the same fields `skeleton.json` and `tokens.json` already emit. No text content (text nodes
  carry `font` + the upstream `text_len`, never the string).

### `web_states.py` (wiring) — modify the per-trigger loop

After the existing `d = diff_skeletons(pre, after)`:

```python
comp = build_component(pre, after)
states.append({"trigger": tr, "n_appeared": d["n_appeared"],
               "appeared": d["appeared"], "component": comp})
```

- `appeared` / `n_appeared` are **kept** (the count summary + back-compat for any consumer).
- `component` is the additive new key; `None` when nothing revealed.
- Import: `from _states import classify_trigger, diff_skeletons, build_component`.
- Schema stays `probe-states/1` (additive key — settle/consent precedent; `bundle_writer` writes
  `states` wholesale with no field introspection, so no new scan surface).
- The `--out` summary `emit_json` gains `"components_built": sum(1 for s in states if s["component"])`
  (count of states that produced a component; NOT a node total — that would duplicate
  `appeared_total` given the invariant above).

## Forks settled (advisor)

| Fork | Decision |
|---|---|
| A — component shape | (a) compact subtree + mount (this spec) |
| B — per-state tokens | reuse `after["_node_colors"]` + node `font`; no clustering pass |
| C — schema | additive `component` key; **no** bump from `probe-states/1` |
| D — scope | **G4 trigger states only.** REST is `skeleton.json`; the G6 consent overlay stays geometry-only (componentizing it fights G6's honest ceiling) |
| E — capture | reuse the in-hand `after` snapshot; no extra CDP trip |

## Honest ceilings (documented, not bugs)

1. **Origin-anchored full-bleed modal container** collapses into the `mount` frame (its colors
   preserved via `mount.colors`; its box is not a first-class component node). Same under-capture
   direction as `diff_skeletons`; local geometry cannot separate it from a grown `<body>`.
2. **Closed shadow roots / OOPIF** revealed content is unreachable — inherited from
   `_snapshot_skeleton` (open roots are pierced; closed are not, like a cross-site iframe).
3. **One post-click snapshot, no animation timeline.** The component is the settled revealed
   state, not the reveal motion — consistent with `web_states`' existing single-snapshot model
   (motion is `web_anim`'s axis).
4. **Greedy, role-gated match** (inherited from `diff_skeletons`): `_matches_rest` is a count-style
   match, not a bijection. Errs toward marking a node "revealed" only when it has no REST
   counterpart — safe (under-, not over-capture).

## Testing

### Pure-core unit tests (`test_states.py`, browser-free)
- `build_component` simple: one trigger reveals a 3-node subtree under an existing container →
  component has 3 nodes, one root with `mount` = the container descriptor, parent links resolve to
  component-local ids.
- multi-root: two disjoint revealed subtrees (e.g. a menu + a tooltip) → two roots, each with its
  own `mount`.
- modal-collapse: a full-bleed container corner-matched to `<body>` + its children → container is
  NOT a component node, children are roots whose `mount` carries the container's bbox + colors.
- empty → `None` (after == rest).
- colors + font carry: a revealed text node carries `font` and `colors{bg,fg,border}` from the
  after sidecar; a node missing from `_node_colors` gets None-safe color fields.
- `_matches_rest` regression: the existing `diff_skeletons` tests still pass unchanged after the
  extraction (behavior identical).

### Host gate (CDP, host Chrome — controller runs it)
Extend `fixtures/states` (or a sibling `fixtures/component/run_component.py`): an offline page with
a click affordance that reveals a **styled** panel (known bg color + a text child). Run `web_states
--url … --out`, then assert on the emitted `states[0]["component"]`:
- `n_nodes` matches the revealed subtree size,
- every node's `parent` is either a valid component-local id or `null`,
- a node carries the panel's known `colors.bg`,
- a root's `mount` references the panel's container,
- content-free (`bundle_writer` round-trip / `audit_bundle` does not raise on a bundle carrying
  the component).

## Files

- **Modify** `scripts/_states.py` — extract `_matches_rest`, add `build_component`.
- **Modify** `scripts/web_states.py` — import + call `build_component`, add `component` key + summary field.
- **Modify** `scripts/test_states.py` — add `build_component` unit tests; keep diff tests untouched.
- **Create** `fixtures/component/run_component.py` (or extend `fixtures/states/`) — host gate.
- **Update** `.gitignore` — ignore the host gate's `_out.json` if a new fixtures dir is added.
- **Append** results to `docs/plans/probe-runner-engine-capture-gaps.md` (a `§C9-R-P4` style record)
  and a one-line CONTEXT.md note on the State glossary entry, after landing.
