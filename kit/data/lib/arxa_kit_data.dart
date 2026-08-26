/// arxa_kit_data — the data layer for arxa_kit apps.
///
/// One backend at a time — seed (fixture-backed, optional snapshot
/// persistence), Supabase (default), or Appwrite — selected by
/// [ArxaKitDataConfig] and wired by `ArxaKitData.initialize`. Repositories are the
/// swap seam; facades compose them into UI state; canonical IDs are
/// deterministic across every backend (ADR-0001).
library;

import 'package:appwrite/appwrite.dart' as aw;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'assets/arxa_kit_asset_reader.dart';
import 'assets/arxa_kit_root_bundle_asset_reader.dart';
import 'auth/appwrite/arxa_kit_appwrite_auth_service.dart';
import 'auth/arxa_kit_auth_service.dart';
import 'auth/seed/arxa_kit_seed_auth_service.dart';
import 'auth/supabase/arxa_kit_supabase_auth_service.dart';
import 'config/arxa_kit_data_config.dart';
import 'config/arxa_kit_seed_profile.dart';
import 'ids/arxa_kit_id_service.dart';
import 'models/arxa_kit_entity_registration.dart';
import 'repositories/appwrite/arxa_kit_appwrite_repository.dart';
import 'repositories/arxa_kit_repository.dart';
import 'repositories/seed/arxa_kit_seed_persistence.dart';
import 'repositories/seed/arxa_kit_seed_repository.dart';
import 'repositories/seed/arxa_kit_seed_store.dart';
import 'repositories/supabase/arxa_kit_supabase_repository.dart';
import 'schema/arxa_kit_schema_registry.dart';
import 'seeding/arxa_kit_fixture_loader.dart';
import 'storage/appwrite/arxa_kit_appwrite_storage_service.dart';
import 'storage/arxa_kit_storage_service.dart';
import 'storage/seed/arxa_kit_seed_storage_service.dart';
import 'storage/seed/arxa_kit_storage_persistence.dart';
import 'storage/supabase/arxa_kit_supabase_storage_service.dart';

// Entry point & config
export 'config/arxa_kit_data_config.dart';
export 'config/arxa_kit_seed_profile.dart';

// Assets (AssetBundle inversion: pure-Dart port + Flutter adapter)
export 'assets/arxa_kit_asset_reader.dart';
export 'assets/arxa_kit_root_bundle_asset_reader.dart';

// Auth
export 'auth/arxa_kit_auth_types.dart';
export 'auth/arxa_kit_auth_service.dart';
export 'auth/seed/arxa_kit_seed_auth_service.dart';
export 'auth/supabase/arxa_kit_supabase_auth_service.dart';
export 'auth/appwrite/arxa_kit_appwrite_auth_service.dart';

// IDs
export 'ids/arxa_kit_id_service.dart';

// Schema
export 'schema/arxa_kit_table_schema.dart';
export 'schema/arxa_kit_schema_registry.dart';
export 'schema/arxa_kit_schema_topology.dart';

// Models
export 'models/arxa_kit_entity_registration.dart';

// Query
export 'query/arxa_kit_query.dart';

// Repositories
export 'repositories/arxa_kit_repository.dart';
export 'repositories/seed/arxa_kit_seed_store.dart';
export 'repositories/seed/arxa_kit_seed_persistence.dart';
export 'repositories/seed/arxa_kit_seed_repository.dart';
export 'repositories/supabase/arxa_kit_supabase_repository.dart';
export 'repositories/appwrite/arxa_kit_appwrite_repository.dart';

// Seeding
export 'seeding/arxa_kit_fixture_loader.dart';
export 'seeding/arxa_kit_data_seeder.dart';

// Facades
export 'facades/arxa_kit_data_facade.dart';

// Emitters (pure Dart — safe in `dart run` tools)
export 'emitters/arxa_kit_supabase_sql_emitter.dart';
export 'emitters/arxa_kit_supabase_seed_emitter.dart';
export 'emitters/arxa_kit_appwrite_json_emitter.dart';

