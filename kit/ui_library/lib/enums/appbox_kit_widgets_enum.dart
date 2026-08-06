// BUTTON
import 'package:flutter/rendering.dart';

enum AppBoxKitButtonType {
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

enum AppBoxKitButtonLoaderDuration {
  short,
  medium,
  long,
}

enum AppBoxKitButtonLoaderState {
  idle,
  loading,
  loaded,
}

enum AppBoxKitIconButtonShape { normal, round, square }

// NAVBAR
enum AppBoxKitAnimatedNavbarContainerHeightState {
  initial,
  minimized,
  maximized,
  expanded,
  hidden
}

// BLOCK
enum AppBoxKitBlockPanelExpanded { left, right, top, bottom, none }

enum AppBoxKitBlockPanelAlignment { horizontal, vertical }

// CONTAINER
enum AppBoxKitContainerExpandDirection {
  /// Expands horizontally (along the X-axis)
  horizontal,

  /// Expands vertically (along the Y-axis)
  vertical,
}

/// Expansion type for container
enum AppBoxKitContainerExpansionLimit {
  /// Container expands from min to max (full range)
  minToMax,
}

enum AppBoxKitContainerRetractButtonPosition {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  center,
  topCenter,
  bottomCenter,
}

extension AppBoxKitContainerRetractButtonPositionExtension
    on AppBoxKitContainerRetractButtonPosition {
  bool get isCenter =>
      this == AppBoxKitContainerRetractButtonPosition.center ||
      this == AppBoxKitContainerRetractButtonPosition.topCenter ||
      this == AppBoxKitContainerRetractButtonPosition.bottomCenter;

  Alignment get alignment {
    switch (this) {
      case AppBoxKitContainerRetractButtonPosition.topLeft:
        return Alignment.topLeft;
      case AppBoxKitContainerRetractButtonPosition.topRight:
        return Alignment.topRight;
      case AppBoxKitContainerRetractButtonPosition.bottomLeft:
        return Alignment.bottomLeft;
      case AppBoxKitContainerRetractButtonPosition.bottomRight:
        return Alignment.bottomRight;
      case AppBoxKitContainerRetractButtonPosition.topCenter:
        return Alignment.topCenter;
      case AppBoxKitContainerRetractButtonPosition.bottomCenter:
        return Alignment.bottomCenter;
      case AppBoxKitContainerRetractButtonPosition.center:
        return Alignment.center;
    }
  }

  double? get left {
    switch (this) {
      case AppBoxKitContainerRetractButtonPosition.topLeft:
      case AppBoxKitContainerRetractButtonPosition.bottomLeft:
        return 8.0;
      case AppBoxKitContainerRetractButtonPosition.center:
        return null;
      case AppBoxKitContainerRetractButtonPosition.topCenter:
      case AppBoxKitContainerRetractButtonPosition.bottomCenter:
        return 0.0; // Will be ignored due to alignment
      case AppBoxKitContainerRetractButtonPosition.topRight:
      case AppBoxKitContainerRetractButtonPosition.bottomRight:
        return null; // Using right instead
    }
  }

  double? get right {
    switch (this) {
      case AppBoxKitContainerRetractButtonPosition.topRight:
      case AppBoxKitContainerRetractButtonPosition.bottomRight:
        return 8.0;
      case AppBoxKitContainerRetractButtonPosition.center:
        return null;
      case AppBoxKitContainerRetractButtonPosition.topCenter:
      case AppBoxKitContainerRetractButtonPosition.bottomCenter:
        return 0.0; // Will be ignored due to alignment
      case AppBoxKitContainerRetractButtonPosition.topLeft:
      case AppBoxKitContainerRetractButtonPosition.bottomLeft:
        return null; // Using left instead
    }
  }

  double? get top {
    switch (this) {
      case AppBoxKitContainerRetractButtonPosition.topLeft:
      case AppBoxKitContainerRetractButtonPosition.topRight:
      case AppBoxKitContainerRetractButtonPosition.topCenter:
        return 8.0;
      case AppBoxKitContainerRetractButtonPosition.center:
        return null;
      case AppBoxKitContainerRetractButtonPosition.bottomLeft:
      case AppBoxKitContainerRetractButtonPosition.bottomRight:
      case AppBoxKitContainerRetractButtonPosition.bottomCenter:
        return null; // Using bottom instead
    }
  }

  double? get bottom {
    switch (this) {
      case AppBoxKitContainerRetractButtonPosition.bottomLeft:
      case AppBoxKitContainerRetractButtonPosition.bottomRight:
      case AppBoxKitContainerRetractButtonPosition.bottomCenter:
        return 8.0;
      case AppBoxKitContainerRetractButtonPosition.topLeft:
      case AppBoxKitContainerRetractButtonPosition.topRight:
      case AppBoxKitContainerRetractButtonPosition.topCenter:
        return null; // Using top instead
      case AppBoxKitContainerRetractButtonPosition.center:
        return null;
    }
  }

  Offset getSlideInDirection(AppBoxKitContainerExpandDirection expandDirection) {
    switch (this) {
      case AppBoxKitContainerRetractButtonPosition.topLeft:
        return const Offset(-1.0, -1.0);
      case AppBoxKitContainerRetractButtonPosition.topRight:
        return const Offset(1.0, -1.0);
      case AppBoxKitContainerRetractButtonPosition.bottomLeft:
        return const Offset(-1.0, 1.0);
      case AppBoxKitContainerRetractButtonPosition.bottomRight:
        return const Offset(1.0, 1.0);
      case AppBoxKitContainerRetractButtonPosition.topCenter:
        return const Offset(0.0, -1.0);
      case AppBoxKitContainerRetractButtonPosition.bottomCenter:
        return const Offset(0.0, 1.0);
      case AppBoxKitContainerRetractButtonPosition.center:
        return expandDirection == AppBoxKitContainerExpandDirection.horizontal
            ? const Offset(1.0, 0.0)
            : const Offset(0.0, 1.0);
    }
  }
}
