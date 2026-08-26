# Scaffold shell — whole-system synthesis (from 4 research reports)

Sources: `pipeline-map.md`, `scaffolder-implementation.md`, `kit-system.md`, `arxa-studio-inventory.md`.

## The system picture

1. **The engine already exists and is deterministic.** `arxa/lib/scaffold.dart` (`scaffold(...)` 556-671, `loadStructure` 461-486), `gate_scaffold.dart`, `scaffold_cli.dart` — fully implemented with tests. Input contract: FROZEN `structure.json` (produced by `emit_structure.dart` from `registry.json`) + `--targets` (form factors via `deriveFactors`, scaffold.dart:62-97, reading `viewports` / `pipeline/state/targets.derivation.json`). It never touches `pubspec.yaml` or widget bodies (builder's job).
2. **The studio has zero scaffold surface.** The design.freeze→build.loop edge trigger is literally named "Scaffold" (`flows.json:63-67`) but lands nowhere; freeze approval only flips a session boolean. Build's `run.en.json:58-70` carries scaffold as fixture row 4-of-7 only.
3. **Kit facts.** 24 kits in `config/kit-registry.json`; verification tiers (stub/port-tested/device-verified); anti-rot selftest; only 4/24 have provider seams; kit selection is carried in the frozen structure — detected from the design, not chosen at scaffold time.
4. **Known engine gaps** (shell must not promise these; analyst's section 5, priority order):
   1. Navigation isn't generated — `scaffold.dart:586` reads only `screens`; `flows`/`shellRoots` silently ignored.
   2. Kit wiring is inert — kit-registry's `package`/`provides` never consulted; declared `kits` surface only as comments, no pubspec/import wiring.
   3. Platform ceremonies (Info.plist, Android icons, PWA manifest/SW, macOS entitlements) declared in `targets.derivation.json`, asserted by `gate_coverage.dart` C5 — but scaffold.dart emits none, and gate_coverage currently defers those checks, so the gap is uncaught.
   4. SKILL.md's "route table contract" (go_router from typed nav actions) does not exist in code; `flows.json` schema (only `trigger`) cannot represent it.
5. **Two output pipelines exist**: `arxa emit scaffold` (Flutter, the one that matters here) and `arxa design eject` (`design_tools.dart:1208`, non-Flutter htmx hardening).

## Consequences for the shell design

- **Overrides are structurally impossible at scaffold time.** The engine reads only frozen `structure.json` + `--targets`. Changing the kit set means unfreezing and returning to design. The override question dissolves: the only genuine scaffold-time parameter is **targets**.
- **A "plan" can be exact, not speculative.** Determinism + `--check` drift mode means the plan screen can show the real file/surface manifest, not an estimate.
- **The shell is thin by nature:** derived-plan review (read-only) → targets confirm → run progress → hand-off to build.loop.

## Open question (in grilling)

Whether scaffold.run is a dedicated screen or reuses build.loop's existing timeline row.
