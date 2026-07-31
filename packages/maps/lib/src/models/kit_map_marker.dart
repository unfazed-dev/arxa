import 'package:flutter/foundation.dart';

import 'kit_lat_lng.dart';

/// A map pin, owned by appbox_kit_maps and translated to each provider's
/// native marker/annotation type internally.
@immutable
class KitMapMarker {
  const KitMapMarker({
    required this.id,
    required this.position,
    this.title,
    this.snippet,
    this.onTap,
  });

  /// Stable identifier — used as the native MarkerId / AnnotationId.
  final String id;

  final KitLatLng position;

  /// Info-window title shown when the marker is selected.
  final String? title;

  /// Info-window secondary text.
  final String? snippet;

  final VoidCallback? onTap;

  @override
  bool operator ==(Object other) =>
      other is KitMapMarker &&
      other.id == id &&
      other.position == position &&
      other.title == title &&
      other.snippet == snippet;

  @override
  int get hashCode => Object.hash(id, position, title, snippet);

  @override
  String toString() => 'KitMapMarker($id @ $position)';
}
