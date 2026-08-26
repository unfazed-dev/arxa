import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_documents/arxa_kit_testing.dart';

void main() {
  test('kit.documents.ports — picker cancel returns null', () async {
    final picker = FakeArxaKitDocumentPickerService(next: null);
    expect(await picker.pickDocument(extensions: const ['pdf']), isNull);
    expect(picker.lastExtensions, ['pdf']);
  });

  test('kit.documents.ports — failure states surface as thrown errors', () async {
    final ocr = FakeArxaKitOcrService(failWith: StateError('engine down'));
    await expectLater(
        ocr.recognizeText(Uint8List(0)), throwsA(isA<StateError>()));

    final pdf = FakeArxaKitPdfService(failWith: StateError('render failed'));
    await expectLater(pdf.pageCount(Uint8List(0)), throwsA(isA<StateError>()));
  });

  test('kit.documents.ports — real stub ports throw UnimplementedError', () {
    expect(() => const UnimplementedArxaKitDocumentScanService().scan(),
        throwsUnimplementedError);
    expect(() => const UnimplementedArxaKitPdfService().pageCount(Uint8List(0)),
        throwsUnimplementedError);
  });
}
