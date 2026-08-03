# Scaffolder implementation: entry points, inputs, derivations, outputs, gaps

Scope: the code that turns a frozen design artifact into next-stage output. Two
distinct pipelines exist and are documented separately below — (A) the Flutter
scaffolder (`appbox emit scaffold`), which was the primary subject of this
brief, and (B) the eject/productionize pipeline (`appbox design eject`), which
does not touch Flutter at all. Both are fully implemented; neither is missing.

## 1. Entry points and CLI commands

**Pipeline A — Flutter scaffolder**
- `appbox emit scaffold --design-dir <d> --app-root <a> --targets <t1,t2> [--check] [--self-test]`
  - Dispatch: `appboxd/bin/appbox.dart:606-609` (`case 'scaffold': ... emitStructure(...)` for `emit structure`, and the `emit scaffold` case calling `scaffoldMain(rest)`).
  - CLI parsing: `appboxd/lib/scaffold_cli.dart:21-94` (`scaffoldMain`).
  - Engine: `appboxd/lib/scaffold.dart:556-671` (`scaffold(...)`), a Dart port of `skills/appbox-scaffolder/scaffold.py`.
- `appbox gate scaffold` — validator, not a generator: `appboxd/bin/appbox.dart:352-353` dispatches to `appboxd/lib/gate_scaffold.dart` (`scaffoldGate`, 1126 lines; checks §6/SN/S5/S8/S10/S6c/S0/S1/S4/S2/S6/S7/S9/S3 per its header, lines 12-32).
- `appbox emit structure [--check]` — the producer feeding the scaffolder: `appboxd/bin/appbox.dart:606-609` → `appboxd/lib/emit_structure.dart:377-411` (`emitStructure`), building `structure.json` from the authored htmx layer via `buildStructure` (`emit_structure.dart:37-339`).
- Design doc: `.kimi-code/skills/appbox-scaffolder/SKILL.md` (166 lines) — states the scaffolder "turn[s] a FROZEN design into the per-surface Flutter file set the coverage gate asserts" and explicitly scopes out widget bodies, business logic, and platform ceremony files (lines 74-78).

**Pipeline B — eject/productionize (not Flutter)**
- `appbox design eject <artifact-dir> <out-dir>` — dispatch `appboxd/lib/design_cli.dart:98-99` (`case 'eject': return _emit(designEject(rest));`), implementation `appboxd/lib/design_tools.dart:1208-1303` (`designEject`).
- Doc: `.claude/skills/appbox-designer/built-in-skills/productionize.md` (45 lines).
- This pipeline turns the htmx artifact into a self-contained, hardened, still-htmx production app served by the same Dart design server (`appboxd/lib/design_server.dart`) — it is not a candidate for "the scaffolder" in the Flutter sense and is documented here only to prevent it being mistaken for the missing piece.

## 2. Exact inputs consumed

`emit_structure.dart` (producer of `structure.json`) reads, per its header (lines 1-13) and `buildStructure` body (lines 37-339):
- `models/screens_model/registry.json`
- `models/screens_model/flows.json` (optional)
- `app.routes.js`
- `ui/views/**/*_viewmodel.js`

It validates screen `kits` against `config/kit-registry.json`'s `kits[].dir` set (`_loadKitDirs`, lines 351-368) and screen `states` against a closed vocabulary from `intake.dart`; it rejects `feedback` declared on a screen (edge-only). Final emitted shape (lines 332-338): `{$schema, registry, shellRoots, screens, flows: ?flows}`. Confirmed on the real instance `designs/appbox-studio/structure.json` (476 lines): top-level keys `$schema/registry/shellRoots/screens/flows`, 36 screens (19 with `surface`, 0 with `kits`, 0 with `states`), `flows` present with 3 entries.

`scaffold.dart`'s `scaffold(...)` (lines 556-671) then reads `structure.json` via `loadStructure` (461-486) and:
- consumes **only** `loaded.data!['screens']` (line 586) — per-screen fields `id`, `comp`, `shellDir`, `surface`, `viewmodel`, `deps`, `kits` (validated in `_validateFrozen`, 491-522; expected-file list in `expectFiles`, 526-533).
- **never reads** `data['flows']` or `data['shellRoots']` — confirmed by absence of any reference to those keys anywhere in `scaffold.dart`.
- `deps`/`kits` per screen are recorded only as inert comments in the generated stub files (`_stubView` lines 136-216, `_stubViewmodel` 248-273) — never used to resolve imports or dependencies.

Targets/form-factors: `deriveFactors(targets, derivationPath, configPath)` (`scaffold.dart:62-97`) reads `viewports` (never `ceremonies`) from `pipeline/state/targets.derivation.json`, plus the `viewports` ordering table from `config/appbox.config.json`, resolving `inherits` chains (e.g. `pwa` inherits `web`).

Kit metadata: `config/kit-registry.json` (506 lines, 24 kits) provides `dir, package, capabilities, backing, topology, phase, playbook, hasSkill, provides` per kit. Only `dir` is consulted (by `emit_structure.dart`, for validation) — `package`/`provides` are never read by the scaffolder.

## 3. Automatic derivations vs. configuration

