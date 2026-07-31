import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_data/emitters/kit_appwrite_json_emitter.dart';
import 'package:appbox_kit_data/emitters/kit_supabase_seed_emitter.dart';
import 'package:appbox_kit_data/emitters/kit_supabase_sql_emitter.dart';
import 'package:appbox_kit_data/ids/kit_id_service.dart';
import 'package:appbox_kit_data/schema/kit_table_schema.dart';

/// Emitter tests, covering all three pure-Dart generators.
///
/// - [KitSupabaseSqlEmitter]: the referenced table's `create table`
///   statement precedes the referrer's; the reference column's SQL type
///   includes the `references` clause; `not null` is respected; `jsonb`
///   maps to `jsonb`; the RLS disclaimer `-- note:` line is present.
/// - [KitSupabaseSeedEmitter]: a single-quote in a string value comes out
///   doubled (SQL escaping); a jsonb value is cast with `::jsonb`; an
///   absent nullable column becomes `NULL`; the upsert clause is
///   `on conflict ("id") do update`; emitted ids are canonical (36-char)
///   UUIDs.
/// - [KitAppwriteJsonEmitter]: the output round-trips through `jsonDecode`
///   with a top-level `tables` key; each column has `key`/`type`/`required`;
///   a `jsonb` column is emitted as a `string` column; a `reference` column
///   is a size-36 `string`; no column named `id` is emitted (Appwrite rows
///   carry `$id` automatically).
void main() {
  final categories = KitTableSchema(
    table: 'categories',
    columns: const [KitColumn.id(), KitColumn('name', KitColumnType.text)],
  );
  final products = KitTableSchema(
    table: 'products',
    columns: const [
      KitColumn.id(),
      KitColumn('name', KitColumnType.text),
      KitColumn(
        'category',
        KitColumnType.reference,
        references: 'categories',
      ),
      KitColumn('tags', KitColumnType.jsonb, nullable: true),
      KitColumn('description', KitColumnType.text, nullable: true),
    ],
  );

  group('KitSupabaseSqlEmitter', () {
    test('referenced table precedes referrer; reference/not-null/jsonb render correctly', () {
      final sql = KitSupabaseSqlEmitter().emit([products, categories]);

      final categoriesIndex = sql.indexOf('create table if not exists "categories"');
      final productsIndex = sql.indexOf('create table if not exists "products"');
      expect(categoriesIndex, greaterThanOrEqualTo(0));
      expect(productsIndex, greaterThan(categoriesIndex));

      expect(sql, contains('"category" uuid references "categories"("id") not null'));
      expect(sql, contains('"name" text not null'));
      expect(sql, contains('"tags" jsonb'));
      expect(sql, isNot(contains('"tags" jsonb not null')));
      expect(
        sql,
        contains(
          "-- note: Row Level Security policies and grants are the operator's responsibility; none are emitted here.",
        ),
      );
    });
  });

  group('KitSupabaseSeedEmitter', () {
    final idService = KitIdService();
    final emitter = KitSupabaseSeedEmitter(idService: idService);

    test('single quote doubled, jsonb cast, absent nullable -> NULL, upsert clause, canonical ids', () {
      final sql = emitter.emit(
        fixturesByTable: {
          'categories': [
            {'id': 'cat-1', 'name': "O'Brien"},
          ],
          'products': [
            {
              'id': 'p-1',
              'name': 'Widget',
              'category': 'cat-1',
              'tags': ['a', 'b'],
              // 'description' intentionally absent (nullable).
            },
          ],
        },
        schemasByTable: {'categories': categories, 'products': products},
      );

      expect(sql, contains("O''Brien"));
      expect(sql, contains('::jsonb'));
      expect(sql, contains('NULL'));
      expect(sql, contains('on conflict ("id") do update'));

      final uuidPattern = RegExp(
        r"values \('([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'",
      );
      final match = uuidPattern.firstMatch(sql);
      expect(match, isNotNull, reason: 'expected a canonical uuid literal in the output');
      expect(match!.group(1), hasLength(36));
      expect(match.group(1), idService.canonicalId('categories', 'cat-1'));
    });
  });

  group('KitAppwriteJsonEmitter', () {
    test('parses via jsonDecode with tables/columns shaped as expected', () {
      final json = KitAppwriteJsonEmitter().emit(
        schemas: [categories, products],
        databaseId: 'db-1',
      );

      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded.containsKey('tables'), isTrue);

      final tables = decoded['tables'] as List<dynamic>;
      final productsTable =
          tables.firstWhere((t) => (t as Map)[r'$id'] == 'products') as Map<String, dynamic>;
      final columns = (productsTable['columns'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      for (final column in columns) {
        expect(column.containsKey('key'), isTrue);
        expect(column.containsKey('type'), isTrue);
        expect(column.containsKey('required'), isTrue);
      }

      final tagsColumn = columns.firstWhere((c) => c['key'] == 'tags');
      expect(tagsColumn['type'], 'string');

      final categoryColumn = columns.firstWhere((c) => c['key'] == 'category');
      expect(categoryColumn['type'], 'string');
      expect(categoryColumn['size'], 36);

      expect(columns.any((c) => c['key'] == 'id'), isFalse);
    });
  });
}
