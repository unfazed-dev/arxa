// The boot screen's brand moment (2026-08-18 pass): the brand icon, then the
// centered 'ARXA SHOWCASE' lockup, then a prominent accent-colored native
// spinner with a real gap between them — and no 'Loading…' copy. The spinner
// is the kit's ArxaKitNativeLoadingIndicator (M3E morph on Android,
// Cupertino spinner on iOS, Material elsewhere).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_kit_showcase_app/ui/common/arxa_kit_app_strings.dart';
import 'package:arxa_kit_showcase_app/ui/widgets/showcase_startup_widgets/showcase_startup_loading_widget.dart';

void main() {
  testWidgets(
      'shell-demos.startup-and-unknown-shells.boot-through-the-startup-shell — '
      'the boot screen centers the brand lockup over a prominent accent '
      'spinner, with a real gap and no loading copy', (tester) async {
    const accent = Color(0xFF123456);
    await tester.pumpWidget(MaterialApp(
      theme: arxaKitLightTheme(accent: accent),
      home: const ShowcaseStartupLoadingWidget(),
    ));
    final screen = tester.getRect(find.byType(Scaffold));

    // The lockup is the app name, centered on the screen.
    final title = find.text(abxStrStartupAppTitle);
    expect(title, findsOneWidget,
        reason: 'anti-vacuous: the brand lockup must be on screen');
    final titleRect = tester.getRect(title);
    expect(titleRect.center.dx, moreOrLessEquals(screen.center.dx, epsilon: 1),
        reason: 'the lockup is centered, not left-aligned in a row');

    // One spinner, centered under the lockup, prominent (the old inline
    // spinner was 16px next to a 'Loading…' label), and wearing the accent.
    final spinner = find.byType(ArxaKitNativeLoadingIndicator);
    expect(spinner, findsOneWidget,
        reason: 'anti-vacuous: the native loading indicator must be on screen');
    final spinnerRect = tester.getRect(spinner);
    expect(spinnerRect.center.dx, moreOrLessEquals(screen.center.dx, epsilon: 1),
        reason: 'the spinner is centered under the lockup');
    expect(spinnerRect.top, greaterThan(titleRect.bottom),
        reason: 'the spinner sits below the lockup, not beside it');
    expect(spinnerRect.top - titleRect.bottom, greaterThanOrEqualTo(24),
        reason: 'a decent gap separates the lockup and the spinner');
    expect(spinnerRect.width, greaterThan(24),
        reason: 'the boot spinner is prominent, not the old 16px inline size');
    final rendered = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator));
    expect(rendered.color, accent,
        reason: 'the spinner wears the brand accent (the default Material '
            'tier in this harness reads colorScheme.primary, which the theme '
            'constructor maps from the accent)');

    // No loading copy survives anywhere on the screen.
    expect(find.textContaining('Loading'), findsNothing);
  });
}
