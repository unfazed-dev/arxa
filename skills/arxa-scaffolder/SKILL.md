---
name: arxa-scaffolder
description: Use when a FROZEN design must become the per-surface Flutter file set the coverage gate asserts. Scaffolds app surfaces from structure.json + targets; form factors follow targets (macos -> 3 files/surface, ios/android -> 4), never empty. Trigger on "scaffold the app", "generate the views", "emit the Dart", "why does coverage find no lib/ui/views". Drives `arxa emit scaffold` (the Dart port in arxa/lib/scaffold.dart).
---

# arxa-scaffolder — produce the Dart tree the gates assert

> Per-skill playbook (the folded canon for this phase): [`SCAFFOLD_playbook.mdx`](SCAFFOLD_playbook.mdx)

## Core principle

> **The scaffolder PRODUCES the tree; the gates ASSERT it.** (architecture §16)

The structure gate checks the authored layer (`registry.json` + `ui/views/**`)
against `structure.json`. The coverage gate checks the scaffolded layer
(`lib/ui/views/**`) against `structure.json` + targets. **This skill is the
missing producer between them** — the one the P14 dogfood named (dogfood-report
14.8 / honest-bar #2): until it existed, no tool turned a frozen design into the
Flutter file set, so "scaffold D1" and "coverage of D1" had no target.

It is the **inverse of the structure gate**: where that gate asserts the tree
matches the registry, the scaffolder emits that tree from a frozen
`structure.json`. What it writes is exactly what `gates/coverage` then walks.

## Pipeline position

Stage 3 of `arxa-orchestrator` (Ø, front door) → `arxa-story-mapper / arxa-moodboarder` (0, optional) → `arxa-intake` (1) → `arxa-designer` (2) → `arxa-scaffolder` (3) → `arxa-builder` (4) → `arxa-tester` (5) → `arxa-reviewer` (6) → `arxa-deployer` (9) — cross-cutting: `arxa-lint` (7), `arxa-lens` (8), `arxa-cicd` (10, day-zero frame wrapping all stages). Stage numbers and every stage's input/output artifacts: `docs/research/pipeline-map.md` §1; the visual map: `docs/arxa-system-map.md`; the CLI FSM phases: `arxa/lib/phases.dart`.

- **Upstream:** `arxa-designer` — a FROZEN `structure.json` + the target set are the inputs; an unfrozen design is never scaffolded.
- **Downstream:** `arxa-builder` — fills the stub tree and wires the `deps`/`kits` recorded in each stub header; the `scaffold` S0–S10 + `coverage` C1–C5 gates (and `arxa-reviewer`'s arch gates) assert what this skill produces.

## Mode: transliteration by default (Q2)

Two modes, and the default is the conservative one.

**Transliteration (default).** The designer's materialized anatomy is already the
app's shape. You carry it across into the showcase structure with kit widgets —
same nodes, same nesting, same order. You are a translator, not an author. If a
node exists in the anatomy, a widget exists in the output; if it doesn't, nothing
appears. This is the mode that makes the output auditable: a reviewer can diff the
anatomy against the tree and see a one-to-one map.

**Transformation (opt-in).** Restructuring — collapsing nodes, hoisting shared
widgets, splitting a surface — happens **only** when explicitly requested, and each
transformation is recorded in the run artifact with the rule that fired. An
unrecorded transformation is indistinguishable from a bug.

Defaulting to transformation would be the seductive mistake: the output would look
more "designed" and would silently stop corresponding to anything the designer
approved. Transliteration keeps the correspondence checkable.

## Inputs: frozen run artifacts (Q10)

Everything derives from versioned `intake/registry.json` through an **immutable run
artifact**. You consume the designer's materialized anatomy plus the registry
version; you never invent scope, and you never re-read live intake mid-run.

The reason is concurrency, not purity: designer and scaffolder run against the same
intake, and a registry that changes underneath a half-finished scaffold produces a
tree that matches no version of anything. The frozen artifact makes a run
reproducible — same artifact id, same bytes out.

If a flow needs something the registry does not declare, that is a **design defect**
to report, not a branch for you to invent.

### The frozen palettes block (palette plane)

When the design ships the palette plane (`docs/plans/arxa-palette-plane-universal.md`,
Q8), the freeze threads the design's `palettes.json` **verbatim** into
`structure.json["palettes"] = {default, palettes}` — the manifest's default id
plus its entries, carried as frozen data. The scaffold reads the block; it never
re-derives palettes and never re-reads the dial store.

**Absent = no plane.** A pre-law `structure.json` has no `palettes` key and
scaffolds exactly as before — the same optionality contract as `flows`,
`theme` and `fonts` (absent, not empty). A missing block is never an error.

At freeze time the freeze **WARNS — advisory, never blocks — when the dial
store's published pick ≠ the manifest default** (the plan, Q8). The read is
best-effort (it fires only when the store is configured; a store that cannot be
read fails nothing) and read-only (the freeze never writes the store). The
warning names both ids because the two diverge in meaning: the live artifact
shows the published pick; the scaffolded app is built from the manifest
default. It changes nothing the freeze writes.

## Procedure

1. **Confirm the design is frozen.** `structure.json` must exist and be in sync
   with the authored layer. The scaffold reads it as the frozen input; it never
   re-derives structure. Check:
   ```sh
   KIT_DESIGN_DIR=<design> arxa emit structure --check
   ```

2. **Scaffold, naming the targets explicitly.**
   ```sh
   arxa emit scaffold \
     --design-dir <design> --app-root <app> --targets macos
   ```
   `--targets` is **required** (or `ARXA_TARGETS` env). The scaffold never
   reads ambient pipeline state for targets — a run that picked up whatever
   targets happen to be in state is the stale-green defect (§16). Widths and
   factor names come from the derivation table + config, never literals (R3).

   When the frozen `structure.json` carries the `palettes` block, the same run
   also emits the app's Tier-1 color vocabulary — from the frozen **DEFAULT**
   palette only (`references/data-vocabulary-assets.md`): each role anchor →
   HCT tonal ramp → theme roles with APCA-picked on-colors, through the DTCG
   path into `lib/ui/common/arxa_kit_app_colors.dart`. The other palettes ride
   `structure.json` as audit trail only — apps never runtime-switch palettes
   (that stays the style/theme axes' job).

3. **Verify the tree matches** (drift check, e.g. after a registry edit):
   ```sh
   arxa emit scaffold \
     --design-dir <design> --app-root <app> --targets macos --check
   ```
   `--check` regenerates the expected set in memory and diffs against disk:
   a missing factor file, a stale manifest, or a hand-edited dir is named and
   fails. This is the same file set `gates/coverage` (C1) walks. When the
   design carries the palettes block, the same discipline also re-renders the
   expected color vocabulary from the frozen default's anchors and diffs it
   against disk — a hand edit is drift and fails, named. The coverage gate
   runs that assertion as its drift check (C6).

4. **Hand off to the builder.** The scaffold is structure; `arxa-builder`
   implements the widget trees and wires services from the `deps` recorded in
   each stub's header. The coverage gate then asserts the scaffolded layer.

## The guardrail, as a test

The engine's self-test is the proof the guardrail holds:
```sh
arxa emit scaffold --self-test
```
It asserts, negatively (R5): a missing `structure.json` fails naming it; a
frozen surface with no viewmodel fails; a wrong file count fails `--check` and
names the missing file; an unknown target fails; two surfaces colliding on one
directory fail. And positively (§16): `macos` derives exactly `[desktop]` and
emits no `.mobile`/`.tablet`; `ios,android` derives `[mobile, tablet]` and emits
no `.desktop`.

## Common mistakes

- **Emitting an empty factor file to satisfy a count.** If the targets do not
  imply a factor, no file for it exists. That is §16's whole point — the
  self-test guards it.
- **Hardcoding widths or factors.** They come from the derivation table +
  config (P06/R3). Adding a target is a data edit to that table, not a code
  change here.
- **Treating the stub bodies as finished.** They are skeletons. The builder
  replaces them; leaving a stub's placeholder `Text` in a shipped app is a
  missed handoff, not a scaffold defect.
- **Editing scaffolded Dart directly.** That creates a second writer and the
  drift check dies. Edit the registry / authored layer, re-freeze, re-scaffold.
- **Hand-editing the emitted color vocabulary.** `arxa_kit_app_colors.dart` is
  scaffolder-owned: regenerated from the frozen default palette, byte-identical
  on unchanged inputs. A hand edit is drift and the drift check fails it. Edit
  the palette at the design, re-freeze, re-scaffold.
- **Emitting from an alternate palette.** The vocabulary comes from the frozen
  DEFAULT palette only — even when the dial store publishes a different pick
  (the freeze's skew warning is the advisory that surfaces that divergence).
  Alternates are audit trail, never app tokens.
- **Reading targets from ambient state.** Pass `--targets` explicitly. A
  reproducibility run that inherits state targets is the stale-green pattern.

## References

Load these situationally — they hold the detailed law, not the every-run path.

- [`references/output-contract.md`](references/output-contract.md) — load when deciding exactly what files/dirs a scaffold run emits: the per-target file-count table, `.shell-structure.json`, l10n handling, the palette vocabulary emission, dependency/native_deps boundaries, the `kit/showcase_app/lib` structure contract (Q1), and the per-surface desktop/mobile/tablet split (Q3).
- [`references/data-vocabulary-assets.md`](references/data-vocabulary-assets.md) — load when touching seed data (Q4), the feature-recipe manifest (Q8), or the design-vocabulary/assets pipeline (Q6): palette-sourced Tier-1 colors, fonts, brand icons, images, the web entrypoint, and layout-token rules.
- [`references/kind-resolution.md`](references/kind-resolution.md) — load when a design node's `kind` needs resolving to a kit widget (Q7), including the escape-hatch and `arxa gate kind_registry` validation.
- [`references/contracts-and-verdicts.md`](references/contracts-and-verdicts.md) — load when checking frontmatter conventions (Q5), the scaffolder-owned vs user-owned generation gap (Q9), inspect-identity stamping (Q12), the five run verdicts (Q11), the frozen palettes block with its skew warning and the coverage gate's drift check, or the go_router route-table compile rules.
- [`references/upstream-integration.md`](references/upstream-integration.md) — load when reasoning about how registry patches arrive from upstream composers (Q14), what to report (Q15), or the studio design-shell parallel-run cutover (Q13).
