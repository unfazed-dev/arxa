import 'dart:typed_data';

/// A recognized block of text with its position on the source image.
class ArxaKitOcrBlock {
  const ArxaKitOcrBlock({
    required this.text,
    this.confidence,
  });

  /// The recognized text for this block.
  final String text;

  /// Recognizer confidence in `[0, 1]`, when the engine reports it.
  final double? confidence;
}

/// The result of running OCR over an image.
class ArxaKitOcrResult {
  const ArxaKitOcrResult({
    required this.fullText,
    required this.blocks,
  });

  /// All recognized text concatenated in reading order.
  final String fullText;

  /// Per-block breakdown.
  final List<ArxaKitOcrBlock> blocks;
}

/// Port for optical character recognition over an image.
///
/// STUB (phase 2). Corresponds to the mission's `OcrService`. Native-first
/// plan: **Vision `VNRecognizeTextRequest` on iOS**, **ML Kit Text Recognition
/// on Android**.
abstract interface class ArxaKitOcrService {
  /// Recognizes text in the encoded image [imageBytes].
  Future<ArxaKitOcrResult> recognizeText(Uint8List imageBytes);
}

/// Not-yet-implemented [ArxaKitOcrService] — throws so callers fail loudly.
class UnimplementedArxaKitOcrService implements ArxaKitOcrService {
  const UnimplementedArxaKitOcrService();

  // TODO(arxa_kit_documents): implement over Vision (iOS) / ML Kit (Android).
  @override
  Future<ArxaKitOcrResult> recognizeText(Uint8List imageBytes) =>
      throw UnimplementedError('ArxaKitOcrService.recognizeText');
}
