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
/// This deliberately does NOT force layout. `layoutIfNeeded` inside a Flutter
/// platform view re-enters a hierarchy whose geometry Flutter owns; the
/// package's existing uses of it are all on the creation path, hopped onto the
/// next run-loop turn, and copying that into a per-flip path would trade one
/// timing bug for another.
enum CNAppearance {
  /// Applies [body] with every implicit animation suppressed, and commits it
  /// immediately rather than at the run loop's convenience.
  ///
  /// Safe to nest: `CATransaction` is a stack and `performWithoutAnimation`
  /// restores the previous flag.
  static func applyInstantly(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    UIView.performWithoutAnimation {
      body()
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
