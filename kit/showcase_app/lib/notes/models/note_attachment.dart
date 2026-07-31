/// One media attachment on a [Note], stored inside the note row's
/// `attachments` jsonb column (swap rule 2: nested collections are jsonb,
/// never child tables).
///
/// Binaries themselves live in the app-documents directory —
/// `NotesMediaService` owns the files; rows carry only [fileName] (relative,
/// because the iOS app container path changes across reinstalls) plus
/// metadata. Rows therefore sync to any backend while files stay local — the
/// documented ceiling until a storage seam exists.
library;

enum NoteAttachmentKind { photo, audio }

class NoteAttachment {
  final String id;
  final NoteAttachmentKind kind;

  /// File name relative to the showcase attachments directory.
  final String fileName;

  /// Recording length; null for photos.
  final int? durationMs;
  final DateTime createdAt;

  const NoteAttachment({
    required this.id,
    required this.kind,
    required this.fileName,
    this.durationMs,
    required this.createdAt,
  });

  factory NoteAttachment.fromJson(Map<String, dynamic> json) => NoteAttachment(
        id: json['id'] as String,
        kind: NoteAttachmentKind.values.byName(json['kind'] as String),
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
