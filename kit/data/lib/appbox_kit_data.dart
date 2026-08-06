/// appbox_kit_data — the data layer for appbox_kit apps.
///
/// One backend at a time — seed (fixture-backed, optional snapshot
/// persistence), Supabase (default), or Appwrite — selected by
/// [AppBoxKitDataConfig] and wired by `AppBoxKitData.initialize`. Repositories are the
/// swap seam; facades compose them into UI state; canonical IDs are
/// deterministic across every backend (ADR-0001).
library;

import 'package:appwrite/appwrite.dart' as aw;
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'assets/appbox_kit_asset_reader.dart';
import 'assets/appbox_kit_root_bundle_asset_reader.dart';
import 'auth/appwrite/appbox_kit_appwrite_auth_service.dart';
import 'auth/appbox_kit_auth_service.dart';
import 'auth/seed/appbox_kit_seed_auth_service.dart';
import 'auth/supabase/appbox_kit_supabase_auth_service.dart';
import 'config/appbox_kit_data_config.dart';
import 'config/appbox_kit_seed_profile.dart';
import 'ids/appbox_kit_id_service.dart';
import 'models/appbox_kit_entity_registration.dart';
import 'repositories/appwrite/appbox_kit_appwrite_repository.dart';
import 'repositories/appbox_kit_repository.dart';
import 'repositories/seed/appbox_kit_seed_persistence.dart';
import 'repositories/seed/appbox_kit_seed_repository.dart';
import 'repositories/seed/appbox_kit_seed_store.dart';
import 'repositories/supabase/appbox_kit_supabase_repository.dart';
import 'schema/appbox_kit_schema_registry.dart';
import 'seeding/appbox_kit_fixture_loader.dart';
import 'storage/appwrite/appbox_kit_appwrite_storage_service.dart';
import 'storage/appbox_kit_storage_service.dart';
import 'storage/seed/appbox_kit_seed_storage_service.dart';
import 'storage/seed/appbox_kit_storage_persistence.dart';
import 'storage/supabase/appbox_kit_supabase_storage_service.dart';

// Entry point & config
export 'config/appbox_kit_data_config.dart';
export 'config/appbox_kit_seed_profile.dart';

// Assets (AssetBundle inversion: pure-Dart port + Flutter adapter)
export 'assets/appbox_kit_asset_reader.dart';
export 'assets/appbox_kit_root_bundle_asset_reader.dart';

// Auth
export 'auth/appbox_kit_auth_types.dart';
export 'auth/appbox_kit_auth_service.dart';
export 'auth/seed/appbox_kit_seed_auth_service.dart';
export 'auth/supabase/appbox_kit_supabase_auth_service.dart';
export 'auth/appwrite/appbox_kit_appwrite_auth_service.dart';

// IDs
export 'ids/appbox_kit_id_service.dart';

// Schema
export 'schema/appbox_kit_table_schema.dart';
export 'schema/appbox_kit_schema_registry.dart';
export 'schema/appbox_kit_schema_topology.dart';

// Models
export 'models/appbox_kit_entity_registration.dart';

// Query
export 'query/appbox_kit_query.dart';

// Repositories
export 'repositories/appbox_kit_repository.dart';
export 'repositories/seed/appbox_kit_seed_store.dart';
export 'repositories/seed/appbox_kit_seed_persistence.dart';
export 'repositories/seed/appbox_kit_seed_repository.dart';
export 'repositories/supabase/appbox_kit_supabase_repository.dart';
export 'repositories/appwrite/appbox_kit_appwrite_repository.dart';

// Seeding
export 'seeding/appbox_kit_fixture_loader.dart';
export 'seeding/appbox_kit_data_seeder.dart';

// Facades
export 'facades/appbox_kit_data_facade.dart';

// Emitters (pure Dart — safe in `dart run` tools)
export 'emitters/appbox_kit_supabase_sql_emitter.dart';
export 'emitters/appbox_kit_supabase_seed_emitter.dart';
export 'emitters/appbox_kit_appwrite_json_emitter.dart';

/// Entry point the host calls once in `main()`, after `setupLocator()`:
///
/// ```dart
/// await AppBoxKitData.initialize(
///   config: const AppBoxKitDataConfig(
///     backend: AppBoxKitDataBackend.supabase,
///     supabase: AppBoxKitSupabaseConfig(url: ..., publishableKey: ...),
///   ),
///   entities: [productRegistration, categoryRegistration],
///   fixtureAssets: ['assets/seed/products.json', ...],
/// );
/// ```
///
/// Registers one `AppBoxKitRepository<T>` per entity into the shared appBoxKitLocator for
/// the configured backend. The kit never self-registers — the host owns the
/// call, matching appbox_kit's host-integration contract.
class AppBoxKitData {
  AppBoxKitData._();

  static AppBoxKitDataConfig? _config;
  static AppBoxKitSchemaRegistry? _registry;

  static AppBoxKitDataConfig get config {
    final c = _config;
    if (c == null) {
      throw StateError('AppBoxKitData.initialize has not been called');
    }
    return c;
  }

  static AppBoxKitSchemaRegistry get registry {
    final r = _registry;
    if (r == null) {
      throw StateError('AppBoxKitData.initialize has not been called');
    }
    return r;
  }

