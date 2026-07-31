import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_documents/testing.dart';

void main() {
  test('picker cancel returns null', () async {
    final picker = FakeKitDocumentPickerService(next: null);
    expect(await picker.pickDocument(extensions: const ['pdf']), isNull);
    expect(picker.lastExtensions, ['pdf']);
  });

  test('failure states surface as thrown errors', () async {
    final ocr = FakeKitOcrService(failWith: StateError('engine down'));
    await expectLater(
        ocr.recognizeText(Uint8List(0)), throwsA(isA<StateError>()));

    final pdf = FakeKitPdfService(failWith: StateError('render failed'));
    await expectLater(pdf.pageCount(Uint8List(0)), throwsA(isA<StateError>()));
  });

  test('real stub ports throw UnimplementedError', () {
    expect(() => const UnimplementedKitDocumentScanService().scan(),
        throwsUnimplementedError);
    expect(() => const UnimplementedKitPdfService().pageCount(Uint8List(0)),
        throwsUnimplementedError);
  });
}
