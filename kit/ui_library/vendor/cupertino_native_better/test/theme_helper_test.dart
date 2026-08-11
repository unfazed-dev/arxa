// `ThemeHelper.getBrightness` is what every CN component's `_isDark` resolves
// through, so a wrong answer here pins every native view to one appearance.
//
// The bug: `CupertinoThemeData.brightness` is NULLABLE, and null does not mean
// "light" — it means "follow `MediaQuery.platformBrightness`". The helper read
// `brightness ?? Brightness.light`, which answered light for a system-dark
// device whenever a CupertinoTheme without an explicit brightness was in scope.
//
// Latent in this app (under `MaterialApp` the value is a
// `MaterialBasedCupertinoThemeData` and is non-null — covered below so that
// stays true), and wrong on its own terms everywhere else.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupertino_native_better/utils/theme_helper.dart';

void main() {
  /// Resolves `getBrightness` from inside [ancestor].
  Future<Brightness> resolve(WidgetTester tester, Widget Function(Widget) ancestor) async {
    late Brightness resolved;
    await tester.pumpWidget(ancestor(Builder(builder: (BuildContext context) {
      resolved = ThemeHelper.getBrightness(context);
      return const SizedBox.shrink();
    })));
    return resolved;
  }

  testWidgets('cn.theme-helper — a null CupertinoTheme brightness follows the '
      'platform, it does not mean light', (WidgetTester tester) async {
    final Brightness resolved = await resolve(
      tester,
      (Widget child) => MediaQuery(
        // The device is in dark mode...
        data: const MediaQueryData(platformBrightness: Brightness.dark),
        child: CupertinoTheme(
          // ...and the theme in scope states no opinion, which per
          // `CupertinoThemeData` means "follow the device".
          data: const CupertinoThemeData(),
          child: Directionality(textDirection: TextDirection.ltr, child: child),
        ),
      ),
    );

    expect(resolved, Brightness.dark,
        reason: 'null brightness means "follow the platform"; answering light '
            'pins every native view to the light appearance on a dark device');
  });

  testWidgets('cn.theme-helper — an explicit CupertinoTheme brightness still wins',
      (WidgetTester tester) async {
    // Anti-vacuous companion: the fix must not have turned the helper into
    // "always read the platform".
    final Brightness resolved = await resolve(
      tester,
      (Widget child) => MediaQuery(
        data: const MediaQueryData(platformBrightness: Brightness.dark),
        child: CupertinoTheme(
          data: const CupertinoThemeData(brightness: Brightness.light),
          child: Directionality(textDirection: TextDirection.ltr, child: child),
        ),
      ),
    );

    expect(resolved, Brightness.light,
        reason: 'an explicit in-app brightness must override the device');
  });

  testWidgets('cn.theme-helper — under MaterialApp the Material theme still wins',
      (WidgetTester tester) async {
    // This is the path the app actually takes: `Theme` inserts a
    // `MaterialBasedCupertinoThemeData`, whose brightness tracks the Material
    // theme and is non-null, so the null branch above is never reached here.
    // Pinned because the fix edits the branch immediately above it.
    final Brightness resolved = await resolve(
      tester,
      (Widget child) => MediaQuery(
        // Device light, app dark — they must not agree, or this proves nothing.
        data: const MediaQueryData(platformBrightness: Brightness.light),
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: child,
        ),
      ),
    );

    expect(resolved, Brightness.dark,
        reason: 'the in-app Material theme drives native brightness, not the '
            'device — this is what an in-app theme switcher relies on');
  });
}
