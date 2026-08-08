/// The app layer holds the wiring every feature depends on and no feature
/// owns: routing, locator registration and the identity carriers the
/// tooling reads.
///
/// This file declares the inspect-attribute triple that every emitted view
/// and view-factor stamps at emit time. Studio inspect mode reads the
/// triple only; nothing is inferred at runtime.
///
/// History: git log --follow -- tool/spike-q11-shells/golden/lib/app/inspect_attrs.dart
library;

import 'package:flutter/foundation.dart';

/// Identity stamped at emit time, never inferred at runtime.
///
/// PROVISIONAL VOCABULARY: the anatomy-node namespace has no
/// ratified closed set yet. Presence is contractual; the value
/// space is not. See docs/plans/q11-shell-spike.md (F3).
@immutable
class InspectAttrs {
  const InspectAttrs({
    required this.screenId,
    required this.surfaceId,
    required this.anatomyNodeId,
  });

  /// The screen this element belongs to.
  final String screenId;

  /// The surface this element belongs to.
  final String surfaceId;

  /// The anatomy node this element realises.
  final String anatomyNodeId;
}
