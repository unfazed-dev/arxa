import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arxa_kit_cairn/arxa_kit_cairn.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';
import 'package:arxa_kit_notifications/arxa_kit_notifications.dart';
import 'package:flutter/foundation.dart';

import '../data/approvals/approval.dart';
import '../services/transport_service.dart';

/// Data-layer boot. Called once from `main()` after `setupLocator()`.
///
/// Cairn is the v1 backend (settled decision) — no seed fallback. Boot
/// mode (B2 phase-1b): with a stored pairing the boot waits bounded for
/// the transport's first connected announcement and — when the engine
/// answers the cairn-sync bootstrap route — opens the database in SYNC
/// mode against the desktop's mirror sidecar riding the SAME tunnel
/// (`ws://127.0.0.1:<proxyPort>/__cairn/sync`, bearer from the bootstrap).
/// Anything else (no pairing, dial timeout, unconfigured engine) boots
/// `localOnly` — offline reads come from local SQLite either way.
/// `ArxaKitCairnConfig.fromEnvironment()` remains the dart-define escape
/// hatch (`ARXA_CAIRN_*`) for agency builds; the runtime decision here is
/// the phone's default because the proxy port only exists at runtime.
class AppData {
  AppData._();

  /// How long the sync boot waits for the first connected announcement
  /// before falling back to localOnly. Covers the transport's reconnect
  /// dial budget (5 x 3s) with margin; a desktop that is simply DOWN costs
  /// the full window on a cold start — the honest price of syncing at all.
  /// Mutable for tests.
  static Duration syncBootWait = const Duration(seconds: 18);

  /// The bootstrap route's HTTP timeout — the engine answers from local
  /// files only; anything slower is treated as not configured.
  static const _bootstrapTimeout = Duration(seconds: 5);

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
  static Future<void> initialize({
    ArxaKitDataConfig? config,
    TransportService? transport,
    ArxaKitNotificationsService? notifications,
  }) async {
    await ArxaKitData.initialize(
      config: config ?? await bootConfig(transport, notifications: notifications),
      entities: const [approvalEntityRegistration],
      fixtureAssets: const [],
    );
  }

  /// The boot decision (B2 phase-1b) — sync when pairing + tunnel + engine
  /// bootstrap all come up in time, localOnly otherwise. Exposed for tests.
  @visibleForTesting
  static Future<ArxaKitDataConfig> bootConfig(
    TransportService? transport, {
    ArxaKitNotificationsService? notifications,
  }) async {
    final sync = transport == null
        ? null
        : await resolveSyncConfig(transport, notifications: notifications);
    if (sync == null) return defaultConfig();
    return ArxaKitDataConfig(
      backend: ArxaKitDataBackend.plugin,
      plugin: ArxaKitCairnBackend(
        config: sync.config,
        tokenProvider: sync.token,
        notifications: notifications,
      ),
    );
  }

  /// The sync decision: null means localOnly. `hasStoredPairing` gates
  /// everything — a fresh install never waits — then the first connected
  /// announcement, then the engine's bootstrap bearer.
  @visibleForTesting
  static Future<({ArxaKitCairnConfig config, Future<String?> Function() token})?>
      resolveSyncConfig(
    TransportService transport, {
    ArxaKitNotificationsService? notifications,
  }) async {
    if (!await transport.hasStoredPairing()) return null;
    final studioUrl = await _firstConnectedStudioUrl(transport);
    if (studioUrl == null) return null;
    final token = await _bootstrapToken(studioUrl);
    if (token == null) return null;
    final syncUrl =
        studioUrl.replace(scheme: 'ws', path: '/__cairn/sync').toString();
    return (
      config: ArxaKitCairnConfig(
        mode: ArxaKitCairnMode.sync,
        syncUrl: syncUrl,
        // Push registration needs the authenticated session the bearer
        // creates (ADR-0037 §3 refuses anonymous rows) — only asked for
        // when a notifications seam exists to draw the device token from.
        push: notifications != null,
      ),
      token: () async => token,
    );
  }

  /// The first connected announcement's studioUrl: the CURRENT status wins
  /// (a warm resume can announce before this runs — subscribed FIRST so a
  /// fast announcement is never missed), else the next one, bounded by
  /// [syncBootWait]. Null = the tunnel never came up in time.
  static Future<Uri?> _firstConnectedStudioUrl(
    TransportService transport,) async {
    final announced = Completer<Uri?>();
    final sub = transport.status.listen((s) {
      if (!announced.isCompleted &&
          s.state == ArxaConnectionState.connected &&
          s.studioUrl != null) {
        announced.complete(s.studioUrl);
      }
    });
    try {
      final current = transport.current;
      if (current.state == ArxaConnectionState.connected &&
          current.studioUrl != null) {
        return current.studioUrl;
      }
      return await announced.future.timeout(
        syncBootWait,
        onTimeout: () => null,
      );
    } finally {
      await sub.cancel();
    }
  }

  /// GET `<studio>/__arxa/cairn-sync` -> the mirror's shared bearer. Null
  /// on any failure (offline, 404-not-configured, junk body) — the boot
  /// then falls back to localOnly.
  static Future<String?> _bootstrapToken(Uri studioUrl) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = _bootstrapTimeout;
      final request =
          await client.getUrl(studioUrl.resolve('__arxa/cairn-sync'));
      final response = await request.close().timeout(_bootstrapTimeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(await response.transform(utf8.decoder).join());
      final token = body is Map ? body['token'] as String? : null;
      return (token == null || token.isEmpty) ? null : token;
    } on Object {
      return null;
    } finally {
      client?.close();
    }
  }
}
