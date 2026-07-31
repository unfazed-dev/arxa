/// Schema descriptors — the single source of truth for every backend.
///
/// One [KitTableSchema] per table drives fixture validation, the seed store,
/// and the emitters that generate Supabase migration SQL and the Appwrite
/// `appwrite.json` tables fragment.
library;

enum KitColumnType {
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

  /// Foreign key holding another table's canonical ID. [KitColumn.references]
  /// names the target table.
  reference,
}

class KitColumn {
  final String name;
  final KitColumnType type;
  final bool nullable;

  /// Target table name; required iff [type] is [KitColumnType.reference].
  final String? references;

  const KitColumn(
    this.name,
    this.type, {
    this.nullable = false,
    this.references,
  })  : assert(
          (type == KitColumnType.reference) == (references != null),
          'references must be set exactly when type is reference',
        ),
        assert(
          type != KitColumnType.id || name == 'id',
          'the id column must be named "id"',
        );

  const KitColumn.id() : this('id', KitColumnType.id);
}

class KitTableSchema {
  final String table;
  final List<KitColumn> columns;

  const KitTableSchema({required this.table, required this.columns});

  KitColumn get idColumn =>
      columns.firstWhere((c) => c.type == KitColumnType.id,
          orElse: () => throw StateError(
              'KitTableSchema("$table") has no id column'));

  List<KitColumn> get referenceColumns =>
      columns.where((c) => c.type == KitColumnType.reference).toList();

  KitColumn? column(String name) {
    for (final c in columns) {
      if (c.name == name) return c;
    }
    return null;
  }
}
