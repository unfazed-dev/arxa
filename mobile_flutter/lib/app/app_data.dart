import 'package:arxa_kit_cairn/arxa_kit_cairn.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';

import '../data/approvals/approval.dart';

/// Data-layer boot. Called once from `main()` after `setupLocator()`.
///
/// Cairn is the v1 backend (settled decision) — no seed fallback.
/// `ArxaKitCairnConfig.fromEnvironment()` reads the `ARXA_CAIRN_*` define
/// surface; an empty/absent `ARXA_CAIRN_MODE` boots `localOnly` (the
/// database-boundary default — no Arxa Digital Solutions Supabase required;
/// `supabaseBridge` only for bring-your-own-DB users).
class AppData {
  AppData._();

  static ArxaKitDataConfig defaultConfig() => ArxaKitDataConfig(
        backend: ArxaKitDataBackend.plugin,
        plugin: ArxaKitCairnBackend(
          config: ArxaKitCairnConfig.fromEnvironment(),
        ),
      );

  /// The approvals data slice (grill D60–D68): the Approval entity is the
  /// phone's cairn-backed local projection of the engine's pending
  /// questions — wire-shaped as the future cairn row (D61), so the B2 sync
  /// swap changes transport, not model.
  static Future<void> initialize({ArxaKitDataConfig? config}) async {
    await ArxaKitData.initialize(
      config: config ?? defaultConfig(),
      entities: const [approvalEntityRegistration],
      fixtureAssets: const [],
    );
  }
}
