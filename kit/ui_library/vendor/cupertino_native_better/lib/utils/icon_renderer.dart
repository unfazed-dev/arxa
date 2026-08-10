import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// Detects image format from asset path or image data.
///
/// Returns the format string ('png', 'svg', 'jpg', 'jpeg', etc.) based on:
/// 1. File extension from [assetPath] if provided
/// 2. Image data magic bytes if [imageData] is provided
/// 3. Returns null if format cannot be determined
String? detectImageFormat(String? assetPath, Uint8List? imageData) {
  // First, try to detect from file extension
  if (assetPath != null && assetPath.isNotEmpty) {
    final extension = assetPath.split('.').last.toLowerCase();
    if (extension == 'svg') return 'svg';
    if (extension == 'png') return 'png';
    if (extension == 'jpg' || extension == 'jpeg') return 'jpg';
    if (extension == 'gif') return 'gif';
    if (extension == 'webp') return 'webp';
  }

  // If no extension or format not detected, try to detect from image data magic bytes
  if (imageData != null && imageData.length >= 4) {
    // PNG: 89 50 4E 47 (PNG signature)
    if (imageData[0] == 0x89 &&
        imageData[1] == 0x50 &&
        imageData[2] == 0x4E &&
        imageData[3] == 0x47) {
      return 'png';
    }

    // JPEG: FF D8 FF
    if (imageData[0] == 0xFF && imageData[1] == 0xD8 && imageData[2] == 0xFF) {
      return 'jpg';
    }

    // GIF: 47 49 46 38 (GIF8)
    if (imageData[0] == 0x47 &&
        imageData[1] == 0x49 &&
        imageData[2] == 0x46 &&
        imageData[3] == 0x38) {
      return 'gif';
    }

    // SVG: Check if it starts with '<' or contains 'svg' in the first bytes
    // SVG files are XML, so they typically start with '<' or whitespace followed by '<'
    final firstBytes = String.fromCharCodes(imageData.take(100));
    if (firstBytes.trim().startsWith('<') &&
        (firstBytes.contains('<svg') || firstBytes.contains('SVG'))) {
      return 'svg';
    }
  }

  // Default to PNG if we have image data but can't determine format
  // (PNG is the most common format for icons)
  if (imageData != null) {
    return 'png';
  }

  return null;
}

/// Resolves asset path based on device pixel ratio, similar to Flutter's automatic asset selection.
///
/// Flutter automatically picks assets from folders like:
/// - `icons/` (1x)
/// - `icons/2.0x/` (2x)
/// - `icons/3.0x/` (3x)
///
/// This function does the same for native platform views:
/// 1. Tries to find asset at the exact pixel ratio (e.g., 3.0x for @3x devices)
/// 2. If not found, picks the closest bigger size
/// 3. Falls back to the original path if no resolution-specific asset is found
///
/// - [assetPath]: The base asset path (e.g., "assets/icons/checkcircle.png")
/// - [devicePixelRatio]: Optional device pixel ratio (defaults to current device)
/// - Returns: Resolved asset path or original path if no resolution-specific asset found
Future<String> resolveAssetPathForPixelRatio(
  String assetPath, {
  double? devicePixelRatio,
}) async {
  // Get device pixel ratio if not provided
  final pixelRatio =
      devicePixelRatio ??
      ui.PlatformDispatcher.instance.views.first.devicePixelRatio;

  // Round to nearest 0.5 (1.0, 1.5, 2.0, 2.5, 3.0, etc.)
  final roundedRatio = (pixelRatio * 2).round() / 2.0;

  // Extract directory and filename from path
  final pathParts = assetPath.split('/');
  if (pathParts.isEmpty) return assetPath;

  final fileName = pathParts.last;
  final directory = pathParts.length > 1
      ? pathParts.sublist(0, pathParts.length - 1).join('/')
      : '';

  // Try exact ratio first (e.g., 3.0x)
  final exactRatioPath = roundedRatio == 1.0
      ? assetPath
      : '$directory/${roundedRatio}x/$fileName';

  if (await _assetExists(exactRatioPath)) {
    return exactRatioPath;
  }

  // If exact ratio not found, try to find closest bigger size
  // Common ratios: 1.0, 1.5, 2.0, 2.5, 3.0, 4.0
  final possibleRatios = [1.0, 1.5, 2.0, 2.5, 3.0, 4.0];

  // Find all bigger ratios
  final biggerRatios = possibleRatios.where((r) => r > roundedRatio).toList()
    ..sort();

  // Try each bigger ratio until we find one that exists
  for (final ratio in biggerRatios) {
    final ratioPath = ratio == 1.0
        ? assetPath
        : '$directory/${ratio}x/$fileName';
    if (await _assetExists(ratioPath)) {
      return ratioPath;
    }
  }

  // Fallback to original path
  return assetPath;
}

