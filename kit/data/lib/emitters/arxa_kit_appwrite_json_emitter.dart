/// Generates an Appwrite `appwrite.json` "tables" fragment from
/// [ArxaKitTableSchema] descriptors. Pure Dart — no `flutter` imports — so it
/// runs under `dart run` outside the Flutter toolchain (see
/// `example/generate.dart`).
///
/// Format verified 2026-07-12 against the Appwrite CLI docs
/// (https://appwrite.io/docs/tooling/command-line/tables, Appwrite 1.9.x /
/// SDK 25.x era, post collections-to-tables rename): the top-level key is
/// `tables` (not `collections`), each table has `$id`, `databaseId`, `name`,
/// `enabled`, `rowSecurity`, `$permissions`, and a `columns` array; each
/// column has `key`, `type`, `required`, `array`, and (for sized types)
/// `size`. Verified column type names, from the CLI's
/// `create-<type>-column` commands: `string`, `integer`, `float`,
/// `boolean`, `datetime`, plus `email` / `enum` / `ip` / `url` /
/// `relationship`, none of which this emitter uses. Appwrite has **no**
/// native JSON column type, so `jsonb` schema columns are emitted as a
/// large `string` column here (see [_column]).
library;

import 'dart:convert';

import '../schema/arxa_kit_table_schema.dart';

class ArxaKitAppwriteJsonEmitter {
  /// Renders [schemas] into a pretty-printed `{"tables": [...]}` JSON
  /// fragment for [databaseId], suitable for merging into an operator's
  /// `appwrite.json`. Permissions are left empty (`[]`) — like Supabase RLS,
  /// row/table permissions are the operator's responsibility.
  ///
  /// The `id` column needs no entry: Appwrite rows carry their canonical ID
  /// as `$id` automatically.
  String emit({
    required List<ArxaKitTableSchema> schemas,
    required String databaseId,
  }) {
    final fragment = <String, dynamic>{
      'tables': schemas.map((s) => _table(s, databaseId)).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(fragment);
  }

  Map<String, dynamic> _table(ArxaKitTableSchema schema, String databaseId) {
    return <String, dynamic>{
      r'$id': schema.table,
      'databaseId': databaseId,
      'name': schema.table,
      'enabled': true,
      'rowSecurity': false,
      r'$permissions': <String>[],
      'columns': schema.columns
          .where((c) => c.type != ArxaKitColumnType.id)
          .map(_column)
          .toList(),
    };
  }

  Map<String, dynamic> _column(ArxaKitColumn column) {
    final out = <String, dynamic>{
      'key': column.name,
      'type': _type(column.type),
      'required': !column.nullable,
      'array': false,
    };

    switch (column.type) {
      case ArxaKitColumnType.text:
        out['size'] = 4096;
      case ArxaKitColumnType.jsonb:
        // No JSON column type exists in Appwrite (see class doc comment).
        // 1,048,576 chars (1 MiB) sits well above the ~16,384-char
        // breakpoint where Appwrite's MySQL/MariaDB-backed string columns
        // switch from VARCHAR to a TEXT variant, so nested `jsonb` payloads
        // (e.g. a product's `tags` array) aren't truncated or rejected.
        out['size'] = 1048576;
      case ArxaKitColumnType.reference:
        // Deliberately a plain 36-char string holding the canonical UUID —
        // NOT an Appwrite relationship column. This keeps every row
        // single-table and portable across backends, matching the kit's
        // swap rule that repository methods stay single-table (no joins).
        out['size'] = 36;
      case ArxaKitColumnType.id:
      case ArxaKitColumnType.integer:
      case ArxaKitColumnType.real:
      case ArxaKitColumnType.boolean:
      case ArxaKitColumnType.timestamptz:
        break;
    }

    return out;
  }

  String _type(ArxaKitColumnType type) {
    switch (type) {
      case ArxaKitColumnType.text:
      case ArxaKitColumnType.jsonb:
      case ArxaKitColumnType.reference:
        return 'string';
      case ArxaKitColumnType.integer:
        return 'integer';
      case ArxaKitColumnType.real:
        return 'float';
      case ArxaKitColumnType.boolean:
        return 'boolean';
      case ArxaKitColumnType.timestamptz:
        return 'datetime';
      case ArxaKitColumnType.id:
        throw ArgumentError(
          'id columns are never emitted — Appwrite rows carry `\$id`',
        );
    }
  }
}
