// The composer's media seam — camera / photo library / files / recent
// photos behind one injectable surface, so the viewmodel and the sheet
// stay plugin-free and tests fake the whole shelf. Backed by the kit's
// media capture (image_picker) plus file_picker and photo_manager.
import 'dart:io';

import 'package:arxa_kit_media/arxa_kit_media.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';

/// Bounded encode for anything the composer sends: the long edge and the
/// JPEG quality decide the base64 payload the tunnel carries.
const int kContextImageMaxEdge = 1600;
const int kContextImageQuality = 82;

class ConversationMedia {
  ConversationMedia({ArxaKitMediaCaptureService? capture})
      : _capture = capture ?? ArxaKitImagePickerMediaCaptureService();

  final ArxaKitMediaCaptureService _capture;
  final ImagePicker _picker = ImagePicker();

  /// No camera hardware (iPad wifi, simulator) — the sheet hides the tile.
  bool get hasCamera => _capture.hasCamera;

  /// Shoot one bounded photo. null = the user backed out.
  Future<XFile?> capturePhoto() async {
    final result = await _capture.capturePhoto(
        source: ArxaKitMediaSource.camera,
        maxWidth: kContextImageMaxEdge.toDouble(),
        imageQuality: kContextImageQuality);
    final shot = switch (result) {
      ArxaKitMediaCaptured(:final media) => XFile(media.path),
      _ => null,
    };
    return shot;
  }

  /// Pick one bounded photo from the library (the system picker — no
  /// photo-library permission needed for this path).
  Future<XFile?> pickPhoto() => _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: kContextImageMaxEdge.toDouble(),
      imageQuality: kContextImageQuality);

  /// Pick one file of any type (the system document picker).
  Future<XFile?> pickFile() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    final path = files.isEmpty ? null : files.single.path;
    return path == null ? null : XFile(path);
  }

  /// The library's most recent photos for the sheet's inline grid. Empty
  /// when the photo-library permission is limited or refused — the grid
  /// simply stays empty, the system picker remains the full path.
  Future<List<AssetEntity>> recentPhotos({int limit = 60}) async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) return const [];
    final paths = await PhotoManager.getAssetPathList(
        type: RequestType.image, onlyAll: true, filterOption: FilterOptionGroup());
    if (paths.isEmpty) return const [];
    return paths.first.getAssetListRange(start: 0, end: limit);
  }

  /// One library asset as a file (bounded encode on the way in).
  Future<File?> originFile(AssetEntity asset) => asset.originFile;
}
