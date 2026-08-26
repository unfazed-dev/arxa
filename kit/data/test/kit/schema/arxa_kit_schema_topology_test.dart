import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_data/schema/arxa_kit_schema_topology.dart';
import 'package:arxa_kit_data/schema/arxa_kit_table_schema.dart';

/// arxaKitTopologicalSchemaOrder tests.
///
/// Branches under test:
/// - A 3-table reference chain orders every referenced table before its
///   referrer.
/// - A reference to a table not present in the input schema list throws
///   [ArgumentError].
/// - A 2-table reference cycle throws [ArgumentError] naming the cycle.
/// - A self-referencing table (a `reference` column whose target is its own
///   table) does NOT throw — the emitters already special-case this
///   (`arxa_kit_supabase_sql_emitter.dart` / `arxa_kit_supabase_seed_emitter.dart`
///   skip `ref.references == schema.table` while topo-sorting), so the
///   shared topology helper should behave the same way rather than treating
///   a table's reference to itself as a cycle.
void main() {
  test('kit.data.schema-topology — referenced-before-referrer ordering across a 3-table chain', () {
    final grandparent = ArxaKitTableSchema(
      table: 'grandparent',
      columns: const [ArxaKitColumn.id()],
    );
    final parent = ArxaKitTableSchema(
      table: 'parent',
      columns: const [
        ArxaKitColumn.id(),
        ArxaKitColumn('grandparent', ArxaKitColumnType.reference, references: 'grandparent'),
      ],
    );
    final child = ArxaKitTableSchema(
      table: 'child',
      columns: const [
        ArxaKitColumn.id(),
        ArxaKitColumn('parent', ArxaKitColumnType.reference, references: 'parent'),
      ],
    );

    // Deliberately out of dependency order in the input.
    final ordered = arxaKitTopologicalSchemaOrder([child, parent, grandparent]);

    final names = ordered.map((s) => s.table).toList();
    expect(names.indexOf('grandparent'), lessThan(names.indexOf('parent')));
    expect(names.indexOf('parent'), lessThan(names.indexOf('child')));
  });

  test(
      'kit.data.schema-topology — reference target absent from the input '
      'imposes no ordering (forward-declared FK, assumed to exist on the '
      'backend)', () {
    final orphan = ArxaKitTableSchema(
      table: 'orphan',
      columns: const [
        ArxaKitColumn.id(),
        ArxaKitColumn('missing', ArxaKitColumnType.reference, references: 'nonexistent'),
      ],
    );

    final ordered = arxaKitTopologicalSchemaOrder([orphan]);
    expect(ordered.map((s) => s.table), ['orphan']);
  });

  test('kit.data.schema-topology — 2-table cycle throws ArgumentError naming the cycle', () {
    final a = ArxaKitTableSchema(
      table: 'a',
      columns: const [
        ArxaKitColumn.id(),
        ArxaKitColumn('b', ArxaKitColumnType.reference, references: 'b'),
      ],
    );
    final b = ArxaKitTableSchema(
      table: 'b',
      columns: const [
        ArxaKitColumn.id(),
        ArxaKitColumn('a', ArxaKitColumnType.reference, references: 'a'),
      ],
    );

    expect(
      () => arxaKitTopologicalSchemaOrder([a, b]),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.toString(),
          'message',
          allOf(contains('a'), contains('b')),
        ),
      ),
    );
  });

  test('kit.data.schema-topology — self-reference does not throw', () {
    final tree = ArxaKitTableSchema(
      table: 'tree_nodes',
      columns: const [
        ArxaKitColumn.id(),
        ArxaKitColumn(
          'parent',
          ArxaKitColumnType.reference,
          references: 'tree_nodes',
          nullable: true,
        ),
      ],
    );

    expect(() => arxaKitTopologicalSchemaOrder([tree]), returnsNormally);
    expect(arxaKitTopologicalSchemaOrder([tree]).map((s) => s.table), ['tree_nodes']);
  });
}
