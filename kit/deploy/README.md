# arxa_kit_deploy

Deploy port for arxa_kit apps. External CLIs run through a
`ArxaKitProcessRunner` port, so every command shape is unit-tested with
`ScriptedArxaKitProcessRunner` — no toolchain needed in CI.

Pure Dart and standalone: no flutter, stacked, or arxa_kit dependency.

## Targets

| Name | Backend | Status |
| --- | --- | --- |
| `fastlane-android` / `fastlane-ios` | `bundle exec fastlane <platform> <lane>` | **Wired** |
| `shorebird-release` | `shorebird release <platform> [--flutter-version=X]` | **Wired** |
| `shorebird-patch` | `shorebird patch <platform> [--release-version=Y]` | **Wired** |
| `cloudflare-pages` | `flutter build web --release` → `wrangler pages deploy build/web --project-name=<n>` | **Wired** |
| `cloudflare-workers` | `wrangler deploy` (from the working directory's `wrangler.toml`) | **Wired** |
| `vercel` | `flutter build web --release` → `vercel deploy build/web --prod --yes` | **Wired** |

`vercel` reads `VERCEL_TOKEN` from `ArxaKitDeployConfig.environment`. Vercel CLI
v55+ tightened non-interactive project linking — pin a CLI major version
(`doctor` reports `vercel --version`) and set `VERCEL_ORG_ID` /
`VERCEL_PROJECT_ID` to link non-interactively.

`cloudflare-workers` needs `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID`
and a `workingDirectory` containing the Worker's `wrangler.toml` (there is no
flutter build step); it fails with `ok: false` when `workingDirectory` is
null.

## Usage

```dart
import 'package:arxa_kit_deploy/arxa_kit_deploy.dart';

const runner = ArxaKitIoProcessRunner();
final service = ArxaKitDeployService(targets: [
  const ArxaKitShorebirdTarget(runner, mode: ArxaKitShorebirdMode.release),
  const ArxaKitCloudflarePagesTarget(runner),
]);

final config = ArxaKitDeployConfig(
  projectName: 'showcase',
  flutterVersion: '3.24.0',
  dartDefines: {'ENV': 'prod'},
  environment: {'CLOUDFLARE_API_TOKEN': token},
);

final checks = await service.doctor(config);   // preflight
final result = await service.deployTo('cloudflare-pages', config);
```

CLI: `dart run arxa_kit_deploy doctor` /
`dart run arxa_kit_deploy deploy cloudflare-pages --project-name=showcase`.

## Testing

```dart
import 'package:arxa_kit_deploy/arxa_kit_testing.dart';

final runner = ScriptedArxaKitProcessRunner(script: {
  'flutter build web': ArxaKitProcessResult(exitCode: 1, stderr: 'boom'),
});
// runner.commandsRun / workingDirectories / environments record each call.
```

Targets never throw on tool failure — they return
`ArxaKitDeployResult(ok: false, failureReason: ...)`.

## Live smoke

`test/live_smoke_test.dart` is an opt-in harness that proves the CLI + token
path against the real providers. Without credentials every test skips, so CI
is unaffected. To run it, set the tokens (via
`arxa credentials set VERCEL_TOKEN` + re-export, or directly):

```sh
export VERCEL_TOKEN=…                       # vercel
export CLOUDFLARE_API_TOKEN=…               # cloudflare-pages + cloudflare-workers
export CLOUDFLARE_ACCOUNT_ID=…              # cloudflare-pages + cloudflare-workers
dart test test/live_smoke_test.dart
```

Per target it asserts `doctor()` is all-ok, then does a REAL deploy of a tiny
fixture — preview/non-prod only: vercel without `--prod`, Pages to a
throwaway `arxa-smoke-<timestamp>` project on a `smoke-preview` branch, and
an unrouted Worker. These create real preview deployments on your account —
delete them afterwards in the Vercel / Cloudflare dashboard (vercel preview
deployments and workers are both deletable).

