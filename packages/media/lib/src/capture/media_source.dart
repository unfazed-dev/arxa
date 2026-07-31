/// Where a photo capture request should draw from.
///
/// Kit-owned so callers never import `image_picker`'s `ImageSource`; the real
/// [MediaCaptureService] maps this onto the plugin's enum internally.
enum MediaSource {
  /// The device camera. Requests a `MediaCaptureUnavailable` result where no
  /// camera exists (e.g. the iOS Simulator) rather than throwing.
  camera,

  /// The system photo library / gallery picker.
  gallery,
}
