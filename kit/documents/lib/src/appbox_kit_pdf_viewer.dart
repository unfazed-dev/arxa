import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

/// Interactive PDF viewer — scroll, zoom, text selection, links — backed by
/// pdfrx's `PdfViewer` (PDFium: iOS/Android/macOS/Windows/Linux/Web).
///
/// Four source constructors mirror `PdfViewer`'s own. For headless page
/// rasterization use [AppBoxKitPdfrxPdfService] instead.
class AppBoxKitPdfViewer extends StatelessWidget {
  const AppBoxKitPdfViewer.data(
    Uint8List bytes, {
    super.key,
    required this.sourceName,
    this.params = const PdfViewerParams(),
    this.controller,
  }) : _bytes = bytes,
       _asset = null,
       _filePath = null,
       _uri = null;

  const AppBoxKitPdfViewer.asset(
    String asset, {
    super.key,
    this.params = const PdfViewerParams(),
    this.controller,
  }) : _bytes = null,
       _asset = asset,
       _filePath = null,
       _uri = null,
       sourceName = asset;

  const AppBoxKitPdfViewer.file(
    String path, {
    super.key,
    this.params = const PdfViewerParams(),
    this.controller,
  }) : _bytes = null,
       _asset = null,
       _filePath = path,
       _uri = null,
       sourceName = path;

  const AppBoxKitPdfViewer.network(
    String url, {
    super.key,
    this.params = const PdfViewerParams(),
    this.controller,
  }) : _bytes = null,
       _asset = null,
       _filePath = null,
       _uri = url,
       sourceName = url;

  final Uint8List? _bytes;
  final String? _asset;
  final String? _filePath;
  final String? _uri;

  /// Source ID pdfrx uses to key caches/password prompts. Required only for
  /// [AppBoxKitPdfViewer.data] (bytes carry no identity); the path/URL constructors
  /// default it to the path/URL itself.
  final String sourceName;

  /// Viewer tuning (scroll physics, selection, overlays…).
  final PdfViewerParams params;

  /// Optional controller for programmatic page/zoom control.
  final PdfViewerController? controller;

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final asset = _asset;
    final filePath = _filePath;
    if (bytes != null) {
      return PdfViewer.data(
        bytes,
        sourceName: sourceName,
        params: params,
        controller: controller,
      );
    }
    if (asset != null) {
      return PdfViewer.asset(asset, params: params, controller: controller);
    }
    if (filePath != null) {
      return PdfViewer.file(filePath, params: params, controller: controller);
    }
    return PdfViewer.uri(
      Uri.parse(_uri!),
      params: params,
      controller: controller,
    );
  }
}
