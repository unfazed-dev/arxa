import 'package:flutter/material.dart';
import 'package:m3e_design/m3e_design.dart' as m3e;

/// Provides colors & shapes from `m3e_design` with safe fallbacks to Theme.of(context).
class NavigationRailTokensAdapter {
  /// Creates a [NavigationRailTokensAdapter].
  const NavigationRailTokensAdapter(this.context);

  /// Source context for resolving Theme and m3e tokens.
  final BuildContext context;

  ColorScheme get _cs => Theme.of(context).colorScheme;

  // Colors per spec
  /// Background color of the rail container.
  Color get containerColor {
    // Use surface container token if present, else fallback.
    return _maybe(() => context.m3e.colors.surface) ?? _cs.surface;
  }

  /// Background color of the active item indicator.
  Color get activeIndicatorColor {
    return _maybe(() => context.m3e.colors.secondaryContainer) ??
        _cs.secondaryContainer;
  }

  /// Color for the icon and label when the item is active.
  Color get activeIconAndLabel {
    return _maybe(() => context.m3e.colors.secondary) ?? _cs.secondary;
  }

  /// Color for the icon and label when the item is inactive.
  Color get inactiveIconAndLabel {
    return _maybe(() => context.m3e.colors.onSurfaceVariant) ??
        _cs.onSurfaceVariant;
  }

  /// Foreground color used for the menu (top) slot.
  Color get menuColor {
    return _maybe(() => context.m3e.colors.onSecondaryContainer) ??
        _cs.onSecondaryContainer;
  }

  /// Background color of the numeric badge.
  Color get badgeBackground =>
      _maybe(() => context.m3e.colors.primary) ?? _cs.primary;

  /// Label color inside the large numeric badge.
  Color get badgeLargeLabel =>
      _maybe(() => context.m3e.colors.onPrimary) ?? _cs.onPrimary;

  /// Shape of the active item indicator.
  ShapeBorder get indicatorShapeFull {
    // Fork patch: the m3.material.io token table maps the active indicator to
    // `md.sys.shape.corner.full` — a stadium pill — not `round.xs`.
    return const StadiumBorder();
  }

  T? _maybe<T>(T Function() pick) {
    try {
      return pick();
    } catch (_) {
      return null;
    }
  }
}
