import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';

import 'media_capture_result.dart';
import 'media_source.dart';

/// Photo capture from the camera or the photo library.
///
/// Permission denial and missing hardware come back as
/// [MediaCaptureResult] variants, never as thrown exceptions — see
/// [capturePhoto].
abstract class MediaCaptureService {
  /// Whether the device has usable camera hardware. Callers use this to hide
  /// "Take Photo" affordances where capture would be impossible.
  bool get hasCamera;

  /// Capture a photo from [source]. Returns:
  /// * [MediaCaptured] with the temp file on success,
  /// * [MediaCaptureCancelled] if the user backed out,
  /// * [MediaCapturePermissionDenied] if the OS denied access,
  /// * [MediaCaptureUnavailable] if [source] is camera but none exists,
  /// * [MediaCaptureFailed] for any other plugin/platform error.
  ///
  /// [maxWidth]/[maxHeight]/[imageQuality] bound the output like the underlying
  /// plugin (quality is 0–100; null leaves the original).
  Future<MediaCaptureResult> capturePhoto({
    required MediaSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  });
}

/// [MediaCaptureService] backed by the native `image_picker` plugin.
class ImagePickerMediaCaptureService implements MediaCaptureService {
  ImagePickerMediaCaptureService([ImagePicker? picker])
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  bool get hasCamera {
    if (kIsWeb) return true;
    // Non-iOS platforms are assumed to have a camera (image_picker degrades on
    // its own where they don't). The iOS *Simulator* has no camera and the
    // plugin throws for ImageSource.camera there; it injects `SIMULATOR_*`
    // env vars, which is detectable without a MethodChannel.
    if (!Platform.isIOS) return true;
    return !Platform.environment.containsKey('SIMULATOR_DEVICE_NAME');
  }

  @override
  Future<MediaCaptureResult> capturePhoto({
    required MediaSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) async {
    if (source == MediaSource.camera && !hasCamera) {
      return const MediaCaptureUnavailable('no camera on this device');
    }
    try {
      final shot = await _picker.pickImage(
        source: source == MediaSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );
      if (shot == null) return const MediaCaptureCancelled();
      return MediaCaptured(XFileCapturedMedia(shot));
    } on PlatformException catch (e) {
      // image_picker raises `camera_access_denied` / `photo_access_denied`
      // (and similar) when the OS permission prompt is refused.
      if (e.code.contains('denied')) {
        return MediaCapturePermissionDenied(e.message);
      }
      return MediaCaptureFailed(e);
    } catch (e, st) {
      return MediaCaptureFailed(e, st);
    }
  }
}
