import '../utils/mouse_transforms/fill_on_hover.dart';
import '../utils/mouse_transforms/outline_on_hover.dart';
import '../utils/mouse_transforms/scale_on_hover.dart';
import '../utils/mouse_transforms/translate_on_hover.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Extension methods for adding hover effects to widgets
/// These effects are only applied on desktop platforms and are ignored on mobile
extension HoverExtensions on Widget {
  /// Adds a clickable cursor when hovering over the widget
  ///
  /// Returns a [MouseRegion] wrapped widget on desktop platforms
  /// Returns the original widget unchanged on mobile platforms
  Widget get showCursorOnHover {
    return _returnUnalteredOnMobile(MouseRegion(
      cursor: SystemMouseCursors.click,
      child: this,
    ));
  }

  /// Moves the widget by x,y pixels on hover
  ///
  /// Parameters:
  /// - [x]: Horizontal movement in pixels (negative moves left, positive moves right)
  /// - [y]: Vertical movement in pixels (negative moves up, positive moves down)
  ///
  /// Returns a [TranslateOnHover] wrapped widget on desktop platforms
  /// Returns the original widget unchanged on mobile platforms
  Widget moveOnHover({double? x, double? y}) {
    return _returnUnalteredOnMobile(TranslateOnHover(
      x: x,
      y: y,
      child: this,
    ));
  }

  /// Scales the widget by [scale] factor on hover
  ///
  /// Parameters:
  /// - [scale]: Scale factor to apply (1.0 = no change, > 1.0 = grow, < 1.0 = shrink)
  ///
  /// Returns a [ScaleOnHover] wrapped widget on desktop platforms
  /// Returns the original widget unchanged on mobile platforms
  Widget scaleOnHover({double scale = 1.1}) {
    return _returnUnalteredOnMobile(ScaleOnHover(
      scale: scale,
      child: this,
    ));
  }

  /// Fills the widget with a color on hover
  ///
  /// Parameters:
  /// - [color]: Color to fill with
  /// - [opacity]: Opacity of the fill color (0.0 = transparent, 1.0 = solid)
  /// - [disabled]: Whether the hover effect is disabled
  ///
  /// Returns a [FillOnHover] wrapped widget on desktop platforms
  /// Returns the original widget unchanged on mobile platforms
  Widget fillOnHover({
    required Color color,
    double opacity = 0.1,
    bool disabled = false,
  }) {
    return _returnUnalteredOnMobile(FillOnHover(
      fillColor: color,
      opacity: opacity,
      borderRadius: BorderRadius.circular(8),
      disabled: disabled,
      child: this,
    ));
  }

  /// Adds an outline when hovering over the widget
  ///
  /// Parameters:
  /// - [hoverOutlineColor]: Color of the outline
  /// - [outlineWidth]: Width of the outline
  ///
  /// Returns a [OutlineOnHover] wrapped widget on desktop platforms
  /// Returns the original widget unchanged on mobile platforms
  Widget outlineOnHover({
    required Color hoverOutlineColor,
    double outlineWidth = 2,
  }) {
    return _returnUnalteredOnMobile(OutlineOnHover(
      hoverOutlineColor: hoverOutlineColor,
      outlineWidth: outlineWidth,
      child: this,
    ));
  }

  /// Takes in the alteredWidget and if we detect we're on Android or iOS
  /// we return the unaltered widget.
  ///
  /// The reason we can do this is because all altered widgets require mouse
  /// functionality to work.
  Widget _returnUnalteredOnMobile(Widget alteredWidget) {
    if (kIsWeb) {
      return alteredWidget;
    }
    return this;
  }
}
