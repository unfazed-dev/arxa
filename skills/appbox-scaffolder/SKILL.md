---
name: appbox-scaffolder
description: Use to turn a FROZEN design into the per-surface Flutter file set the coverage gate asserts. Scaffolds app surfaces from structure.json + targets; form factors follow targets (macos -> 3 files/surface, ios/android -> 4), never empty. Trigger on "scaffold the app", "generate the views", "emit the Dart", "why does coverage find no lib/ui/views". Drives `appbox emit scaffold` (the Dart port in appboxd/lib/scaffold.dart).
---

# appbox-scaffolder — produce the Dart tree the gates assert

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

## What you produce (and what you do not)

One engine (`appbox emit scaffold`, Dart in `appboxd/lib/scaffold.dart`) reads `structure.json` + the target set and writes,
per frozen surface, **exactly the derived form-factor file set** (architecture
§16, P06):

| `--targets` | derived factors | files / surface |
|---|---|---|
| `macos` | `desktop` | `_view.dart` + `_view.desktop.dart` + `_viewmodel.dart` = **3** |
| `ios,android` | `mobile, tablet` | `_view.dart` + `_view.mobile.dart` + `_view.tablet.dart` + `_viewmodel.dart` = **4** |
| `web` | `mobile, tablet, desktop` | **5** |

The set is read from `pipeline/state/targets.derivation.json` + config
viewports (P06), **never a per-surface literal**. An empty `.mobile`/`.tablet`
is **never** emitted to satisfy a counter — a file that exists, passes the
check, and is never rendered is the stale-green pattern §16 exists to kill.

It also writes `lib/ui/views/.shell-structure.json` — the manifest the coverage
gate reads (`selfContained` shells + the `{shell: {surfaceId: dir}}` map). The
directory name is a scaffolder **decision** (coverage refuses to guess it);
here it is `<shell>_<short>` from the registry id (the stable key, §18),
recorded so the gate can check it. When a frozen surface declares `kits`
(registry → `structure.json`), the scaffolder records them per surface: a
`//   kits (builder wires): <names>` line in each stub header and a `kits`
entry in `.shell-structure.json`. It records, never acts — the builder wires
the modules.

When the design carries `l10n/*.arb` catalogs (`app_<locale>.arb`), the
scaffolder also copies them verbatim into `lib/l10n/`, drops a fixed-contract
`l10n.yaml` at the app root (gen-l10n; `template-arb-file: app_en.arb`, no
synthetic package), and records `"l10n": {"arbDir", "locales"}` in the
manifest so gates never re-derive the locale set. `--check` asserts the
catalog file set + `l10n.yaml` too. A design with no `l10n/` dir gets **no**
l10n artifacts (backward compat). The pubspec side of l10n
(`flutter_localizations`, `intl`, `flutter.generate: true`) is emitted
unconditionally by `appboxd/lib/blueprint.dart`.

**You do not choose dependencies.** The scaffold never reads or writes a
`pubspec.yaml`; the dependency set arrives from the kit and the app template.
This holds for declared `kits` too — the stub header names them for the
builder, but resolving the actual package deps is the builder's wiring step,
not yours.
That means a dependency which cannot be built for a declared target is not
something you can prevent here — it is caught over the assembled app by
[`gates/native_deps`](../../gates/native_deps/README.md), which asserts that
every plugin is packaged for each target's native toolchain (today: Swift
Package Manager on Apple platforms, where Flutter 3.44 warns that an
unmigrated plugin "will become an error in a future version"). If that gate
fires on an app you scaffolded, the remedy is in its README — do not silence it
by dropping a target.

You do **not** produce: widget bodies, business logic, platform
ceremony files (entitlements, Info.plist — those are the deployer/builder's
concern), or anything that is design. Every emitted file is a **minimal valid
Dart skeleton** carrying the class name the builder implements, marked as a
stub. The builder (plan 08) fills the bodies.

## Route table contract

Besides the file tree, the scaffolder compiles **ONE go_router-shaped route
table** from the project's `intake/registry.json` + `intake/flows.json`
(exact shapes per `appboxd/lib/intake.dart`):

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

## Procedure

1. **Confirm the design is frozen.** `structure.json` must exist and be in sync
   with the authored layer. The scaffold reads it as the frozen input; it never
   re-derives structure. Check:
   ```sh
   KIT_DESIGN_DIR=<design> appbox emit structure --check
   ```

2. **Scaffold, naming the targets explicitly.**
   ```sh
   appbox emit scaffold \
     --design-dir <design> --app-root <app> --targets macos
   ```
   `--targets` is **required** (or `APPBOX_TARGETS` env). The scaffold never
   reads ambient pipeline state for targets — a run that picked up whatever
   targets happen to be in state is the stale-green defect (§16). Widths and
   factor names come from the derivation table + config, never literals (R3).

3. **Verify the tree matches** (drift check, e.g. after a registry edit):
   ```sh
   appbox emit scaffold \
     --design-dir <design> --app-root <app> --targets macos --check
   ```
   `--check` regenerates the expected set in memory and diffs against disk:
   a missing factor file, a stale manifest, or a hand-edited dir is named and
   fails. This is the same file set `gates/coverage` (C1) walks.

4. **Hand off to the builder.** The scaffold is structure; `appbox-builder`
   implements the widget trees and wires services from the `deps` recorded in
   each stub's header. The coverage gate then asserts the scaffolded layer.

## The guardrail, as a test

The engine's self-test is the proof the guardrail holds:
```sh
appbox emit scaffold --self-test
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
- **Reading targets from ambient state.** Pass `--targets` explicitly. A
  reproducibility run that inherits state targets is the stale-green pattern.
