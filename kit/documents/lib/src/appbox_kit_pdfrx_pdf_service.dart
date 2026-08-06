import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import 'appbox_kit_pdf_service.dart';

/// [AppBoxKitPdfService] backed by `pdfrx` (PDFium).
///
/// Chosen over the native-first PDFKit/`PdfRenderer` plan because PDFium via
/// pdfrx covers iOS, Android, macOS, Windows, Linux **and web** with one code
/// path — the native plan covered only the two mobile OSes.
///
/// [createFromImages] stays unimplemented: pdfrx renders PDFs, it does not
/// assemble them.
class AppBoxKitPdfrxPdfService implements AppBoxKitPdfService {
  static bool _initialized = false;

  /// Engine APIs used before any pdfrx widget is built require this once.
  static void _ensureInitialized() {
    if (_initialized) return;
    pdfrxFlutterInitialize();
    _initialized = true;
  }

  @override
  Future<int> pageCount(Uint8List pdfBytes) async {
    _ensureInitialized();
    final doc = await PdfDocument.openData(pdfBytes);
    try {
      return doc.pages.length;
    } finally {
      await doc.dispose();
    }
  }

  @override
  Future<AppBoxKitPdfPageImage> renderPage(
    Uint8List pdfBytes,
    int pageIndex, {
    double scale = 1.0,
  }) async {
    _ensureInitialized();
    final doc = await PdfDocument.openData(pdfBytes);
    try {
      final page = doc.pages[pageIndex];
      final image = await page.render(
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
      );
      if (image == null) {
        throw StateError('pdfrx rendered nothing for page $pageIndex');
      }
      try {
        final png = await _encodePng(image.pixels, image.width, image.height);
        return AppBoxKitPdfPageImage(
          imageBytes: png,
          width: image.width,
          height: image.height,
        );
      } finally {
        image.dispose();
      }
    } finally {
      await doc.dispose();
    }
  }

  /// Raw pixels → PNG via `dart:ui` (no extra dependency).
  // kimitail: pixels assumed RGBA8888 (pdfrx normalizes PDFium's BGRA) — if a
  // smoke test shows a red/blue channel swap, switch to PixelFormat.bgra8888.
  static Future<Uint8List> _encodePng(
    Uint8List pixels,
    int width,
    int height,
  ) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    try {
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      codec.dispose();
      frame.image.dispose();
      descriptor.dispose();
      return data!.buffer.asUint8List();
    } finally {
      buffer.dispose();
    }
  }

  // TODO(appbox_kit_documents): pdfrx renders only — assemble via
  // package:pdf (or the native compositor) when a caller needs this.
  @override
  Future<Uint8List> createFromImages(List<Uint8List> pageImages) =>
      throw UnimplementedError('AppBoxKitPdfService.createFromImages');
}
