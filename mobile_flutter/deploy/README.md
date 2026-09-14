# arxa-studio-mobile — deploy

This stage holds store-deployment evidence: fastlane lanes and receipts for
TestFlight/App Store and Play internal/production, plus Shorebird OTA patch
records.

What starts it: a released-green review in `../review/`. The
`arxa-deployer` skill owns the mechanics; stores are production and are
never touched without an explicit go.

## Release readiness (Task 12 Part A, 2026-09-14)

- **Fastlane** lives in `../fastlane/` — `android beta|production` (Play
  internal/production) and `ios beta|release` (TestFlight/App Store) are
  OPERATOR-RUN lanes with credential presence checks that fail clearly and
  print nothing secret. CI (`.github/workflows/mobile-release.yml`) builds,
  validates, checksums — then HALTS at the human deploy gate (HUMAN GATE 3:
  a person confirms target + version + releasing account; CI never mints
  the approval).
- **Android signing**: release inputs come from gitignored
  `android/key.properties` (CI writes it from `mobile-release` environment
  secrets); a release packaging task with absent inputs fails with a clear
  GradleException. Debug builds alone may use the debug key. Contract pinned
  by `../test/android_release_signing_contract_test.dart` and the
  `mobile-signing` area of `scripts/check.sh`.
- **iOS signing**: confirmed against the committed project — team
  `43GNRCGQXQ`, bundle `solutions.arxadigital.arxa.mobile`, automatic signing
  for development. Release signing is match-owned; export options (method
  app-store, manual style) are carried in the Fastfile, so no Xcode tree
  edit was needed. The committed `Runner/Runner.entitlements` pins
  `aps-environment: development` (correct for dev-signed builds); the
  app-store export profile flips it to production at re-sign — never by
  substituting a development signature for a release claim.
- **OTA**: `../shorebird.yaml` is a dormant extension point (empty `app_id`)
  — the migration spec's distribution plan (M5) has no OTA rows; activation
  steps are in that file.
- **Physical-device gates** (iPhone/APNs, Android/FCM/APK): see
  `physical-gates.md` in this directory for exact commands and redaction
  rules; execution is device-gated (Task 16).
