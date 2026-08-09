# Inputs, deltas and re-enterable phases

How work reaches this skill, and what it is allowed to touch. Binding; derived
from the locked decision log
(`docs/plans/designer-scaffolder-grill-decisions.md`, Q9–Q15).

---

## 1. One authoring surface (Q10)

**`intake/registry.json` (+ `intake/flows.json`) is the only authoring surface
in the pipeline.** It is versioned and pinned by a content-addressed version id.
It carries *all* design instructions, **including seed data**.

The designer **never authors a second source of truth.** Specifically:

- The designer does **not** write `intake/registry.json`. Composers do.
- The designer does **not** receive or write per-feature intake artifacts.
  These were considered and **rejected**: they create a second authoring
  surface, contradicting the derived-delta model.
- The artifact-internal `models/screens_model/registry.json` is **derived** —
  materialized from the run artifact, not authored freehand. It is a
  projection of the pinned registry version into the design medium, and it is
  regenerated, never edited to disagree with its source.

Deltas are **computed by diff between approved registry versions and frozen as
immutable run artifacts under run ids**. The designer consumes the run
artifact. Composers write the registry; composers never write deltas and never
write files.

```
composer → registry patch → (schema validation) → intake/registry.json vN
                                                        │
                              diff(vN-1, vN) → frozen run artifact @ runId
                                                        │
                                        designer ───────┴──→ scaffolder
```

Precedent for the pattern: Copier `.copier-answers.yml` + `copier update`,
OpenSpec's ephemeral `changes/` proposals, Terraform state/plan, oasdiff — one
truth, derived change scope. Flyway/Alembic-style per-change files are a
*journal of applied changes*, not an authoring surface; do not model on them.

### Composer touchpoints (Q14)

Three composers feed the registry: the **intake interview**, **design-update**,
and the **feature-add** entry point in studio UI. All three emit
**schema-validated registry patches only** (strict schema, retry on validation
failure); deterministic code applies valid patches.

There is **no sync mechanism and none is needed**. A design-composer creating a
new view emits an *intake-level* registry patch — the design stage is another
door into the same single authoring surface. Scope changes (new view or
feature) patch intake scope; design-only changes (layout, styling of existing
views) patch design-owned registry sections. Same validation, same gate.

The approval gate fires **only** when the derived diff touches a locked
decision. Routine additive changes are gated by probes alone — this is
deliberate, to avoid approval fatigue. Do not request human approval for
ordinary additive work.

---

## 2. Delta runs: never regenerate what exists (Q9)

There is **no new pipeline stage**. The existing phases —
intake → prototype → design → scaffold → review → build → deploy — are
**re-enterable, scoped to one feature**. Adding a feature after scaffold is a
**feature-scoped delta run**, not a fresh run.

Rules, in force for every delta run:

1. **Already-designed features are never regenerated.** Only the new or changed
   feature is materialized. Existing feature files are left untouched; a
   divergence gate *verifies* them against the last-generated baseline rather
   than rewriting them.
2. **Shared join points are scaffolder-owned and deterministically
   regenerated**: `registry.json`, `app.routes.js` / `app.router.dart`, root
   barrels, locator/DI. Unchanged inputs ⇒ byte-identical entries. Diffs are
   **additive-only**. Idempotence is asserted by a golden probe: regenerating
   with an unchanged feature set is a no-op diff.
3. **Cross-feature touches must be declared in the delta scope.** They go
   through 3-way merge plus human approval. An undeclared cross-feature edit is
   a gate failure, not a convenience.
4. For cross-boundary changes the **LLM proposes** the merge and a
   **deterministic validator applies** it. LLM output is never applied
   unvalidated.
5. Design stays SSOT; the generation-gap boundary (scaffolder-owned vs
   user-owned, declared in the Q8 manifest) is the default seam.

**Idempotence scope.** "Second run byte-identical" applies **strictly to
transliteration output**. Transformation output — LLM-touched, and non-default
— is pinned by its frozen run artifact and re-verified by the non-clobber
verdict, not by byte-identity. Do not claim byte-identity for transformed
surfaces.

---

## 3. Shell taxonomy (Q11)

- **Ceremony shells — four, fixed:** `startup`, `unknown`, `auth`,
  `application`.
- **Design shells — N, project-defined:** every non-ceremony shell. Showcase
  has `home`, `notes`, `profile`, `search`.
