/// The cairn backend plugin — plugs cairn into kit/data's
/// `ArxaKitBackendPlugin` seam so apps select cairn with:
///
/// ```dart
/// await ArxaKitData.initialize(
///   config: ArxaKitDataConfig(
///     backend: ArxaKitDataBackend.plugin,
///     plugin: ArxaKitCairnBackend(), // reads ARXA_CAIRN_* dart-defines
///   ),
///   entities: [...],
/// );
/// ```
///
/// Per [ArxaKitCairnConfig.mode] the plugin opens `CairnDatabase.local`
/// (zero server), `.connect` (self-hosted sync; token from the host's
/// [tokenProvider] — never env), or `.supabase` (Supabase JWT bridge; the
/// double-init probe runs first, and token rotation is cairn's own
/// `onAuthStateChange` wiring). Repositories are registered into the shared
/// arxaKitLocator exactly like kit/data's built-in backends.
library;

import 'package:flutter/foundation.dart';
import 'package:cairn_flutter/cairn_flutter.dart';
import 'package:arxa_kit_core/arxa_kit_locator.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'auth/arxa_kit_cairn_auth_service.dart';
import 'config/arxa_kit_cairn_config.dart';
import 'emitters/cairn_schema_emitter.dart';
import 'repositories/cairn_kit_repository.dart';

/// How the plugin opens its database — injectable in tests so the whole
/// wiring runs without the native library. [token] is the resolved bearer
/// token (host provider for `sync`; `null` otherwise — `supabaseBridge`
/// reads the live Supabase session itself).
typedef ArxaKitCairnOpenDatabase = Future<CairnDatabase> Function(
  ArxaKitCairnConfig config,
  CairnSchema schema,
  String? token,
);

class ArxaKitCairnBackend implements ArxaKitBackendPlugin {
  /// [config] defaults to [ArxaKitCairnConfig.fromEnvironment] — the
  /// dart-define surface is the only env contract apps ever see.
  ArxaKitCairnBackend({
    ArxaKitCairnConfig? config,
    Future<String?> Function()? tokenProvider,
    String? Function()? userIdProvider,
    @visibleForTesting ArxaKitCairnOpenDatabase? openDatabase,
  })  : _config = config ?? ArxaKitCairnConfig.fromEnvironment(),
        // Private named parameters can't be initializing formals — ignore.
        // ignore: prefer_initializing_formals
        _tokenProvider = tokenProvider,
        // ignore: prefer_initializing_formals
        _userIdProvider = userIdProvider,
        _openDatabaseOverride = openDatabase;

  final ArxaKitCairnConfig _config;

  /// `sync` mode only: the host-supplied bearer token (agency deployments).
  final Future<String?> Function()? _tokenProvider;

  /// Tenant-table stamping hook — see [CairnKitRepository].
  final String? Function()? _userIdProvider;

  final ArxaKitCairnOpenDatabase? _openDatabaseOverride;

  CairnDatabase? _db;

  /// The opened database, once [initialize] has run. Exposed for the kit's
  /// own services (storage, push) — apps should not need it.
  CairnDatabase get database {
    final db = _db;
    if (db == null) {
      throw StateError('ArxaKitCairnBackend.initialize has not run');
    }
    return db;
  }

  @override
  String get name => 'cairn';

  @override
  Future<void> initialize(
    ArxaKitDataConfig config,
    List<ArxaKitEntityRegistration<dynamic>> entities,
    ArxaKitIdService idService,
    ArxaKitSchemaRegistry registry,
  ) async {
    _config.validate();
    final schemas = [for (final e in entities) e.schema];
    _validateCrdtConsistency(schemas);

    if (_config.mode == ArxaKitCairnMode.supabaseBridge) {
      await _ensureSupabase(config);
    }

    final schema = CairnSchemaEmitter().schemaFor(schemas);
    final token = switch (_config.mode) {
      ArxaKitCairnMode.sync => await _tokenProvider?.call(),
      _ => null,
    };
    final open = _openDatabaseOverride ?? _openDefault;
    final db = await open(_config, schema, token);
    _db = db;

    // Auth seam: supabaseBridge registers kit/data's Supabase auth service
    // (kit/data owns auth) decorated so sign-out wipes cairn FIRST.
    if (_config.mode == ArxaKitCairnMode.supabaseBridge &&
        config.auth != null) {
      final auth = ArxaKitSupabaseAuthService(
        client: sb.Supabase.instance.client,
        config: config.auth!,
        idService: idService,
      );
      await auth.initialize();
      arxaKitLocator.registerSingleton<ArxaKitAuthService>(
        ArxaKitCairnAuthService(inner: auth, dbSignOut: db.signOut),
      );
    }

    for (final entity in entities) {
      entity.apply(<E>(registration) {
        arxaKitLocator.registerLazySingleton<ArxaKitRepository<E>>(
          () => CairnKitRepository<E>(
            db: db,
            registration: registration,
            idService: idService,
            orSetTables: _config.orSetTables ?? const {},
            counterTables: _config.counterTables ?? const {},
            userIdProvider: _userIdProvider,
          ),
        );
        return null;
      });
    }
  }

