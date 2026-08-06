import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_documents/appbox_kit_testing.dart';

void main() {
  test('picker cancel returns null', () async {
    final picker = FakeAppBoxKitDocumentPickerService(next: null);
    expect(await picker.pickDocument(extensions: const ['pdf']), isNull);
    expect(picker.lastExtensions, ['pdf']);
  });

  test('failure states surface as thrown errors', () async {
    final ocr = FakeAppBoxKitOcrService(failWith: StateError('engine down'));
    await expectLater(
        ocr.recognizeText(Uint8List(0)), throwsA(isA<StateError>()));

    final pdf = FakeAppBoxKitPdfService(failWith: StateError('render failed'));
    await expectLater(pdf.pageCount(Uint8List(0)), throwsA(isA<StateError>()));
  });

  test('real stub ports throw UnimplementedError', () {
    expect(() => const UnimplementedAppBoxKitDocumentScanService().scan(),
        throwsUnimplementedError);
    expect(() => const UnimplementedAppBoxKitPdfService().pageCount(Uint8List(0)),
        throwsUnimplementedError);
  });
}