- **Splashscreen is *not* a shell.** It is the mobile-device splash surface, a
  brand surface carrying the **logo only**. Do not give it a viewmodel, a
  shell folder, or navigation. Do not count it among the shells.

Surfaces absent from showcase — `auth`, `design`, `splashscreen` — expand from
the Q8 manifest exactly like the synthetic `payments` feature; showcase
instances corroborate `application` / `startup` / `unknown`.

---

## 4. Inspector identity (Q12)

**Identity is stamped at emit time, never inferred at runtime** — the same
principle as Flutter's `--track-widget-creation`.

Every emitted surface carries `inspectAttrs`, derived from registry ids, as the
triple:

```
(screenId, surfaceId, anatomy-node id)
```

Presence is mechanically enforced (Q11 verdict 4) — a surface without the
triple fails the probe. Studio inspect mode reads **the triple only**: hover
tint, tags, and both icon buttons (visually-edit-in-auto-layout, and
add-widget-to-slider-panel composer) key off it. **Zero DOM heuristics.**
Because identity is stamped rather than sniffed, inspect mode survives
regeneration by construction — so never emit a surface without it "just for
now", and never let a class name or DOM position stand in for the triple.

This supersedes the older rule that a viewmodel exports a bare `surfaceId`:
`surfaceId` is now one leg of the triple, not the whole identity.

---

## 5. Live generation (Q15)

Studio renders pipeline progress itself. The Flutter `genui` package / A2UI
stays **out** of the studio viewer — our pipeline is deterministic after the
registry patch. The A2UI *pattern* (constrained catalog, skeleton-then-fill
streaming) is honored studio-natively, and the designer's output is what makes
it possible:

1. Registry patch accepted → viewer renders an **exact accent-tinted skeleton**
   of the new view or tile derived from the patch. The full anatomy is known
   upfront — right slots, right placement, `inspectAttrs`-addressable — so this
   is a real skeleton, **not a generic shimmer**.
2. The pipeline emits progress events per materialized unit —
   `screen-started`, `widget-materialized`, `screen-complete` — over the
   studio's existing stream channel.
3. The viewer swaps each tinted slot for the real widget live as its event
   arrives; the tint clears on `screen-complete`.
4. On mid-run failure, unfilled slots stay tinted — a visual diff of what did
   not materialize.

Practical consequence for this skill: a surface's anatomy must be fully
derivable from the registry patch *before* the surface is materialized. Design
so that slot identity and placement are known from the registry alone.

---

## 6. Parallel-run cutover (Q13)

The new showcase-anatomy design shell is generated **alongside** the current
studio design shell behind a flag. Probes render the same views through both
and diff the results. Cut over **view-by-view**: a view flips to the new shell
only when its probe is green against it; flipping back is a toggle, not a
revert. The old shell is deleted only when every view is flipped and green.

Do not big-bang a migration, and do not remove the old shell early.

---

## Unresolved dependency

The **Q8 path-template manifest** — the machine-readable SSOT that both this
skill and the scaffolder load, mapping artifact-type → path template + naming
template + frontmatter/comment requirements, and classifying every path
scaffolder-owned vs user-owned — is specified to live **showcase-adjacent under
`kit/showcase_app/`**. It did not exist at the time of this refactor and is
outside this skill's edit scope. Until it lands:

- `references/showcase-anatomy.md` is the prose statement of the same contract;
- when the manifest lands, the manifest wins on every path question and this
  skill should be re-pointed at it;
- the golden-expansion probe (expand `payments`, diff produced tree vs
  expansion, extra or missing file = fail, showcase itself must pass) cannot be
  wired until it exists.

## Migration debt (tracked, not fixed here)

The two-tier widget placement law makes some paths in *existing on-disk
artifacts* illegal. These are real files outside this skill's edit scope; docs
still reference them by their true current paths rather than lying about where
they live. They need a Q13-style view-by-view migration:

- `examples/hello-hda/ui/views/main_shell/shared/widgets/lang_switcher.tsx`
  (referenced from `runtime/README.md`) → belongs in
  `ui/widgets/<app>_main_widgets/`.
- `designs/appbox-studio/ui/views/main_shell/shared/widgets/design_viewer.tsx`
  and `designs/appbox-studio/ui/common/` (referenced from
  `DESIGN-ARCHITECTURE.md`) → same migration; the studio shell is itself the
  subject of the parallel-run cutover in §6, so it moves with that work.

Do not cite these paths as precedent for placement. The law is §2 of
`showcase-anatomy.md`; these are pre-law survivors.
