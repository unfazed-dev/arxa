import UIKit
import os

/// Appearance changes that must land on the frame they are commanded.
///
/// ## Why this exists
///
/// A theme flip reaches every native view as a `setBrightness` method call.
/// Applying it is not free: re-resolving a `UIButton.Configuration` re-assigns
/// a fresh `.glass()`, and *establishing* glass materialises with an animation
/// by Apple's design (WWDC25 #284 — the same fact
/// `lib/utils/transition_observer.dart:284` relies on for the route-gate).
///
/// That animation is right when glass first appears. It is wrong for a theme
/// flip, where the app has already decided both halves of the UI should change
/// on the same frame. Measured on device (60fps clip, 2026-08-11 20:16): every
/// native view's appearance change takes a uniform ~200-300ms to play out,
/// against a Flutter half that flips in one frame.
///
/// The one `setBrightness` handler that does *not* re-establish glass — the tab
/// bar's, a single `overrideUserInterfaceStyle` assignment
/// (`CupertinoTabBarPlatformView.swift:896`) — is consistently among the
/// fastest views to restyle. Before this file, no `setBrightness` path anywhere
/// in the package suppressed implicit animation.
///
/// ## What it does
///
/// `CATransaction` with actions disabled kills implicit CALayer animations;
/// `UIView.performWithoutAnimation` kills UIKit's. Both are needed — they
/// govern different layers, and a `UIHostingController`'s SwiftUI content is
/// driven by the former. `flush()` commits the transaction rather than waiting
/// for the run loop to do it, so the change is on the very next commit instead
/// of an unspecified later one.
///
/// ## Why it also forces layout
///
/// A hybrid-composition platform view lives in the native hierarchy *above*
/// `FlutterViewController`, outside Flutter's own render pipeline. Its layer is
/// therefore not necessarily re-composited when only Flutter-side state
/// changes — a scroll or a touch forces the pass, which is why an appearance
/// change "catches up" later instead of on the frame it was commanded
/// (flutter#69104: recovers "after other operations such as switching pages and
/// going back" — the exact symptom originally reported against this kit).
///
/// Measured here on device: onset varied 0ms to 2117ms, non-deterministically,
/// for the *same* view across flips, while Dart demonstrably sent on frame 0
/// and the app rendered 59fps. That is what an incidental re-composite looks
/// like — whichever view a Flutter repaint happens to touch updates, the rest
/// wait.
///
/// The package already uses `setNeedsLayout`/`layoutIfNeeded` for exactly this
/// on its creation paths (`CupertinoButtonPlatformView.swift:263-272`,
/// `:815-824`). This applies the same idiom to the per-flip path, synchronously
/// rather than hopped onto a later run-loop turn — a deferred force is the bug,
/// not the fix.
///
/// (An earlier revision of this file deliberately omitted the layout force,
/// on the theory that re-entering a Flutter-owned hierarchy would trade one
/// timing bug for another. That was reasoning, not evidence, and the evidence
/// above contradicts it.)
enum CNAppearance {
  /// Applies [body] with every implicit animation suppressed, commits it
  /// immediately, and forces [views] to lay out and redraw now.
  ///
  /// Pass every view whose appearance [body] affects — for a hosted SwiftUI
  /// tier that means the hosting controller's view as well as the container,
  /// since they are separate layer trees.
  ///
  /// Safe to nest: `CATransaction` is a stack and `performWithoutAnimation`
  /// restores the previous flag.
  static func applyInstantly(forcing views: [UIView?] = [], _ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    UIView.performWithoutAnimation {
      body()
      for case let view? in views {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        view.setNeedsDisplay()
      }
    }
    CATransaction.commit()
    CATransaction.flush()
  }

  // MARK: - Diagnostics

  /// `true` when `CN_TRACE_APPEARANCE=1` is set in the environment.
  ///
  /// Off by default and read once. The remaining unexplained defect is that a
  /// view can start its appearance change anywhere from 0ms to 2117ms after
  /// being told, non-deterministically, while Dart demonstrably sends on frame
  /// 0 and the app renders at 59fps. Nothing in a widget test can observe when
  /// a `UIView` actually repaints, so closing it needs timestamps from the
  /// device itself. Run the app with that variable set (Xcode scheme →
  /// Run → Arguments → Environment Variables) and filter the console on
  /// `CNAppearance`.
  static let tracing: Bool =
    ProcessInfo.processInfo.environment["CN_TRACE_APPEARANCE"] == "1"

  private static let log = OSLog(
    subsystem: "cupertino_native_better", category: "appearance")

  /// Timestamps one appearance event against a process-wide clock, so the
  /// spread *between* views on a single flip is readable directly.
  ///
  /// `view` should identify the instance (view type + id), not just the class,
  /// or sibling views collapse into one line and the spread — the thing being
  /// measured — is exactly what is lost.
  static func trace(_ view: String, _ event: String) {
    guard tracing else { return }
    let ms = Date().timeIntervalSince1970 * 1000.0
    os_log("%{public}@ %{public}@ t=%{public}.1f",
           log: log, type: .info, view, event, ms)
  }
}
