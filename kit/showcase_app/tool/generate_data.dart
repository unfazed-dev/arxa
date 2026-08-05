/// Pure-Dart CLI that renders the app's backend artifacts from the schema
/// descriptors in `lib/data/schemas/` — the schemas are the single source of
/// truth; everything under `data/generated/` is derived ("do not hand-edit").
///
/// Run from the package directory:
///
/// ```sh
/// dart run tool/generate_data.dart          # write data/generated/
/// dart run tool/generate_data.dart --check  # fail if data/generated/ is stale
/// ```
///
/// Reads `data/seed/<table>.json` for each declared table (paths resolved
/// relative to this script, not the caller's cwd). `--check` regenerates in
/// memory and diffs — exit 1 lists the stale files; the scaffold gate's data
/// section runs this.
library;

import 'dart:convert';
import 'dart:io';

import 'package:appbox_kit_data/emitters/kit_appwrite_json_emitter.dart';
import 'package:appbox_kit_data/emitters/kit_supabase_seed_emitter.dart';
import 'package:appbox_kit_data/emitters/kit_supabase_sql_emitter.dart';
import 'package:appbox_kit_data/ids/kit_id_service.dart';
import 'package:appbox_kit_data/schema/kit_table_schema.dart';

import 'package:appbox_kit_showcase_app/data/schemas/showcase_notes_schemas/showcase_note_folder_schema.dart';
import 'package:appbox_kit_showcase_app/data/schemas/showcase_notes_schemas/showcase_note_schema.dart';

/// The app's tables, reference order (the emitters re-derive it anyway).
final List<KitTableSchema> showcaseSchemas = [
  showcaseNoteFolderSchema,
  showcaseNoteSchema,
];

Future<Map<String, String>> _emitAll(Directory seedDir, String databaseId) async {
  final fixturesByTable = <String, List<Map<String, dynamic>>>{};
  final schemasByTable = <String, KitTableSchema>{};
  for (final schema in showcaseSchemas) {
    schemasByTable[schema.table] = schema;
    final fixtureFile = File('${seedDir.path}/${schema.table}.json');
    final decoded = jsonDecode(await fixtureFile.readAsString()) as List;
    fixturesByTable[schema.table] = decoded.cast<Map<String, dynamic>>();
  }

  return {
    'supabase_migration.sql': KitSupabaseSqlEmitter().emit(showcaseSchemas),
    'supabase_seed.sql': KitSupabaseSeedEmitter(idService: KitIdService())
        .emit(fixturesByTable: fixturesByTable, schemasByTable: schemasByTable),
    'appwrite.tables.json': KitAppwriteJsonEmitter()
        .emit(schemas: showcaseSchemas, databaseId: databaseId),
  };
}

Future<void> main(List<String> args) async {
  final scriptDir = File(Platform.script.toFilePath()).parent;
  final packageDir = scriptDir.parent;
  final seedDir = Directory('${packageDir.path}/data/seed');
  final outDir = Directory('${packageDir.path}/data/generated');
  final check = args.contains('--check');

  // The Appwrite database id is the package name: deterministic, unique per
  // app, no placeholder to drift.
  final pubspec = File('${packageDir.path}/pubspec.yaml').readAsStringSync();
  final packageName =
      RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1)!;

  final outputs = await _emitAll(seedDir, packageName);

  if (check) {
    final stale = <String>[
      for (final entry in outputs.entries)
        if (!File('${outDir.path}/${entry.key}').existsSync() ||
            File('${outDir.path}/${entry.key}').readAsStringSync() !=
                entry.value)
          entry.key,
    ];
    if (stale.isEmpty) {
      stdout.writeln('data/generated/ is fresh.');
      return;
    }
    stderr.writeln('data/generated/ is STALE: ${stale.join(', ')}\n'
        'Run `dart run tool/generate_data.dart` and commit the result.');
    exitCode = 1;
    return;
  }

  outDir.createSync(recursive: true);
  for (final entry in outputs.entries) {
    final file = File('${outDir.path}/${entry.key}')
      ..writeAsStringSync(entry.value);
    stdout.writeln(file.path);
  }
}