Automatic (no user input beyond `--targets`):
- Form-factor/viewport set per target, via `deriveFactors` (`scaffold.dart:62-97`) — union of a target's own + inherited viewports, ordered by the config table.
- Per-surface directory naming: `<shell>_<short>` from the screen's 2-part `id` (`surfaceDir`, lines 105-113).
- Stub file bodies: `_view.dart`, `_view.<factor>.dart` per derived factor, `_viewmodel.dart`, design-system markdown docs, shell chrome class stub (lines 136-358).
- `.shell-structure.json` manifest content (`buildManifest`, 413-453).
- Optional l10n ARB copy-through if present (`_emitL10n`, 366-406) — copied verbatim, no per-target config.
- Best-effort `MEM-B.md` memory file via `mem_b.dart`.

User-configurable (flags/env, `scaffold_cli.dart:21-94`):
- `--targets` / `APPBOX_TARGETS` — **required explicitly**; the CLI refuses to fall back to ambient pipeline state, citing the "stale-green" defect (lines 62-76 of `scaffold_cli.dart`): "a scaffold run that reads ambient state is the stale-green defect (§16)".
- `--design-dir` / `KIT_DESIGN_DIR` (default `design`) — must stay app-root-relative (R3, lines 79-83).
- `--app-root` / `APPBOX_APP` (default `.`).
- `--check` — drift-check mode instead of write (`_check`, `scaffold.dart:675-767`).

Not configurable at all: screen→surface mapping, factor stub content, manifest shape — these are fully determined by `structure.json` + targets, consistent with the stated principle that "the scaffolder PRODUCES the tree; the gates ASSERT it."

## 4. Outputs emitted

Per surfaced screen, under `lib/ui/views/<shell>_<short>/`:
- `<name>_view.dart` (base StackedView skeleton, busy/error/content branches)
- `<name>_view.<factor>.dart` per derived viewport factor (mobile/tablet/desktop, etc.)
- `<name>_viewmodel.dart` (BaseViewModel skeleton, `refresh()` stub)
- Design-system markdown doc(s) per surface and per shell
- Shell chrome class stub (`_shellChrome`, lines 333-358)

Tree-level:
- `.shell-structure.json` manifest (drift-check baseline for `gate_scaffold.dart`)
- Optional ARB l10n files if a design l10n layer exists
- `MEM-B.md` (best-effort, travels with the delivered app)

Pipeline B (eject, for contrast): `<out-dir>/runtime/vendor/` (narrowed vendor libs + narrowed `manifest.json`, htmx-required hard-fail), `<out-dir>/README.md`, plus a verbatim copy of the artifact's own tree (`design_tools.dart:1229-1303`). No Dart, no Flutter — this path never touches `structure.json` or `scaffold.dart`.

## 5. Gaps — what the scaffold process needs that design output does not currently provide

1. **No navigation/routing is generated.** `structure.json` carries `flows` and `shellRoots` (confirmed present in the real instance, 3 flow entries), but `scaffold.dart` reads only `screens` (line 586) — `flows`/`shellRoots` are silently ignored. Nothing in the emitted Dart tree wires screen-to-screen navigation.
2. **Kit dependency wiring is absent.** `kit-registry.json` kits carry `package` and `provides` (widgets/services) per kit, and screens may declare `kits: [...]` (validated by `emit_structure.dart` against the registry's `dir` set). The scaffolder never reads `package`/`provides` — kit names surface only as inert comments in generated stubs (`scaffold.dart:136-216, 248-273`). No `pubspec.yaml` dependency or import is ever added for a declared kit. This is called out as intentional scope in `SKILL.md` but leaves a manual step with zero tooling support.
3. **Platform "ceremony" files are never emitted by the scaffolder**, despite being declared per-target in `pipeline/state/targets.derivation.json` (iOS Info.plist keys, Android adaptive-icon/splash resources, web `index.html`, PWA manifest+service-worker, macOS Keychain entitlements) and asserted by `gate_coverage.dart`'s C5 check. `SKILL.md` (lines 74-78) explicitly scopes these out as "the deployer/builder's concern." Additionally, `gate_coverage.dart`'s header comment states that for an **htmx producer** (`app.routes.js` at the design root, i.e. the current dogfood shape), coverage "DEFERS the scaffold/ceremony checks (no Flutter layer for an htmx design yet)" — meaning today this gap is not even gated; it is silently skipped.
4. **The SKILL.md "Route table contract" is aspirational, not implemented.** `.kimi-code/skills/appbox-scaffolder/SKILL.md` (lines 80-105) describes a go_router-shaped route compiler reading `intake/registry.json` + `intake/flows.json`, with typed nav actions (`push|replace|back|modal|system`), `requiresAuth` guards, and `tab` data. Grep across `appboxd/lib`, `appboxd/bin`, `appboxd/test` finds `go_router`/`requiresAuth`/`GoRouter` only in `decision_log.dart` and `intake.dart` (which merely validate/record the flags, not compile a route table) — and the real `designs/appbox-studio/models/screens_model/flows.json` only ever declares a `trigger` key on edges, no `action` field. So the design data model does not even carry the shape this contract would need; the feature is fully unimplemented, and its own SKILL.md is currently inaccurate about present-tense capability.

Net: the scaffolder is deterministic and gate-verified for the *view/viewmodel skeleton* layer, but three of its declared responsibilities (navigation, kit dependency wiring, platform ceremonies) are either unimplemented, gate-deferred, or contradicted by the actual data model. Anyone consuming scaffolder output for a real target build must currently hand-wire navigation, pubspec/kit dependencies, and all platform ceremony files themselves.
