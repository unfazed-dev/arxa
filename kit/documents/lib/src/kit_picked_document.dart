import 'dart:typed_data';

/// A document the user picked from the OS file picker.
///
/// Plugin-neutral: `file_selector`'s `XFile` stays behind the seam. Bytes are
/// read lazily via [readBytes] so a large file is not loaded until needed (and
/// so the value stays cheap to pass around / fake).
class KitPickedDocument {
  const KitPickedDocument({
    required this.name,
    required this.readBytes,
    this.path,
    this.mimeType,
  });

  /// File name including extension, e.g. `"invoice.pdf"`.
  final String name;

  /// Absolute path on native platforms; `null` on web.
  final String? path;

  /// MIME type if the platform reported one.
  final String? mimeType;

  /// Reads the document's bytes on demand.
  final Future<Uint8List> Function() readBytes;

  @override
  String toString() =>
      'KitPickedDocument($name, path: $path, mimeType: $mimeType)';
}
