import '../ids/arxa_kit_id_service.dart';
import '../models/arxa_kit_entity_registration.dart';
import '../schema/arxa_kit_schema_registry.dart';
import 'arxa_kit_data_config.dart';

/// The out-of-package backend seam (phase 1 of the cairn kit chain).
///
/// kit/data cannot name cairn types — Dart has no optional dependencies, so a
/// backend whose package lives outside kit/data (native payload, separate
/// license track, faster churn) plugs in through this interface instead of a
/// built-in `ArxaKitDataBackend` case:
///
/// ```dart
/// await ArxaKitData.initialize(
///   config: ArxaKitDataConfig(
///     backend: ArxaKitDataBackend.plugin,
///     plugin: ArxaKitCairnBackend(...), // package:arxa_kit_cairn
///   ),
///   entities: [...],
/// );
/// ```
///
/// `ArxaKitData.initialize` runs the plugin AFTER it has registered the
/// shared `ArxaKitIdService` / `ArxaKitSchemaRegistry` singletons, and hands
/// over those same instances — the plugin registers its repositories (and
/// optional auth/storage services) into the shared arxaKitLocator exactly like
/// a built-in backend would. Nothing above the repository seam changes.
abstract interface class ArxaKitBackendPlugin {
  /// Stable backend name (e.g. `'cairn'`) — used in diagnostics.
  String get name;

  /// Wire the backend: open connections, then register
  /// `ArxaKitRepository<T>` per entity (and any auth/storage services) into
  /// `arxaKitLocator`. [config] is the full data config (the plugin reads its
  /// own section — e.g. `ArxaKitAuthConfig` — from it); [entities] are the
  /// declared registrations; [idService] and [registry] are the instances
  /// already registered in the locator.
  Future<void> initialize(
    ArxaKitDataConfig config,
    List<ArxaKitEntityRegistration<dynamic>> entities,
    ArxaKitIdService idService,
    ArxaKitSchemaRegistry registry,
  );

  /// Release connections and streams. The host owns the call (kit/data has no
  /// dispose lifecycle); implementations must be idempotent.
  Future<void> dispose();
}
