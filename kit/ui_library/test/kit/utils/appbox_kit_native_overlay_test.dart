import 'dart:async';

import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTabBarRouteObserver;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' show GetSnackBar, SnackbarController;
import 'package:appbox_kit_ui_library/utils/appbox_kit_native_overlay.dart';

void main() {
  int depth() => CNTabBarRouteObserver.anyModalDepth.value;

  tearDown(() {
    // Drain any depth a test left behind so the static global can't leak
    // between tests. markAnyModalInactive clamps at zero.
    while (depth() > 0) {
      CNTabBarRouteObserver.markAnyModalInactive();
    }
  });

  test('balances depth for a plain future that completes on dismiss',
      () async {
    expect(depth(), 0);
    await appBoxKitWithNativeChromeHidden(() async {});
    expect(depth(), 0);
  });

  test('balances depth when present() returns null', () async {
    await appBoxKitWithNativeChromeHidden(() => null);
    expect(depth(), 0);
  });

  test('balances depth when present() throws', () async {
    await expectLater(
      appBoxKitWithNativeChromeHidden(() => Future.error(StateError('boom'))),
      throwsStateError,
    );
    expect(depth(), 0);
  });

  test(
      'HOLDS the hide while a SnackbarController is live '
      '(showCustomSnackBar resolves at show time, not dismiss)', () async {
    // Regression for the iOS blur bleed-through: stacked_services'
    // showCustomSnackBar completes one frame after the snackbar APPEARS,
    // resolving to GetX's SnackbarController. The helper must keep
    // anyModalDepth > 0 until controller.future (dismissal) completes.
    final controller = SnackbarController(const GetSnackBar(message: 'x'));
    unawaited(appBoxKitWithNativeChromeHidden(() async => controller));

    // Let present() resolve and the helper reach the controller await.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(depth(), 1,
        reason: 'hide must stay active while the snackbar is on screen — '
            'releasing here is the sharp-native-views-over-blur bug');
    // controller.future can only complete via a real show/dismiss cycle;
    // tearDown drains the held depth.
  });
}
