/// Scriptable test doubles for arxa_kit_documents.
///
/// Every fake supports a `failWith` error to exercise failure states, and the
/// picker fake can simulate a user cancel (return `null` / empty).
///
/// ```dart
/// final picker = FakeArxaKitDocumentPickerService(
///   next: ArxaKitPickedDocument(name: 'a.pdf', readBytes: () async => Uint8List(0)),
/// );
/// picker.next = null;                     // simulate cancel
/// final ocr = FakeArxaKitOcrService(failWith: StateError('engine down'));
/// ```
library;

import 'dart:typed_data';

import 'src/arxa_kit_document_picker_service.dart';
import 'src/arxa_kit_document_scan_service.dart';
import 'src/arxa_kit_ocr_service.dart';
import 'src/arxa_kit_pdf_service.dart';
import 'src/arxa_kit_picked_document.dart';

export 'src/arxa_kit_picked_document.dart';
export 'src/arxa_kit_document_picker_service.dart';
export 'src/arxa_kit_document_scan_service.dart';
export 'src/arxa_kit_ocr_service.dart';
export 'src/arxa_kit_pdf_service.dart';

/// In-memory [ArxaKitDocumentPickerService]. Set [next] to the single-pick result
/// (or `null` to simulate cancel) and [nextMany] for multi-pick.
class FakeArxaKitDocumentPickerService implements ArxaKitDocumentPickerService {
  FakeArxaKitDocumentPickerService({
    this.next,
    this.nextMany = const [],
    this.failWith,
  });

  /// Returned by the next [pickDocument]; `null` simulates a user cancel.
  ArxaKitPickedDocument? next;

  /// Returned by the next [pickDocuments].
  List<ArxaKitPickedDocument> nextMany;

  /// When non-null, every call throws this instead of returning.
  Object? failWith;

  /// Extensions passed to the most recent call, for assertions.
  List<String>? lastExtensions;

  @override
  Future<ArxaKitPickedDocument?> pickDocument({List<String> extensions = const []}) async {
    lastExtensions = extensions;
    if (failWith != null) throw failWith!;
    return next;
  }

  @override
  Future<List<ArxaKitPickedDocument>> pickDocuments({List<String> extensions = const []}) async {
    lastExtensions = extensions;
    if (failWith != null) throw failWith!;
    return nextMany;
  }
}

/// In-memory [ArxaKitDocumentScanService]. Returns [next] (or `null` for cancel),
/// or throws [failWith].
class FakeArxaKitDocumentScanService implements ArxaKitDocumentScanService {
  FakeArxaKitDocumentScanService({this.next, this.failWith});

  ArxaKitScannedDocument? next;
  Object? failWith;

  @override
  Future<ArxaKitScannedDocument?> scan({int? pageLimit}) async {
    if (failWith != null) throw failWith!;
    return next;
  }
}

/// In-memory [ArxaKitOcrService]. Returns [result], or throws [failWith].
class FakeArxaKitOcrService implements ArxaKitOcrService {
  FakeArxaKitOcrService({this.result, this.failWith});

  ArxaKitOcrResult? result;
  Object? failWith;

  @override
  Future<ArxaKitOcrResult> recognizeText(Uint8List imageBytes) async {
    if (failWith != null) throw failWith!;
    return result ?? const ArxaKitOcrResult(fullText: '', blocks: []);
  }
}

/// In-memory [ArxaKitPdfService]. Serves scripted values, or throws [failWith].
class FakeArxaKitPdfService implements ArxaKitPdfService {
  FakeArxaKitPdfService({
    this.pageCountValue = 0,
    this.pageImage,
    this.createdBytes,
    this.failWith,
  });

  int pageCountValue;
  ArxaKitPdfPageImage? pageImage;
  Uint8List? createdBytes;
  Object? failWith;

  @override
  Future<int> pageCount(Uint8List pdfBytes) async {
    if (failWith != null) throw failWith!;
    return pageCountValue;
  }

  @override
  Future<ArxaKitPdfPageImage> renderPage(
    Uint8List pdfBytes,
    int pageIndex, {
    double scale = 1.0,
  }) async {
    if (failWith != null) throw failWith!;
    return pageImage ??
        ArxaKitPdfPageImage(imageBytes: Uint8List(0), width: 0, height: 0);
  }

  @override
  Future<Uint8List> createFromImages(List<Uint8List> pageImages) async {
    if (failWith != null) throw failWith!;
    return createdBytes ?? Uint8List(0);
  }
}