  /// The UI gate: resolves once the first sync has landed (immediately on a
  /// local database). See `CairnDatabase.waitForFirstSync`.
  Future<void> waitForFirstSync() => database.waitForFirstSync();

  @override
  Future<void> dispose() async {
    final db = _db;
    if (db == null) return; // idempotent
    _db = null;
    await db.close();
  }

  /// Triple consistency, client side: schema `crdt:` flags and the config's
  /// table sets must agree exactly, or CRDT verbs would clobber on one side
  /// and merge on the other. The server env half is emitted by
  /// [CairnSchemaEmitter.emitServerCrdtEnv].
  void _validateCrdtConsistency(List<ArxaKitTableSchema> schemas) {
    final flaggedCounters = <String>{};
    final flaggedOrSets = <String>{};
    for (final schema in schemas) {
      for (final column in schema.columns) {
        switch (column.crdt) {
          case ArxaKitCrdtTier.counter:
            flaggedCounters.add(schema.table);
          case ArxaKitCrdtTier.orSet:
            flaggedOrSets.add(schema.table);
          case null:
            break;
        }
      }
    }
    void check(String field, Set<String> flagged, Set<String> configured) {
      for (final table in flagged.difference(configured)) {
        throw StateError(
          'ArxaKitCairnBackend: table "$table" carries crdt-flagged columns '
          'but is missing from ArxaKitCairnConfig.$field — declare it so the '
          'verbs merge instead of clobbering (and keep the server env in '
          'sync via CairnSchemaEmitter.emitServerCrdtEnv).',
        );
      }
      for (final table in configured.difference(flagged)) {
        throw StateError(
          'ArxaKitCairnBackend: ArxaKitCairnConfig.$field declares "$table" '
          'but no column in its schema carries the matching crdt flag.',
        );
      }
    }

    check('counterTables', flaggedCounters, _config.counterTables ?? const {});
    check('orSetTables', flaggedOrSets, _config.orSetTables ?? const {});
  }

  /// The Supabase double-init probe: `Supabase.initialize` is process-global
  /// and once-only, so an already-initialized instance (the app did it
  /// itself) is reused; otherwise the plugin initializes from
  /// [ArxaKitDataConfig.supabase].
  Future<void> _ensureSupabase(ArxaKitDataConfig config) async {
    var initialized = true;
    try {
      sb.Supabase.instance;
    } on AssertionError {
      initialized = false;
    }
    if (initialized) return;
    final supabase = config.supabase;
    if (supabase == null) {
      throw StateError(
        'ArxaKitCairnBackend: mode is supabaseBridge but Supabase is not '
        'initialized and ArxaKitDataConfig.supabase was not provided to '
        'initialize it from.',
      );
    }
    await sb.Supabase.initialize(
      url: supabase.url,
      publishableKey: supabase.publishableKey,
    );
  }

  Future<CairnDatabase> _openDefault(
    ArxaKitCairnConfig config,
    CairnSchema schema,
    String? token,
  ) async {
    final dir = config.sqliteDirOverride ??
        (await getApplicationSupportDirectory()).path;
    switch (config.mode) {
      case ArxaKitCairnMode.localOnly:
        return CairnDatabase.local(
          sqliteDir: dir,
          schema: schema,
          orSetTables: config.orSetTables,
          counterTables: config.counterTables,
        );
      case ArxaKitCairnMode.sync:
        return CairnDatabase.connect(
          url: config.syncUrl!,
          token: token,
          sqlitePath: '$dir/cairn.sqlite',
          schema: schema,
          orSetTables: config.orSetTables,
          counterTables: config.counterTables,
        );
      case ArxaKitCairnMode.supabaseBridge:
        return CairnDatabase.supabase(
          cairnUrl: config.syncUrl!,
          sqlitePath: '$dir/cairn.sqlite',
          schema: schema,
          orSetTables: config.orSetTables,
          counterTables: config.counterTables,
        );
    }
  }
}
