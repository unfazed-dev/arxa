import 'package:file_selector/file_selector.dart';

import 'arxa_kit_picked_document.dart';

/// Port for picking existing documents from the OS file picker.
///
/// This is the **one working path** in arxa_kit_documents; scan / OCR / PDF
/// are stubs. Backed in production by `file_selector`.
abstract interface class ArxaKitDocumentPickerService {
  /// Opens the system picker for a single document, optionally constrained to
  /// [extensions] (e.g. `['pdf', 'png']`; empty = any file).
  Future<ArxaKitPickedDocument?> pickDocument({List<String> extensions});

  /// Opens the system picker allowing multiple selections.
  Future<List<ArxaKitPickedDocument>> pickDocuments({List<String> extensions});
}

/// Production [ArxaKitDocumentPickerService] backed by `file_selector`.
///
/// Native-first: `file_selector` wraps the OS document pickers
/// (`UIDocumentPickerViewController` on iOS, the Storage Access Framework on
/// Android). This adapter only translates extension filters into
/// [XTypeGroup]s and projects [XFile]s onto [ArxaKitPickedDocument].
class FileSelectorArxaKitDocumentPickerService
    implements ArxaKitDocumentPickerService {
  const FileSelectorArxaKitDocumentPickerService();

  @override
  Future<ArxaKitPickedDocument?> pickDocument({
    List<String> extensions = const [],
  }) async {
    final file = await openFile(acceptedTypeGroups: _typeGroups(extensions));
    if (file == null) return null;
    return _toDocument(file);
  }

  @override
  Future<List<ArxaKitPickedDocument>> pickDocuments({
    List<String> extensions = const [],
  }) async {
    final files = await openFiles(acceptedTypeGroups: _typeGroups(extensions));
    return files.map(_toDocument).toList();
  }

  List<XTypeGroup> _typeGroups(List<String> extensions) {
    if (extensions.isEmpty) return const [];
    return [XTypeGroup(label: 'documents', extensions: extensions)];
  }

  ArxaKitPickedDocument _toDocument(XFile file) => ArxaKitPickedDocument(
        name: file.name,
        path: file.path.isEmpty ? null : file.path,
        mimeType: file.mimeType,
        readBytes: file.readAsBytes,
      );
}
