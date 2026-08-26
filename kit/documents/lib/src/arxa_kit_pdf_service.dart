import 'dart:typed_data';

/// A rasterized PDF page.
class ArxaKitPdfPageImage {
  const ArxaKitPdfPageImage({
    required this.imageBytes,
    required this.width,
    required this.height,
  });

  /// Encoded image bytes (PNG) for the rendered page.
  final Uint8List imageBytes;

  /// Rendered pixel dimensions.
  final int width;
  final int height;
}

/// Port for rendering and assembling PDF documents.
///
/// STUB (phase 2). Corresponds to the mission's `PdfService`. Native-first
/// plan: **PDFKit / `CGPDFDocument` on iOS**, **`PdfRenderer` on Android**.
abstract interface class ArxaKitPdfService {
  /// Returns the number of pages in the PDF given by [pdfBytes].
  Future<int> pageCount(Uint8List pdfBytes);

  /// Renders page [pageIndex] (0-based) of [pdfBytes] to an image at the given
  /// [scale].
  Future<ArxaKitPdfPageImage> renderPage(
    Uint8List pdfBytes,
    int pageIndex, {
    double scale,
  });

  /// Assembles a PDF from encoded page images and returns the PDF bytes.
  Future<Uint8List> createFromImages(List<Uint8List> pageImages);
}

/// Not-yet-implemented [ArxaKitPdfService] — throws so callers fail loudly.
class UnimplementedArxaKitPdfService implements ArxaKitPdfService {
  const UnimplementedArxaKitPdfService();

  // TODO(arxa_kit_documents): implement over PDFKit (iOS) / PdfRenderer (Android).
  @override
  Future<int> pageCount(Uint8List pdfBytes) =>
      throw UnimplementedError('ArxaKitPdfService.pageCount');

  // TODO(arxa_kit_documents): implement over PDFKit (iOS) / PdfRenderer (Android).
  @override
  Future<ArxaKitPdfPageImage> renderPage(
    Uint8List pdfBytes,
    int pageIndex, {
    double scale = 1.0,
  }) =>
      throw UnimplementedError('ArxaKitPdfService.renderPage');

  // TODO(arxa_kit_documents): implement over PDFKit (iOS) / native compositor.
  @override
  Future<Uint8List> createFromImages(List<Uint8List> pageImages) =>
      throw UnimplementedError('ArxaKitPdfService.createFromImages');
}
