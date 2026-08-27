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

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:cairn_flutter/cairn_flutter.dart';
import 'package:arxa_kit_core/arxa_kit_locator.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';
import 'package:arxa_kit_notifications/arxa_kit_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'auth/arxa_kit_cairn_auth_service.dart';
import 'config/arxa_kit_cairn_config.dart';
import 'emitters/cairn_schema_emitter.dart';
import 'push/arxa_kit_cairn_push_bridge.dart';
import 'repositories/cairn_kit_repository.dart';
import 'storage/arxa_kit_cairn_storage_service.dart';

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
    this.tokenProvider,
    this.userIdProvider,
    this.storage = false,
    this.storageAdapter,
    this.storageBlobStore,
    this.storageUrlFor,
    this.notifications,
    @visibleForTesting this.pushRegister,
    @visibleForTesting ArxaKitCairnOpenDatabase? openDatabase,
  })  : _config = config ?? ArxaKitCairnConfig.fromEnvironment(),
        _openDatabaseOverride = openDatabase;

  final ArxaKitCairnConfig _config;

  /// `sync` mode only: the host-supplied bearer token (agency deployments).
  final Future<String?> Function()? tokenProvider;

  /// Tenant-table stamping hook — see [CairnKitRepository].
  final String? Function()? userIdProvider;

  /// Opt-in blob storage over cairn attachments (ADR-0034). When true, the
  /// attachments metadata table is appended to the emitted schema and an
  /// `ArxaKitStorageService` lands in the locator.
  final bool storage;

  /// The remote blob plane. Required in `sync` mode; `supabaseBridge` wires
  /// [ArxaKitCairnSupabaseBucketAdapter] and `localOnly` wires
  /// [ArxaKitCairnLocalOnlyAdapter] when omitted.
  final AttachmentStorageAdapter? storageAdapter;

  /// The local blob cache. Defaults to a [LocalFileBlobStore] at
  /// `<sqlite dir>/cairn_blobs`; injectable for tests and custom caches.
  final BlobStore? storageBlobStore;

  /// `getUrl` override (CDN, signed-URL service, …). `supabaseBridge`
  /// defaults to Supabase's public URL; without any callback the service
  /// falls back to `data:` URLs from the local blob (seed-backend parity).
  final String Function(String bucket, String path)? storageUrlFor;

  /// The notifications seam the push bridge draws tokens from. Required when
  /// `ARXA_CAIRN_PUSH=true`; ignored otherwise. The provider rail (Firebase
  /// init, native wiring, background isolate, VAPID web) stays app-side.
  final ArxaKitNotificationsService? notifications;

  /// Test seam replacing `CairnDatabase.registerPushToken` in the wired
  /// bridge — production always uses the database's own method.
  final Future<void> Function(String platform, String token)? pushRegister;

  final ArxaKitCairnOpenDatabase? _openDatabaseOverride;

  CairnDatabase? _db;
  Attachments? _attachments;
  ArxaKitCairnPushBridge? _pushBridge;
  String? _openedToken;

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
    if (storage) _validateStorage(schemas);
    if (_config.push) _validatePush();

    if (_config.mode == ArxaKitCairnMode.supabaseBridge) {
      await _ensureSupabase(config);
    }

    var schema = CairnSchemaEmitter().schemaFor(schemas);
    if (storage) {
      // The driver writes its metadata rows like any business write — the
      // table must be declared (subscribed) exactly like the app's own.
      schema = CairnSchema(
        tables: [...schema.tables, CairnSchemaEmitter.attachmentsTable()],
      );
    }
    final token = switch (_config.mode) {
      ArxaKitCairnMode.sync => await tokenProvider?.call(),
      _ => null,
    };
    final open = _openDatabaseOverride ?? _openDefault;
    final db = await open(_config, schema, token);
    _db = db;
    _openedToken = token;

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
            userIdProvider: userIdProvider,
          ),
        );
        return null;
      });
    }

    if (storage) {
      await _registerStorage(db);
    }

    if (_config.push) {
      // Attach AFTER the engine start — the SDK deregisters session tokens on
      // sign-out, so every (re-)open must re-register (atlet checklist).
      final bridge = ArxaKitCairnPushBridge(
        notifications: notifications!,
        register: pushRegister ?? db.registerPushToken,
      );
      _pushBridge = bridge;
      await bridge.attach();
    }
  }

  /// ADR-0037 §3, surfaced for the app: register a token obtained OUTSIDE the
  /// notifications seam (the push bridge covers the stream itself). Platform
  /// ∈ {fcm, apns, webpush} — cairn validates.
  Future<void> registerPushToken(String platform, String token) =>
      database.registerPushToken(platform, token);

  /// The session's access token: the host token in `sync` mode, the live
  /// Supabase session's in `supabaseBridge`, null in `localOnly`. The
  /// background-isolate doorbell handler persists this (best-effort — a stale
  /// token's wake 401s into a documented no-op).
  String? get currentAccessToken => switch (_config.mode) {
        ArxaKitCairnMode.sync => _openedToken,
        ArxaKitCairnMode.supabaseBridge =>
          sb.Supabase.instance.client.auth.currentSession?.accessToken,
        ArxaKitCairnMode.localOnly => null,
      };

  /// The UI gate: resolves once the first sync has landed (immediately on a
  /// local database). See `CairnDatabase.waitForFirstSync`.
  Future<void> waitForFirstSync() => database.waitForFirstSync();

  @override
  Future<void> dispose() async {
    final db = _db;
    if (db == null) return; // idempotent
    await _pushBridge?.detach();
    _pushBridge = null;
    _openedToken = null;
    _attachments?.stop();
    _attachments = null;
    _db = null;
    await db.close();
  }

  /// Push pre-open validation: `localOnly` has no server to register with,
  /// and without the [notifications] seam there is no token source.
  void _validatePush() {
    if (_config.mode == ArxaKitCairnMode.localOnly) {
      throw StateError(
        'ArxaKitCairnBackend: ARXA_CAIRN_PUSH=true but the mode is localOnly '
        '— there is no server to register push tokens with. Unset the define '
        'or run sync/supabaseBridge.',
      );
    }
    if (notifications == null) {
      throw StateError(
        'ArxaKitCairnBackend: ARXA_CAIRN_PUSH=true requires the notifications '
        'param (an ArxaKitNotificationsService — the seam owning the provider '
        'rail; the kit never touches Firebase/APNs itself).',
      );
    }
  }

  /// Storage pre-open validation: the metadata table name must not collide
  /// with an app entity (the driver would fight the app's writes), and
  /// `sync` mode needs a host-supplied [storageAdapter] — the blob plane is
  /// the app's bucket, which the kit cannot guess.
  void _validateStorage(List<ArxaKitTableSchema> schemas) {
    for (final schema in schemas) {
      if (schema.table == AttachmentSchema.table) {
        throw StateError(
          'ArxaKitCairnBackend: storage is enabled but entity '
          '"${schema.table}" squats the attachments metadata table — rename '
          'the entity (the cairn driver owns that table, ADR-0034).',
        );
      }
    }
    if (_config.mode == ArxaKitCairnMode.sync && storageAdapter == null) {
      throw StateError(
        'ArxaKitCairnBackend: storage in sync mode requires a host-supplied '
        'storageAdapter (the remote blob plane is the app\'s bucket). '
        'supabaseBridge wires Supabase automatically; localOnly needs none.',
      );
    }
  }

  /// Builds the attachments driver (its blob-store wipe self-registers as a
  /// sign-out hook) and registers the kit storage seam into the locator.
  Future<void> _registerStorage(CairnDatabase db) async {
    final blobStore = storageBlobStore ??
        LocalFileBlobStore(Directory('${await _resolveDir()}/cairn_blobs'));
    final adapter = storageAdapter ??
        switch (_config.mode) {
          ArxaKitCairnMode.localOnly => const ArxaKitCairnLocalOnlyAdapter(),
          ArxaKitCairnMode.supabaseBridge => ArxaKitCairnSupabaseBucketAdapter(
              client: sb.Supabase.instance.client,
            ),
          // _validateStorage already failed this branch loudly.
          ArxaKitCairnMode.sync => throw StateError('unreachable'),
        };
    final attachments = db.attachments(adapter: adapter, blobStore: blobStore);
    _attachments = attachments;
    // The self-driving pump only matters with a server; localOnly's driver
    // never goes online, so starting its timer would be pure churn.
    if (_config.mode != ArxaKitCairnMode.localOnly) {
      attachments.start();
    }
    arxaKitLocator.registerLazySingleton<ArxaKitStorageService>(
      () => ArxaKitCairnStorageService(
        attachments: attachments,
        blobStore: blobStore,
        publicUrlFor: storageUrlFor ?? _defaultUrlFor(),
      ),
    );
  }

  String Function(String bucket, String path)? _defaultUrlFor() =>
      switch (_config.mode) {
        ArxaKitCairnMode.supabaseBridge => (bucket, path) => sb
            .Supabase.instance.client.storage
            .from(bucket)
            .getPublicUrl(path),
        _ => null,
      };

  Future<String> _resolveDir() async => _config.sqliteDirOverride ??
      (await getApplicationSupportDirectory()).path;

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
    final dir = await _resolveDir();
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
