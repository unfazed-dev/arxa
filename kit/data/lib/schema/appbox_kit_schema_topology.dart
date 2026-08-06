import 'appbox_kit_table_schema.dart';

/// Orders schemas so every referenced table precedes its referrers — the
/// order rows must be created in under foreign-key constraints (Supabase) and
/// the order the seeder pushes tables. Shared by both Supabase emitters and
/// the seeder. Multi-table reference cycles are rejected (plain `create
/// table` can't satisfy them); self-references aren't cycles (Postgres allows
/// them within one table); reference targets absent from [schemas] impose no
/// ordering — they're assumed to already exist on the backend.
List<AppBoxKitTableSchema> appBoxKitTopologicalSchemaOrder(List<AppBoxKitTableSchema> schemas) {
  final byTable = {for (final s in schemas) s.table: s};
  final ordered = <AppBoxKitTableSchema>[];
  final state = <String, int>{}; // 0 = visiting, 1 = done

  void visit(String table, List<String> path) {
    final seen = state[table];
    if (seen == 1) return;
    if (seen == 0) {
      throw ArgumentError(
        'reference cycle between tables: ${[...path, table].join(' -> ')}',
      );
    }
    final schema = byTable[table];
    if (schema == null) return; // forward-declared FK — no ordering constraint
    state[table] = 0;
    for (final ref in schema.referenceColumns) {
      if (ref.references == table) continue;
      visit(ref.references!, [...path, table]);
    }
    state[table] = 1;
    ordered.add(schema);
  }

  for (final s in schemas) {
    visit(s.table, const []);
  }
  return ordered;
}
