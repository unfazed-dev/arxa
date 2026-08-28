/// Configuration surface for the cairn backend.
///
/// A host app either builds one [ArxaKitCairnConfig] directly or lets
/// [ArxaKitCairnConfig.fromEnvironment] read the dart-define surface — the
/// ONLY env contract apps ever see:
///
/// ```
/// ARXA_CAIRN_MODE = local | sync | supabase   (default: local)
/// ARXA_CAIRN_URL  = wss://…/sync              (required unless local)
/// ARXA_CAIRN_PUSH = true|false                (default: false; literal "true")
/// ```
///
/// Tokens are NEVER env: `supabaseBridge` pulls session JWTs from kit/data's
/// `ArxaKitAuthService`; `sync` takes a host-supplied token-provider callback
/// on `ArxaKitCairnBackend`.
library;

import 'package:flutter/foundation.dart';

/// How the cairn backend reaches (or doesn't reach) a server.
enum ArxaKitCairnMode {
  /// Zero server, zero env: `CairnDatabase.local` — free-user parity.
  localOnly,

  /// Self-hosted cairn sync server at `ARXA_CAIRN_URL`.
  sync,

  /// Cairn server bridging Supabase Auth JWTs; session tokens come from
  /// kit/data's auth service and rotate onto the database via `setToken`.
  supabaseBridge,
}

class ArxaKitCairnConfig {
  /// Defaults to [ArxaKitCairnMode.localOnly] — zero configuration boots a
  /// local database.
  final ArxaKitCairnMode mode;

  /// `ws(s)://…/sync` — required for [ArxaKitCairnMode.sync] and
  /// [ArxaKitCairnMode.supabaseBridge].
  final String? syncUrl;

  /// Default: the path_provider app-support directory.
  final String? sqliteDirOverride;

  /// Opt into push token registration.
  final bool push;

  /// CRDT tiers — must triple-match the server env (`CAIRN_OR_SET_TABLES` /
  /// `CAIRN_COUNTER_TABLES`) and the emitted schema.
  final Set<String>? orSetTables;
  final Set<String>? counterTables;

  const ArxaKitCairnConfig({
    this.mode = ArxaKitCairnMode.localOnly,
    this.syncUrl,
    this.sqliteDirOverride,
    this.push = false,
    this.orSetTables,
    this.counterTables,
  });

  /// Reads the dart-define surface (see the library doc).
  factory ArxaKitCairnConfig.fromEnvironment() => ArxaKitCairnConfig.fromDefines(
        mode: const String.fromEnvironment('ARXA_CAIRN_MODE'),
        syncUrl: const String.fromEnvironment('ARXA_CAIRN_URL'),
        push: const String.fromEnvironment('ARXA_CAIRN_PUSH'),
      );

  /// The testable core of [fromEnvironment]: raw define strings in, typed
  /// config out. Blank strings mean "unset".
  @visibleForTesting
  factory ArxaKitCairnConfig.fromDefines({
    String mode = '',
    String syncUrl = '',
    String push = '',
  }) {
    final parsedMode = switch (mode.trim()) {
      '' || 'local' => ArxaKitCairnMode.localOnly,
      'sync' => ArxaKitCairnMode.sync,
      'supabase' => ArxaKitCairnMode.supabaseBridge,
      final other => throw StateError(
          'ArxaKitCairnConfig: ARXA_CAIRN_MODE must be local|sync|supabase, got "$other".',
        ),
    };
    return ArxaKitCairnConfig(
      mode: parsedMode,
      syncUrl: syncUrl.trim().isEmpty ? null : syncUrl.trim(),
      push: push.trim() == 'true',
    );
  }

  /// Throws [StateError] — naming the exact missing define — when the selected
  /// mode is missing its requirements (mirrors kit/data's credential checks).
  ///
  /// Also rejects a table tagged into BOTH CRDT tier sets: the engine merges
  /// one CRDT tier per table (or-set wins the first branch checked, silently
  /// dropping the counter tag), so a dual tag is always a misconfiguration.
  void validate() {
    switch (mode) {
      case ArxaKitCairnMode.localOnly:
        break;
      case ArxaKitCairnMode.sync:
      case ArxaKitCairnMode.supabaseBridge:
        if (syncUrl == null || syncUrl!.isEmpty) {
          throw StateError(
            'ArxaKitCairnConfig: mode is ${mode.name} but no syncUrl was provided — '
            'set the ARXA_CAIRN_URL dart-define.',
          );
        }
    }
    final dual = (orSetTables ?? const <String>{})
        .intersection(counterTables ?? const <String>{});
    if (dual.isNotEmpty) {
      throw StateError(
        'ArxaKitCairnConfig: ${dual.join(', ')} appear(s) in BOTH orSetTables '
        'and counterTables — the engine merges one CRDT tier per table '
        '(or-set wins, silently dropping the counter tag); tag each table '
        'with exactly one tier.',
      );
    }
  }
}
