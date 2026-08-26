# Output Contract

## What you produce (and what you do not)

One engine (`arxa emit scaffold`, Dart in `arxa/lib/scaffold.dart`) reads `structure.json` + the target set and writes,
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
unconditionally by `arxa/lib/blueprint.dart`.

**You do not choose dependencies.** The scaffold never reads or writes a
`pubspec.yaml`; the dependency set arrives from the kit and the app template.
This holds for declared `kits` too — the stub header names them for the
builder, but resolving the actual package deps is the builder's wiring step,
not yours.
That means a dependency which cannot be built for a declared target is not
something you can prevent here — it is caught over the assembled app by
`arxa gate native_deps` (`arxa/lib/gate_native_deps.dart`), which asserts that
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

- **File structure (canon: `BUILDER_playbook.mdx` → File structure):** every emitted file (view, viewmodel, facade, adapter, repository, widget) carries the semantic library doc comment above `library;` — layer intro → role paragraph → requirements → relationships diagram → history — with locked body sections per kind. Models get the light variant. The scaffolded stubs must include the `library;` directive and a placeholder frontmatter the builder fills in.

## The structure contract (Q1)

`kit/showcase_app/lib` is **the contract, not an example.** Its folder layout,
naming, barrels, comment conventions and frontmatter are what you emit — for every
app, not just showcase-shaped ones. 207 `.dart` files across
`app/ ui/views/ ui/widgets/ services/ data/models/ data/schemas/ enums/`.

Naming is `<app>_<feature>_` almost everywhere. The two structural rules people get
wrong:

- **A barrel is named after its bucket kind, never its directory.**
  `ui/widgets/showcase_notes_widgets/` contains `widgets.dart` — *not*
  `showcase_notes_widgets.dart`.
- **`lib/ui/views` has no barrel.** Views are imported by full path. Do not emit
  `views.dart`; the manifest carries that as a negative assertion so a later run
  can't "helpfully" add one.

Deliberate absences are part of the contract. `payments` is absent from showcase,
which is exactly why it is the synthetic feature the golden probe expands.

## Per-surface split (Q3)

A surface is not one file. Per showcase convention every surface splits into a view
plus its **desktop / mobile / tablet** variants, with the base view acting as the
responsive factor. The manifest's `surface-view` and `surface-view-factor` types carry
this; emit all variants a surface declares, never a single collapsed file.
