import 'package:flutter/foundation.dart';

import 'arxa_kit_lat_lng.dart';

/// A map pin, owned by arxa_kit_maps and translated to each provider's
/// native marker/annotation type internally.
@immutable
class ArxaKitMapMarker {
  const ArxaKitMapMarker({
    required this.id,
    required this.position,
    this.title,
    this.snippet,
    this.onTap,
  });

  /// Stable identifier — used as the native MarkerId / AnnotationId.
  final String id;

  final ArxaKitLatLng position;

  /// Info-window title shown when the marker is selected.
  final String? title;

  /// Info-window secondary text.
  final String? snippet;

  final VoidCallback? onTap;

  @override
  bool operator ==(Object other) =>
      other is ArxaKitMapMarker &&
      other.id == id &&
      other.position == position &&
      other.title == title &&
      other.snippet == snippet;

  @override
  int get hashCode => Object.hash(id, position, title, snippet);

  @override
  String toString() => 'ArxaKitMapMarker($id @ $position)';
}
