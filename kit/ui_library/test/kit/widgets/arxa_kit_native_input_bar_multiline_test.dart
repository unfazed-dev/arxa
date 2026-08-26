import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:text_field_m3e/text_field_m3e.dart' show TextFieldM3E;

/// [ArxaKitNativeInputBar] + [ArxaKitNativeTextField] multiline contracts —
/// the native Liquid Glass composer work.
///
/// The tier-testable seams: the Material fallback tier (wantNative: false) is a
/// real TextField in the tree, so multiline params are assertable directly; the
/// M3E tier is pure Dart (TextFieldM3E); the CN tier's multiline is Swift-side
/// and pinned by creation-params shape (headless tests cannot mount UiKitView).
void main() {
  tearDown(ArxaKitPlatform.reset);

  testWidgets(
      'kit.ui-library.native-input-bar — the bar field is multiline by default '
      '(grows with content)', (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child:
              ArxaKitNativeInputBar(hintText: 'Message', wantNative: false),
        ),
      ),
    ));

    final TextField field = tester.widget(find.byType(TextField));
    expect(field.maxLines, 6,
        reason: 'the composer default caps at 6 lines then scrolls — the '
            'chat-composer idiom (bar default), not unbounded');
    expect(field.minLines, 1, reason: 'one line at rest, growing from there');
    expect(find.byType(TextField), findsOneWidget);

    // Growth: enter a long text, the field's height must grow beyond one line.
    final before = tester.getSize(find.byType(TextField)).height;
    await tester.enterText(find.byType(TextField), 'a' * 200);
    await tester.pumpAndSettle();
    final after = tester.getSize(find.byType(TextField)).height;
    expect(after, greaterThan(before),
        reason: 'wrapping multiline input must grow the field height');
  });

  testWidgets(
      'kit.ui-library.native-input-bar — maxLines caps the composer growth',
      (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ArxaKitNativeInputBar(
              hintText: 'Message', wantNative: false, maxLines: 3),
        ),
      ),
    ));

    final TextField field = tester.widget(find.byType(TextField));
    expect(field.maxLines, 3,
        reason: 'an explicit cap reaches the underlying field');
  });

  testWidgets(
      'kit.ui-library.native-input-bar — the multiline default flows to the '
      'M3E tier', (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ArxaKitNativeInputBar(hintText: 'Message'),
        ),
      ),
    ));

    expect(find.byType(TextFieldM3E), findsOneWidget,
        reason: 'Android native tier renders the vendored M3E field');
    // The M3E field must carry multiline through to its inner TextField.
    final inner = find.descendant(
        of: find.byType(TextFieldM3E), matching: find.byType(TextField));
    expect(inner, findsOneWidget);
    expect(tester.widget<TextField>(inner).maxLines, 6,
        reason: 'the composer default (grow to 6, then scroll) must reach the '
            'M3E inner field');
    expect(tester.widget<TextField>(inner).minLines, 1,
        reason: 'and the one-line-at-rest floor reaches it too');
  });

  testWidgets(
      'kit.ui-library.native-input-bar — multiline defaults the keyboard type '
      'to multiline (return = newline, matching the native tiers)', (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ArxaKitNativeInputBar(
              hintText: 'Message', wantNative: false),
        ),
      ),
    ));

    final TextField field = tester.widget(find.byType(TextField));
    expect(field.keyboardType, TextInputType.multiline,
        reason: 'a multiline composer with no explicit keyboard type must '
            'request the multiline keyboard so return inserts a newline — the '
            'same behavior the CN vertical-axis field and the Android tier give');
  });

  testWidgets(
      'kit.ui-library.native-input-bar — an explicit keyboard type wins over '
      'the multiline default', (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ArxaKitNativeInputBar(
              hintText: 'Email', wantNative: false, keyboardType: TextInputType.emailAddress),
        ),
      ),
    ));

    final TextField field = tester.widget(find.byType(TextField));
    expect(field.keyboardType, TextInputType.emailAddress,
        reason: 'hosts keep full control when they name a keyboard type');
  });

  testWidgets(
      'kit.ui-library.native-input-bar — bar field stays single-line when '
      'multiline: false (search-style bars)', (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ArxaKitNativeInputBar(
              hintText: 'Search', wantNative: false, multiline: false),
        ),
      ),
    ));

    final TextField field = tester.widget(find.byType(TextField));
    expect(field.maxLines, 1,
        reason: 'opting out of the composer default keeps a single-line field');
  });
}
