import 'package:file_selector/file_selector.dart';

import 'kit_picked_document.dart';

/// Port for picking existing documents from the OS file picker.
///
/// This is the **one working path** in appbox_kit_documents; scan / OCR / PDF
/// are stubs. Backed in production by `file_selector`.
abstract interface class KitDocumentPickerService {
  /// Opens the system picker for a single document, optionally constrained to
  /// [extensions] (e.g. `['pdf', 'png']`; empty = any file).
  Future<KitPickedDocument?> pickDocument({List<String> extensions});

  /// Opens the system picker allowing multiple selections.
  Future<List<KitPickedDocument>> pickDocuments({List<String> extensions});
}

/// Production [KitDocumentPickerService] backed by `file_selector`.
///
/// Native-first: `file_selector` wraps the OS document pickers
/// (`UIDocumentPickerViewController` on iOS, the Storage Access Framework on
/// Android). This adapter only translates extension filters into
/// [XTypeGroup]s and projects [XFile]s onto [KitPickedDocument].
class FileSelectorKitDocumentPickerService
    implements KitDocumentPickerService {
  const FileSelectorKitDocumentPickerService();

  @override
  Future<KitPickedDocument?> pickDocument({
    List<String> extensions = const [],
  }) async {
    final file = await openFile(acceptedTypeGroups: _typeGroups(extensions));
    if (file == null) return null;
    return _toDocument(file);
  }

  @override
  Future<List<KitPickedDocument>> pickDocuments({
    List<String> extensions = const [],
  }) async {
    final files = await openFiles(acceptedTypeGroups: _typeGroups(extensions));
    return files.map(_toDocument).toList();
  }

  List<XTypeGroup> _typeGroups(List<String> extensions) {
    if (extensions.isEmpty) return const [];
    return [XTypeGroup(label: 'documents', extensions: extensions)];
  }

  KitPickedDocument _toDocument(XFile file) => KitPickedDocument(
        name: file.name,
        path: file.path.isEmpty ? null : file.path,
        mimeType: file.mimeType,
        readBytes: file.readAsBytes,
      );
}
