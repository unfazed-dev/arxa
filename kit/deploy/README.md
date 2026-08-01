# appbox_kit_deploy

Deploy port for appbox_kit apps. External CLIs run through a
`KitProcessRunner` port, so every command shape is unit-tested with
`ScriptedProcessRunner` — no toolchain needed in CI.

Pure Dart and standalone: no flutter, stacked, or appbox_kit dependency.

## Targets

| Name | Backend | Status |
| --- | --- | --- |
| `fastlane-android` / `fastlane-ios` | `bundle exec fastlane <platform> <lane>` | **Wired** |
| `shorebird-release` | `shorebird release <platform> [--flutter-version=X]` | **Wired** |
| `shorebird-patch` | `shorebird patch <platform> [--release-version=Y]` | **Wired** |
| `cloudflare-pages` | `flutter build web --release` → `wrangler pages deploy build/web --project-name=<n>` | **Wired** |
| `cloudflare-workers` | `wrangler deploy` (from the working directory's `wrangler.toml`) | **Wired** |
| `vercel` | `flutter build web --release` → `vercel deploy build/web --prod --yes` | **Wired** |

`vercel` reads `VERCEL_TOKEN` from `KitDeployConfig.environment`. Vercel CLI
v55+ tightened non-interactive project linking — pin a CLI major version
(`doctor` reports `vercel --version`) and set `VERCEL_ORG_ID` /
`VERCEL_PROJECT_ID` to link non-interactively.

`cloudflare-workers` needs `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID`
and a `workingDirectory` containing the Worker's `wrangler.toml` (there is no
flutter build step); it fails with `ok: false` when `workingDirectory` is
null.

## Usage

```dart
import 'package:appbox_kit_deploy/appbox_kit_deploy.dart';

const runner = IoProcessRunner();
final service = KitDeployService(targets: [
  const ShorebirdTarget(runner, mode: ShorebirdMode.release),
  const CloudflarePagesTarget(runner),
]);

final config = KitDeployConfig(
  projectName: 'showcase',
  flutterVersion: '3.24.0',
  dartDefines: {'ENV': 'prod'},
  environment: {'CLOUDFLARE_API_TOKEN': token},
);

final checks = await service.doctor(config);   // preflight
final result = await service.deployTo('cloudflare-pages', config);
```

CLI: `dart run appbox_kit_deploy doctor` /
`dart run appbox_kit_deploy deploy cloudflare-pages --project-name=showcase`.

## Testing

```dart
import 'package:appbox_kit_deploy/testing.dart';

final runner = ScriptedProcessRunner(script: {
  'flutter build web': KitProcessResult(exitCode: 1, stderr: 'boom'),
});
// runner.commandsRun / workingDirectories / environments record each call.
```

Targets never throw on tool failure — they return
`KitDeployResult(ok: false, failureReason: ...)`.
