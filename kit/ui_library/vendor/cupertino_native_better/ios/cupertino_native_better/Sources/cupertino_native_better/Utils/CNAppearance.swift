import UIKit
import os
import Combine

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

  /// os_log gate: `true` when `CN_TRACE_APPEARANCE=1` is set in the
  /// environment (Xcode scheme → Run → Arguments → Environment Variables).
  /// For a plain `flutter run` the print below already covers it — os_log
  /// `.info` never reaches stdout.
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
  ///
  /// DEBUG builds always `print` (a handful of lines per theme flip, readable
  /// in any `flutter run` console — the remaining defect is a 0–2117ms
  /// non-deterministic onset, still reproducing in the 08-11 22:51 clip with
  /// recovery exactly on scroll). Set `CN_TRACE_APPEARANCE=0` to silence.
  static func trace(_ view: String, _ event: String) {
    #if DEBUG
    if ProcessInfo.processInfo.environment["CN_TRACE_APPEARANCE"] != "0" {
      print("CNAppearance \(view) \(event) t=\(Date().timeIntervalSince1970 * 1000.0)")
    }
    #endif
    guard tracing else { return }
    os_log("%{public}@ %{public}@ t=%{public}.1f",
           log: log, type: .info, view, event,
           Date().timeIntervalSince1970 * 1000.0)
  }
}

/// A bump counter SwiftUI glass views hang `.id(epoch)` on their glass
/// subtree, so a theme flip DESTROYS and recreates the backing effect view
/// instead of diffing an unchanged `.glassEffect` modifier (which reuses the
/// stale material — expo#43743; cured the split-button pill via
/// `GlassButtonGroupViewModel.appearanceEpoch`).
///
/// Used where a full rootView re-root would wipe user state (`@State` search
/// text, focus): only the `.id`'d glass subtree is recreated, siblings diff
/// clean. Bumped from `setBrightness` inside `applyInstantly`.
final class CNAppearanceEpoch: ObservableObject {
  @Published var epoch: Int = 0
}

/// Generation-guarded settle replay for theme flips.
///
/// Rapid successive flips (08-12 14-01 clip) strand individual views on a
/// STALE theme for seconds: the per-flip teardown/re-attach/re-root lands
/// mid-storm, the render server coalesces, and a view that was mid-mutation
/// when the next flip arrived completes with the previous flip's appearance,
/// then waits for an incidental re-composite to self-heal. Replaying the
/// same apply once the storm has settled — guarded so only the LATEST
/// generation's replay runs — makes the end state deterministic without
/// touching the single-flip fast path. kimitail: the 0.35s delay is a
/// heuristic, not a proven minimum; it must outlast a flip storm and beat a
/// finger moving to a popup trigger (a group re-root mid-presentation is
/// untested).
final class CNAppearanceSettleReplay {
  private var generation: Int = 0
  private let delay: TimeInterval

  init(delay: TimeInterval = 0.35) { self.delay = delay }

  /// Schedules [replay] after the settle delay. Any later `poke` supersedes
  /// it — intermediate flips never replay, so the closure may capture the
  /// flip's `isDark`: the only closure that ever runs carries the final value.
  func poke(_ replay: @escaping () -> Void) {
    generation &+= 1
    let g = generation
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self, self.generation == g else { return }
      replay()
    }
  }
}
