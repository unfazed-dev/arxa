import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for C1 of `docs/plans/glass-chrome-root-cause-fixes.md`.
///
/// ## What the bug actually is (measured, not assumed)
///
/// The vendored components built their `future:` argument *inside* `build()`.
/// `FutureBuilder` compares futures by identity, so every parent rebuild
/// handed it a brand-new future and it re-subscribed.
///
/// The plan predicted that this collapses the subtree to the placeholder and
/// tears down the `UiKitView`. **That prediction does not hold.** Flutter's
/// `_FutureBuilderState.didUpdateWidget` does
/// `_snapshot = _snapshot.inState(ConnectionState.none)`, and
/// `AsyncSnapshot.inState` preserves `data`. So `snapshot.hasData` stays
/// true across a parent rebuild, the `!snapshot.hasData` placeholder branch
/// is never taken, and the platform view keeps its Element. Verified: the
/// `UiKitView` count stayed at 1 across every rebuild, before any fix.
///
/// What the bug *is* is redundant work. Every parent rebuild kicks off a
/// fresh `resolveIconSource`, which for the asset path costs a measured two
/// `rootBundle.load` round-trips per rebuild (unbounded: 2 after first mount
/// -> 12 after five rebuilds) and for the `customIcon` path costs a full
/// `PictureRecorder -> toImage -> toByteData` rasterization on the main
/// isolate. Each completion then fires a `setState`, so every parent rebuild
/// also buys a second, redundant subtree rebuild. During a scroll or a route
/// animation that is per-frame raster work.
///
/// ## What these tests assert
///
/// - **Red-then-green:** the resolve count must not grow with parent
///   rebuilds. This is the discriminator; it fails before the fix.
/// - **Already-green invariant guards:** the platform view must stay present
///   and keep its Element across rebuilds. These pass before the fix too and
///   are *not* red-then-green evidence. They exist because the fix takes
///   ownership of the stale-value preservation that `FutureBuilder` used to
///   provide for free: a cache that clears itself before re-resolving would
///   introduce exactly the placeholder flash the plan wrongly assumed was
///   already happening.
///
/// ## Reachability notes (measured)
///
/// - `CNButton`, `CNGlassButtonGroup` and `CNPopupMenuButton` gate on
///   `PlatformVersion.shouldUseNativeGlass`, true on a macOS 26+ test host,
///   so their native branch is reachable under `flutter test`.
/// - `CNIcon` additionally gates on `!PlatformViewGuard.isTestEnvironment`
///   (LOCAL PATCH #4), so its native branch is unreachable here by design.
///   `icon.dart` receives the same fix but has no component-level coverage;
///   widening that gate was rejected because `fallback_tier_test.dart`
///   asserts it.
/// - The `imageAsset` path is used throughout: it resolves under plain
///   pumps. The `customIcon` path never completes under `flutter test`
///   (`iconDataToImageBytes` needs a real rasterizer), so it is not covered.
void main() {
  /// Counts `rootBundle.load` round-trips, which is how the asset branch of
  /// `resolveIconSource` reaches the bundle. Returns a getter for the count.
  int Function() installAssetLoadCounter() {
    var loads = 0;
    TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (ByteData? message) async {
          loads++;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null);
    });
    return () => loads;
  }

  /// Sets [debugDefaultTargetPlatformOverride] for the duration of [body].
  /// The restore must happen before the test body returns (flutter_test's
  /// invariant check runs before tearDown), so it lives in a finally here.
  Future<void> withIOS(Future<void> Function() body) async {
    final saved = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = saved;
    }
  }

  /// Drives the shared assertions for a component whose icon resolution must
  /// survive unrelated parent rebuilds.
  ///
  /// [childBuilder] is called on every parent build and must return a
  /// *freshly constructed* widget with an identical configuration — a cached
  /// or `const` instance would let Flutter skip the child rebuild entirely
  /// and the test would pass vacuously.
  Future<void> expectResolutionSurvivesParentRebuilds(
    WidgetTester tester,
    Widget Function() childBuilder, {
    int rebuilds = 5,
  }) async {
    final loads = installAssetLoadCounter();
    final rebuildTick = ValueNotifier<int>(0);
    addTearDown(rebuildTick.dispose);
    final textScale = ValueNotifier<double>(1.0);
    addTearDown(textScale.dispose);

    await tester.pumpWidget(
      ValueListenableBuilder<double>(
        valueListenable: textScale,
        builder: (context, scale, child) => MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: ValueListenableBuilder<int>(
                valueListenable: rebuildTick,
                builder: (context, tick, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Unrelated sibling whose content changes each rebuild,
                    // so the parent subtree genuinely rebuilds.
                    Text('tick $tick'),
                    childBuilder(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Let the initial resolution land and the platform view appear.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // Invariant guard (already green before the fix).
    expect(
      find.byType(UiKitView),
      findsOneWidget,
      reason: 'platform view should exist after the first resolution settles',
    );
    final firstElement = tester.element(find.byType(UiKitView));

    final loadsAfterFirstMount = loads();
    expect(
      loadsAfterFirstMount,
      greaterThan(0),
      reason:
          'the asset branch must actually reach the bundle, otherwise this '
          'test measures nothing',
    );

    for (var i = 1; i <= rebuilds; i++) {
      rebuildTick.value = i;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      // THE DISCRIMINATOR. Before the fix this grows by two loads per
      // rebuild because `build()` constructs a fresh `resolveIconSource`
      // future every time.
      expect(
        loads(),
        loadsAfterFirstMount,
        reason:
            'icon resolution re-ran on parent rebuild #$i — the asset bundle '
            'was hit again for an unchanged icon configuration',
      );

      // Invariant guards (already green before the fix): the fix must not
      // introduce a teardown or a placeholder frame that did not exist.
      expect(
        find.byType(UiKitView),
        findsOneWidget,
        reason: 'platform view vanished on parent rebuild #$i',
      );
      expect(
        tester.element(find.byType(UiKitView)),
        same(firstElement),
        reason: 'platform view Element was re-created on parent rebuild #$i',
      );
    }

    // A dependency change (MediaQuery) must not re-resolve either: the icon
    // configuration is unchanged, so the key guard in didChangeDependencies
    // has to make this a no-op.
    textScale.value = 1.3;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      loads(),
      loadsAfterFirstMount,
      reason:
          'icon resolution re-ran on an unrelated MediaQuery change — '
          'didChangeDependencies is not guarded by the resolution key',
    );
  }

  group('C1: icon resolution must not restart on every parent rebuild', () {
    testWidgets('CNButton', (tester) async {
      await withIOS(() async {
        await expectResolutionSurvivesParentRebuilds(
          tester,
          () => CNButton.icon(
            imageAsset: const CNImageAsset('assets/icons/star.png'),
            onPressed: () {},
          ),
        );
      });
    });

    testWidgets('CNGlassButtonGroup', (tester) async {
      await withIOS(() async {
        await expectResolutionSurvivesParentRebuilds(
          tester,
          () => CNGlassButtonGroup(
            buttons: [
              CNButtonData(
                label: 'a',
                imageAsset: const CNImageAsset('assets/icons/star.png'),
                onPressed: () {},
              ),
              CNButtonData(
                label: 'b',
                imageAsset: const CNImageAsset('assets/icons/heart.png'),
                onPressed: () {},
              ),
            ],
          ),
        );
      });
    });

    testWidgets('CNPopupMenuButton with a button image asset', (tester) async {
      await withIOS(() async {
        await expectResolutionSurvivesParentRebuilds(
          tester,
          () => CNPopupMenuButton.icon(
            buttonImageAsset: const CNImageAsset('assets/icons/star.png'),
            items: const [
              CNPopupMenuItem(label: 'a'),
              CNPopupMenuItem(label: 'b'),
            ],
            onSelected: (_) {},
          ),
        );
      });
    });

    testWidgets('CNPopupMenuButton with menu item image assets', (
      tester,
    ) async {
      await withIOS(() async {
        await expectResolutionSurvivesParentRebuilds(
          tester,
          () => CNPopupMenuButton(
            buttonLabel: 'Menu',
            items: const [
              CNPopupMenuItem(
                label: 'a',
                imageAsset: CNImageAsset('assets/icons/star.png'),
              ),
              CNPopupMenuItem(label: 'b'),
            ],
            onSelected: (_) {},
          ),
        );
      });
    });
  });
}
