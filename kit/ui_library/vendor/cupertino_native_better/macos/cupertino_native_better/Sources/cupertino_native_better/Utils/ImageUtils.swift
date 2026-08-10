import Cocoa

/// Shared image and color helpers for the macOS platform views.
///
/// Deliberately narrower than the iOS twin. macOS has no asset-path or SVG icon
/// pipeline: every macOS view resolves its icon from an SF Symbol name, and the
/// tab bar is the only one that decodes bytes at all. Mirrored names are for the
/// entry points that actually have macOS callers, so the two files stay
/// diffable without this one growing dead API.
final class ImageUtils {

  // MARK: - Color Conversion

  /// Converts ARGB integer to NSColor
  /// - Parameter argb: ARGB color as integer (0xAARRGGBB format)
  /// - Returns: NSColor instance
  static func colorFromARGB(_ argb: Int) -> NSColor {
    let a = CGFloat((argb >> 24) & 0xFF) / 255.0
    let r = CGFloat((argb >> 16) & 0xFF) / 255.0
    let g = CGFloat((argb >> 8) & 0xFF) / 255.0
    let b = CGFloat(argb & 0xFF) / 255.0
    return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
  }

  // MARK: - Icon Source Resolution

  /// Decodes PNG bytes rasterized from a Flutter `IconData` glyph into a
  /// template image laid out at `pointSize`.
  ///
  /// The backing representation is sized in physical pixels (`pointSize *
  /// scale`) while the image itself reports `pointSize`, so AppKit draws the
  /// bitmap at native resolution instead of upscaling a 1x raster.
  ///
  /// `scale` is required on purpose: a defaulted scale is how the equivalent
  /// iOS split went unnoticed.
  static func iconFromTemplateBytes(_ data: Data, pointSize: CGFloat, scale: CGFloat) -> NSImage? {
    guard let image = NSImage(data: data) else { return nil }
    if let rep = image.representations.first {
      rep.pixelsWide = Int(pointSize * scale)
      rep.pixelsHigh = Int(pointSize * scale)
    }
    image.size = NSSize(width: pointSize, height: pointSize)
    image.isTemplate = true  // Allow macOS to tint the icon
    return image
  }
}
