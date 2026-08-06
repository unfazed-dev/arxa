import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_data/schema/appbox_kit_schema_topology.dart';
import 'package:appbox_kit_data/schema/appbox_kit_table_schema.dart';

/// appBoxKitTopologicalSchemaOrder tests.
///
/// Branches under test:
/// - A 3-table reference chain orders every referenced table before its
///   referrer.
/// - A reference to a table not present in the input schema list throws
///   [ArgumentError].
/// - A 2-table reference cycle throws [ArgumentError] naming the cycle.
/// - A self-referencing table (a `reference` column whose target is its own
///   table) does NOT throw — the emitters already special-case this
///   (`appbox_kit_supabase_sql_emitter.dart` / `appbox_kit_supabase_seed_emitter.dart`
///   skip `ref.references == schema.table` while topo-sorting), so the
///   shared topology helper should behave the same way rather than treating
///   a table's reference to itself as a cycle.
void main() {
  test('referenced-before-referrer ordering across a 3-table chain', () {
    final grandparent = AppBoxKitTableSchema(
      table: 'grandparent',
      columns: const [AppBoxKitColumn.id()],
    );
    final parent = AppBoxKitTableSchema(
      table: 'parent',
      columns: const [
        AppBoxKitColumn.id(),
        AppBoxKitColumn('grandparent', AppBoxKitColumnType.reference, references: 'grandparent'),
      ],
    );
    final child = AppBoxKitTableSchema(
      table: 'child',
      columns: const [
        AppBoxKitColumn.id(),
        AppBoxKitColumn('parent', AppBoxKitColumnType.reference, references: 'parent'),
      ],
    );

    // Deliberately out of dependency order in the input.
    final ordered = appBoxKitTopologicalSchemaOrder([child, parent, grandparent]);

    final names = ordered.map((s) => s.table).toList();
    expect(names.indexOf('grandparent'), lessThan(names.indexOf('parent')));
    expect(names.indexOf('parent'), lessThan(names.indexOf('child')));
  });

  test(
      'reference target absent from the input imposes no ordering '
      '(forward-declared FK, assumed to exist on the backend)', () {
    final orphan = AppBoxKitTableSchema(
      table: 'orphan',
      columns: const [
        AppBoxKitColumn.id(),
        AppBoxKitColumn('missing', AppBoxKitColumnType.reference, references: 'nonexistent'),
      ],
    );

    final ordered = appBoxKitTopologicalSchemaOrder([orphan]);
    expect(ordered.map((s) => s.table), ['orphan']);
  });

  test('2-table cycle throws ArgumentError naming the cycle', () {
    final a = AppBoxKitTableSchema(
      table: 'a',
      columns: const [
        AppBoxKitColumn.id(),
        AppBoxKitColumn('b', AppBoxKitColumnType.reference, references: 'b'),
      ],
    );
    final b = AppBoxKitTableSchema(
      table: 'b',
      columns: const [
        AppBoxKitColumn.id(),
        AppBoxKitColumn('a', AppBoxKitColumnType.reference, references: 'a'),
      ],
    );

    expect(
      () => appBoxKitTopologicalSchemaOrder([a, b]),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.toString(),
          'message',
          allOf(contains('a'), contains('b')),
        ),
      ),
    );
  });

  test('self-reference does not throw', () {
    final tree = AppBoxKitTableSchema(
      table: 'tree_nodes',
      columns: const [
        AppBoxKitColumn.id(),
        AppBoxKitColumn(
          'parent',
          AppBoxKitColumnType.reference,
          references: 'tree_nodes',
          nullable: true,
        ),
      ],
    );

    expect(() => appBoxKitTopologicalSchemaOrder([tree]), returnsNormally);
    expect(appBoxKitTopologicalSchemaOrder([tree]).map((s) => s.table), ['tree_nodes']);
  });
}
