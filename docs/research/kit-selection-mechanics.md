# Kit-selection mechanics — where kit declarations live today, and how a three-point picker could reach scaffold

Mechanical trace for the kit-picker design (intake wishlist → design declarations → scaffold final pick). All citations are file:line in this worktree.

## 1. Where kits are declarable today

**Per-screen, in `registry.json` — the only declaration point that exists.** There is no per-app kits field anywhere in the codebase.

- Schema and rules: `skills/arxa-designer/references/app-architecture.md:53` (table row) and `:55-67` (prose). A registry entry may carry an optional `kits` array of kit dir names, e.g. `"kits": ["maps", "payments"]`. Declared **only** when the surface genuinely needs the module in the built app — never decorative.
- The registry itself (`models/screens_model/registry.json`) is a flat **list of screen entries** (`app-architecture.md:26-39`) — there is no top-level/app-wide object to hang an app-level kits list on without changing the registry's shape from a list to `{screens: [...], kits: [...]}` or similar.
- `config/kit-registry.json` (found at `config/kit-registry.json`, also a stale copy at `archives/tooling-pre-dart/tools/vendor/kit_registry/kit-registry.json`) is the **catalog**, not a selection surface: `version: 1`, `kits: [...]`, each entry `{dir, package, capabilities, backing, topology, phase, playbook, hasSkill, provides}`. It's the validation source of truth a design's per-screen `kits` names are checked against.

**Confirmed: `designs/arxa-studio/` has no kits field anywhere.**
- `designs/arxa-studio/models/screens_model/registry.json` (326 lines) — `grep -i kit` returns **zero matches**. No screen entry declares `kits`.
- `designs/arxa-studio/structure.json` (476 lines) — `grep -i kit` returns **one match**, line 471: `"trigger": "Use kit in design"`. That's flow/UI-copy text (a `flows.json`-derived trigger label for a screen transition), not a `kits` data field. Structurally there is no `kits` key on any screen record or top-level.

## 2. What `emit_structure.dart` carries into `structure.json`, and room for a separate manifest

- `arxa/lib/emit_structure.dart:234-255` — per-screen, reads the optional `kits` list, validates it's a list of non-empty strings, lazy-loads `kitDirs` from `config/kit-registry.json`, and **fails hard** (`FAIL: screen '$sid' declares unknown kit '$name'`) if a name isn't a registered `dir`. What survives the freeze is **only the kit dir-name strings**, attached per-screen — no capabilities/backing/etc. carried through.
- `arxa/lib/scaffold.dart:339` (comment): frozen screen records are `id/comp/shellDir/surface/viewmodel/kits` — `kits` is a first-class but optional field of the frozen contract.
- `arxa/lib/scaffold.dart:510-516` — scaffold's own re-validation of a frozen screen's `kits` is **shape-only** ("the emitter already validated the names against the kit registry; scaffold consumes frozen output"). `kits` is conspicuously **absent** from the required-key list at `scaffold.dart` `_validateFrozen` (`id`, `comp`, `shellDir`, `surface`, `viewmodel` only) — confirming it's optional all the way through.
- **Existing precedent for a manifest beside frozen `structure.json`:** `scaffold.dart:443-451` builds `kitsBySurface` (surface → kit-dir-list map) and writes it into `.shell-structure.json` (`lib/ui/views/.shell-structure.json`, written at `scaffold.dart` in the `scaffold()` entry function, manifest assembled ~line 460-465) — a **derived, scaffold-time artifact separate from `structure.json`**, omitted entirely when no surface declares kits so untouched apps' manifests don't drift (comment at `scaffold.dart:443-444`). This is the mechanism to imitate: it already proves kit data can live in a file the scaffolder writes *after* reading frozen `structure.json`, without the freeze itself needing to change shape.
- `loadStructure()` (`scaffold.dart`, ~line 450-470) only requires `screens` to be a list; it does not care what else is in the JSON. `scaffold()`'s entry logic (`scaffold.dart` ~540-600, matching the requested "556-671" range) filters `frozen` from `screens` where `surface` is non-null and validates required keys — it reads nothing else top-level from `structure.json` besides `screens`. Line ~586 area is inside this filter/validate block, not a separate kits read.
- `arxa/lib/gate_scaffold.dart` (69 KB) is a **structural gate** over the emitted Dart tree (shell/widget-escape rules, S1-S6) — it does not read or validate `kits` at all; it operates on the scaffolded file tree, not on `structure.json` fields.

## 3. Intake capability/requirements section

`designs/arxa-studio/models/intake_model/intake.json` top-level keys: `project, map, brief, moodboard, questionBanks, statuses, files, state, narrative, replies, replyFallback, personas, flows, direction, counts`. **No `capability`, `requirements`, or `kits` field exists.** The only hits for `kit`/`capabilit`/`requirement` (grep, 5 matches) are prose strings inside `brief`/`narrative`/`questionBanks` content — e.g. line 44 `"Surface count + kit-coverage estimate within an hour of signing"`, line 758 `"Kit vendoring from targets + capabilities; dependencyMode config from day one"`. These are copy describing the arxa pipeline itself (this design *is* the arxa-studio tool), not a structured wishlist mechanism a picker could write into.

## 4. Kit dependency data (`config/kit-registry.json`, all 22 entries' `backing` field)

Only two kits declare backing on **another kit** by name:
- `ui_library` → `"core + vendored cupertino_native/m3e forks"` — depends on `core`.
- `data` → `"core + ui_library"` — depends on `core` **and** `ui_library`.

`showcase_app` → `"every kit"` (an integration/reference app, not a normal dependency). All other 19 kits (`core`, `state`, `auth`, `forms`, `permissions`, `media`, `documents`, `notifications`, `analytics`, `payments`, `maps`, `deploy`, `haptics`, `bluetooth`, `wifi`, `support`, `security`, `compliance`, `branding`, `motion`, `i18n`) back onto external packages or "pure Dart" / "zero deps" — no kit-to-kit dependency declared.

**Caveat:** `backing` is a free-text prose string (e.g. `"core + ui_library"`), not a structured list of `dir` values. An automated dependency-auto-include resolver cannot safely machine-parse it today — it would need a new structured field (e.g. `"dependsOn": ["core", "ui_library"]`) alongside or replacing `backing`, or a hardcoded lookup table seeded from this trace (`ui_library→[core]`, `data→[core, ui_library]`).

## 5. Proposed minimal-diff mechanism (summary)

See reply for the ≤150-word summary. Full proposal: add a **`kit-manifest.json`** file living beside `structure.json` (design-root level), written/updated at each of the three touchpoints — intake writes a `wishlist` array, design declarations (registry `kits` per screen, already frozen into `structure.json` unchanged) supply the "declared" set, and scaffold-time reads both plus the registry's `backing` to resolve final + auto-included dependencies, writing the merged result into `.shell-structure.json`'s existing `kits` map (already proven safe at `scaffold.dart:443-451`). `structure.json`'s freeze contract and determinism are untouched — `kit-manifest.json` is an **additional scaffold input**, read the same way `l10n`/`targets`/`derivationPath` already are (extra params to `scaffold()`), not a mutation of the frozen file.
