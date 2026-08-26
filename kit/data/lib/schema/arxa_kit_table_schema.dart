/// Schema descriptors — the single source of truth for every backend.
///
/// One [ArxaKitTableSchema] per table drives fixture validation, the seed store,
/// and the emitters that generate Supabase migration SQL and the Appwrite
/// `appwrite.json` tables fragment.
library;

enum ArxaKitColumnType {
  /// Primary key. Exactly one per table, always named `id`, always a
  /// canonical UUID.
  id,
  text,
  integer,
  real,
  boolean,
  timestamptz,

  /// Nested collections live here — never child tables — so every repository
  /// method stays single-table and realtime-streamable (swap rule 2).
  jsonb,

  /// Foreign key holding another table's canonical ID. [ArxaKitColumn.references]
  /// names the target table.
  reference,
}

class ArxaKitColumn {
  final String name;
  final ArxaKitColumnType type;
  final bool nullable;

  /// Target table name; required iff [type] is [ArxaKitColumnType.reference].
  final String? references;

  const ArxaKitColumn(
    this.name,
    this.type, {
    this.nullable = false,
    this.references,
  })  : assert(
          (type == ArxaKitColumnType.reference) == (references != null),
          'references must be set exactly when type is reference',
        ),
        assert(
          type != ArxaKitColumnType.id || name == 'id',
          'the id column must be named "id"',
        );

  const ArxaKitColumn.id() : this('id', ArxaKitColumnType.id);
}

class ArxaKitTableSchema {
  final String table;
  final List<ArxaKitColumn> columns;

  const ArxaKitTableSchema({required this.table, required this.columns});

  ArxaKitColumn get idColumn =>
      columns.firstWhere((c) => c.type == ArxaKitColumnType.id,
          orElse: () => throw StateError(
              'ArxaKitTableSchema("$table") has no id column'));

  List<ArxaKitColumn> get referenceColumns =>
      columns.where((c) => c.type == ArxaKitColumnType.reference).toList();

  ArxaKitColumn? column(String name) {
    for (final c in columns) {
      if (c.name == name) return c;
    }
    return null;
  }
}
