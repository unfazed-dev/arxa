/// Pure-Dart CLI that exercises the three schema/seed emitters end to end.
///
/// Run from the package directory:
///
/// ```sh
/// dart run example/generate.dart
/// ```
///
/// Reads `example/assets/seed/*.json` (paths resolved relative to this
/// script, not the caller's cwd) and writes the generated Supabase
/// migration, Supabase seed, and Appwrite tables fragment under
/// `example/generated/`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:appbox_kit_data/emitters/kit_appwrite_json_emitter.dart';
import 'package:appbox_kit_data/emitters/kit_supabase_seed_emitter.dart';
import 'package:appbox_kit_data/emitters/kit_supabase_sql_emitter.dart';
import 'package:appbox_kit_data/ids/kit_id_service.dart';
import 'package:appbox_kit_data/schema/kit_table_schema.dart';

import 'schema.dart';

Future<void> main() async {
  final scriptDir = File(Platform.script.toFilePath()).parent;
  final seedDir = Directory('${scriptDir.path}/assets/seed');
  final outDir = Directory('${scriptDir.path}/generated')
    ..createSync(recursive: true);

  final fixturesByTable = <String, List<Map<String, dynamic>>>{};
  final schemasByTable = <String, KitTableSchema>{};
  for (final schema in exampleSchemas) {
    schemasByTable[schema.table] = schema;
    final fixtureFile = File('${seedDir.path}/${schema.table}.json');
    final decoded = jsonDecode(await fixtureFile.readAsString()) as List;
    fixturesByTable[schema.table] = decoded.cast<Map<String, dynamic>>();
  }

  final migrationSql = KitSupabaseSqlEmitter().emit(exampleSchemas);

  final seedSql = KitSupabaseSeedEmitter(idService: KitIdService()).emit(
    fixturesByTable: fixturesByTable,
    schemasByTable: schemasByTable,
  );

  final appwriteJson = KitAppwriteJsonEmitter().emit(
    schemas: exampleSchemas,
    databaseId: 'example_db',
  );

  final migrationFile = File('${outDir.path}/supabase_migration.sql')
    ..writeAsStringSync(migrationSql);
  final seedFile = File('${outDir.path}/seed.sql')
    ..writeAsStringSync(seedSql);
  final appwriteFile = File('${outDir.path}/appwrite.tables.json')
    ..writeAsStringSync(appwriteJson);

  stdout
    ..writeln(migrationFile.path)
    ..writeln(seedFile.path)
    ..writeln(appwriteFile.path);
}
