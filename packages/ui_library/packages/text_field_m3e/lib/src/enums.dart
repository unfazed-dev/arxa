import 'package:flutter/material.dart';

part '_tokens_adapter.dart';

/// 3-step size scale for text fields.
enum TextFieldM3ESize { sm, md, lg }

/// Base silhouette for the container corners in resting state.
/// (Focused state morphs using tokens regardless of the base.)
enum TextFieldM3EShape { round, square }

/// Public helpers to access tokens without exposing numbers.
extension TextFieldM3ETokensX on TextFieldM3ESize {
  double get height => TextFieldM3ETokens.height[this]!;
  double get outerRoundRadius => TextFieldM3ETokens.outerRadiusRound[this]!;
  double get outerSquareRadius => TextFieldM3ETokens.outerRadiusSquare[this]!;
  double get focusedRadius => TextFieldM3ETokens.focusedRadius[this]!;
  double get horizontalPadding => TextFieldM3ETokens.horizontalPadding[this]!;
  double get iconPx => TextFieldM3ETokens.icon[this]!;
  double get gapIconToText => TextFieldM3ETokens.gapIconToText[this]!;
}
