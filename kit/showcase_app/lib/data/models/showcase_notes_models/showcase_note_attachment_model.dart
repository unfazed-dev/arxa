/// One media attachment on a [ShowcaseNoteModel], stored inside the note row's
/// `attachments` jsonb column (swap rule 2: nested collections are jsonb,
/// never child tables).
///
/// Binaries themselves live in the app-documents directory —
/// `ShowcaseNotesMediaAdapterService` owns the files; rows carry only [fileName] (relative,
/// because the iOS app container path changes across reinstalls) plus
/// metadata. Rows therefore sync to any backend while files stay local — the
/// documented ceiling until a storage seam exists.
library;

enum ShowcaseNoteAttachmentKind { photo, audio }

class ShowcaseNoteAttachmentModel {
  final String id;
  final ShowcaseNoteAttachmentKind kind;

  /// File name relative to the showcase attachments directory.
  final String fileName;

  /// Recording length; null for photos.
  final int? durationMs;
  final DateTime createdAt;

  const ShowcaseNoteAttachmentModel({
    required this.id,
    required this.kind,
    required this.fileName,
    this.durationMs,
    required this.createdAt,
  });

  factory ShowcaseNoteAttachmentModel.fromJson(Map<String, dynamic> json) => ShowcaseNoteAttachmentModel(
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
