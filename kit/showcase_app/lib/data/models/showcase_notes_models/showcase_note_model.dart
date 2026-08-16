/// A model is a pure data class representing a domain entity — fields and
/// serialization only, no behavior, no Flutter, no services.
///
/// This is the data shape for a note — its text, when it was created and edited,
/// whether it's pinned or soft-deleted, and its attachments. iOS-style: there is
/// no separate title column — the title and snippet derive from the body's first
/// lines, and `deleted_at` implements Recently Deleted (soft delete, restorable)
/// without a second table.
///
/// History: git log --follow -- kit/showcase_app/lib/data/models/showcase_notes_models/showcase_note_model.dart
library;

import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_attachment_model.dart';
import 'package:appbox_kit_showcase_app/enums/showcase_notes_enums/enums.dart';

class ShowcaseNoteModel {
  /// The note's unique id.
  final String id;

  /// The folder this note lives in.
  final String folderId;

  /// The user who owns this note.
  final String owner;

  /// The note's full text; the list title and snippet derive from its first lines.
  final String body;

  /// Whether the note is pinned to the top of the inbox.
  final bool pinned;

  /// Photos and voice recordings attached to the note.
  final List<ShowcaseNoteAttachmentModel> attachments;

  /// When the note was soft-deleted; null means it's live (Recently Deleted is
  /// this set, not a separate table).
  final DateTime? deletedAt;

  /// When the note was first created.
  final DateTime createdAt;

  /// When the note was last edited.
  final DateTime updatedAt;

  const ShowcaseNoteModel({
    required this.id,
    required this.folderId,
    required this.owner,
    required this.body,
    this.pinned = false,
    this.attachments = const [],
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isDeleted => deletedAt != null;

  /// First non-empty line, like iOS Notes' list title.
  String get title {
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return 'New Note';
  }

  /// The line after the title line, for the list's secondary text.
  String get snippet {
    var seenTitle = false;
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (!seenTitle) {
        seenTitle = true;
        continue;
      }
      return trimmed;
    }
    return attachments.isEmpty ? 'No additional text' : _attachmentSummary;
  }

  String get _attachmentSummary {
    final photos =
        attachments.where((a) => a.kind == ShowcaseNoteAttachmentKind.photo);
    final audio =
        attachments.where((a) => a.kind == ShowcaseNoteAttachmentKind.audio);
    return [
      if (photos.isNotEmpty) '📷 ${photos.length}',
      if (audio.isNotEmpty) '🎙 ${audio.length}',
    ].join('  ');
  }

  ShowcaseNoteModel copyWith({
    String? folderId,
    String? body,
    bool? pinned,
    List<ShowcaseNoteAttachmentModel>? attachments,
    DateTime? Function()? deletedAt,
    DateTime? updatedAt,
  }) =>
      ShowcaseNoteModel(
        id: id,
        folderId: folderId ?? this.folderId,
        owner: owner,
        body: body ?? this.body,
        pinned: pinned ?? this.pinned,
        attachments: attachments ?? this.attachments,
        // Nullable-field copyWith: pass `() => null` to clear, omit to keep.
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory ShowcaseNoteModel.fromJson(Map<String, dynamic> json) =>
      ShowcaseNoteModel(
        id: json['id'] as String,
        folderId: json['folder_id'] as String,
        owner: json['owner'] as String,
        body: json['body'] as String,
        pinned: json['pinned'] as bool? ?? false,
        attachments: (json['attachments'] as List? ?? const [])
            .map((a) => ShowcaseNoteAttachmentModel.fromJson(
                Map<String, dynamic>.from(a as Map)))
            .toList(),
        deletedAt: json['deleted_at'] == null
            ? null
            : DateTime.parse(json['deleted_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'folder_id': folderId,
        'owner': owner,
        'body': body,
        'pinned': pinned,
        'attachments': attachments.map((a) => a.toJson()).toList(),
        'deleted_at': deletedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
