# Data, Vocabulary, and Assets

## Seeds and fixtures (Q4)

Seed data lives at **app-root `data/seed/`, not under `lib/`** — and it is the one
bucket where the `<app>_` prefix rule does **not** apply: files are feature-named
(`notes.json`, `notes_folders.json`, `kit_auth_users.json`). The designer's seed mirror
must be *mirror-exact* with these, which is only achievable if both sides use the same
un-prefixed feature naming.

Seeds are a **gated design-time overlay.** They load in design/dev boot and must never
reach a shipped build — un-gated seed data shipping as real user content is precisely
the failure Q4 exists to prevent. `data/generated/` (`supabase_seed.sql`,
`supabase_migration.sql`, `appwrite.tables.json`) is derived from `data/seed/` plus the
schemas and is never hand-edited. `lib/app/app_data.dart` is the data-layer boot that
registers entities + fixtures with `arxa_kit_data`; note that service registration
does *not* live there — it lives in the `@StackedApp` dependencies in `lib/app/app.dart`.

## The feature recipe (Q8)

`kit/showcase_app/feature-recipe.manifest.json` (schema alongside it) is the SSOT for
paths and names — showcase-adjacent, so both skills read it from one place. It is
**machine-readable on purpose**: the golden-expansion probe
diffs a produced tree against an expansion of the manifest, so agreement is checked
mechanically rather than by prose reading.

The designer loads the same file. That is the whole point — a single manifest is why
the designer's output and your output land on the same tree instead of two plausible
trees that have to be reconciled by hand.

A new feature expands deterministically: shell view (+ derived factor variants),
viewmodel, per-surface views/viewmodels, widget bucket, service facade/adapters/
repositories, models, schemas, enums, and every bucket barrel.

**Form factor is derived, never literal.** `--targets` → `pipeline/state/targets.derivation.json`
→ factors. A factor outside the derived set produces **no file**. Emitting an empty
`.mobile`/`.tablet` to satisfy a counter is the stale-green defect: a file that
exists, passes the count, and renders nothing.

**Gate:** showcase itself must pass expansion (modulo the recorded `exemptions[]`).
If it doesn't, the manifest is wrong — not the showcase.

## Design vocabulary: copy from kit, never author (Q6, revised)

Tier 1 — colors, spacing, glyphs, fonts, app constants, strings — is
**kit-owned**: `kit/core/lib/common/` is the single SSOT. The stacked CLI
generates `lib/ui/common/` (including its own `app_strings.dart`) in every new
app; the scaffolder **deletes every stacked-generated file in that folder and
replaces them with a verbatim copy of the kit common set**, plus one app-specific
`arxa_kit_app_strings.dart` (`abxStr`-prefixed `const String` named copy,
e.g. `abxStrNotesEmptyTitle` — the kit carries a generic template of the same
file). App code imports its **own
copy**: `package:<app_package>/ui/common/…` — never
`package:arxa_kit_core/common/…`. The registry keeps kit-canonical paths;
rewrite the package prefix to the app's copy at emit time (one rule, no per-app
registry churn). Showcase demonstrates this end-to-end.

**Hand-authoring or hand-editing any copied vocabulary file is a FAIL** — the
only file with app-authored content is `arxa_kit_app_strings.dart`. Emitting
new `*_colors.dart`, `*_spacing.dart` or `*_ui_helpers.dart` variants is a
**FAIL**, not a style preference — duplicated vocabulary is how a design system
silently forks. The copy is refreshed from kit, never edited in place.

### Assets (ratified v2)

The designer authors the app's `assets/` artifact (intake uploads merged over
the passive SSOT `kit/assets_default/`); the scaffolder's job is a **pure
copy-paste** of that folder into the scaffolded app, then wiring driven ONLY
by `assets.manifest.json`:

- **Fonts:** Google Fonts by name — emit the `google_fonts` package and call
  families from the manifest's font roles (`primary`, `monospace`, …); the
  roles name families from the design's `[data-font]` menu, so the app
  requests exactly what the design's css2 link showed (designer law:
  DESIGN-ARCHITECTURE.md "Fonts (Google Fonts by name)"). No
  font binaries, no pubspec `fonts:` block — UNLESS the manifest declares
  `"source": "file"` (user uploaded a custom brand font at intake), in which
  case emit a real `fonts:` block for `assets/fonts/` instead.
