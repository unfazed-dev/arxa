import 'dart:convert';

import 'package:appwrite/appwrite.dart' as aw;
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../arxa_kit_data.dart';

/// Pushes the same fixtures the seed backend boots from into the remote
/// backend selected by [ArxaKitData.config] — the operator supplies credentials,
/// the kit supplies the data.
///
/// Idempotent by construction: canonical IDs are deterministic (ADR-0001), so
/// every push upserts the same rows. Tables are pushed in reference order so
/// Supabase foreign keys are satisfied.
class ArxaKitDataSeeder {
  final ArxaKitIdService _idService;
  final ArxaKitSchemaRegistry _registry;

  ArxaKitDataSeeder({ArxaKitIdService? idService, ArxaKitSchemaRegistry? registry})
      : _idService = idService ?? arxaKitLocator<ArxaKitIdService>(),
        _registry = registry ?? arxaKitLocator<ArxaKitSchemaRegistry>();

  Future<void> push({
    required List<String> fixtureAssets,
    ArxaKitAssetReader? assetReader,
  }) async {
    final config = ArxaKitData.config;
    if (config.backend == ArxaKitDataBackend.seed) {
      throw StateError(
        'ArxaKitDataSeeder.push targets a remote backend; the seed backend loads '
        'fixtures itself at initialize.',
      );
    }

    if (config.backend == ArxaKitDataBackend.plugin) {
      // kit/data cannot push to a backend it cannot name — a plugin that owns
      // its seeding story implements ArxaKitPluginSeeder and push delegates
      // (cairn: fixtures flow through its repositories' ordinary upserts).
      // NB: the two plugin interfaces are unrelated types, so `is` does not
      // promote — the if-case binds the seeder view explicitly.
      if (config.plugin case final ArxaKitPluginSeeder seeder) {
        await seeder.seedFixtures(fixtureAssets, assetReader: assetReader);
        return;
      }
      throw StateError(
        'ArxaKitDataSeeder.push does not know how to seed the plugin '
        'backend ("${config.plugin!.name}") — the plugin does not implement '
        'ArxaKitPluginSeeder; seed through the plugin package.',
      );
    }

    final tables = await ArxaKitFixtureLoader(
      idService: _idService,
      assetReader: assetReader ?? const ArxaKitRootBundleAssetReader(),
    ).load(
      assetPaths: fixtureAssets,
      schemasByTable: _registry.schemasByTable,
    );

    final order = arxaKitTopologicalSchemaOrder(
      _registry.registrations.map((r) => r.schema).toList(),
    );

    for (final schema in order) {
      final rows = tables[schema.table];
      if (rows == null || rows.isEmpty) continue;
      switch (config.backend) {
        case ArxaKitDataBackend.supabase:
          await _pushSupabase(schema, rows.values.toList());
        case ArxaKitDataBackend.appwrite:
          await _pushAppwrite(config, schema, rows.values.toList());
        case ArxaKitDataBackend.seed:
        case ArxaKitDataBackend.plugin:
          break; // unreachable — handled above
      }
    }
  }

  Future<void> _pushSupabase(
    ArxaKitTableSchema schema,
    List<Map<String, dynamic>> rows,
  ) async {
    await sb.Supabase.instance.client.from(schema.table).upsert(rows);
  }

  Future<void> _pushAppwrite(
    ArxaKitDataConfig config,
    ArxaKitTableSchema schema,
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
            column?.type == ArxaKitColumnType.jsonb && entry.value != null
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
