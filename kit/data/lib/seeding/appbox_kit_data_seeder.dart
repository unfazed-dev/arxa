import 'dart:convert';

import 'package:appwrite/appwrite.dart' as aw;
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../appbox_kit_data.dart';

/// Pushes the same fixtures the seed backend boots from into the remote
/// backend selected by [AppBoxKitData.config] — the operator supplies credentials,
/// the kit supplies the data.
///
/// Idempotent by construction: canonical IDs are deterministic (ADR-0001), so
/// every push upserts the same rows. Tables are pushed in reference order so
/// Supabase foreign keys are satisfied.
class AppBoxKitDataSeeder {
  final AppBoxKitIdService _idService;
  final AppBoxKitSchemaRegistry _registry;

  AppBoxKitDataSeeder({AppBoxKitIdService? idService, AppBoxKitSchemaRegistry? registry})
      : _idService = idService ?? appBoxKitLocator<AppBoxKitIdService>(),
        _registry = registry ?? appBoxKitLocator<AppBoxKitSchemaRegistry>();

  Future<void> push({
    required List<String> fixtureAssets,
    AppBoxKitAssetReader? assetReader,
  }) async {
    final config = AppBoxKitData.config;
    if (config.backend == AppBoxKitDataBackend.seed) {
      throw StateError(
        'AppBoxKitDataSeeder.push targets a remote backend; the seed backend loads '
        'fixtures itself at initialize.',
      );
    }

    final tables = await AppBoxKitFixtureLoader(
      idService: _idService,
      assetReader: assetReader ?? const AppBoxKitRootBundleAssetReader(),
    ).load(
      assetPaths: fixtureAssets,
      schemasByTable: _registry.schemasByTable,
    );

    final order = appBoxKitTopologicalSchemaOrder(
      _registry.registrations.map((r) => r.schema).toList(),
    );

    for (final schema in order) {
      final rows = tables[schema.table];
      if (rows == null || rows.isEmpty) continue;
      switch (config.backend) {
        case AppBoxKitDataBackend.supabase:
          await _pushSupabase(schema, rows.values.toList());
        case AppBoxKitDataBackend.appwrite:
          await _pushAppwrite(config, schema, rows.values.toList());
        case AppBoxKitDataBackend.seed:
          break; // unreachable — guarded above
      }
    }
  }

  Future<void> _pushSupabase(
    AppBoxKitTableSchema schema,
    List<Map<String, dynamic>> rows,
  ) async {
    await sb.Supabase.instance.client.from(schema.table).upsert(rows);
  }

  Future<void> _pushAppwrite(
    AppBoxKitDataConfig config,
    AppBoxKitTableSchema schema,
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
            column?.type == AppBoxKitColumnType.jsonb && entry.value != null
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
