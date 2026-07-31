/// Scriptable test doubles for appbox_kit_documents.
///
/// Every fake supports a `failWith` error to exercise failure states, and the
/// picker fake can simulate a user cancel (return `null` / empty).
///
/// ```dart
/// final picker = FakeKitDocumentPickerService(
///   next: KitPickedDocument(name: 'a.pdf', readBytes: () async => Uint8List(0)),
/// );
/// picker.next = null;                     // simulate cancel
/// final ocr = FakeKitOcrService(failWith: StateError('engine down'));
/// ```
library;

import 'dart:typed_data';

import 'src/kit_document_picker_service.dart';
import 'src/kit_document_scan_service.dart';
import 'src/kit_ocr_service.dart';
import 'src/kit_pdf_service.dart';
import 'src/kit_picked_document.dart';

export 'src/kit_picked_document.dart';
export 'src/kit_document_picker_service.dart';
export 'src/kit_document_scan_service.dart';
export 'src/kit_ocr_service.dart';
export 'src/kit_pdf_service.dart';

/// In-memory [KitDocumentPickerService]. Set [next] to the single-pick result
/// (or `null` to simulate cancel) and [nextMany] for multi-pick.
class FakeKitDocumentPickerService implements KitDocumentPickerService {
  FakeKitDocumentPickerService({
    this.next,
    this.nextMany = const [],
    this.failWith,
  });

  /// Returned by the next [pickDocument]; `null` simulates a user cancel.
  KitPickedDocument? next;

  /// Returned by the next [pickDocuments].
  List<KitPickedDocument> nextMany;

  /// When non-null, every call throws this instead of returning.
  Object? failWith;

  /// Extensions passed to the most recent call, for assertions.
  List<String>? lastExtensions;

  @override
  Future<KitPickedDocument?> pickDocument({List<String> extensions = const []}) async {
    lastExtensions = extensions;
    if (failWith != null) throw failWith!;
    return next;
  }

  @override
  Future<List<KitPickedDocument>> pickDocuments({List<String> extensions = const []}) async {
    lastExtensions = extensions;
    if (failWith != null) throw failWith!;
    return nextMany;
  }
}

/// In-memory [KitDocumentScanService]. Returns [next] (or `null` for cancel),
/// or throws [failWith].
class FakeKitDocumentScanService implements KitDocumentScanService {
  FakeKitDocumentScanService({this.next, this.failWith});

  KitScannedDocument? next;
  Object? failWith;

  @override
  Future<KitScannedDocument?> scan({int? pageLimit}) async {
    if (failWith != null) throw failWith!;
    return next;
  }
}

/// In-memory [KitOcrService]. Returns [result], or throws [failWith].
class FakeKitOcrService implements KitOcrService {
  FakeKitOcrService({this.result, this.failWith});

  KitOcrResult? result;
  Object? failWith;

  @override
  Future<KitOcrResult> recognizeText(Uint8List imageBytes) async {
    if (failWith != null) throw failWith!;
    return result ?? const KitOcrResult(fullText: '', blocks: []);
  }
}

/// In-memory [KitPdfService]. Serves scripted values, or throws [failWith].
class FakeKitPdfService implements KitPdfService {
  FakeKitPdfService({
    this.pageCountValue = 0,
    this.pageImage,
    this.createdBytes,
    this.failWith,
  });

  int pageCountValue;
  KitPdfPageImage? pageImage;
  Uint8List? createdBytes;
  Object? failWith;

  @override
  Future<int> pageCount(Uint8List pdfBytes) async {
    if (failWith != null) throw failWith!;
    return pageCountValue;
  }

  @override
  Future<KitPdfPageImage> renderPage(
    Uint8List pdfBytes,
    int pageIndex, {
    double scale = 1.0,
  }) async {
    if (failWith != null) throw failWith!;
    return pageImage ??
        KitPdfPageImage(imageBytes: Uint8List(0), width: 0, height: 0);
  }

  @override
  Future<Uint8List> createFromImages(List<Uint8List> pageImages) async {
    if (failWith != null) throw failWith!;
    return createdBytes ?? Uint8List(0);
  }
}
