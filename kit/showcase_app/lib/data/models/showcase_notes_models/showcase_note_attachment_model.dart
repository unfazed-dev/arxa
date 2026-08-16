/// A model is a pure data class representing a domain entity — fields and
/// serialization only, no behavior, no Flutter, no services.
///
/// This is the data shape for one media attachment on a note — a photo or
/// voice recording's file name and metadata, stored inside the note row's
/// `attachments` jsonb column. The binary file lives in the app-documents
/// directory, owned by the media adapter; the row carries only a relative
/// file name (the app container path changes across reinstalls), so rows
/// sync to any backend while files stay local.
///
/// History: git log --follow -- kit/showcase_app/lib/data/models/showcase_notes_models/showcase_note_attachment_model.dart
library;

import 'package:appbox_kit_showcase_app/enums/showcase_notes_enums/enums.dart';

class ShowcaseNoteAttachmentModel {
  /// The attachment's unique id.
  final String id;

  /// Whether this is a photo or an audio recording.
  final ShowcaseNoteAttachmentKind kind;

  /// File name relative to the showcase attachments directory.
  final String fileName;

  /// Recording length; null for photos.
  final int? durationMs;

  /// When the attachment was added to the note.
  final DateTime createdAt;

  const ShowcaseNoteAttachmentModel({
    required this.id,
    required this.kind,
    required this.fileName,
    this.durationMs,
    required this.createdAt,
  });

  factory ShowcaseNoteAttachmentModel.fromJson(Map<String, dynamic> json) =>
      ShowcaseNoteAttachmentModel(
        id: json['id'] as String,
        kind: ShowcaseNoteAttachmentKind.values.byName(json['kind'] as String),
        fileName: json['file_name'] as String,
        durationMs: json['duration_ms'] as int?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'file_name': fileName,
        'duration_ms': durationMs,
        'created_at': createdAt.toIso8601String(),
      };
}
