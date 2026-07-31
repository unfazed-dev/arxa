import 'dart:typed_data';

import 'package:image_picker/image_picker.dart' show XFile;

/// A media file produced by a capture — a thin handle over the plugin's temp
/// file. The caller decides where it lands: capture returns a temp path (which
/// the OS may reclaim), so move it somewhere durable with [saveTo].
abstract class CapturedMedia {
  /// Absolute path to the (temporary) captured file.
  String get path;

  /// File name including extension, e.g. `IMG_0001.jpg`.
  String get name;

  /// Copy the file to [destinationPath]. Use this to move a capture out of the
  /// plugin's cache before it is reclaimed.
  Future<void> saveTo(String destinationPath);

  /// Read the file's bytes — for uploads or in-memory processing.
  Future<Uint8List> readAsBytes();
}

/// Real [CapturedMedia] wrapping an `image_picker` [XFile].
class XFileCapturedMedia implements CapturedMedia {
  XFileCapturedMedia(this._file);

  final XFile _file;

  @override
  String get path => _file.path;

  @override
  String get name => _file.name;

  @override
  Future<void> saveTo(String destinationPath) => _file.saveTo(destinationPath);

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();
}

/// Outcome of a photo capture. Permission denial, cancellation and missing
/// hardware are surfaced as typed results rather than thrown exceptions, so a
/// caller can `switch` exhaustively instead of guessing at plugin error codes.
sealed class MediaCaptureResult {
  const MediaCaptureResult();
}

/// The user picked/shot a file; [media] is the captured handle.
class MediaCaptured extends MediaCaptureResult {
  const MediaCaptured(this.media);

  final CapturedMedia media;
}

/// The user backed out of the picker/camera without choosing anything.
class MediaCaptureCancelled extends MediaCaptureResult {
  const MediaCaptureCancelled();
}

/// The OS denied camera or photo-library permission.
class MediaCapturePermissionDenied extends MediaCaptureResult {
  const MediaCapturePermissionDenied([this.message]);

  final String? message;
}

/// The requested source is not available on this device (e.g. camera on a
/// simulator).
class MediaCaptureUnavailable extends MediaCaptureResult {
  const MediaCaptureUnavailable([this.reason]);

  final String? reason;
}

/// An unexpected plugin/platform failure. [error] is the original object.
class MediaCaptureFailed extends MediaCaptureResult {
  const MediaCaptureFailed(this.error, [this.stackTrace]);

  final Object error;
  final StackTrace? stackTrace;
}
