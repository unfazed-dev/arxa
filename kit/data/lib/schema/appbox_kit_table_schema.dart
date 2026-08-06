/// Schema descriptors — the single source of truth for every backend.
///
/// One [AppBoxKitTableSchema] per table drives fixture validation, the seed store,
/// and the emitters that generate Supabase migration SQL and the Appwrite
/// `appwrite.json` tables fragment.
library;

enum AppBoxKitColumnType {
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

  /// Foreign key holding another table's canonical ID. [AppBoxKitColumn.references]
  /// names the target table.
  reference,
}

class AppBoxKitColumn {
  final String name;
  final AppBoxKitColumnType type;
  final bool nullable;

  /// Target table name; required iff [type] is [AppBoxKitColumnType.reference].
  final String? references;

  const AppBoxKitColumn(
    this.name,
    this.type, {
    this.nullable = false,
    this.references,
  })  : assert(
          (type == AppBoxKitColumnType.reference) == (references != null),
          'references must be set exactly when type is reference',
        ),
        assert(
          type != AppBoxKitColumnType.id || name == 'id',
          'the id column must be named "id"',
        );

  const AppBoxKitColumn.id() : this('id', AppBoxKitColumnType.id);
}

class AppBoxKitTableSchema {
  final String table;
  final List<AppBoxKitColumn> columns;

  const AppBoxKitTableSchema({required this.table, required this.columns});

  AppBoxKitColumn get idColumn =>
      columns.firstWhere((c) => c.type == AppBoxKitColumnType.id,
          orElse: () => throw StateError(
              'AppBoxKitTableSchema("$table") has no id column'));

  List<AppBoxKitColumn> get referenceColumns =>
      columns.where((c) => c.type == AppBoxKitColumnType.reference).toList();

  AppBoxKitColumn? column(String name) {
    for (final c in columns) {
      if (c.name == name) return c;
    }
    return null;
  }
}