- **Brand icons:** wire `flutter_launcher_icons` (dev-dependency + per-app
  config yaml redirected to `assets/brand-icons/`, master from the manifest's
  `brandIcon`) to derive ALL iOS/Android/web launcher icons. **The config
  yaml update is a MANDATORY step of EVERY scaffold — never skipped, never
  left at a template/default path**: on every scaffold (and every re-scaffold
  after a brand-icon change) the scaffolder rewrites the config to point at
  the app's `assets/brand-icons/` master and re-runs icon generation. A
  scaffolded app whose launcher-icons config still points anywhere else is a
  FAIL. Brand only — UI icons still resolve to kit code glyphs
  (`arxa_kit_glyphs.dart`); a hand-authored per-platform icon set is a FAIL.
  The brand icon is ALSO a runtime asset — apps render it in-app (splash
  screen, startup brand logo) — so `assets/brand-icons/` IS registered under
  `flutter: assets:` and the master gets `abxImgBrandIcon` in the app's
  `arxa_kit_assets.dart`. The derived platform icon files (android/ios/web)
  are generated by the tool and **committed** — derived, never hand-edited.
- **Images:** register `assets/images/` (and any sibling type dirs present in
  the copied folder) in `pubspec.yaml`; emit `arxa_kit_assets.dart` into
  `lib/ui/common/` (app-authored copy of the kit generic template, the
  `arxa_kit_app_strings.dart` pattern): every bundled path is an `abxImg*`
  const and emitted code references the NAME, never a loose path string.

- **Web entrypoint (`web/index.html`):** the stacked-cli/Flutter default is a
  starting point, never the shipped file. On EVERY scaffold the scaffolder
  normalizes `web/index.html` to the reference shape
  (`kit/showcase_app/web/index.html` is canon); leaving the cli default is a
  FAIL. The normalized file carries, in order:
  1. `<base href="$FLUTTER_BASE_HREF">` — untouched, build-injected.
  2. `<meta name="description">` = the app's one-line description; iOS meta
     trio + `apple-touch-icon` → `icons/Icon-192.png` (derived by
     `flutter_launcher_icons` from the brand master); `favicon.png`.
  3. **Font-law wiring**: exactly two preconnects —
     `<link rel="preconnect" href="https://fonts.googleapis.com">` and
     `<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>` —
     mirroring the designer's `base.tsx` pair. No `css2` stylesheet link and
     no self-hosted font files: on web the `google_fonts` package fetches
     binaries from `fonts.gstatic.com` at runtime, the preconnects just warm
     the connection (custom `"source": "file"` fonts ship in the Flutter
     bundle and need no HTML wiring).
  4. `<title>` = the app display name; `manifest.json` link.
  5. `flutter_native_splash:create` web output, kept theme-reactive: the
     `#splash-screen-style` block sets `body` background to the kit surface
     pair — `#F5F0E8` light, `#1C1814` dark via `prefers-color-scheme`
     (uppercase hex, matching the native configs) — and the `#splash`
     `<picture>` carries light/dark srcsets (1x–4x) of the brand splash
     derivative. Splash teardown stays the generated
     `removeSplashFromWeb()` script.
  6. The stock `flutter.js` `loadEntrypoint` bootstrap — no custom loader.

Showcase demonstrates end-to-end: `abxImgShowcaseLogo` →
`assets/images/showcase_logo.png`, the full launcher-icon chain:
`assets/brand-icons/arxa-icon.{png,svg}` (copied from
`kit/assets_default/`) + `flutter_launcher_icons` dev-dep + config yaml +
committed derived platform icons + `abxImgBrandIcon` + `assets/brand-icons/`
registered in `pubspec.yaml`, and the normalized web entrypoint
(`kit/showcase_app/web/index.html`).

**Layout tokens are names, never numbers.** Every layout value arriving in
`design.json` is a kit constant name and is emitted verbatim as that
identifier: `abxPad*` for padding, `abxGap*` for gaps (numeric ladder, no tier
aliases), `abxHug` / `abxFill` / `abxFixed` for sizing modes,
`arxaKitVerticalSpace*` / `arxaKitHorizontalSpace*` for spacers,
`abxButtonHeight*` / `abxDefault*` for role sizes. Emitting a raw numeric
literal where a kit constant exists is a **FAIL**. A value with no matching
constant is a blocker to surface, not a number to inline — new constants are
added to kit deliberately and always carry the `abx` prefix.
`kit/core/lib/utils/formatters/` remains kit-owned with no per-app copy.
