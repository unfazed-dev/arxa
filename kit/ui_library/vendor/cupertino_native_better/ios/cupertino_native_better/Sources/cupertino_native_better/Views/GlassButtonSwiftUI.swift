import SwiftUI
import UIKit

/// SwiftUI button view with full Liquid Glass support using glassEffect() modifier.
/// This provides full blending and morphing capabilities when used in groups.
@available(iOS 26.0, *)
struct GlassButtonSwiftUI: View {
  let title: String?
  let iconName: String?
  let iconImage: UIImage?
  let iconSize: CGFloat
  let iconColor: Color?
  let tint: Color?
  let isRound: Bool
  let style: String
  let isEnabled: Bool
  let isInteractive: Bool
  let onPressed: () -> Void
  let glassEffectUnionId: String?
  let glassEffectId: String?
  let glassEffectInteractive: Bool
  var namespace: Namespace.ID
  let config: GlassButtonConfig
  let badgeCount: Int?
  /// When false, the button skips applying its own `.glassEffect()`. Used
  /// by `CNGlassButtonGroup` so a single shared glass effect can be applied
  /// at the group level (uniform pill outline) while each button keeps its
  /// own `Button(action:)` for per-button hit-testing.
  var applyOwnGlass: Bool = true

  /// Computes the effective icon color
  private var effectiveIconColor: Color? {
    return tint ?? iconColor
  }

  var body: some View {
    Button(action: onPressed) {
      HStack(spacing: config.spacing) {
        if let icon = iconImage {
          Image(uiImage: icon)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: iconSize, height: iconSize)
            .foregroundColor(effectiveIconColor)
        } else if let iconName = iconName {
          Image(systemName: iconName)
            .font(.system(size: iconSize))
            .foregroundColor(effectiveIconColor)
            // SF Symbol replace content transition (iOS 17+ API; this view is
            // gated iOS 26+). When iconName changes — e.g. a voice recorder's
            // mic → stop → mic toggle — the system animates the glyph swap
            // (old symbol exits down, new enters up) instead of hard-cutting.
            // Requires the change to arrive as an in-place SwiftUI update, not
            // a view recreation — see CupertinoButtonPlatformView.updateSwiftUIView.
            .contentTransition(.symbolEffect(.replace))
            .animation(.snappy, value: iconName)
        }

        if let title = title {
          Text(title)
            .foregroundColor(tint != nil ? Color(tint!) : nil)
        }
      }
      .padding(config.padding)
      .frame(minHeight: config.minHeight)
      .contentShape(shapeForStyle(isRound, borderRadius: config.borderRadius))
      .applyConditionalGlassEffect(
        apply: applyOwnGlass,
        glass: glassEffectForStyle(style, interactive: glassEffectInteractive),
        shape: shapeForStyle(isRound, borderRadius: config.borderRadius),
        unionId: glassEffectUnionId,
        glassEffectId: glassEffectId,
        namespace: namespace
      )
      .animation(.easeInOut(duration: 0.25), value: iconSize)
      .animation(.easeInOut(duration: 0.25), value: iconColor)
      .animation(.easeInOut(duration: 0.25), value: tint)
      .animation(.easeInOut(duration: 0.25), value: style)
      .animation(.easeInOut(duration: 0.25), value: config.spacing)
      .animation(.easeInOut(duration: 0.25), value: config.padding)
      .animation(.easeInOut(duration: 0.25), value: config.minHeight)
      .animation(.easeInOut(duration: 0.25), value: config.borderRadius)
    }
    .disabled(!isEnabled)
    .buttonStyle(NoHighlightButtonStyle())
    .badge(badgeCount != nil && badgeCount! > 0 ? (badgeCount! > 99 ? "99+" : "\(badgeCount!)") : nil)
    // Disable hit testing on the button when not interactive
    .allowsHitTesting(isEnabled && isInteractive)
  }
  
  private func glassEffectForStyle(_ style: String, interactive: Bool) -> Glass {
    // Always use .regular for now - prominent glass API may be available in future
    var glass = Glass.regular
    
    // Make glass interactive if requested
    if interactive {
      glass = glass.interactive()
    }
    
    return glass
  }
  
  private func shapeForStyle(_ isRound: Bool, borderRadius: CGFloat?) -> some Shape {
    // If borderRadius is provided, use it
    if let radius = borderRadius {
      return AnyShape(RoundedRectangle(cornerRadius: radius))
    }
    // If no borderRadius provided, use capsule for round buttons
    if isRound {
      return AnyShape(Capsule())
    }
    // For non-round buttons without radius, also use capsule (as per user requirement)
    return AnyShape(Capsule())
  }
}

// Apply the per-button glassEffect + union/id modifiers ONLY when
// `apply` is true. When false (group mode), the button skips its own glass
// and relies on the group's outer .glassEffect to produce one uniform pill.
//
// `.glassEffectTransition(.identity)`: governs ONLY SwiftUI-driven
// insertion/removal of glass inside a `GlassEffectContainer` in our own tree
// (incl. the engine's platform-view detach/reattach on scroll — the
// `LiquidGlassContainerView` rationale, :305-322). It snaps those glass
// changes to their final state instead of replaying the materialise
// animation. It does NOT affect the popup `Menu` dismiss morph: that flash
// is the system presentation layer reparenting the glass (Apple bug, forums
// 826863 / expo#44126), unreachable from any of our modifiers — rounds 8
// (this knob) and 9 (post-dismiss re-root replay) both proved inert on
// device (11-22/11-46 clips). The working cure lives in
// `GlassButtonGroupView.buttonView`: popup triggers render their glass via
// the system's own `.buttonStyle(.glass)`, which the morph hands back
// correctly.
@available(iOS 26.0, *)
extension View {
  @ViewBuilder
  func applyConditionalGlassEffect(
    apply: Bool,
    glass: Glass,
    shape: some Shape,
    unionId: String?,
    glassEffectId: String?,
    namespace: Namespace.ID
  ) -> some View {
    if apply {
      self
        .glassEffect(glass, in: shape)
        .glassEffectTransition(.identity)
        .applyGlassEffectModifiers(unionId: unionId, id: glassEffectId, namespace: namespace)
    } else {
      self
    }
  }
}

// Helper to apply glass effect modifiers conditionally
@available(iOS 26.0, *)
extension View {
  @ViewBuilder
  func applyGlassEffectModifiers(unionId: String?, id: String?, namespace: Namespace.ID) -> some View {
    if let unionId = unionId {
      if let id = id {
        self
          .glassEffectUnion(id: unionId, namespace: namespace)
          .glassEffectID(id, in: namespace)
      } else {
        self
          .glassEffectUnion(id: unionId, namespace: namespace)
      }
    } else if let id = id {
      self
        .glassEffectID(id, in: namespace)
    } else {
      self
    }
  }
}

// Custom button style that removes all highlights and press effects
@available(iOS 26.0, *)
struct NoHighlightButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      // No opacity or scale changes - let the glass effect handle visual feedback
  }
}

// Type erasure for Shape
@available(iOS 26.0, *)
struct AnyShape: Shape {
  private let _path: (CGRect) -> Path
  
  init<S: Shape>(_ shape: S) {
    _path = shape.path(in:)
  }
  
  func path(in rect: CGRect) -> Path {
    return _path(rect)
  }
}

