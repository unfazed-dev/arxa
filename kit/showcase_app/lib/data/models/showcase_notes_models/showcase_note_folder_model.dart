/// A model is a pure data class representing a domain entity — fields and
/// serialization only, no behavior, no Flutter, no services.
///
/// This is the data shape for a user folder — a named grouping like "Notes" or
/// "Work". Recently Deleted is not a folder row; it's the virtual set of notes
/// with `deleted_at` set, computed by the facade (iOS treats it as a system view).
///
/// History: git log --follow -- kit/showcase_app/lib/data/models/showcase_notes_models/showcase_note_folder_model.dart
library;

class ShowcaseNoteFolderModel {
  /// The folder's unique id.
  final String id;

  /// The folder's display name.
  final String name;

  /// Where this folder sits in the folder list.
  final int sortOrder;

  /// Canonical id of the owning `kit_auth_users` row — lines fixtures up with
  /// the fake-auth session (both canonicalize through the same namespace).
  final String owner;

  /// When the folder was created.
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
