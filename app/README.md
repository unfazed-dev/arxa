# app_box — the macOS desktop app

app_box itself: a chromed Stacked MVVM macOS app, forked from the stacked_kit
showcase app so the chrome, theming and seed data are copied, not written. It
takes a client conversation to a shipped, bespoke Flutter app — designed, gated,
scaffolded and deployed, with the human holding every irreversible decision.

## Run

```sh
cd app
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # regen router/locator
flutter run -d macos
```

The macOS build runs **unsigned** for local dogfood (`macos/Flutter/Flutter-*.xcconfig`
sets `CODE_SIGNING_ALLOWED=NO`). The Keychain Sharing entitlement is in place for
a signed + notarised build; set `DEVELOPMENT_TEAM` in Xcode and remove that line
to produce one.

## Layout

- `lib/app/` — generated app wiring (router, locator) + `app_data.dart` (data boot).
- `lib/services/` — the app's service layer: credentials (Keychain), the pipeline
  runner (shells out, never reimplements), the MCP client (stdio + HTTP+SSE), the
  three gates, the licence precondition, the kit inventory (wired vs stubbed),
  subscription auth, first-run launch.
- `lib/ui/views/` — the 14 product surfaces (brief §4) under a desktop sidebar
  shell (`app_shell`): projects · design · build · ship · chat · settings.
- `assets/config/app_box.config.json` — bundled runtime config (R3: no literals).

## Tests

```sh
flutter test
```

The load-bearing behaviours are unit-tested with scripted seams (no toolchain,
no live MCP server): the pipeline runner's command shape, the MCP JSON-RPC
handshake over both transports, and that an automated agent cannot advance past
any of the three gates.
