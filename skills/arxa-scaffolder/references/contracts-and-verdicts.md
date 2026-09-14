# Contracts and Verdicts

## Frontmatter is normative (Q5)

The semantic library doc comment in showcase files is a contract, not decoration.
Canon: `skills/arxa-builder/BUILDER_playbook.mdx` → *File structure*. Order is
locked, and every file terminates the block with a bare `library;`.

Full kind: layer-intro → role → requirements → relationships → History.
Light kind (models, schemas, enums, consts, barrels): layer-intro → role → History.

You own layer-intro, role and the `History:` line. You leave requirements and
relationships as marked placeholders — those are the builder's. The `History` line is
mechanically derivable (`git log --follow -- <path>`), which is why it is mechanically
gated.

## The generation gap (Q9)

Two ownership classes, and the boundary is declared in the manifest per artifact type:

- **scaffolder-owned** — regenerated every run, byte-identical on unchanged inputs.
  A hand edit here is drift and `--check` fails it.
- **user-owned** — stubbed once, then owned by the builder. Regeneration **never**
  clobbers it.

This needs a persisted baseline, so the first scaffold writes
`pipeline/state/scaffold-baseline.json` (the `.copier-answers` analog): registry
version, run artifact id, target set, and a content hash per emitted file. The
divergence gate checks user-owned files against that baseline, and a 3-way merge uses
it as the common ancestor. Without it, "don't clobber" degrades into "never update",
and the scaffold rots.

Shared join points — barrels, `app.router.dart`, `app.locator.dart`, the shell
structure manifest — are regenerated deterministically with additive-only diffs.

## Inspect identity is stamped, not inferred (Q12)

Every emitted view and widget carries the triple `screenId` / `surfaceId` /
`anatomyNodeId`, stamped **at emit time** from the frozen artifact — the same trick
as Flutter's `--track-widget-creation`.

Studio's inspect mode reads the triple and nothing else: zero DOM heuristics, no
structural guessing. Inspect therefore survives regeneration by construction rather
than by luck.

`screenId` is a verbatim `intake/registry.json` entry id — never a value derived from
a class or file name. `ShowcaseNotesCreateAccountView` carries its shell as a prefix and
belongs to `showcase.createaccount`; convention-matching loses it. That miss is the whole
reason the triple is stamped rather than inferred. `surfaceId` is the surface's own
tree-derived id (`surface.<feature>.<surface>`, or `surface.<feature>.shell` for a shell
view); `anatomyNodeId` is drawn from the CLOSED set at
`kind-resolution.registry.json#/anatomyNodes` (registry v1.3.0).

Note: `kit/showcase_app` was back-stamped at the Q11/Q12 ratification — all 20 view files
carry the triple. Showcase is therefore normative for identity, the golden probe's
showcase corroboration exempts nothing, and a new emit that omits the triple fails
verdict 4 against a showcase that satisfies it.

## Verdicts (Q11)

**Five** verdicts decide whether a run is good — one probe, five verdicts, reusing the
existing `ProbeReport` / `ProbeTarget` plumbing (no new harness). The list is locked;
do not add to it or reorder it:

1. **Golden expansion** — the tree matches the Q8 manifest expansion exactly. Extra or
   missing file = fail.
2. **`dart analyze` clean.**
3. **Second run byte-identical** — **transliteration output ONLY.** Transformation
   output is LLM-touched and is pinned by its frozen run artifact (Q10) and re-verified
   by the non-clobber rule, *not* by byte-identity. Asserting byte-identity on
   transformation output is a misreading of this verdict (Q2↔Q11 audit resolution).
4. **Identity coverage** — every emitted surface carries `inspectAttrs`.
5. **Frontmatter/comment conventions present** — Q5's normative rules, mechanically
   enforced rather than reviewed by eye.

Kit-only vocabulary (no local duplicates; every widget resolves through the kind
registry) is an always-on invariant enforced at emit time by the closed vocabulary —
it is deliberately *not* one of the five verdicts.

