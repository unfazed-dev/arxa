# Arxa Dial — Undo/Redo (Design Mode)

Grilled and confirmed 2026-08-26. Six decisions locked one-by-one; implementation
calls flagged during the grill and accepted with the set.

> ⚠ **SUPERSEDED 2026-09-11** by the grilled edit redesign (see
> `arxa-dial-palettes.md` → "Addendum — the edit redesign"): the persistent
> server-side journal is DELETED (decision 3 of the redesign — undo is a
> session-local inverse stack in the island, depth ~50, dying on reload;
> Revert-to-published is the only global reset). This plan stands as the
> record of the 2026-08-26 decisions it replaced.

## Locked decisions

1. **Scope — persistent draft journal, commit is the barrier.** A per-artifact
   journal beside the draft file. Survives reload and server restart. Undo never
   crosses a commit: before commit the journal owns time travel; after commit,
   git and the `arxa/dial-*` PR own history (revert is a cicd verb, not a dial
   verb). The dial never rewrites git.
2. **Grain — gesture coalescing.** Consecutive edits to the same patch key merge
   into one step until: focus moves to a different target, ~1s idle passes, or
   the edit tier changes. Slider drag = 1 step; typed phrase = 1 step.
3. **Surface — the three Design tiers only** (tokens / element style / text —
   i.e. exactly the Draft Overlay). Author pin-status moves in Feedback Mode are
   excluded: shared state clients watch, reversible by an explicit click.
4. **Commit seam — clear at commit.** The journal dies with the draft it
   shadows, in the same `_commitDraft()` transaction that consumes the overlay.
   Undo immediately after commit does nothing — honest signal that history now
   lives in the PR.
5. **Redo — linear.** A new edit truncates the undone branch. Array + cursor; no
   undo tree.
6. **Controls — both.** Cmd+Z / Shift+Cmd+Z in the island's Author-mode keydown
   path, plus undo/redo arrows in the Design panel whose disabled state shows
   "at the barrier" without a toast.

## Architecture

Single-writer rule: the server owns the journal; the island only *marks step
boundaries* and renders state. Loopback-Author-only, same gate as `/draft`
(locked decision 5 of the dial: clients never see draft state).

### Storage

Sibling JSON next to the draft under `~/.arxa/drafts/`, keyed by artifact
absolute path exactly like the draft (a moved checkout starts fresh — same WIP
law). Never in Supabase, never in the watched artifact tree.

```json
{
  "artifact": "/abs/path/to/artifact",
  "cursor": 3,
  "steps": [
    {
      "id": "j-<uuid>",
      "ts": 1756200000000,
      "tier": "token|el|text",
      "key": "el:hero-cta",
      "before": null,
      "after": { "prop": "background", "value": "#0a4" },
      "gesture": "g-<uuid>"
    }
  ]
}
```

- `before` is the overlay's value for `key` captured at the FIRST write of a
  gesture (`null` = key absent → undo deletes it from the overlay).
- `after` is updated in place while the same `gesture` + `key` keeps writing
  (that IS the coalescing — the server does it, so a lost island timer cannot
  fragment steps).
- Caps: `JournalCaps.steps = 200`, prune oldest-first (never past the cursor
  from above); entry field caps reuse `DraftCaps` values. Malformed journal on
  load → reset to empty (draft stays untouched; journal is derived comfort,
  the draft is the work).

### Server (`arxa/lib/`)

- New `design_journal.dart`: `JournalStore` (file IO, validation, caps) +
  `JournalStep`. Mirrors `DraftFileStore` structure in `design_draft.dart`.
- `arxa_dial.dart` routes, Author-gated like `/draft`:
  - `POST /__dial/draft` — body gains optional `gesture` id. Server captures
    `before` on first write of a gesture, coalesces subsequent same-gesture
    same-key writes, truncates redo tail on any new step.
  - `POST /__dial/undo` and `POST /__dial/redo` — apply `before` / `after` to
    the overlay, move cursor, persist both files, respond with the updated
    overlay patch set + `{undoDepth, redoDepth}` so the island re-applies live
    (no reload — the draft law about not fighting the Author holds).
  - `/draft` GET/POST responses gain `{undoDepth, redoDepth}` so the dock
    arrows are correct from first paint.
- `_commitDraft()` clears the journal in the same operation that consumes the
  overlay. Ship flow (`/ship/*`) untouched — the tandem is the barrier itself.

### Island (`skills/arxa-designer/runtime/vendor/arxa-dial.js`)

- Gesture ids: minted on edit-start per target+tier; rotated on focus change,
  ~1s idle, or tier change. Sent with every draft POST.
- Keydown: extend the existing document-level Author-mode handler — Cmd+Z /
  Shift+Cmd+Z (and Cmd+Y as redo alias). MUST NOT fire while `inlineEditing`
  is active or focus is in a dial input — native text undo wins there.
- Dock: two arrows in the Design panel; enabled state from
  `{undoDepth, redoDepth}`; on response, re-apply returned overlay live.
- Shadow-root/textContent/no-framework laws of ADR-0002 all hold.

### Doctrine interactions (no new decisions, existing law applied)

- **Stale keys:** if source changed underneath (studio redesign) and an undo
  step touches a key that no longer renders, undo still applies to the draft
  data and staleness is reported — Orphaned-edit doctrine; steps are never
  skipped, so Cmd+Z stays deterministic.
- **Every-row-at-once / `el:` binding:** journal keys are draft patch keys;
  application rides `patchAllRendered` unchanged.

## Build order

1. `design_journal.dart` + unit tests (store, caps, coalescing, truncation,
   clear-on-commit).
2. `arxa_dial.dart`: gesture param on `/draft`, `/undo`, `/redo`, depths in
   responses; route tests beside the existing dial tests.
3. Island: gesture minting, keydown, dock arrows, live re-apply.
4. End-to-end: edit → undo → redo → commit → undo-is-empty; reload persistence;
   stale-key undo report.

## Out of scope (named during the grill)

- Client-side undo of any kind (clients never edit).
- Undo of pin status moves.
- History viewer / undo tree.
- Ripping out dormant drawing plumbing (`asDrawing`, `arxa_dial_drawings`
  insert path, 2 migrations) — flagged separately, operator's call.

## Related fix landed with this grill

`docs/VOCABULARY.md` de-staled: Feedback Mode rewritten to pins + replies +
3-state island lifecycle (API tolerates 5), Review Shade marked retired,
draw-over references removed — matching the island's displaced-verbs deletion
list (operator decision).
