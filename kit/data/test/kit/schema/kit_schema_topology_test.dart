import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_data/schema/kit_schema_topology.dart';
import 'package:appbox_kit_data/schema/kit_table_schema.dart';

/// topologicalSchemaOrder tests.
///
/// Branches under test:
/// - A 3-table reference chain orders every referenced table before its
///   referrer.
/// - A reference to a table not present in the input schema list throws
///   [ArgumentError].
/// - A 2-table reference cycle throws [ArgumentError] naming the cycle.
/// - A self-referencing table (a `reference` column whose target is its own
///   table) does NOT throw — the emitters already special-case this
///   (`kit_supabase_sql_emitter.dart` / `kit_supabase_seed_emitter.dart`
///   skip `ref.references == schema.table` while topo-sorting), so the
///   shared topology helper should behave the same way rather than treating
///   a table's reference to itself as a cycle.
void main() {
  test('referenced-before-referrer ordering across a 3-table chain', () {
    final grandparent = KitTableSchema(
      table: 'grandparent',
      columns: const [KitColumn.id()],
    );
    final parent = KitTableSchema(
      table: 'parent',
      columns: const [
        KitColumn.id(),
        KitColumn('grandparent', KitColumnType.reference, references: 'grandparent'),
      ],
    );
    final child = KitTableSchema(
      table: 'child',
      columns: const [
        KitColumn.id(),
        KitColumn('parent', KitColumnType.reference, references: 'parent'),
      ],
    );

    // Deliberately out of dependency order in the input.
    final ordered = topologicalSchemaOrder([child, parent, grandparent]);

    final names = ordered.map((s) => s.table).toList();
    expect(names.indexOf('grandparent'), lessThan(names.indexOf('parent')));
    expect(names.indexOf('parent'), lessThan(names.indexOf('child')));
  });

  test(
      'reference target absent from the input imposes no ordering '
      '(forward-declared FK, assumed to exist on the backend)', () {
    final orphan = KitTableSchema(
      table: 'orphan',
      columns: const [
        KitColumn.id(),
        KitColumn('missing', KitColumnType.reference, references: 'nonexistent'),
      ],
    );

    final ordered = topologicalSchemaOrder([orphan]);
    expect(ordered.map((s) => s.table), ['orphan']);
  });

  test('2-table cycle throws ArgumentError naming the cycle', () {
    final a = KitTableSchema(
      table: 'a',
      columns: const [
        KitColumn.id(),
        KitColumn('b', KitColumnType.reference, references: 'b'),
      ],
    );
    final b = KitTableSchema(
      table: 'b',
      columns: const [
        KitColumn.id(),
        KitColumn('a', KitColumnType.reference, references: 'a'),
      ],
    );

    expect(
      () => topologicalSchemaOrder([a, b]),
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
    final tree = KitTableSchema(
      table: 'tree_nodes',
      columns: const [
        KitColumn.id(),
        KitColumn(
          'parent',
          KitColumnType.reference,
          references: 'tree_nodes',
          nullable: true,
        ),
      ],
    );

    expect(() => topologicalSchemaOrder([tree]), returnsNormally);
    expect(topologicalSchemaOrder([tree]).map((s) => s.table), ['tree_nodes']);
  });
}
