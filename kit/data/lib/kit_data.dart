import 'package:appwrite/appwrite.dart' as aw;
import 'package:ui_library/ui_library.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'assets/kit_asset_reader.dart';
import 'assets/kit_root_bundle_asset_reader.dart';
import 'auth/appwrite/kit_appwrite_auth_service.dart';
import 'auth/kit_auth_service.dart';
import 'auth/seed/kit_seed_auth_service.dart';
import 'auth/supabase/kit_supabase_auth_service.dart';
import 'config/kit_data_config.dart';
import 'config/kit_seed_profile.dart';
import 'ids/kit_id_service.dart';
import 'models/kit_entity_registration.dart';
import 'repositories/appwrite/kit_appwrite_repository.dart';
import 'repositories/kit_repository.dart';
import 'repositories/seed/kit_seed_persistence.dart';
import 'repositories/seed/kit_seed_repository.dart';
import 'repositories/seed/kit_seed_store.dart';
import 'repositories/supabase/kit_supabase_repository.dart';
import 'schema/kit_schema_registry.dart';
import 'seeding/kit_fixture_loader.dart';
import 'storage/appwrite/kit_appwrite_storage_service.dart';
import 'storage/kit_storage_service.dart';
import 'storage/seed/kit_seed_storage_service.dart';
import 'storage/seed/kit_storage_persistence.dart';
import 'storage/supabase/kit_supabase_storage_service.dart';

/// Entry point the host calls once in `main()`, after `setupLocator()`:
///
/// ```dart
/// await KitData.initialize(
///   config: const KitDataConfig(
///     backend: KitDataBackend.supabase,
///     supabase: KitSupabaseConfig(url: ..., publishableKey: ...),
///   ),
///   entities: [productRegistration, categoryRegistration],
///   fixtureAssets: ['assets/seed/products.json', ...],
/// );
/// ```
///
/// Registers one `KitRepository<T>` per entity into the shared locator for
/// the configured backend. The kit never self-registers — the host owns the
/// call, matching appbox_kit's host-integration contract.
class KitData {
  KitData._();

  static KitDataConfig? _config;
  static KitSchemaRegistry? _registry;

  static KitDataConfig get config {
    final c = _config;
    if (c == null) {
      throw StateError('KitData.initialize has not been called');
    }
    return c;
  }

  static KitSchemaRegistry get registry {
    final r = _registry;
    if (r == null) {
      throw StateError('KitData.initialize has not been called');
    }
    return r;
  }

  static Future<void> initialize({
    required KitDataConfig config,
    required List<KitEntityRegistration<dynamic>> entities,
    List<String> fixtureAssets = const [],
    KitAssetReader? assetReader,
  }) async {
    if (_config != null) {
      throw StateError('KitData.initialize called twice');
    }
    config.validate();

    final idService = KitIdService(namespace: config.idNamespace);
    final registry = KitSchemaRegistry();
    for (final entity in entities) {
      registry.register(entity);
    }

    _config = config;
    _registry = registry;
    locator.registerSingleton<KitIdService>(idService);
    locator.registerSingleton<KitSchemaRegistry>(registry);

    final reader = assetReader ?? const KitRootBundleAssetReader();

    switch (config.backend) {
      case KitDataBackend.seed:
        await _initializeSeed(config, entities, registry, idService,
            fixtureAssets: fixtureAssets, assetReader: reader);
      case KitDataBackend.supabase:
        await _initializeSupabase(config, entities, idService);
      case KitDataBackend.appwrite:
        await _initializeAppwrite(config, entities, idService);
    }
  }

