import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_attachment_model.dart';

/// A note. iOS-style: no separate title column — [title] and [snippet] derive
/// from [body]'s first lines; `deleted_at` implements Recently Deleted
/// (soft delete, restorable) without a second table.
class ShowcaseNoteModel {
  final String id;
  final String folderId;
  final String owner;
  final String body;
  final bool pinned;
  final List<ShowcaseNoteAttachmentModel> attachments;
  final DateTime? deletedAt;
  final DateTime createdAt;
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
    final photos = attachments.where((a) => a.kind == ShowcaseNoteAttachmentKind.photo);
    final audio = attachments.where((a) => a.kind == ShowcaseNoteAttachmentKind.audio);
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

  factory ShowcaseNoteModel.fromJson(Map<String, dynamic> json) => ShowcaseNoteModel(
        id: json['id'] as String,
        folderId: json['folder_id'] as String,
        owner: json['owner'] as String,
        body: json['body'] as String,
        pinned: json['pinned'] as bool? ?? false,
        attachments: (json['attachments'] as List? ?? const [])
            .map((a) =>
                ShowcaseNoteAttachmentModel.fromJson(Map<String, dynamic>.from(a as Map)))
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
