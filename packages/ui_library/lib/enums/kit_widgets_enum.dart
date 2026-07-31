// BUTTON
import 'package:flutter/rendering.dart';

enum KitButtonType {
  textFilled,
  textOutline,
  textGhost,
  textLink,
  iconFilled,
  iconOutline,
  iconGhost,
  iconTextFilled,
  iconTextOutline,
  iconTextGhost,
  iconTextLink,
}

enum KitButtonLoaderDuration {
  short,
  medium,
  long,
}

enum KitButtonLoaderState {
  idle,
  loading,
  loaded,
}

enum KitIconButtonShape { normal, round, square }

// NAVBAR
enum KitAnimatedNavbarContainerHeightState {
  initial,
  minimized,
  maximized,
  expanded,
  hidden
}

// BLOCK
enum KitBlockPanelExpanded { left, right, top, bottom, none }

enum KitBlockPanelAlignment { horizontal, vertical }

// CONTAINER
enum KitContainerExpandDirection {
  /// Expands horizontally (along the X-axis)
  horizontal,

  /// Expands vertically (along the Y-axis)
  vertical,
}

/// Expansion type for container
enum KitContainerExpansionLimit {
  /// Container expands from min to max (full range)
  minToMax,
}

enum KitContainerRetractButtonPosition {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  center,
  topCenter,
  bottomCenter,
}

extension KitContainerRetractButtonPositionExtension
    on KitContainerRetractButtonPosition {
  bool get isCenter =>
      this == KitContainerRetractButtonPosition.center ||
      this == KitContainerRetractButtonPosition.topCenter ||
      this == KitContainerRetractButtonPosition.bottomCenter;

  Alignment get alignment {
    switch (this) {
      case KitContainerRetractButtonPosition.topLeft:
        return Alignment.topLeft;
      case KitContainerRetractButtonPosition.topRight:
        return Alignment.topRight;
      case KitContainerRetractButtonPosition.bottomLeft:
        return Alignment.bottomLeft;
      case KitContainerRetractButtonPosition.bottomRight:
        return Alignment.bottomRight;
      case KitContainerRetractButtonPosition.topCenter:
        return Alignment.topCenter;
      case KitContainerRetractButtonPosition.bottomCenter:
        return Alignment.bottomCenter;
      case KitContainerRetractButtonPosition.center:
        return Alignment.center;
    }
  }

  double? get left {
    switch (this) {
      case KitContainerRetractButtonPosition.topLeft:
      case KitContainerRetractButtonPosition.bottomLeft:
        return 8.0;
      case KitContainerRetractButtonPosition.center:
        return null;
      case KitContainerRetractButtonPosition.topCenter:
      case KitContainerRetractButtonPosition.bottomCenter:
        return 0.0; // Will be ignored due to alignment
      case KitContainerRetractButtonPosition.topRight:
      case KitContainerRetractButtonPosition.bottomRight:
        return null; // Using right instead
    }
  }

  double? get right {
    switch (this) {
      case KitContainerRetractButtonPosition.topRight:
      case KitContainerRetractButtonPosition.bottomRight:
        return 8.0;
      case KitContainerRetractButtonPosition.center:
        return null;
      case KitContainerRetractButtonPosition.topCenter:
      case KitContainerRetractButtonPosition.bottomCenter:
        return 0.0; // Will be ignored due to alignment
      case KitContainerRetractButtonPosition.topLeft:
      case KitContainerRetractButtonPosition.bottomLeft:
        return null; // Using left instead
    }
  }

  double? get top {
    switch (this) {
      case KitContainerRetractButtonPosition.topLeft:
      case KitContainerRetractButtonPosition.topRight:
      case KitContainerRetractButtonPosition.topCenter:
        return 8.0;
      case KitContainerRetractButtonPosition.center:
        return null;
      case KitContainerRetractButtonPosition.bottomLeft:
      case KitContainerRetractButtonPosition.bottomRight:
      case KitContainerRetractButtonPosition.bottomCenter:
        return null; // Using bottom instead
    }
  }

  double? get bottom {
    switch (this) {
      case KitContainerRetractButtonPosition.bottomLeft:
      case KitContainerRetractButtonPosition.bottomRight:
      case KitContainerRetractButtonPosition.bottomCenter:
        return 8.0;
      case KitContainerRetractButtonPosition.topLeft:
      case KitContainerRetractButtonPosition.topRight:
      case KitContainerRetractButtonPosition.topCenter:
        return null; // Using top instead
      case KitContainerRetractButtonPosition.center:
        return null;
    }
  }

  Offset getSlideInDirection(KitContainerExpandDirection expandDirection) {
    switch (this) {
      case KitContainerRetractButtonPosition.topLeft:
        return const Offset(-1.0, -1.0);
      case KitContainerRetractButtonPosition.topRight:
        return const Offset(1.0, -1.0);
      case KitContainerRetractButtonPosition.bottomLeft:
        return const Offset(-1.0, 1.0);
      case KitContainerRetractButtonPosition.bottomRight:
        return const Offset(1.0, 1.0);
      case KitContainerRetractButtonPosition.topCenter:
        return const Offset(0.0, -1.0);
      case KitContainerRetractButtonPosition.bottomCenter:
        return const Offset(0.0, 1.0);
      case KitContainerRetractButtonPosition.center:
        return expandDirection == KitContainerExpandDirection.horizontal
            ? const Offset(1.0, 0.0)
            : const Offset(0.0, 1.0);
    }
  }
}
