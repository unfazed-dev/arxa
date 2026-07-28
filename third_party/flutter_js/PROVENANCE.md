# flutter_js — vendored fork

**Upstream:** [`flutter_js` 0.8.7](https://pub.dev/packages/flutter_js/versions/0.8.7)
(published 2026-01-27, the latest release as of 2026-07-28)
**Archive:** `https://pub.dev/api/archives/flutter_js-0.8.7.tar.gz`
**SHA-256:** `046428059ac7bef71e305dc35fc24be933b684684a43e83eab7ebd0dc407ad85`
**Upstream repo:** https://github.com/abner/flutter_js
**Licence:** unchanged, see `LICENSE`.

## Why this is vendored

Upstream has not adopted **Swift Package Manager**. pub.dev tags 0.8.7
`is:darwin-legacy-native-build`, and Flutter names `flutter_js` in its list of
plugins with an open migration request.

Flutter **3.44 enables SwiftPM by default**, so every `flutter analyze` and
`flutter build macos` printed:

> The following plugins do not support Swift Package Manager for macos:
> `flutter_js` — This will become an error in a future version of Flutter.

CocoaPods remains supported in maintenance mode, so nothing was broken *today*
— the build fell back to CocoaPods for this one plugin. **Note the CocoaPods
trunk going read-only on 2026-12-02 is *not* the driver:** Flutter plugin pods
are local `:path` pods, not registry pods, so the registry freeze does not
affect them. The driver is Flutter's own schedule — warning now, error later.

`flutter_js` was the **last** unmigrated plugin in this app. With the fork in
place `flutter pub get` now reports *"All plugins found for macos are Swift
Packages"* across all 26 plugins.

## The entire fork delta

Three changes, all confined to `macos/`. Nothing else was authored.

| Change | Path |
|---|---|
| **moved** | `macos/Classes/FlutterJsPlugin.swift` → `macos/flutter_js/Sources/flutter_js/FlutterJsPlugin.swift` |
| **added** | `macos/flutter_js/Package.swift` |
| **edited** | `macos/flutter_js.podspec` — `s.source_files` now points at the moved sources, so CocoaPods and SwiftPM compile the *same* files |

Layout and `Package.swift` follow
[Flutter's plugin-author migration guide](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors),
cross-checked against `record_macos` and `package_info_plus`, which ship
migrated Swift/Obj-C packages resolved for this same Flutter version. The
library product is `flutter-js` (a `_` in the plugin name becomes `-`), which is
exactly what Flutter's generated manifest asks for:

```swift
.package(name: "flutter_js", path: "../.packages/flutter_js"),
.product(name: "flutter-js", package: "flutter_js"),
```

`platforms: [.macOS("10.15")]` matches `app/macos/Podfile`; the upstream podspec
still declares 10.11, which SwiftPM would reject against FlutterMacOS's floor.

### What was NOT changed

**`lib/` is byte-identical to upstream** — verified by `diff -r`, and by a
checksum over every file in the tree:

```
upstream lib/ sha256: 199f4cec7e15e4a493bab3c15e5a3d8190e0cf507ffe79315d89ba5d0dbdf86b
fork     lib/ sha256: 199f4cec7e15e4a493bab3c15e5a3d8190e0cf507ffe79315d89ba5d0dbdf86b
```

This matters: the JavaScript path must stay byte-for-byte comparable with the
Node baseline (plan 09's premise). **A future change to `lib/` turns this from a
packaging fork into a behavioural one — don't.**

`android/`, `linux/` and `windows/` are kept untouched even though app_box ships
neither: `pubspec.yaml` still declares a `pluginClass` for each, and deleting the
directories while the declaration stands would fail the first non-Darwin build.

### Removed to keep the tree small (no code, no build coupling)

`example/`, `doc/`, `ios.mp4` (a 1.3 MB demo video). 5.1 MB → 2.1 MB.

## Known gap — iOS is NOT migrated

Only **macOS** has a `Package.swift`. `ios/` still uses `Classes/` + CocoaPods,
and its plugin is Objective-C (`FlutterJsPlugin.m/.h` plus Swift sources), which
is the harder migration — it needs `Sources/flutter_js/include/flutter_js/` and
public headers moved.

**This is a prerequisite of the companion merge** (see
`docs/plans/merge-companion-into-one-flutter-project.md`): the first iOS build
from `app/` will surface the same warning for `flutter_js` on iOS.

## Upgrading

1. Download the new upstream archive and verify its SHA-256 against pub.dev.
2. Re-apply the three-row table above — it is deliberately small enough to redo
   by hand in minutes.
3. Confirm `lib/` matches upstream byte-for-byte again.
4. Re-verify with the commands under "Verification" below.

**Prefer dropping the fork entirely** if upstream ships SwiftPM support: revert
`app/pubspec.yaml` to the hosted dependency and delete this directory.

## Verification

```sh
cd app
flutter pub get      # ⇒ "All plugins found for macos are Swift Packages"
flutter analyze      # ⇒ No issues found; no SPM warning
flutter test         # ⇒ 36 passed, incl. the JSC probe and the
                     #   embedded-vs-Node prototype comparison
flutter build macos --debug   # ⇒ exit 0, no SPM warning
grep flutter_js macos/Podfile.lock   # ⇒ absent: SwiftPM owns this plugin now
```
