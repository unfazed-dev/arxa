/// Generates an Appwrite `appwrite.json` "tables" fragment from
/// [AppBoxKitTableSchema] descriptors. Pure Dart — no `flutter` imports — so it
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

import '../schema/appbox_kit_table_schema.dart';

class AppBoxKitAppwriteJsonEmitter {
  /// Renders [schemas] into a pretty-printed `{"tables": [...]}` JSON
  /// fragment for [databaseId], suitable for merging into an operator's
  /// `appwrite.json`. Permissions are left empty (`[]`) — like Supabase RLS,
  /// row/table permissions are the operator's responsibility.
  ///
  /// The `id` column needs no entry: Appwrite rows carry their canonical ID
  /// as `$id` automatically.
  String emit({
    required List<AppBoxKitTableSchema> schemas,
    required String databaseId,
  }) {
    final fragment = <String, dynamic>{
      'tables': schemas.map((s) => _table(s, databaseId)).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(fragment);
  }

  Map<String, dynamic> _table(AppBoxKitTableSchema schema, String databaseId) {
    return <String, dynamic>{
      r'$id': schema.table,
      'databaseId': databaseId,
      'name': schema.table,
      'enabled': true,
      'rowSecurity': false,
      r'$permissions': <String>[],
      'columns': schema.columns
          .where((c) => c.type != AppBoxKitColumnType.id)
          .map(_column)
          .toList(),
    };
  }

  Map<String, dynamic> _column(AppBoxKitColumn column) {
    final out = <String, dynamic>{
      'key': column.name,
      'type': _type(column.type),
      'required': !column.nullable,
      'array': false,
    };

    switch (column.type) {
      case AppBoxKitColumnType.text:
        out['size'] = 4096;
      case AppBoxKitColumnType.jsonb:
        // No JSON column type exists in Appwrite (see class doc comment).
        // 1,048,576 chars (1 MiB) sits well above the ~16,384-char
        // breakpoint where Appwrite's MySQL/MariaDB-backed string columns
        // switch from VARCHAR to a TEXT variant, so nested `jsonb` payloads
        // (e.g. a product's `tags` array) aren't truncated or rejected.
        out['size'] = 1048576;
      case AppBoxKitColumnType.reference:
        // Deliberately a plain 36-char string holding the canonical UUID —
        // NOT an Appwrite relationship column. This keeps every row
        // single-table and portable across backends, matching the kit's
        // swap rule that repository methods stay single-table (no joins).
        out['size'] = 36;
      case AppBoxKitColumnType.id:
      case AppBoxKitColumnType.integer:
      case AppBoxKitColumnType.real:
      case AppBoxKitColumnType.boolean:
      case AppBoxKitColumnType.timestamptz:
        break;
    }

    return out;
  }

  String _type(AppBoxKitColumnType type) {
    switch (type) {
      case AppBoxKitColumnType.text:
      case AppBoxKitColumnType.jsonb:
      case AppBoxKitColumnType.reference:
        return 'string';
      case AppBoxKitColumnType.integer:
        return 'integer';
      case AppBoxKitColumnType.real:
        return 'float';
      case AppBoxKitColumnType.boolean:
        return 'boolean';
      case AppBoxKitColumnType.timestamptz:
        return 'datetime';
      case AppBoxKitColumnType.id:
        throw ArgumentError(
          'id columns are never emitted — Appwrite rows carry `\$id`',
        );
    }
  }
}
