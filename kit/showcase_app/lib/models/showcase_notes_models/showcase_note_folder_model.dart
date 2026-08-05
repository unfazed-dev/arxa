// Targeted imports (not the barrel) keep this file pure-Dart so
// `tool/generate.dart` can compile it as a CLI — the barrel pulls in the
// Supabase/Appwrite clients and their FFI deps.
import 'package:appbox_kit_data/auth/kit_auth_types.dart';
import 'package:appbox_kit_data/models/kit_entity_registration.dart';
import 'package:appbox_kit_data/schema/kit_table_schema.dart';

/// A user folder ("Notes", "Work", …). Recently Deleted is NOT a folder row —
/// it's the virtual set of notes with `deleted_at` set, computed by
/// `ShowcaseNotesFacadeService`, matching how iOS treats it as a system view.
class ShowcaseNoteFolderModel {
  final String id;
  final String name;
  final int sortOrder;

  /// Canonical id of the owning `kit_auth_users` row — lines fixtures up with
  /// the fake-auth session (both canonicalize through the same namespace).
  final String owner;
  final DateTime createdAt;

  const ShowcaseNoteFolderModel({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.owner,
    required this.createdAt,
  });

  ShowcaseNoteFolderModel copyWith({String? name}) => ShowcaseNoteFolderModel(
        id: id,
        name: name ?? this.name,
        sortOrder: sortOrder,
        owner: owner,
        createdAt: createdAt,
      );

  factory ShowcaseNoteFolderModel.fromJson(Map<String, dynamic> json) => ShowcaseNoteFolderModel(
        id: json['id'] as String,
        name: json['name'] as String,
        sortOrder: json['sort_order'] as int,
        owner: json['owner'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sort_order': sortOrder,
        'owner': owner,
        'created_at': createdAt.toIso8601String(),
      };
}

const kNoteFoldersTable = 'notes_folders';

const noteFolderSchema = KitTableSchema(
  table: kNoteFoldersTable,
  columns: [
    KitColumn.id(),
    KitColumn('name', KitColumnType.text),
    KitColumn('sort_order', KitColumnType.integer),
    // References the reserved auth users table: exists as a real seed-store
    // table locally, as an id namespace everywhere. Phase-2 ceiling: the SQL
    // emitter will emit a FK to "kit_auth_users", which on Supabase should be
    // mapped to auth.users (or the FK dropped) by the operator.
    KitColumn('owner', KitColumnType.reference, references: kKitAuthUsersTable),
    KitColumn('created_at', KitColumnType.timestamptz),
  ],
);

final showcaseNoteFolderRegistration = KitEntityRegistration<ShowcaseNoteFolderModel>(
  schema: noteFolderSchema,
  fromJson: ShowcaseNoteFolderModel.fromJson,
  toJson: (folder) => folder.toJson(),
);
