/// Advanced media editing / transcoding — the phase-2A seam.
///
/// STUB: no backing implementation yet. Signatures use only kit-owned types
/// (file paths + [Duration]) so a future ffmpeg/native-backed implementation
/// slots in without changing callers. Every member throws [UnimplementedError].
abstract class ArxaKitMediaEditingService {
  /// Transcode [inputPath] into a new container/codec at [outputPath],
  /// returning the output path.
  Future<String> transcode({
    required String inputPath,
    required String outputPath,
  });

  /// Trim [inputPath] to the `[start, end)` range, writing [outputPath] and
  /// returning it.
  Future<String> trimAudio({
    required String inputPath,
    required String outputPath,
    required Duration start,
    required Duration end,
  });

  /// Re-encode an image at reduced [quality] (0–100), writing [outputPath] and
  /// returning it.
  Future<String> compressImage({
    required String inputPath,
    required String outputPath,
    int? quality,
  });
}

/// Placeholder [ArxaKitMediaEditingService]. Every member throws until the phase-2A
/// editing/transcode seam is wired.
class ArxaKitStubMediaEditingService implements ArxaKitMediaEditingService {
  // TODO(arxa_kit_media): implement editing/transcode (ffmpeg_kit_flutter or
  // native AVFoundation / MediaCodec). Phase 2A.
  static const _todo =
      'arxa_kit_media: ArxaKitMediaEditingService is a phase-2A stub — '
      'no transcode backend is wired yet.';

  @override
  Future<String> transcode({
    required String inputPath,
    required String outputPath,
  }) =>
      throw UnimplementedError(_todo);

  @override
  Future<String> trimAudio({
    required String inputPath,
    required String outputPath,
    required Duration start,
    required Duration end,
  }) =>
      throw UnimplementedError(_todo);

  @override
  Future<String> compressImage({
    required String inputPath,
    required String outputPath,
    int? quality,
  }) =>
      throw UnimplementedError(_todo);
}