/// Checks if an asset exists in the Flutter asset bundle.
Future<bool> _assetExists(String assetPath) async {
  try {
    await rootBundle.load(assetPath);
    return true;
  } catch (e) {
    return false;
  }
}

/// Renders an [IconData] to PNG bytes for use in native platform views.
///
/// The [size] parameter is the logical font size of the glyph. The output
/// is always a square `size × size` logical-pixel bitmap with the glyph's
/// visible bounds centered inside it. This keeps the embedded icon's
/// effective dimensions consistent regardless of how much line-box
/// leading the source font reports — so native containers like UITabBar
/// lay out a predictable distance between icon and label.
///
/// The function works in three passes:
///   1. Paint the glyph onto a generously padded canvas (TextPainter
///      reports line-box metrics, not glyph metrics — we can't ask the
///      engine ahead of time how far the glyph overflows).
///   2. Scan the alpha channel to find the actual non-transparent bounds.
///   3. Re-render the glyph IN VECTOR at the fontSize that makes its ink
///      fill `size`, positioned from the linearly-scaled pass-1 bounds.
///      (Never resample the pass-1 bitmap — a nearest-neighbor upscale
///      here was the cause of pixelated customIcon glyphs on device.)
Future<Uint8List?> iconDataToImageBytes(
  IconData iconData, {
  double size = 25.0,
  Color color = CupertinoColors.black,
}) async {
  try {
    final double pixelRatio =
        ui.PlatformDispatcher.instance.views.first.devicePixelRatio;

    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          inherit: false,
          color: color,
          fontSize: size,
          fontFamily: iconData.fontFamily,
          package: iconData.fontPackage,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final double padding = size;
    final double logicalWidth = painter.width + padding * 2;
    final double logicalHeight = painter.height + padding * 2;
    final int paddedPixelWidth = (logicalWidth * pixelRatio).ceil();
    final int paddedPixelHeight = (logicalHeight * pixelRatio).ceil();

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder)..scale(pixelRatio);
    painter.paint(canvas, Offset(padding, padding));
    final ui.Image paddedImage = await recorder.endRecording().toImage(
      paddedPixelWidth,
      paddedPixelHeight,
    );

    final ByteData? rgbaData = await paddedImage.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (rgbaData == null) {
      paddedImage.dispose();
      return null;
    }
    final Uint8List rgba = rgbaData.buffer.asUint8List();

    int minX = paddedPixelWidth;
    int minY = paddedPixelHeight;
    int maxX = -1;
    int maxY = -1;
    for (int y = 0; y < paddedPixelHeight; y++) {
      final int rowOffset = y * paddedPixelWidth * 4;
      for (int x = 0; x < paddedPixelWidth; x++) {
        if (rgba[rowOffset + x * 4 + 3] != 0) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }

    if (maxX < 0) {
      // Nothing was painted (e.g. unknown glyph for the requested font).
      paddedImage.dispose();
      return null;
    }

    final double glyphPixelWidth = (maxX - minX + 1).toDouble();
    final double glyphPixelHeight = (maxY - minY + 1).toDouble();

    // Produce a square `size × size` (logical pixels) canvas, with the
    // visible glyph scaled to FILL the canvas (preserving aspect ratio).
    // Standard icon fonts like CupertinoIcons / Material Icons render
    // their glyphs inside the em-box with their own built-in padding —
    // if we just placed the glyph 1:1, the visible ink would be smaller
    // than the SF Symbol at the same pointSize and the rows would look
    // mismatched. Scaling to fill the requested `size` matches SF
    // Symbol's "pointSize is ink size" convention.
    //
    // Crucially, the fill-scaling is done by RE-RENDERING the glyph in
    // vector at the corrected fontSize — NOT by resampling the pass-1
    // bitmap. drawImageRect on the cropped ink was the pixelation bug:
    // a ~1.2–1.6× bitmap upscale through Paint()'s default
    // FilterQuality.none (nearest neighbor) produced jagged edges on
    // every customIcon surface (icon buttons, app bar glyphs) while the
    // SVG asset path stayed crisp. Outline fonts scale linearly with
    // fontSize, so the pass-1 ink bounds predict the pass-2 ink position.
    final int outputPixelSize = (size * pixelRatio).ceil();
    final double maxGlyphDim = glyphPixelWidth > glyphPixelHeight
        ? glyphPixelWidth
        : glyphPixelHeight;
    final double fitScale = outputPixelSize / maxGlyphDim;
    final double drawnWidth = glyphPixelWidth * fitScale;
    final double drawnHeight = glyphPixelHeight * fitScale;
    final double dstX = (outputPixelSize - drawnWidth) / 2.0;
    final double dstY = (outputPixelSize - drawnHeight) / 2.0;
    paddedImage.dispose();

    // Ink offset relative to the pass-1 text origin, in physical pixels.
    // Scales linearly with fontSize, so at `size * fitScale` the ink sits
    // at `inkRel * fitScale` from wherever we paint the text origin.
    final double paddingPx = padding * pixelRatio;
    final double inkRelX = minX - paddingPx;
    final double inkRelY = minY - paddingPx;

    final TextPainter fillPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          inherit: false,
          color: color,
          fontSize: size * fitScale,
          fontFamily: iconData.fontFamily,
          package: iconData.fontPackage,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final ui.PictureRecorder squareRecorder = ui.PictureRecorder();
    final Canvas squareCanvas = Canvas(squareRecorder)..scale(pixelRatio);
    fillPainter.paint(
      squareCanvas,
      Offset(
        (dstX - inkRelX * fitScale) / pixelRatio,
        (dstY - inkRelY * fitScale) / pixelRatio,
      ),
    );
    final ui.Image squareImage = await squareRecorder.endRecording().toImage(
      outputPixelSize,
      outputPixelSize,
    );

    final ByteData? pngData = await squareImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    squareImage.dispose();

    return pngData?.buffer.asUint8List();
  } catch (e) {
    debugPrint('Error rendering icon to image: $e');
    return null;
  }
}

