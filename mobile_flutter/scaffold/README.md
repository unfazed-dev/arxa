# arxa-studio-mobile — scaffold

This stage holds the Flutter scaffold evidence: `structure.json`, the emit
manifest, and per-surface coverage records. The Dart itself lands in the
app dir's `lib/ui/views/` — the app-dir root IS the Flutter project
(pubspec.yaml, `flutter run` from there), so tooling sees a normal project.

What starts it: a frozen design in `../design/`. The `arxa-scaffolder`
skill emits the per-surface file set (3 files/surface for macOS, 4 for
iOS/Android) — never empty stubs.