  static Future<void> _initializeSeed(
    KitDataConfig config,
    List<KitEntityRegistration<dynamic>> entities,
    KitSchemaRegistry registry,
    KitIdService idService, {
    required List<String> fixtureAssets,
    required KitAssetReader assetReader,
  }) async {
    final persistence = switch (config.seedPersistence) {
      KitSeedPersistenceMode.none => KitNoPersistence(),
      KitSeedPersistenceMode.snapshot => KitSnapshotPersistence(),
    };
    final store = KitSeedStore(persistence: persistence);
    // Boot precedence per table: snapshot while the bundled fixtures are
    // unchanged, re-seed when they differ (see resolveBootTables — this is
    // what lets shipped fixture updates reach devices that already persisted
    // a snapshot, instead of the snapshot shadowing them forever).
    final fixtures =
        await KitFixtureLoader(idService: idService, assetReader: assetReader).load(
      assetPaths: fixtureAssets,
      schemasByTable: registry.schemasByTable,
    );
    final resolution = resolveBootTables(
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
    locator.registerSingleton<KitSeedStore>(store);

    // Blob-storage seam: same seedPersistence switch as tables.
    final storagePersistence = switch (config.seedPersistence) {
      KitSeedPersistenceMode.none => const KitNoStoragePersistence(),
      KitSeedPersistenceMode.snapshot => const KitSnapshotStoragePersistence(),
    };
    locator.registerLazySingleton<KitStorageService>(
      () => KitSeedStorageService(persistence: storagePersistence),
    );

    for (final entity in entities) {
      entity.apply(<E>(registration) {
        locator.registerLazySingleton<KitRepository<E>>(
          () => KitSeedRepository<E>(
            store: store,
            registration: registration,
            idService: idService,
            // Seed Profile injection (slow/failing); defaults to pass-through.
            profile: config.seedProfile ?? const KitSeedProfile(),
          ),
        );
        return null;
      });
    }

    final authConfig = config.auth;
    if (authConfig != null) {
      final auth = KitSeedAuthService(
        store: store,
        idService: idService,
        fakeUsersAsset: authConfig.fakeUsersAsset,
        assetReader: assetReader,
      );
      await auth.initialize();
      locator.registerSingleton<KitAuthService>(auth);
    }
  }

  static Future<void> _initializeSupabase(
    KitDataConfig config,
    List<KitEntityRegistration<dynamic>> entities,
    KitIdService idService,
  ) async {
    final supabase = config.supabase!;
    await sb.Supabase.initialize(
      url: supabase.url,
      publishableKey: supabase.publishableKey,
    );
    final client = sb.Supabase.instance.client;

    locator.registerLazySingleton<KitStorageService>(
      () => KitSupabaseStorageService(client: client),
    );

    for (final entity in entities) {
      entity.apply(<E>(registration) {
        locator.registerLazySingleton<KitRepository<E>>(
          () => KitSupabaseRepository<E>(
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
      final auth = KitSupabaseAuthService(
        client: client,
        config: authConfig,
        idService: idService,
      );
      await auth.initialize();
      locator.registerSingleton<KitAuthService>(auth);
    }
  }

  static Future<void> _initializeAppwrite(
    KitDataConfig config,
    List<KitEntityRegistration<dynamic>> entities,
    KitIdService idService,
  ) async {
    final appwrite = config.appwrite!;
    final client = aw.Client()
        .setEndpoint(appwrite.endpoint)
        .setProject(appwrite.projectId);
    final tablesDB = aw.TablesDB(client);
    final realtime = aw.Realtime(client);

    locator.registerLazySingleton<KitStorageService>(
      () => KitAppwriteStorageService(
        storage: aw.Storage(client),
        client: client,
      ),
    );

    for (final entity in entities) {
      entity.apply(<E>(registration) {
        locator.registerLazySingleton<KitRepository<E>>(
          () => KitAppwriteRepository<E>(
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
      final auth = KitAppwriteAuthService(
        account: aw.Account(client),
        idService: idService,
      );
      await auth.initialize();
      locator.registerSingleton<KitAuthService>(auth);
    }
  }

  /// Test-only: clears static state so initialize can run again.
  static void resetForTesting() {
    _config = null;
    _registry = null;
  }
}
