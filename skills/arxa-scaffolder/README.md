The scaffolder skill (plan 03 / dogfood 14.8). Scaffolds app surfaces from a frozen structure.json + target set, emitting the per-surface Dart files that match the target-DERIVED form-factor set. Belongs: the scaffold engine (`arxa/lib/scaffold.dart` — `arxa emit scaffold`) and its manifest emission. Does not belong: widget bodies (arxa-builder), platform ceremony files (arxa-deployer), design judgement (arxa-reviewer), or the coverage gate that consumes this skill's output (gates/coverage).

## Files

| File | Role |
|---|---|
| `SKILL.md` | The skill. Structure contract, modes, recipe, kind resolution, ownership, verdicts. |
| `SCAFFOLD_playbook.mdx` | Worked procedure and command surface. |
| `kind-resolution.registry.json` | **Q7 SSOT** — designed kind → kit-native widget. Closed vocabulary; unresolvable kind fails loudly. Shared with `arxa-designer`. |
| `arxa gate kind_registry` | **Q7 check, promoted to a gate** (`arxa/lib/gate_kind_registry.dart`; rides `gate --all` + CI). Asserts the registry covers the partials vocabulary exactly, targets real kit classes, names every `widget:null` shape in `resolution.order`, carries no duplicate kind keys, and closes the Q12 inspect-identity set. Run after any registry edit. |
| `scripts/validate-registry.py` | The Python original — now superseded by the gate above; kept as the port's reference implementation. |

One more SSOT lives outside this skill, showcase-adjacent, with its schema beside it:

| File | Role |
|---|---|
| `kit/showcase_app/feature-recipe.manifest.json` | **Q8 SSOT** — path/naming templates per artifact type. Machine-readable; the golden-expansion probe diffs against it. Shared with `arxa-designer`. |
| `kit/showcase_app/feature-recipe.schema.json` | JSON Schema for the manifest (draft-07). Sits beside it; the manifest's `$schema` is relative. |

Governing decision log: `docs/plans/designer-scaffolder-grill-decisions.md` (Q1–Q15, locked). It wins over any summary, including this one.

Structure contract: `kit/showcase_app/lib` — the contract, not an example.

**Placement (settled):** Q8 puts the manifest showcase-adjacent so both skills read it from one place; the schema sits beside it and the manifest's `$schema` is relative (`./feature-recipe.schema.json`), so the pair stays valid wherever it sits as long as it stays together. `kind-resolution.registry.json` deliberately stays here — it is scaffolder-owned vocabulary, and `arxa-designer` already points at `skills/arxa-scaffolder/kind-resolution.registry.json`. There is exactly one copy of each; neither skill carries a duplicate.
