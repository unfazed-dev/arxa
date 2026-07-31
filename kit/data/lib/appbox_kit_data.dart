/// appbox_kit_data — the data layer for appbox_kit apps.
///
/// One backend at a time — seed (fixture-backed, optional snapshot
/// persistence), Supabase (default), or Appwrite — selected by
/// [KitDataConfig] and wired by `KitData.initialize`. Repositories are the
/// swap seam; facades compose them into UI state; canonical IDs are
/// deterministic across every backend (ADR-0001).
library;

// Entry point & config
export 'kit_data.dart';
export 'config/kit_data_config.dart';
export 'config/kit_seed_profile.dart';

// Assets (AssetBundle inversion: pure-Dart port + Flutter adapter)
export 'assets/kit_asset_reader.dart';
export 'assets/kit_root_bundle_asset_reader.dart';

// Auth
export 'auth/kit_auth_types.dart';
export 'auth/kit_auth_service.dart';
export 'auth/seed/kit_seed_auth_service.dart';
export 'auth/supabase/kit_supabase_auth_service.dart';
export 'auth/appwrite/kit_appwrite_auth_service.dart';

// IDs
export 'ids/kit_id_service.dart';

// Schema
export 'schema/kit_table_schema.dart';
export 'schema/kit_schema_registry.dart';
export 'schema/kit_schema_topology.dart';

// Models
export 'models/kit_entity_registration.dart';

// Query
export 'query/kit_query.dart';

// Repositories
export 'repositories/kit_repository.dart';
export 'repositories/seed/kit_seed_store.dart';
export 'repositories/seed/kit_seed_persistence.dart';
export 'repositories/seed/kit_seed_repository.dart';
export 'repositories/supabase/kit_supabase_repository.dart';
export 'repositories/appwrite/kit_appwrite_repository.dart';

// Seeding
export 'seeding/kit_fixture_loader.dart';
export 'seeding/kit_data_seeder.dart';

// Facades
export 'facades/kit_data_facade.dart';

// Emitters (pure Dart — safe in `dart run` tools)
export 'emitters/kit_supabase_sql_emitter.dart';
export 'emitters/kit_supabase_seed_emitter.dart';
export 'emitters/kit_appwrite_json_emitter.dart';
