/// Scriptable test doubles for appbox_kit_documents.
///
/// Every fake supports a `failWith` error to exercise failure states, and the
/// picker fake can simulate a user cancel (return `null` / empty).
///
/// ```dart
/// final picker = FakeAppBoxKitDocumentPickerService(
///   next: AppBoxKitPickedDocument(name: 'a.pdf', readBytes: () async => Uint8List(0)),
/// );
/// picker.next = null;                     // simulate cancel
/// final ocr = FakeAppBoxKitOcrService(failWith: StateError('engine down'));
/// ```
library;

import 'dart:typed_data';

import 'src/appbox_kit_document_picker_service.dart';
import 'src/appbox_kit_document_scan_service.dart';
import 'src/appbox_kit_ocr_service.dart';
import 'src/appbox_kit_pdf_service.dart';
import 'src/appbox_kit_picked_document.dart';

export 'src/appbox_kit_picked_document.dart';
export 'src/appbox_kit_document_picker_service.dart';
export 'src/appbox_kit_document_scan_service.dart';
export 'src/appbox_kit_ocr_service.dart';
export 'src/appbox_kit_pdf_service.dart';

/// In-memory [AppBoxKitDocumentPickerService]. Set [next] to the single-pick result
/// (or `null` to simulate cancel) and [nextMany] for multi-pick.
class FakeAppBoxKitDocumentPickerService implements AppBoxKitDocumentPickerService {
  FakeAppBoxKitDocumentPickerService({
    this.next,
    this.nextMany = const [],
    this.failWith,
  });

  /// Returned by the next [pickDocument]; `null` simulates a user cancel.
  AppBoxKitPickedDocument? next;

  /// Returned by the next [pickDocuments].
  List<AppBoxKitPickedDocument> nextMany;

  /// When non-null, every call throws this instead of returning.
  Object? failWith;

  /// Extensions passed to the most recent call, for assertions.
  List<String>? lastExtensions;

  @override
  Future<AppBoxKitPickedDocument?> pickDocument({List<String> extensions = const []}) async {
    lastExtensions = extensions;
    if (failWith != null) throw failWith!;
    return next;
  }

  @override
  Future<List<AppBoxKitPickedDocument>> pickDocuments({List<String> extensions = const []}) async {
    lastExtensions = extensions;
    if (failWith != null) throw failWith!;
    return nextMany;
  }
}

/// In-memory [AppBoxKitDocumentScanService]. Returns [next] (or `null` for cancel),
/// or throws [failWith].
class FakeAppBoxKitDocumentScanService implements AppBoxKitDocumentScanService {
  FakeAppBoxKitDocumentScanService({this.next, this.failWith});

  AppBoxKitScannedDocument? next;
  Object? failWith;

  @override
  Future<AppBoxKitScannedDocument?> scan({int? pageLimit}) async {
    if (failWith != null) throw failWith!;
    return next;
  }
}

/// In-memory [AppBoxKitOcrService]. Returns [result], or throws [failWith].
class FakeAppBoxKitOcrService implements AppBoxKitOcrService {
  FakeAppBoxKitOcrService({this.result, this.failWith});

  AppBoxKitOcrResult? result;
  Object? failWith;

  @override
  Future<AppBoxKitOcrResult> recognizeText(Uint8List imageBytes) async {
    if (failWith != null) throw failWith!;
    return result ?? const AppBoxKitOcrResult(fullText: '', blocks: []);
  }
}

/// In-memory [AppBoxKitPdfService]. Serves scripted values, or throws [failWith].
class FakeAppBoxKitPdfService implements AppBoxKitPdfService {
  FakeAppBoxKitPdfService({
    this.pageCountValue = 0,
    this.pageImage,
    this.createdBytes,
    this.failWith,
  });

  int pageCountValue;
  AppBoxKitPdfPageImage? pageImage;
  Uint8List? createdBytes;
  Object? failWith;

  @override
  Future<int> pageCount(Uint8List pdfBytes) async {
    if (failWith != null) throw failWith!;
    return pageCountValue;
  }

  @override
  Future<AppBoxKitPdfPageImage> renderPage(
    Uint8List pdfBytes,
    int pageIndex, {
    double scale = 1.0,
  }) async {
    if (failWith != null) throw failWith!;
    return pageImage ??
        AppBoxKitPdfPageImage(imageBytes: Uint8List(0), width: 0, height: 0);
  }

  @override
  Future<Uint8List> createFromImages(List<Uint8List> pageImages) async {
    if (failWith != null) throw failWith!;
    return createdBytes ?? Uint8List(0);
  }
}