/// Entry point the host calls once in `main()`, after `setupLocator()`:
///
/// ```dart
/// await ArxaKitData.initialize(
///   config: const ArxaKitDataConfig(
///     backend: ArxaKitDataBackend.supabase,
///     supabase: ArxaKitSupabaseConfig(url: ..., publishableKey: ...),
///   ),
///   entities: [productRegistration, categoryRegistration],
///   fixtureAssets: ['assets/seed/products.json', ...],
/// );
/// ```
///
/// Registers one `ArxaKitRepository<T>` per entity into the shared arxaKitLocator for
/// the configured backend. The kit never self-registers — the host owns the
/// call, matching arxa_kit's host-integration contract.
class ArxaKitData {
  ArxaKitData._();

  static ArxaKitDataConfig? _config;
  static ArxaKitSchemaRegistry? _registry;

  static ArxaKitDataConfig get config {
    final c = _config;
    if (c == null) {
      throw StateError('ArxaKitData.initialize has not been called');
    }
    return c;
  }

  static ArxaKitSchemaRegistry get registry {
    final r = _registry;
    if (r == null) {
      throw StateError('ArxaKitData.initialize has not been called');
    }
    return r;
  }

  static Future<void> initialize({
    required ArxaKitDataConfig config,
    required List<ArxaKitEntityRegistration<dynamic>> entities,
    List<String> fixtureAssets = const [],
    ArxaKitAssetReader? assetReader,
  }) async {
    if (_config != null) {
      throw StateError('ArxaKitData.initialize called twice');
    }
    config.validate();

    final idService = ArxaKitIdService(namespace: config.idNamespace);
    final registry = ArxaKitSchemaRegistry();
    for (final entity in entities) {
      registry.register(entity);
    }

    _config = config;
    _registry = registry;
    arxaKitLocator.registerSingleton<ArxaKitIdService>(idService);
    arxaKitLocator.registerSingleton<ArxaKitSchemaRegistry>(registry);

    final reader = assetReader ?? const ArxaKitRootBundleAssetReader();

    switch (config.backend) {
      case ArxaKitDataBackend.seed:
        await _initializeSeed(config, entities, registry, idService,
            fixtureAssets: fixtureAssets, assetReader: reader);
      case ArxaKitDataBackend.supabase:
        await _initializeSupabase(config, entities, idService);
      case ArxaKitDataBackend.appwrite:
        await _initializeAppwrite(config, entities, idService);
    }
  }

  static Future<void> _initializeSeed(
    ArxaKitDataConfig config,
    List<ArxaKitEntityRegistration<dynamic>> entities,
    ArxaKitSchemaRegistry registry,
    ArxaKitIdService idService, {
    required List<String> fixtureAssets,
    required ArxaKitAssetReader assetReader,
  }) async {
    // Web has no dart:io / path_provider — snapshot persistence would throw
    // MissingPluginException (getApplicationDocumentsDirectory) and kill boot.
    // Degrade to in-memory there; every other platform honors the config.
    final seedPersistenceMode = kIsWeb
        ? ArxaKitSeedPersistenceMode.none
        : config.seedPersistence;
    final persistence = switch (seedPersistenceMode) {
      ArxaKitSeedPersistenceMode.none => ArxaKitNoPersistence(),
      ArxaKitSeedPersistenceMode.snapshot => ArxaKitSnapshotPersistence(),
    };
    final store = ArxaKitSeedStore(persistence: persistence);
    // Boot precedence per table: snapshot while the bundled fixtures are
    // unchanged, re-seed when they differ (see arxaKitResolveBootTables — this is
    // what lets shipped fixture updates reach devices that already persisted
    // a snapshot, instead of the snapshot shadowing them forever).
    final fixtures =
        await ArxaKitFixtureLoader(idService: idService, assetReader: assetReader).load(
      assetPaths: fixtureAssets,
      schemasByTable: registry.schemasByTable,
    );
    final resolution = arxaKitResolveBootTables(
      fixtures: fixtures,
      snapshot: await persistence.load(),
      recordedFingerprints: await persistence.loadFixtureFingerprints(),
    );
    store.loadTables(resolution.tables);
    // Write-through the refreshed tables + current fingerprints so the next
    // boot compares against this fixture generation (idempotent thereafter).
    for (final table in resolution.reseededTables) {
      await persistence.persistTable(table, resolution.tables[table]!);
    }
    await persistence.persistFixtureFingerprints(resolution.fingerprints);
    arxaKitLocator.registerSingleton<ArxaKitSeedStore>(store);

    // Blob-storage seam: same seedPersistence switch as tables.
    final storagePersistence = switch (seedPersistenceMode) {
      ArxaKitSeedPersistenceMode.none => const ArxaKitNoStoragePersistence(),
      ArxaKitSeedPersistenceMode.snapshot => const ArxaKitSnapshotStoragePersistence(),
    };
    arxaKitLocator.registerLazySingleton<ArxaKitStorageService>(
      () => ArxaKitSeedStorageService(persistence: storagePersistence),
    );

    for (final entity in entities) {
      entity.apply(<E>(registration) {
        arxaKitLocator.registerLazySingleton<ArxaKitRepository<E>>(
          () => ArxaKitSeedRepository<E>(
            store: store,
            registration: registration,
            idService: idService,
            // Seed Profile injection (slow/failing); defaults to pass-through.
            profile: config.seedProfile ?? const ArxaKitSeedProfile(),
          ),
        );
        return null;
      });
    }

    final authConfig = config.auth;
    if (authConfig != null) {
      final auth = ArxaKitSeedAuthService(
        store: store,
        idService: idService,
        fakeUsersAsset: authConfig.fakeUsersAsset,
        assetReader: assetReader,
      );
      await auth.initialize();
      arxaKitLocator.registerSingleton<ArxaKitAuthService>(auth);
    }
  }

