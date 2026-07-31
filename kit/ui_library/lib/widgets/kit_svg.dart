import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// SVG image viewer, backed by `flutter_svg`.
///
/// [KitSvg.asset] renders a bundled asset; [KitSvg.network] fetches one.
/// [color] tints the whole drawing (`BlendMode.srcIn`) — the common
/// "icon takes the theme color" case.
class KitSvg extends StatelessWidget {
  const KitSvg.asset(
    String asset, {
    super.key,
    this.width,
    this.height,
    this.color,
    this.semanticsLabel,
  }) : _asset = asset,
       _url = null;

  const KitSvg.network(
    String url, {
    super.key,
    this.width,
    this.height,
    this.color,
    this.semanticsLabel,
  }) : _asset = null,
       _url = url;

  final String? _asset;
  final String? _url;

  /// Rendered size; the SVG's intrinsic size when null.
  final double? width;
  final double? height;

  /// Optional tint applied to the whole drawing.
  final Color? color;

  /// Accessibility label.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final colorFilter = color == null
        ? null
        : ColorFilter.mode(color!, BlendMode.srcIn);
    final asset = _asset;
    if (asset != null) {
      return SvgPicture.asset(
        asset,
        width: width,
        height: height,
        colorFilter: colorFilter,
        semanticsLabel: semanticsLabel,
      );
    }
    return SvgPicture.network(
      _url!,
      width: width,
      height: height,
      colorFilter: colorFilter,
      semanticsLabel: semanticsLabel,
    );
  }
}
