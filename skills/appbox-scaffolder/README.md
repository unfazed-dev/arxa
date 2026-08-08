The scaffolder skill (plan 03 / dogfood 14.8). Scaffolds app surfaces from a frozen structure.json + target set, emitting the per-surface Dart files that match the target-DERIVED form-factor set. Belongs: the scaffold engine (`appboxd/lib/scaffold.dart` — `appbox emit scaffold`) and its manifest emission. Does not belong: widget bodies (appbox-builder), platform ceremony files (appbox-deployer), design judgement (appbox-reviewer), or the coverage gate that consumes this skill's output (gates/coverage).

## Files

| File | Role |
|---|---|
| `SKILL.md` | The skill. Structure contract, modes, recipe, kind resolution, ownership, verdicts. |
| `SCAFFOLD_playbook.mdx` | Worked procedure and command surface. |
| `feature-recipe.manifest.json` | **Q8 SSOT** — path/naming templates per artifact type. Machine-readable; the golden-expansion probe diffs against it. Shared with `appbox-designer`. *Staged here; final home `kit/showcase_app/`.* |
| `feature-recipe.schema.json` | JSON Schema for the manifest. Travels with it. |
| `kind-resolution.registry.json` | **Q7 SSOT** — designed kind → kit-native widget. Closed vocabulary; unresolvable kind fails loudly. Shared with `appbox-designer`. |

Governing decision log: `docs/plans/designer-scaffolder-grill-decisions.md` (Q1–Q15, locked). It wins over any summary, including this one.

Structure contract: `kit/showcase_app/lib` — the contract, not an example.

**Handoff debt:** Q8 locates the manifest showcase-adjacent at `kit/showcase_app/feature-recipe.manifest.json`. Both refactor agents are read-only on `kit/`, so the single copy lives here; the orchestrator should `git mv` it and rewrite the path references in both skills.
