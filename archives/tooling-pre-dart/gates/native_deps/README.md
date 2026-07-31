# native_deps gate

Asserts that every plugin dependency is packaged the way the toolchain of each
**declared target** needs it.

Today that is one live migration: Apple platforms moving from CocoaPods to
**Swift Package Manager**. Flutter 3.44 enables SwiftPM by default and warns per
build that plugins without a `Package.swift` *"will become an error in a future
version of Flutter"*. That warning scrolls past in build output nobody reads —
appbox shipped for months with `flutter_js` in exactly that state, and it was
found by eye, not by a gate.

## What it asserts

| | |
|---|---|
| **ok** | every native plugin for an Apple target resolves as a Swift package |
| **WARN** (exit 0) | plugins lack SwiftPM **but** CocoaPods integration is present — the app builds today; this is migration debt |
| **WARN** (exit 0) | the two detection strategies disagree — reported with both lists |
| **WARN** (exit 0) | SwiftPM is switched off in `pubspec.yaml` — the gate says so rather than reporting health it cannot vouch for |
| **FAIL** (exit 1) | plugins lack SwiftPM **and** there is no CocoaPods fallback — the build is broken now |
| **FAIL** (exit 1) | a declared target this gate does not know |
| **N/A** (exit 2) | no Apple target, or no dependency metadata to read |

The WARN/FAIL split is brief non-negotiable #1 — **red must mean broken**. A
plugin that is merely behind on a migration still builds, so it must not turn
the pipeline red; a plugin that cannot build must.

## Two strategies, deliberately compared

- **S1 (authoritative)** — Flutter's own generated manifest at
  `<plat>/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift`
  lists every plugin it actually resolved as a Swift package. This is the
  toolchain's verdict, written by the toolchain.
- **S2 (cross-check)** — scan `.dart_tool/package_config.json` for a plugin
  shipping `<plat>/*.podspec` with no `Package.swift` under `<plat>/`.

Both run, and **disagreements are reported rather than adjudicated**.
flutter/flutter has an open defect where a plugin with a valid `Package.swift`
still trips the CLI warning when it arrives as a `git:` + `path:` dependency —
and this repo consumes its kit as ~39 git deps, so this is a live possibility.
A difference we cannot settle is information, not breakage.

## What it deliberately does NOT do

- **No Android / Windows / Linux checks.** SwiftPM is Apple-only; Gradle and
  CMake own native packaging there, and neither has a live migration in this
  repo. Non-Apple targets are **reported as out of scope** on every run — never
  silently passed. Inventing checks for problems we have not hit is how a gate
  suite drifts back into vacuous prohibitions.
- **It does not run `flutter pub get`.** A gate is a read-only assertion, and
  `pub get` rewrites `.dart_tool`. Flutter already persists its verdict, so
  re-running it would add a side effect and no information.
- **It does not require a toolchain.** S2 works from files alone; S1 is used
  when the app has been built for that platform.

## Remedy when it fires

Upstream adoption is always the best fix — check for a newer release first, and
open/upvote the plugin's migration issue.

When upstream is stale, vendor the plugin and add SwiftPM support yourself. The
shape (proven once against `flutter_js`, then reverted as premature while the
CocoaPods fallback still builds — this is the recipe to re-apply the day Flutter
enforces the warning) is:

1. Copy the package into `third_party/<name>/`, dropping only non-code bulk
   (examples, docs, media). **Keep every platform directory the pubspec still
   declares a `pluginClass` for** — deleting one fails the first build for that
   platform.
2. Move the native sources to `<plat>/<name>/Sources/<name>/`. For an
   Objective-C plugin, public headers go to
   `<plat>/<name>/Sources/<name>/include/<name>/` — this is the harder variant.
3. Add `<plat>/<name>/Package.swift`. The library product name replaces `_` with
   `-` (`flutter_js` → `flutter-js`), which is what Flutter's generated manifest
   asks for.
4. Re-point the podspec's `s.source_files` at the moved sources so **CocoaPods
   and SwiftPM compile the same files**.
5. Depend on it by `path:` and record upstream version + SHA-256 + the exact
   delta in a `PROVENANCE.md` beside the fork. **Keep `lib/` byte-identical to
   upstream** — a packaging fork is cheap; a behavioural fork is a permanent
   obligation.

Reference: [Swift Package Manager for plugin
authors](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors).

## Why here and not in the scaffolder

`skills/appbox-scaffolder/scaffold.py` emits per-surface Dart only — it never
reads or writes a `pubspec.yaml` and does not choose dependencies (verified, not
assumed). Dependencies arrive from the kit and the app template, so the place to
catch a bad one is over the assembled app, which is what a gate is.

## Usage

```sh
gates/native_deps/native_deps.sh [--targets macos,ios] [app-root]
gates/native_deps/native_deps.sh --self-test
```

`--targets` absent ⇒ read from pipeline state (`state_targets`).
