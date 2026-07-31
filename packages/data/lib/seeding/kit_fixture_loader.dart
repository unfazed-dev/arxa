import 'dart:convert';

import '../assets/kit_asset_reader.dart';
import '../ids/kit_id_service.dart';
import '../schema/kit_table_schema.dart';

/// Loads hand-authored fixture JSON into canonicalized seed rows.
///
/// Fixtures are the one trust boundary in the seed backend where humans type
/// table/column names by hand, so this loader validates strictly: an unknown
/// table, a row missing `id`, or a typo'd column name all fail loudly at
/// load time instead of seeding silently-wrong data.
///
/// Pure Dart — depends only on the [KitAssetReader] port, never on Flutter's
/// `AssetBundle`/`rootBundle`. The composition root supplies a
/// `KitRootBundleAssetReader`; tests and `dart run` tooling pass a
/// [KitMemoryAssetReader].
class KitFixtureLoader {
  final KitIdService idService;
  final KitAssetReader assetReader;

  KitFixtureLoader({required this.idService, required this.assetReader});

  /// Loads each `assets/seed/<table>.json` in [assetPaths] — table name is
  /// the filename minus `.json` — into rows keyed by canonical id, validated
  /// and canonicalized against [schemasByTable].
  Future<Map<String, Map<String, Map<String, dynamic>>>> load({
    required List<String> assetPaths,
    required Map<String, KitTableSchema> schemasByTable,
  }) async {
    final result = <String, Map<String, Map<String, dynamic>>>{};

    for (final assetPath in assetPaths) {
      final fileName = assetPath.split('/').last;
      final table = fileName.endsWith('.json')
          ? fileName.substring(0, fileName.length - '.json'.length)
          : fileName;

      final schema = schemasByTable[table];
      if (schema == null) {
        throw ArgumentError(
          'Fixture "$assetPath" names table "$table", which has no registered KitTableSchema',
        );
      }

      final raw = await assetReader.readString(assetPath);
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw ArgumentError('Fixture "$assetPath" must be a JSON array of rows');
      }

      final columnNames = schema.columns.map((c) => c.name).toSet();
      final tableRows = <String, Map<String, dynamic>>{};

      for (final entry in decoded) {
        if (entry is! Map) {
          throw ArgumentError('Fixture "$assetPath" contains a non-object row');
        }
        final row = Map<String, dynamic>.from(entry);

        if (row['id'] == null) {
          throw ArgumentError('Fixture "$assetPath" has a row with no "id"');
        }

        for (final column in row.keys) {
          if (!columnNames.contains(column)) {
            throw ArgumentError(
              'Fixture "$assetPath" table "$table" has unknown column "$column"',
            );
          }
        }

        final canonicalRow = idService.canonicalizeRow(schema, row);
        final canonicalId = canonicalRow['id'] as String;
        if (tableRows.containsKey(canonicalId)) {
          throw ArgumentError(
            'Fixture "$assetPath" table "$table" has a duplicate canonical id '
            '"$canonicalId" (from seed key "${row['id']}")',
          );
        }
        tableRows[canonicalId] = canonicalRow;
      }

      result[table] = tableRows;
    }

    return result;
  }
}
