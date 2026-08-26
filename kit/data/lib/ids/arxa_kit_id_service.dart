import 'package:uuid/uuid.dart';

import '../query/arxa_kit_query.dart';
import '../schema/arxa_kit_table_schema.dart';

/// The single authority that turns anything used as an identifier into a
/// canonical ID (ADR-0001).
///
/// Values that already parse as UUIDs pass through (lowercased). Anything
/// else — fixture seed keys like `p-1`, ints, arbitrary strings — becomes
/// `uuid.v5(namespace, '<table>:<key>')`, so the same input always yields the
/// same UUID on every backend. The result is valid both as a Postgres `uuid`
/// and as an Appwrite row ID (36-char hyphenated, allowed charset).
class ArxaKitIdService {
  /// Fixed default namespace. Changing this orphans every previously seeded
  /// row — see ADR-0001 before touching it.
  static const String kDefaultNamespace =
      'c2a1f0d4-7b3e-4c5a-9d8f-2e6b1a0c4f7d';

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  final String _namespace;
  static const Uuid _uuid = Uuid();

  ArxaKitIdService({String? namespace})
      : _namespace = namespace ?? kDefaultNamespace {
    if (!isUuid(_namespace)) {
      throw ArgumentError.value(
        namespace,
        'namespace',
        'ArxaKitIdService namespace must be a valid UUID',
      );
    }
  }

  bool isUuid(String value) => _uuidPattern.hasMatch(value);

  /// Canonicalizes [key] for [table]. UUID inputs pass through unchanged
  /// (lowercased); everything else is minted deterministically.
  String canonicalId(String table, Object key) {
    final raw = key.toString();
    if (raw.isEmpty) {
      throw ArgumentError.value(key, 'key', 'id key must not be empty');
    }
    if (isUuid(raw)) return raw.toLowerCase();
    return _uuid.v5(_namespace, '$table:$raw');
  }

  /// Canonicalizes a wire-shape row against its [schema]: the `id` column and
  /// every reference column (against the referenced table's namespace-key).
  /// Null reference values pass through; everything else in the row is
  /// untouched. Shared by the fixture loader and every repository write path.
  Map<String, dynamic> canonicalizeRow(
    ArxaKitTableSchema schema,
    Map<String, dynamic> row,
  ) {
    final out = Map<String, dynamic>.from(row);
    final id = out[schema.idColumn.name];
    if (id == null) {
      throw ArgumentError(
        'row for "${schema.table}" has no "${schema.idColumn.name}" value',
      );
    }
    out[schema.idColumn.name] = canonicalId(schema.table, id);
    for (final ref in schema.referenceColumns) {
      final value = out[ref.name];
      if (value != null) {
        out[ref.name] = canonicalId(ref.references!, value);
      }
    }
    return out;
  }

  /// Canonicalizes a partial wire-shape patch: every reference column
  /// present (against the referenced table's namespace-key). Null values
  /// pass through — a null patch value clears the column. The id column
  /// must NOT appear: a patch can never re-address a row.
  Map<String, dynamic> canonicalizePatch(
    ArxaKitTableSchema schema,
    Map<String, dynamic> patch,
  ) {
    if (patch.containsKey(schema.idColumn.name)) {
      throw ArgumentError(
        'patch for "${schema.table}" must not contain '
        '"${schema.idColumn.name}" — a patch cannot re-address a row',
      );
    }
    final out = Map<String, dynamic>.from(patch);
    for (final ref in schema.referenceColumns) {
      final value = out[ref.name];
      if (value != null) {
        out[ref.name] = canonicalId(ref.references!, value);
      }
    }
    return out;
  }

  /// Canonicalizes `eq` filter values that target the id column or a
  /// reference column, so callers can query by seed key ("cat-1") or UUID
  /// interchangeably on every backend. Other filters pass through — gt/lt on
  /// an id has no meaningful seed-key semantics.
  ArxaKitQuery canonicalizeQuery(ArxaKitTableSchema schema, ArxaKitQuery query) {
    if (query.filters.isEmpty) return query;
    var changed = false;
    final filters = query.filters.map((filter) {
      if (filter.op != ArxaKitFilterOp.eq) return filter;
      final column = schema.column(filter.column);
      final targetTable = switch (column?.type) {
        ArxaKitColumnType.id => schema.table,
        ArxaKitColumnType.reference => column!.references!,
        _ => null,
      };
      if (targetTable == null) return filter;
      changed = true;
      return ArxaKitFilter.eq(filter.column, canonicalId(targetTable, filter.value));
    }).toList();
    if (!changed) return query;
    return ArxaKitQuery(
      filters: filters,
      orderBy: query.orderBy,
      descending: query.descending,
      limit: query.limit,
    );
  }
}
