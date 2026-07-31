import 'dart:convert';

import 'package:appwrite/appwrite.dart' as aw;
import 'package:ui_library/ui_library.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../assets/kit_asset_reader.dart';
import '../assets/kit_root_bundle_asset_reader.dart';
import '../config/kit_data_config.dart';
import '../ids/kit_id_service.dart';
import '../kit_data.dart';
import '../schema/kit_schema_registry.dart';
import '../schema/kit_schema_topology.dart';
import '../schema/kit_table_schema.dart';
import '../seeding/kit_fixture_loader.dart';

/// Pushes the same fixtures the seed backend boots from into the remote
/// backend selected by [KitData.config] — the operator supplies credentials,
/// the kit supplies the data.
///
/// Idempotent by construction: canonical IDs are deterministic (ADR-0001), so
/// every push upserts the same rows. Tables are pushed in reference order so
/// Supabase foreign keys are satisfied.
class KitDataSeeder {
  final KitIdService _idService;
  final KitSchemaRegistry _registry;

  KitDataSeeder({KitIdService? idService, KitSchemaRegistry? registry})
      : _idService = idService ?? locator<KitIdService>(),
        _registry = registry ?? locator<KitSchemaRegistry>();

  Future<void> push({
    required List<String> fixtureAssets,
    KitAssetReader? assetReader,
  }) async {
    final config = KitData.config;
    if (config.backend == KitDataBackend.seed) {
      throw StateError(
        'KitDataSeeder.push targets a remote backend; the seed backend loads '
        'fixtures itself at initialize.',
      );
    }

    final tables = await KitFixtureLoader(
      idService: _idService,
      assetReader: assetReader ?? const KitRootBundleAssetReader(),
    ).load(
      assetPaths: fixtureAssets,
      schemasByTable: _registry.schemasByTable,
    );

    final order = topologicalSchemaOrder(
      _registry.registrations.map((r) => r.schema).toList(),
    );

    for (final schema in order) {
      final rows = tables[schema.table];
      if (rows == null || rows.isEmpty) continue;
      switch (config.backend) {
        case KitDataBackend.supabase:
          await _pushSupabase(schema, rows.values.toList());
        case KitDataBackend.appwrite:
          await _pushAppwrite(config, schema, rows.values.toList());
        case KitDataBackend.seed:
          break; // unreachable — guarded above
      }
    }
  }

  Future<void> _pushSupabase(
    KitTableSchema schema,
    List<Map<String, dynamic>> rows,
  ) async {
    await sb.Supabase.instance.client.from(schema.table).upsert(rows);
  }

  Future<void> _pushAppwrite(
    KitDataConfig config,
    KitTableSchema schema,
    List<Map<String, dynamic>> rows,
  ) async {
    final client = aw.Client()
        .setEndpoint(config.appwrite!.endpoint)
        .setProject(config.appwrite!.projectId);
    final tablesDB = aw.TablesDB(client);
    for (final row in rows) {
      // Appwrite has no json column type: jsonb columns travel as strings.
      final data = <String, dynamic>{};
      for (final entry in row.entries) {
        if (entry.key == schema.idColumn.name) continue;
        final column = schema.column(entry.key);
        data[entry.key] =
            column?.type == KitColumnType.jsonb && entry.value != null
                ? jsonEncode(entry.value)
                : entry.value;
      }
      await tablesDB.upsertRow(
        databaseId: config.appwrite!.databaseId,
        tableId: schema.table,
        rowId: row[schema.idColumn.name] as String,
        data: data,
      );
    }
  }
}
