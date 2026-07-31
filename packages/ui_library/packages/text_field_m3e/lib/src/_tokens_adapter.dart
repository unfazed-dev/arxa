part of 'enums.dart';

/// Token bucket for TextFieldM3E (dp, ms, etc.).
class TextFieldM3ETokens {
  const TextFieldM3ETokens._();

  // Control heights per size (single-line resting height)
  static const Map<TextFieldM3ESize, double> height = {
    TextFieldM3ESize.sm: 40,
    TextFieldM3ESize.md: 56,
    TextFieldM3ESize.lg: 64,
  };

  // Shape radii (outer corners) and focused morph
  // round = half height; square ≈ 25% height; focused ≈ 20% height
  static const Map<TextFieldM3ESize, double> outerRadiusRound = {
    TextFieldM3ESize.sm: 20,
    TextFieldM3ESize.md: 28,
    TextFieldM3ESize.lg: 32,
  };

  static const Map<TextFieldM3ESize, double> outerRadiusSquare = {
    TextFieldM3ESize.sm: 10,
    TextFieldM3ESize.md: 14,
    TextFieldM3ESize.lg: 16,
  };

  static const Map<TextFieldM3ESize, double> focusedRadius = {
    TextFieldM3ESize.sm: 8,
    TextFieldM3ESize.md: 11,
    TextFieldM3ESize.lg: 13,
  };

  // Horizontal container padding
  static const Map<TextFieldM3ESize, double> horizontalPadding = {
    TextFieldM3ESize.sm: 16,
    TextFieldM3ESize.md: 16,
    TextFieldM3ESize.lg: 20,
  };

  // Icon glyph size (leading/trailing)
  static const Map<TextFieldM3ESize, double> icon = {
    TextFieldM3ESize.sm: 20.0,
    TextFieldM3ESize.md: 24.0,
    TextFieldM3ESize.lg: 24.0,
  };

  // Gap between icon block and text
  static const Map<TextFieldM3ESize, double> gapIconToText = {
    TextFieldM3ESize.sm: 8,
    TextFieldM3ESize.md: 12,
    TextFieldM3ESize.lg: 12,
  };

  // Minimum touch target
  static const double minTapTarget = 48.0;

  // Animation (matches the collection's pressed/focus morph)
  static const Duration morphDuration = Duration(milliseconds: 120);
  static const Curve morphCurve = Curves.easeOut;

  // Focus ring
  static const double focusStrokeWidth = 2.0;

  // Disabled container alpha
  static const double disabledAlpha = 0.04;
  static const double disabledContentAlpha = 0.38;
}
