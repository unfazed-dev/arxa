import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_data/assets/appbox_kit_asset_reader.dart';
import 'package:appbox_kit_data/ids/appbox_kit_id_service.dart';
import 'package:appbox_kit_data/schema/appbox_kit_table_schema.dart';
import 'package:appbox_kit_data/seeding/appbox_kit_fixture_loader.dart';

/// AppBoxKitFixtureLoader tests.
///
/// Branches under test:
/// - Happy path: two tables where a `products` row references a
///   `categories` row by seed key — the loaded product's reference value
///   equals the canonical id minted for the category's seed key (relations
///   survive canonicalization).
/// - Error paths, each a strict-validation trust boundary: an asset naming
///   a table with no registered schema; a row missing `id`; a row with a
///   column name absent from the schema; two rows in the same fixture that
///   canonicalize to the same id (duplicate seed key).
void main() {
  final idService = AppBoxKitIdService();

  final categories = AppBoxKitTableSchema(
    table: 'categories',
    columns: const [AppBoxKitColumn.id(), AppBoxKitColumn('name', AppBoxKitColumnType.text)],
  );
  final products = AppBoxKitTableSchema(
    table: 'products',
    columns: const [
      AppBoxKitColumn.id(),
      AppBoxKitColumn('name', AppBoxKitColumnType.text),
      AppBoxKitColumn(
        'category',
        AppBoxKitColumnType.reference,
        references: 'categories',
      ),
    ],
  );
  final schemasByTable = {'categories': categories, 'products': products};

  AppBoxKitFixtureLoader loaderFor(Map<String, String> assets) =>
      AppBoxKitFixtureLoader(
          idService: idService, assetReader: AppBoxKitMemoryAssetReader(assets));

  test('kit.data.fixture-loader — relations survive: product reference equals category canonical id', () async {
    final assets = {
      'assets/seed/categories.json': jsonEncode([
        {'id': 'cat-1', 'name': 'Widgets'},
      ]),
      'assets/seed/products.json': jsonEncode([
        {'id': 'p-1', 'name': 'Sprocket', 'category': 'cat-1'},
      ]),
    };

    final result = await loaderFor(assets).load(
      assetPaths: assets.keys.toList(),
      schemasByTable: schemasByTable,
    );

    final categoryCanonicalId = idService.canonicalId('categories', 'cat-1');
    final productRow = result['products']!.values.single;

    expect(result['categories']!.keys.single, categoryCanonicalId);
    expect(productRow['category'], categoryCanonicalId);
  });

  test('kit.data.fixture-loader — unknown table (no registered schema) throws', () async {
    final assets = {
      'assets/seed/widgets.json': jsonEncode([
        {'id': 'w-1'},
      ]),
    };

    await expectLater(
      loaderFor(assets).load(
        assetPaths: assets.keys.toList(),
        schemasByTable: schemasByTable,
      ),
      throwsArgumentError,
    );
  });

  test('kit.data.fixture-loader — row missing id throws', () async {
    final assets = {
      'assets/seed/categories.json': jsonEncode([
        {'name': 'no id here'},
      ]),
    };

    await expectLater(
      loaderFor(assets).load(
        assetPaths: assets.keys.toList(),
        schemasByTable: schemasByTable,
      ),
      throwsArgumentError,
    );
  });

  test('kit.data.fixture-loader — unknown column name throws', () async {
    final assets = {
      'assets/seed/categories.json': jsonEncode([
        {'id': 'cat-1', 'name': 'Widgets', 'typo_column': 'oops'},
      ]),
    };

    await expectLater(
      loaderFor(assets).load(
        assetPaths: assets.keys.toList(),
        schemasByTable: schemasByTable,
      ),
      throwsArgumentError,
    );
  });

  test('kit.data.fixture-loader — duplicate canonical id (two rows, same seed key) throws', () async {
    final assets = {
      'assets/seed/categories.json': jsonEncode([
        {'id': 'cat-1', 'name': 'Widgets'},
        {'id': 'cat-1', 'name': 'Widgets again'},
      ]),
    };

    await expectLater(
      loaderFor(assets).load(
        assetPaths: assets.keys.toList(),
        schemasByTable: schemasByTable,
      ),
      throwsArgumentError,
    );
  });
}