The spike runs after **both** skills are refactored, and produces five shells —
`startup`, `unknown`, `auth`, `application` (ceremony shells) + `design` — **plus the
splashscreen**. Surfaces absent from showcase (`auth`, `design`, `splashscreen`) expand
from the manifest exactly like the synthetic `payments` feature; showcase instances
corroborate `application` / `startup` / `unknown`. `splashscreen` is **not a shell**: it
is the mobile-device splash surface, brand logo only. After the spike passes, the rest
of the arxa studio design refactor proceeds (Q13).

## The frozen palettes block (palette plane)

When the design ships the palette plane (`docs/plans/arxa-palette-plane-universal.md`,
Q8), the freeze threads the design's `palettes.json` **verbatim** into
`structure.json`:

```json
"palettes": {
  "default": "<palette id>",
  "palettes": [ { "id", "name", "swatch": ["#…", …], "themeColor", "seeded"? }, … ]
}
```

The block is optional: absent = no plane, valid for pre-law artifacts — the same
optionality contract as `flows` / `theme` / `fonts` (absent, not empty). The
entry shape is the dial manifest's own (`arxa/lib/design_palettes.dart` is its
SSOT): the freeze passes it through, never re-derives it. Validity — the default
resolves, the 3–7 swatch law — is asserted upstream by the design lint's P-gate
(the plan, Q9), not re-litigated here.

**The skew warning.** At freeze time: *"Freeze WARNS (advisory, never blocks)
when the dial store's published pick ≠ manifest default"* (the plan, Q8; the
store row is `arxa_dial_axes.palette` per `docs/plans/arxa-dial-palettes.md`).
Three properties, all law:

- **best-effort** — it fires only when the store is configured; a store that
  cannot be read warns nothing and fails nothing.
- **never blocks** — the freeze's output is byte-identical whether or not the
  warning fires; the warning rides stderr, never the document.
- **read-only** — the freeze never writes the store. Repointing the publish to
  match the manifest (or the manifest to match the publish) is a dial action,
  not a freeze action.

The warning exists because the two ids diverge in meaning: the live artifact
shows the published pick, while the scaffolded app is built from the manifest
default. Surfacing the skew at freeze time makes it a decision, not a surprise.

**The vocabulary file.** The scaffold emits the app's Tier-1 color vocabulary
from the frozen **DEFAULT** palette only, landing at
`lib/ui/common/arxa_kit_app_colors.dart` — the `arxa_kit_app_strings.dart`
pattern: one app-owned vocabulary file beside the verbatim kit copy. It is
**scaffolder-owned** under the generation gap above: regenerated every run,
byte-identical on unchanged inputs; a hand edit is drift. Its header records
provenance — the frozen palette id + its swatch — and carries the law: do not
hand-edit — re-freeze, re-scaffold. The remaining palettes ride
`structure.json` as audit trail only.

**The drift verdict.** The coverage gate's check series gains **C6 — drift**:
re-render the expected vocabulary from `structure.json`'s palettes block and
diff against disk — emitted color tokens must equal the frozen default's
anchors, under the same `--check` discipline as the C1 file-set diff. A
missing file, a stale palette, or a hand edit fails, named. C6 is a gate check,
not a sixth run verdict — the five-verdict list above stays locked.

## Route table contract

Besides the file tree, the scaffolder compiles **ONE go_router-shaped route
table** from the project's `intake/registry.json` + `intake/flows.json`
(exact shapes per `arxa/lib/intake.dart`):

- registry entries: `{id, label, shell, comp, route, surface, states?,
  requiresAuth?, tab?}`
- flows edges: `{from, to, trigger, action}` with typed actions
  `push | replace | back | modal | system`

The compile rules:

- **Typed nav ops only** — `push`, `replace`, `back`; `modal` is a
  presentation flag on the destination, never a fourth verb. `system` edges
  are non-gesture (auth-success, deep-link): they compile to route guards,
  never to buttons.
- **Guards are named predicates** — `requiresAuth: true` entries plus
  `system` edges compile to ONE `redirect`, not per-route copies.
- **Tabs are data** — `tab: true` entries form the bottom-tab shell, in
  registry order.
- **Flow row order is edge-chain order** — a flow's rows appear exactly as
  its edges chain; the table adds no reordering.

One table, derived from the two intake artifacts — a flow needing something
the registry does not declare is a design defect, not a scaffolder branch.
