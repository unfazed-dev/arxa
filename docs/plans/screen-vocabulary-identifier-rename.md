# Screen-vocabulary identifier rename (coordinated, ONE commit)

Prose sweep landed 2026-08-08 (27 skill docs, ~155 sites; law + carve-outs in
`SKILL.md`). What remains is **identifier-level** and breaks the ratified probe
contract, so it lands as one coordinated commit with a gate re-run — not
piecemeal.

## Proposed mapping (needs user ratification)

| current | proposed |
|---|---|
| `screenId` (inspectAttrs triple member) | `viewId` |
| `screenIdSource` (recipe manifest) | `viewIdSource` |
| `models/screens_model/` (+ `registry.json` inside) | `models/views_model/` |
| `data-screen-label` (system-prompt.md authoring attr) | `data-view-label` |
| `/design/flows/<flow>/move\|add\|remove/<screen>` (design_server route) | `.../<view>` |
| `screen-started` / `screen-complete` (delta-run events) | `view-started` / `view-complete` |
| `"kind": "screen\|component"` (use-design-system startingPoint enum) | `"view\|component"` |
| `.page` route-handler export convention (`shell.page`, `home.page`) | `.view` |

## Blast radius (verified by grep, 2026-08-08)

- `kit/core/lib/common/appbox_kit_inspect_attrs.dart` + `kit/core/lib/appbox_kit_core.dart`
- `kit/showcase_app/feature-recipe.schema.json`, `kit/showcase_app/lib/ui/common/appbox_kit_inspect_attrs.dart`, showcase views (v1 medium)
- `kit/showcase_app/lib/probe_inspect.dart` — contract v1.3.0 → **v2.0.0** (breaking)
- 3 byte-identical copies of `kind-resolution.registry.json` (`./skills/`, `./.claude/skills/`, `./.kimi-code/skills/`) — must move together or probe/plan cite different vocabularies
- `designs/appbox-studio-v2/models/screens_model/registry.json` + `services/studio_application_services/repositories/studio_application_repository_service.js`
- Doc line `references/app-architecture.md:180` (`data-inspect-screen` — stale vs live `data-inspect-view`, already flagged in task #19 scope)
- v1 (`designs/appbox-studio`?) — **decision needed**: migrate v1 or pin it to contract v1.3.0 and rename v2-forward only.

## Order of operations

1. Ratify mapping + v1 scoping with user.
2. Rename recipe schema + probe + kit inspect_attrs; bump contract to v2.0.0.
3. Rename v2 tree paths/identifiers; regenerate derived registry.
4. Amend skill docs' identifier mentions (the 31 residuals classified 2026-08-08).
5. Sync all three `kind-resolution.registry.json` copies.
6. Re-run gates (lint, lens shoot, lens net, contract suite, inspect probe)
   against the running server; ONE commit only after user review.

## Recorded debts (housekeeping)

- **SSOT gate script missing**: `~/.agents/skills/consultant/scripts/consult.sh`
  does not exist on this machine; skill edits on 2026-08-08 were gated manually
  (twin-copy md5 agreement `.claude/skills/` ↔ `skills/`). Reconcile when the
  consultant skill is restored.
- **`.kimi-code/skills/appbox-designer/`**: untracked in git, 0/43 md files
  match any SSOT state — independently seeded, no merge base. Left untouched.
  Decision pending: delete, or regenerate from SSOT when the kimi harness is
  next used. Until then it serves stale vocabulary.
