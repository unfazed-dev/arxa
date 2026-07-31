import SwiftUI
import UIKit

/// Safe-area blocker for SwiftUI hosted inside Flutter platform views.
///
/// Flutter moves a platform view's frame in WINDOW coordinates while its
/// host scrollable scrolls (viewport clipping is visual only). Whenever that
/// frame crosses the status-bar / home-indicator regions, a stock
/// `UIHostingController` insets its content — the glass visibly shifts or
/// compresses inside its Flutter slot and the inset can stick after the
/// scroll settles. Neither `additionalSafeAreaInsets = .zero`,
/// `insetsLayoutMarginsFromSafeArea = false`, nor `.ignoresSafeArea()` on
/// the SwiftUI root prevents this (Apple FB8176223); `safeAreaRegions` is
/// the only supported off-switch.
///
/// EVERY platform view that hosts SwiftUI MUST call this right after
/// creating its hosting controller — a repo guard test
/// (`test/kit/guards/cn_hosting_safe_area_guard_test.dart`) fails the build
/// for any `UIHostingController(` call site whose file doesn't. The single
/// deliberate exception is `CNNativeTabBar`: it is docked at the screen
/// bottom, never scrolls, and lays out WITH the home-indicator inset.
extension UIHostingController {
  /// Removes every safe-area region (container + keyboard) from the hosted
  /// content. Also covers keyboard avoidance (Issue #4) on iOS 16.4+.
  func cnBlockSafeArea() {
    if #available(iOS 16.4, *) {
      safeAreaRegions = []
    }
  }
}
