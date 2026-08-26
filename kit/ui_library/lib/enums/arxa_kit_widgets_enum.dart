// BUTTON
import 'package:flutter/rendering.dart';

enum ArxaKitButtonType {
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

enum ArxaKitButtonLoaderDuration {
  short,
  medium,
  long,
}

enum ArxaKitButtonLoaderState {
  idle,
  loading,
  loaded,
}

enum ArxaKitIconButtonShape { normal, round, square }

// NAVBAR
enum ArxaKitAnimatedNavbarContainerHeightState {
  initial,
  minimized,
  maximized,
  expanded,
  hidden
}

// BLOCK
enum ArxaKitBlockPanelExpanded { left, right, top, bottom, none }

enum ArxaKitBlockPanelAlignment { horizontal, vertical }

// CONTAINER
enum ArxaKitContainerExpandDirection {
  /// Expands horizontally (along the X-axis)
  horizontal,

  /// Expands vertically (along the Y-axis)
  vertical,
}

/// Expansion type for container
enum ArxaKitContainerExpansionLimit {
  /// Container expands from min to max (full range)
  minToMax,
}

enum ArxaKitContainerRetractButtonPosition {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  center,
  topCenter,
  bottomCenter,
}

extension ArxaKitContainerRetractButtonPositionExtension
    on ArxaKitContainerRetractButtonPosition {
  bool get isCenter =>
      this == ArxaKitContainerRetractButtonPosition.center ||
      this == ArxaKitContainerRetractButtonPosition.topCenter ||
      this == ArxaKitContainerRetractButtonPosition.bottomCenter;

  Alignment get alignment {
    switch (this) {
      case ArxaKitContainerRetractButtonPosition.topLeft:
        return Alignment.topLeft;
      case ArxaKitContainerRetractButtonPosition.topRight:
        return Alignment.topRight;
      case ArxaKitContainerRetractButtonPosition.bottomLeft:
        return Alignment.bottomLeft;
      case ArxaKitContainerRetractButtonPosition.bottomRight:
        return Alignment.bottomRight;
      case ArxaKitContainerRetractButtonPosition.topCenter:
        return Alignment.topCenter;
      case ArxaKitContainerRetractButtonPosition.bottomCenter:
        return Alignment.bottomCenter;
      case ArxaKitContainerRetractButtonPosition.center:
        return Alignment.center;
    }
  }

  double? get left {
    switch (this) {
      case ArxaKitContainerRetractButtonPosition.topLeft:
      case ArxaKitContainerRetractButtonPosition.bottomLeft:
        return 8.0;
      case ArxaKitContainerRetractButtonPosition.center:
        return null;
      case ArxaKitContainerRetractButtonPosition.topCenter:
      case ArxaKitContainerRetractButtonPosition.bottomCenter:
        return 0.0; // Will be ignored due to alignment
      case ArxaKitContainerRetractButtonPosition.topRight:
      case ArxaKitContainerRetractButtonPosition.bottomRight:
        return null; // Using right instead
    }
  }

  double? get right {
    switch (this) {
      case ArxaKitContainerRetractButtonPosition.topRight:
      case ArxaKitContainerRetractButtonPosition.bottomRight:
        return 8.0;
      case ArxaKitContainerRetractButtonPosition.center:
        return null;
      case ArxaKitContainerRetractButtonPosition.topCenter:
      case ArxaKitContainerRetractButtonPosition.bottomCenter:
        return 0.0; // Will be ignored due to alignment
      case ArxaKitContainerRetractButtonPosition.topLeft:
      case ArxaKitContainerRetractButtonPosition.bottomLeft:
        return null; // Using left instead
    }
  }

  double? get top {
    switch (this) {
      case ArxaKitContainerRetractButtonPosition.topLeft:
      case ArxaKitContainerRetractButtonPosition.topRight:
      case ArxaKitContainerRetractButtonPosition.topCenter:
        return 8.0;
      case ArxaKitContainerRetractButtonPosition.center:
        return null;
      case ArxaKitContainerRetractButtonPosition.bottomLeft:
      case ArxaKitContainerRetractButtonPosition.bottomRight:
      case ArxaKitContainerRetractButtonPosition.bottomCenter:
        return null; // Using bottom instead
    }
  }

  double? get bottom {
    switch (this) {
      case ArxaKitContainerRetractButtonPosition.bottomLeft:
      case ArxaKitContainerRetractButtonPosition.bottomRight:
      case ArxaKitContainerRetractButtonPosition.bottomCenter:
        return 8.0;
      case ArxaKitContainerRetractButtonPosition.topLeft:
      case ArxaKitContainerRetractButtonPosition.topRight:
      case ArxaKitContainerRetractButtonPosition.topCenter:
        return null; // Using top instead
      case ArxaKitContainerRetractButtonPosition.center:
        return null;
    }
  }

  Offset getSlideInDirection(
      ArxaKitContainerExpandDirection expandDirection) {
    switch (this) {
      case ArxaKitContainerRetractButtonPosition.topLeft:
        return const Offset(-1.0, -1.0);
      case ArxaKitContainerRetractButtonPosition.topRight:
        return const Offset(1.0, -1.0);
      case ArxaKitContainerRetractButtonPosition.bottomLeft:
        return const Offset(-1.0, 1.0);
      case ArxaKitContainerRetractButtonPosition.bottomRight:
        return const Offset(1.0, 1.0);
      case ArxaKitContainerRetractButtonPosition.topCenter:
        return const Offset(0.0, -1.0);
      case ArxaKitContainerRetractButtonPosition.bottomCenter:
        return const Offset(0.0, 1.0);
      case ArxaKitContainerRetractButtonPosition.center:
        return expandDirection == ArxaKitContainerExpandDirection.horizontal
            ? const Offset(1.0, 0.0)
            : const Offset(0.0, 1.0);
    }
  }
}
