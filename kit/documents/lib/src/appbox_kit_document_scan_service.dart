import 'dart:typed_data';

/// One captured page from a document scan.
class AppBoxKitScannedPage {
  const AppBoxKitScannedPage({
    required this.imageBytes,
    this.width,
    this.height,
  });

  /// Encoded image bytes (typically JPEG/PNG) for the cropped, de-skewed page.
  final Uint8List imageBytes;

  /// Pixel dimensions, when known.
  final int? width;
  final int? height;
}

/// The result of a multi-page document scan.
class AppBoxKitScannedDocument {
  const AppBoxKitScannedDocument({required this.pages});

  /// Pages in capture order.
  final List<AppBoxKitScannedPage> pages;
}

/// Port for capturing a physical document with the camera (edge detection,
/// perspective correction, multi-page).
///
/// STUB (phase 2). Corresponds to the mission's `DocumentScanService`.
/// Native-first plan: **VisionKit `VNDocumentCameraViewController` / DocKit on
/// iOS**, **ML Kit Document Scanner on Android**.
abstract interface class AppBoxKitDocumentScanService {
  /// Presents the OS document scanner and returns the captured document, or
  /// `null` if the user cancelled. [pageLimit] caps the number of pages.
  Future<AppBoxKitScannedDocument?> scan({int? pageLimit});
}

/// Not-yet-implemented [AppBoxKitDocumentScanService] — throws so callers fail loudly.
class UnimplementedAppBoxKitDocumentScanService implements AppBoxKitDocumentScanService {
  const UnimplementedAppBoxKitDocumentScanService();

  // TODO(appbox_kit_documents): implement over VisionKit (iOS) / ML Kit (Android).
  @override
  Future<AppBoxKitScannedDocument?> scan({int? pageLimit}) =>
      throw UnimplementedError('AppBoxKitDocumentScanService.scan');
}
