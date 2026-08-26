/// Deploy port for arxa_kit apps — fastlane, shorebird, Vercel, and
/// Cloudflare Pages/Workers targets behind a testable process-runner port.
/// Standalone pure Dart: no flutter/stacked/arxa_kit dependency.
library;

export 'src/arxa_kit_deploy_service.dart';
export 'src/arxa_kit_deploy_target.dart';
export 'src/models/arxa_kit_deploy_config.dart';
export 'src/models/arxa_kit_deploy_result.dart';
export 'src/process/arxa_kit_process_runner.dart';
export 'src/targets/arxa_kit_cloudflare_pages_target.dart';
export 'src/targets/arxa_kit_cloudflare_workers_target.dart';
export 'src/targets/arxa_kit_fastlane_target.dart';
export 'src/targets/arxa_kit_shorebird_target.dart';
export 'src/targets/arxa_kit_vercel_target.dart';