/// A resolved icon payload for a native platform view.
///
/// This is the single Dart-side owner of the icon resolution pipeline
/// (Stage 2 of `docs/plans/icon-pipeline-consolidation.md`). Components
/// await [resolveIconSource] and map the result onto their (still
/// per-component, Stage 3 renames them) wire keys.
sealed class IconSource {
  const IconSource();
}

/// A Flutter-bundle asset icon. [resolvedPath] has already been resolved
/// for the device pixel ratio via [resolveAssetPathForPixelRatio].
final class IconSourceAsset extends IconSource {
  /// Creates an asset icon source from an already-resolved asset path.
  const IconSourceAsset({
    required this.resolvedPath,
    this.imageData,
    this.format,
  });

  /// Pixel-ratio-resolved asset path (e.g. `icons/2.0x/check.png`).
  final String resolvedPath;

  /// Raw image bytes accompanying the asset, when the caller provided any.
  final Uint8List? imageData;

  /// Image format string, guaranteed lowercase ('png', 'svg', 'jpg', …),
  /// or null when it could not be determined. Lowercasing is normalized
  /// here at the resolver: the Swift side (Stage 1) compares lowercase
  /// format strings, so Dart must never send mixed-case ones.
  final String? format;
}

/// Pre-rasterized icon bytes produced by [iconDataToImageBytes].
final class IconSourceBytes extends IconSource {
  /// Creates a rasterized icon source from PNG [bytes].
  const IconSourceBytes({required this.bytes});

  /// PNG-encoded icon bitmap.
  final Uint8List bytes;

  /// [iconDataToImageBytes] always encodes PNG.
  String get format => 'png';
}

/// An SF Symbol resolved by name on the native side.
final class IconSourceSymbol extends IconSource {
  /// Creates a symbol icon source for the SF Symbol called [name].
  const IconSourceSymbol(this.name);

  /// SF Symbol name (e.g. `house.fill`).
  final String name;
}

/// Resolves the shared component priority chain
/// `imageAsset > customIcon > icon` into a single [IconSource].
///
/// - Asset branch: taken when [assetPath] is non-null (mirrors the
///   call sites' `imageAsset != null` gate — an empty path still takes
///   this branch, as before). Resolves the pixel-ratio variant, then
///   determines the format as `assetFormat ?? detectImageFormat(...)`,
///   lowercased (the one normalization Stage 2 is allowed to make).
/// - Custom-icon branch: rasterizes [customIcon] at [customIconSize]
///   logical pixels. Returns null when rasterization fails — no call
///   site ever fell through to the symbol branch on failure, and
///   callers rely on that (FutureBuilder placeholders stay up).
/// - Symbol branch: returns [IconSourceSymbol] when [symbolName] is
///   provided; otherwise null (caller renders its no-icon layout).
Future<IconSource?> resolveIconSource({
  String? assetPath,
  Uint8List? assetImageData,
  String? assetFormat,
  double? devicePixelRatio,
  IconData? customIcon,
  double customIconSize = 20.0,
  Color customIconColor = CupertinoColors.black,
  String? symbolName,
}) async {
  if (assetPath != null) {
    final resolvedPath = await resolveAssetPathForPixelRatio(
      assetPath,
      devicePixelRatio: devicePixelRatio,
    );
    return IconSourceAsset(
      resolvedPath: resolvedPath,
      imageData: assetImageData,
      format: (assetFormat ?? detectImageFormat(resolvedPath, assetImageData))
          ?.toLowerCase(),
    );
  }
  if (customIcon != null) {
    final bytes = await iconDataToImageBytes(
      customIcon,
      size: customIconSize,
      color: customIconColor,
    );
    return bytes == null ? null : IconSourceBytes(bytes: bytes);
  }
  if (symbolName != null) {
    return IconSourceSymbol(symbolName);
  }
  return null;
}
