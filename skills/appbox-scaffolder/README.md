The scaffolder skill (plan 03 / dogfood 14.8). Scaffolds app surfaces from a frozen structure.json + target set, emitting the per-surface Dart files that match the target-DERIVED form-factor set. Belongs: the scaffold engine (`appboxd/lib/scaffold.dart` — `appbox emit scaffold`) and its manifest emission. Does not belong: widget bodies (appbox-builder), platform ceremony files (appbox-deployer), design judgement (appbox-reviewer), or the coverage gate that consumes this skill's output (gates/coverage).

## Files

| File | Role |
|---|---|
| `SKILL.md` | The skill. Structure contract, modes, recipe, kind resolution, ownership, verdicts. |
| `SCAFFOLD_playbook.mdx` | Worked procedure and command surface. |
| `kind-resolution.registry.json` | **Q7 SSOT** — designed kind → kit-native widget. Closed vocabulary; unresolvable kind fails loudly. Shared with `appbox-designer`. |

One more SSOT lives outside this skill, showcase-adjacent, with its schema beside it:

| File | Role |
|---|---|
| `kit/showcase_app/feature-recipe.manifest.json` | **Q8 SSOT** — path/naming templates per artifact type. Machine-readable; the golden-expansion probe diffs against it. Shared with `appbox-designer`. |
| `kit/showcase_app/feature-recipe.schema.json` | JSON Schema for the manifest (draft-07). Sits beside it; the manifest's `$schema` is relative. |

Governing decision log: `docs/plans/designer-scaffolder-grill-decisions.md` (Q1–Q15, locked). It wins over any summary, including this one.

Structure contract: `kit/showcase_app/lib` — the contract, not an example.

**Placement (settled):** Q8 puts the manifest showcase-adjacent so both skills read it from one place; the schema sits beside it and the manifest's `$schema` is relative (`./feature-recipe.schema.json`), so the pair stays valid wherever it sits as long as it stays together. `kind-resolution.registry.json` deliberately stays here — it is scaffolder-owned vocabulary, and `appbox-designer` already points at `skills/appbox-scaffolder/kind-resolution.registry.json`. There is exactly one copy of each; neither skill carries a duplicate.