  static Future<void> _initializeSupabase(
    ArxaKitDataConfig config,
    List<ArxaKitEntityRegistration<dynamic>> entities,
    ArxaKitIdService idService,
  ) async {
    final supabase = config.supabase!;
    await sb.Supabase.initialize(
      url: supabase.url,
      publishableKey: supabase.publishableKey,
    );
    final client = sb.Supabase.instance.client;

    arxaKitLocator.registerLazySingleton<ArxaKitStorageService>(
      () => ArxaKitSupabaseStorageService(client: client),
    );

    for (final entity in entities) {
      entity.apply(<E>(registration) {
        arxaKitLocator.registerLazySingleton<ArxaKitRepository<E>>(
          () => ArxaKitSupabaseRepository<E>(
            client: client,
            registration: registration,
            idService: idService,
          ),
        );
        return null;
      });
    }

    final authConfig = config.auth;
    if (authConfig != null) {
      final auth = ArxaKitSupabaseAuthService(
        client: client,
        config: authConfig,
        idService: idService,
      );
      await auth.initialize();
      arxaKitLocator.registerSingleton<ArxaKitAuthService>(auth);
    }
  }

  static Future<void> _initializeAppwrite(
    ArxaKitDataConfig config,
    List<ArxaKitEntityRegistration<dynamic>> entities,
    ArxaKitIdService idService,
  ) async {
    final appwrite = config.appwrite!;
    final client = aw.Client()
        .setEndpoint(appwrite.endpoint)
        .setProject(appwrite.projectId);
    final tablesDB = aw.TablesDB(client);
    final realtime = aw.Realtime(client);

    arxaKitLocator.registerLazySingleton<ArxaKitStorageService>(
      () => ArxaKitAppwriteStorageService(
        storage: aw.Storage(client),
        client: client,
      ),
    );

    for (final entity in entities) {
      entity.apply(<E>(registration) {
        arxaKitLocator.registerLazySingleton<ArxaKitRepository<E>>(
          () => ArxaKitAppwriteRepository<E>(
            tablesDB: tablesDB,
            realtime: realtime,
            databaseId: appwrite.databaseId,
            registration: registration,
            idService: idService,
          ),
        );
        return null;
      });
    }

    if (config.auth != null) {
      final auth = ArxaKitAppwriteAuthService(
        account: aw.Account(client),
        idService: idService,
      );
      await auth.initialize();
      arxaKitLocator.registerSingleton<ArxaKitAuthService>(auth);
    }
  }

  /// Test-only: clears static state so initialize can run again.
  static void resetForTesting() {
    _config = null;
    _registry = null;
  }
}
