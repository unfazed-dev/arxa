# 05 — `emit_structure` reads the registry

**Goal.** `structure.json` becomes a pure function of the authored layer, which
turns on a drift check that is currently **structurally impossible** for an htmx
producer.

**Blocks:** 14. **Depends on:** 04.

## The defect being fixed

`emit_structure` looks for `jsx/app.jsx` and regexes `P2_REGISTRY` out of it. An
htmx producer has no `jsx/`, so it falls back to **filename inference** —
emitting `registry: null` and `tabRoots: {}`. Measured on the reference
producer: **42 registry entries become 37 frozen screens**, and the five with
`surface: null` vanish silently instead of being declared exclusions.

Meanwhile the producer already carries `models/screens_model/registry.json` — a
42-entry list **whose keys are exactly what the regex extracts**. Nothing reads
it.

The drift check is guarded on `[ -f "$DESIGN/jsx/app.jsx" ]`. The gate says so
itself: *"A producer with no jsx/ has no second source to drift from."* This
plan supplies the second source.

## Steps

- [ ] **5.1** Add a second registry source to `tools/emit_structure`: when there
      is no JSX entry point, read `models/screens_model/registry.json`.
      **No regex — it is already JSON.**
- [ ] **5.2** Source `tabRoots` for htmx producers from `app.routes.js`'s
      exported tab-root map (plan 01 step 1.9 makes the designer emit it). A
      producer with no `tabRoots` **fails** — an empty object must no longer
      pass vacuously.
- [ ] **5.3** Join surfaces to viewmodels on the **declared `surfaceId`**, not
      on filename similarity. Measured, a `(tab, short)` join resolves only
      **21 of 37**; the residual is lexical (`giftcards`↔`gift_cards`,
      `productedit`↔`product_edit`) plus genuinely semantic cases
      (`inbox.thread_list` ↔ `inbox/home`).
      **Do not write a normalizer.** It would close ~13 and leave the semantic
      ones failing silently. A missing `surfaceId` is a **hard failure** naming
      the viewmodel.
- [ ] **5.4** Remove the `jsx/app.jsx` guard so the drift check runs for every
      producer that has a registry.
- [ ] **5.5** Implement the drift assertion in `gates/structure/` as
      **regenerate-and-compare**, using `git status --porcelain` semantics.
      `git diff --exit-code` **cannot see new files**, and a producer that adds
      a surface is the expected case.
- [ ] **5.6** Preserve exclusion semantics: `surface: null` **is** the
      exclusion. Do not add a parallel exclusions list — two ways to express one
      fact is the drift this architecture exists to prevent.
- [ ] **5.7** Emit into `structure.json`, per screen: `id`, `tab`, `comp`,
      `shell`, `surface`, plus the resolved `viewmodel` path and its declared
      repository/facade dependencies. The shell mapping is a **pure rename
      table** — measured, `tab → shell` has zero fan-out — so derive it, do not
      hand-maintain it.

## Done-when

1. Running the emitter against the reference htmx producer yields non-null
   `registry` and a **non-empty `tabRoots`**.
2. All declared screens resolve; **zero** unmatched. Removing one `surfaceId`
   makes it fail and name that viewmodel.
3. The count is reconciled: registry entries = frozen screens + `surface: null`
   exclusions, and the gate **prints the exclusion list** rather than silently
   dropping it.
4. Hand-editing `structure.json` by one character makes `gates/structure/` fail.
5. **Adding** a new surface file also makes it fail until the registry declares
   it — proving porcelain semantics, not `git diff`.