  static Future<void> initialize({
    required AppBoxKitDataConfig config,
    required List<AppBoxKitEntityRegistration<dynamic>> entities,
    List<String> fixtureAssets = const [],
    AppBoxKitAssetReader? assetReader,
  }) async {
    if (_config != null) {
      throw StateError('AppBoxKitData.initialize called twice');
    }
    config.validate();

    final idService = AppBoxKitIdService(namespace: config.idNamespace);
    final registry = AppBoxKitSchemaRegistry();
    for (final entity in entities) {
      registry.register(entity);
    }

    _config = config;
    _registry = registry;
    appBoxKitLocator.registerSingleton<AppBoxKitIdService>(idService);
    appBoxKitLocator.registerSingleton<AppBoxKitSchemaRegistry>(registry);

    final reader = assetReader ?? const AppBoxKitRootBundleAssetReader();

    switch (config.backend) {
      case AppBoxKitDataBackend.seed:
        await _initializeSeed(config, entities, registry, idService,
            fixtureAssets: fixtureAssets, assetReader: reader);
      case AppBoxKitDataBackend.supabase:
        await _initializeSupabase(config, entities, idService);
      case AppBoxKitDataBackend.appwrite:
        await _initializeAppwrite(config, entities, idService);
    }
  }

  static Future<void> _initializeSeed(
    AppBoxKitDataConfig config,
    List<AppBoxKitEntityRegistration<dynamic>> entities,
    AppBoxKitSchemaRegistry registry,
    AppBoxKitIdService idService, {
    required List<String> fixtureAssets,
    required AppBoxKitAssetReader assetReader,
  }) async {
    final persistence = switch (config.seedPersistence) {
      AppBoxKitSeedPersistenceMode.none => AppBoxKitNoPersistence(),
      AppBoxKitSeedPersistenceMode.snapshot => AppBoxKitSnapshotPersistence(),
    };
    final store = AppBoxKitSeedStore(persistence: persistence);
    // Boot precedence per table: snapshot while the bundled fixtures are
    // unchanged, re-seed when they differ (see appBoxKitResolveBootTables — this is
    // what lets shipped fixture updates reach devices that already persisted
    // a snapshot, instead of the snapshot shadowing them forever).
    final fixtures =
        await AppBoxKitFixtureLoader(idService: idService, assetReader: assetReader).load(
      assetPaths: fixtureAssets,
      schemasByTable: registry.schemasByTable,
    );
    final resolution = appBoxKitResolveBootTables(
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
    appBoxKitLocator.registerSingleton<AppBoxKitSeedStore>(store);

    // Blob-storage seam: same seedPersistence switch as tables.
    final storagePersistence = switch (config.seedPersistence) {
      AppBoxKitSeedPersistenceMode.none => const AppBoxKitNoStoragePersistence(),
      AppBoxKitSeedPersistenceMode.snapshot => const AppBoxKitSnapshotStoragePersistence(),
    };
    appBoxKitLocator.registerLazySingleton<AppBoxKitStorageService>(
      () => AppBoxKitSeedStorageService(persistence: storagePersistence),
    );

    for (final entity in entities) {
      entity.apply(<E>(registration) {
        appBoxKitLocator.registerLazySingleton<AppBoxKitRepository<E>>(
          () => AppBoxKitSeedRepository<E>(
            store: store,
            registration: registration,
            idService: idService,
            // Seed Profile injection (slow/failing); defaults to pass-through.
            profile: config.seedProfile ?? const AppBoxKitSeedProfile(),
          ),
        );
        return null;
      });
    }

    final authConfig = config.auth;
    if (authConfig != null) {
      final auth = AppBoxKitSeedAuthService(
        store: store,
        idService: idService,
        fakeUsersAsset: authConfig.fakeUsersAsset,
        assetReader: assetReader,
      );
      await auth.initialize();
      appBoxKitLocator.registerSingleton<AppBoxKitAuthService>(auth);
    }
  }

  static Future<void> _initializeSupabase(
    AppBoxKitDataConfig config,
    List<AppBoxKitEntityRegistration<dynamic>> entities,
    AppBoxKitIdService idService,
  ) async {
    final supabase = config.supabase!;
    await sb.Supabase.initialize(
      url: supabase.url,
      publishableKey: supabase.publishableKey,
    );
    final client = sb.Supabase.instance.client;

    appBoxKitLocator.registerLazySingleton<AppBoxKitStorageService>(
      () => AppBoxKitSupabaseStorageService(client: client),
    );

    for (final entity in entities) {
      entity.apply(<E>(registration) {
        appBoxKitLocator.registerLazySingleton<AppBoxKitRepository<E>>(
          () => AppBoxKitSupabaseRepository<E>(
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
      final auth = AppBoxKitSupabaseAuthService(
        client: client,
        config: authConfig,
        idService: idService,
      );
      await auth.initialize();
      appBoxKitLocator.registerSingleton<AppBoxKitAuthService>(auth);
    }
  }

  static Future<void> _initializeAppwrite(
    AppBoxKitDataConfig config,
    List<AppBoxKitEntityRegistration<dynamic>> entities,
    AppBoxKitIdService idService,
  ) async {
    final appwrite = config.appwrite!;
    final client = aw.Client()
        .setEndpoint(appwrite.endpoint)
        .setProject(appwrite.projectId);
    final tablesDB = aw.TablesDB(client);
    final realtime = aw.Realtime(client);

    appBoxKitLocator.registerLazySingleton<AppBoxKitStorageService>(
      () => AppBoxKitAppwriteStorageService(
        storage: aw.Storage(client),
        client: client,
      ),
    );

    for (final entity in entities) {
      entity.apply(<E>(registration) {
        appBoxKitLocator.registerLazySingleton<AppBoxKitRepository<E>>(
          () => AppBoxKitAppwriteRepository<E>(
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
      final auth = AppBoxKitAppwriteAuthService(
        account: aw.Account(client),
        idService: idService,
      );
      await auth.initialize();
      appBoxKitLocator.registerSingleton<AppBoxKitAuthService>(auth);
    }
  }

  /// Test-only: clears static state so initialize can run again.
  static void resetForTesting() {
    _config = null;
    _registry = null;
  }
}
