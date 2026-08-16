// Widget tests for the components-gallery composer demo — the seeded fake
// thread, the attach sheet flow, the tap-to-toggle voice flow (real kit
// audio service, faked at the port), and the live thread (typing indicator +
// fake auto-reply). The keyboard-survives-action-tap regression itself is
// pinned at the kit level (appbox_kit_native_input_bar_test.dart); these pin
// the showcase wiring on top of it.
//
// Record UX is the tap-toggle voice idiom: the trailing action is a NATIVE
// kit icon button (real Liquid Glass circle on iOS 26) whose glyph animates
// mic → stop → mic through the SF Symbol replace transition as the recorder
// phase changes — the button is the state. TAP mic to start (the OS
// microphone-permission prompt fires through the kit on first start), TAP
// stop to stop and send; the strip's Cancel aborts; a stop under one second
// discards as a fumble. Recording runs on the kit audio service — the same
// one the notes shell uses.
//
// Same harness as showcase_components_view_test.dart: Android tier override
// (Material field + IconButtonM3E actions, no platform views) and a tall view
// so the whole demo list — including the conversation section at the end — is
// built and tappable.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_collection/m3e_collection.dart' show IconButtonM3E;
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_ui_library/appbox_kit_testing.dart';
import 'package:appbox_kit_media/appbox_kit_media.dart';
import 'package:appbox_kit_media/appbox_kit_testing.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_components/showcase_components_view.dart';

import 'helpers.dart';

void main() {
  setUpAll(registerKitTestServices);
  tearDownAll(() => appBoxKitLocator.reset());

  setUp(() {
    AppBoxKitPlatform.override =
        const AppBoxKitPlatformOverride(isAndroid: true);
  });
  tearDown(AppBoxKitPlatform.reset);

  // The recorder is faked at the kit port (behavior-TDD canon): the VM runs
  // the REAL permission/start/stop/cancel flow against it, only the plugin is
  // absent. Re-registered per test so scriptable state never leaks across.
  late FakeAppBoxKitAudioRecorderService recorder;
  late FakeAppBoxKitNotificationService notifications;

  setUp(() {
    recorder = FakeAppBoxKitAudioRecorderService();
    if (appBoxKitLocator.isRegistered<AppBoxKitAudioRecorderService>()) {
      appBoxKitLocator.unregister<AppBoxKitAudioRecorderService>();
    }
    appBoxKitLocator
        .registerSingleton<AppBoxKitAudioRecorderService>(recorder);

    // Kit testing rule: the notification fake registered AS the service type,
    // so the widget's permission-denied toast lands where the test reads it.
    if (appBoxKitLocator.isRegistered<AppBoxKitNotificationService>()) {
      appBoxKitLocator.unregister<AppBoxKitNotificationService>();
    }
    appBoxKitLocator.registerSingleton<AppBoxKitNotificationService>(
        notifications = FakeAppBoxKitNotificationService());
  });

  Future<void> pumpView(WidgetTester tester) async {
    // Tall surface so the whole demo list (conversation section included) is
    // built — the default 800x600 view leaves it below the lazy cache extent.
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: ShowcaseComponentsView()));
    await tester.pumpAndSettle();
  }

  // WHICH glyph the trailing record action carries (mic / stop) is the
  // phase — see the tap-toggle tests. (The button itself is keyed
  // composer-record-button for the on-device integration test.)
  final Finder micGlyph = find.widgetWithIcon(IconButtonM3E, Icons.mic);
  final Finder stopGlyph = find.widgetWithIcon(IconButtonM3E, Icons.stop);

  group('seeded thread', () {
    testWidgets(
        'showcase.components-composer — the seeded conversation renders on first frame',
        (tester) async {
      await pumpView(tester);

      expect(find.textContaining('seeded demo thread'), findsOneWidget,
          reason: 'seeded incoming text message renders');
      expect(find.text('site-photo.png'), findsOneWidget,
          reason: 'seeded attachment message renders');
      expect(find.textContaining('voice note'), findsOneWidget,
          reason: 'seeded voice message renders');
      expect(find.textContaining('reviewing now'), findsOneWidget,
          reason: 'seeded outgoing text message renders');
    });

    testWidgets(
        'showcase.components-composer — a text draft swaps mic for send, sends into the thread, and clears',
        (tester) async {
      await pumpView(tester);

      expect(micGlyph, findsOneWidget, reason: 'empty draft shows the mic action');
      await tester.enterText(find.byType(EditableText), 'Shipping the demo');
      await tester.pump();

      expect(find.widgetWithIcon(IconButtonM3E, Icons.send), findsOneWidget,
          reason: 'a non-empty draft swaps mic for send');

      await tester.tap(find.widgetWithIcon(IconButtonM3E, Icons.send));
      await tester.pumpAndSettle();

      expect(find.text('Shipping the demo'), findsOneWidget,
          reason: 'the sent draft lands in the thread');
      expect(micGlyph, findsOneWidget,
          reason: 'draft cleared after send — mic returns');
    });

    testWidgets(
        'showcase.components-composer — the attach sheet adds a fake pick chip that sends into the thread',
        (tester) async {
      await pumpView(tester);

      await tester.tap(find.widgetWithIcon(IconButtonM3E, Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('Photo library'), findsOneWidget,
          reason: 'the attach sheet presents its four options');
      await tester.tap(find.text('Photo library'));
      await tester.pumpAndSettle();

      expect(find.text('gallery-shot.png'), findsOneWidget,
          reason: 'the fake pick appears as a pending chip');
      // The CHIP is the opaque surface: content-layer standard material
      // (frosted tier, opaqueGlass default) — the Liquid Glass tier's
      // 0.45 tint reads translucent. The strip hosts NO base: opaque
      // chips float over the thread (messenger idiom) instead of merging
      // into a same-tint panel.
      final Finder chipCard = find.ancestor(
        of: find.text('gallery-shot.png'),
        matching: find.byType(AppBoxKitGlassCard),
      );
      expect(
        tester.widget<AppBoxKitGlassCard>(chipCard).wantNative,
        isFalse,
        reason: 'the chip renders the OPAQUE content-layer surface — '
            'real Liquid Glass is pinned chrome, and its tint stays '
            'translucent',
      );
      expect(
        tester.widget<AppBoxKitGlassCard>(chipCard).opaqueGlass,
        isTrue,
        reason: 'opaqueGlass is what makes the frosted tier a solid '
            'alpha-1.0 fill',
      );
      expect(
        find.descendant(
          of: find.byType(AppBoxKitNativeInputBar),
          matching: find.text('gallery-shot.png'),
        ),
        findsOneWidget,
        reason: 'the chips dock INSIDE the bar — the anchored pinned-chrome '
            'layer, where the view slicer holds the fill (no luminance '
            'artifacts while scrolling)',
      );
      expect(find.widgetWithIcon(IconButtonM3E, Icons.send), findsOneWidget,
          reason: 'a pending attachment counts as a draft');

      await tester.tap(find.widgetWithIcon(IconButtonM3E, Icons.send));
      await tester.pumpAndSettle();

      expect(find.text('gallery-shot.png'), findsOneWidget,
          reason: 'after send the chip is replaced by a thread bubble');
    });

    testWidgets(
        'showcase.components-composer — a chip\'s remove control is a plain (outline-less) button that discards the pick',
        (tester) async {
      await pumpView(tester);

      await tester.tap(find.widgetWithIcon(IconButtonM3E, Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose file'));
      await tester.pumpAndSettle();

      expect(find.text('handoff-spec.pdf'), findsOneWidget,
          reason: 'the fake file pick appears as a pending chip');

      // The remove control is the chromeless (plain) icon button — no glass
      // circle inside the chip. Tapping it removes the pick.
      final Finder removeButton = find.byWidgetPredicate(
          (w) => w is AppBoxKitNativeIconButton && w.plain);
      expect(removeButton, findsOneWidget,
          reason: 'the chip remove action is a plain icon button');
      expect(
        tester.widget<AppBoxKitNativeIconButton>(removeButton).glyph?.icon,
        AppBoxKitGlyphs.close.icon,
        reason: 'the plain action carries the close glyph',
      );

      await tester.tap(find.descendant(
          of: removeButton, matching: find.byType(IconButtonM3E)));
      await tester.pumpAndSettle();

      expect(find.text('handoff-spec.pdf'), findsNothing,
          reason: 'tapping the chip\'s plain remove button discards the pick');
      expect(micGlyph, findsOneWidget,
          reason: 'no pending picks — the draft is empty again');
    });
  });

  group('tap-to-toggle record (kit audio service)', () {
    testWidgets(
        'showcase.components-composer — tapping mic records through the kit service and the glyph swaps to stop; tapping stop sends',
        (tester) async {
      await pumpView(tester);

      await tester.tap(micGlyph);
      await tester.pumpAndSettle();

      expect(recorder.startedPaths, hasLength(1),
          reason: 'the tap started a REAL recording on the kit service');
      expect(stopGlyph, findsOneWidget,
          reason: 'while recording the trailing action carries the stop glyph');
      expect(find.text('0:00'), findsOneWidget,
          reason: 'the recording strip appears over the field');
      expect(find.text('Cancel'), findsOneWidget,
          reason: 'the strip offers an explicit cancel affordance');

      recorder.driveElapsed(const Duration(seconds: 2));
      // The driven tick crosses the recorder bridge (broadcast → subject)
      // before the frame paints it — two frames pin the painted result.
      await tester.pump();
      await tester.pump();
      expect(find.text('0:02'), findsOneWidget,
          reason: 'the strip timer follows the recorder elapsed stream');

      await tester.tap(stopGlyph);
      await tester.pumpAndSettle();

      expect(find.textContaining('0:02 · voice note'), findsOneWidget,
          reason: 'tapping stop commits the recording into the thread');
      expect(micGlyph, findsOneWidget,
          reason: 'the glyph animates back to the idle mic');
      expect(recorder.isRecording, isFalse,
          reason: 'the recorder stopped with the note');
    });

    testWidgets(
        'showcase.components-composer — a stop under one second discards the fumble: no note, idle again',
        (tester) async {
      await pumpView(tester);

      await tester.tap(micGlyph);
      await tester.pumpAndSettle();
      await tester.tap(stopGlyph);
      await tester.pumpAndSettle();

      expect(find.textContaining('· voice note'), findsOneWidget,
          reason: 'only the seeded voice bubble remains — the fumble sent nothing');
      expect(recorder.isRecording, isFalse,
          reason: 'the too-short recording was discarded, not left running');
      expect(micGlyph, findsOneWidget,
          reason: 'the composer idles again after the discard');
      expect(find.text('Cancel'), findsNothing,
          reason: 'the strip is gone once idle');
    });

    testWidgets(
        'showcase.components-composer — the strip cancel aborts: nothing is sent, recorder stopped',
        (tester) async {
      await pumpView(tester);

      await tester.tap(micGlyph);
      await tester.pumpAndSettle();
      recorder.driveElapsed(const Duration(seconds: 2));
      await tester.pump();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.textContaining('· voice note'), findsOneWidget,
          reason: 'the cancel discarded the recording — seed only');
      expect(recorder.isRecording, isFalse,
          reason: 'cancel stopped the recorder');
      expect(micGlyph, findsOneWidget,
          reason: 'cancel returns the composer to the idle mic');
    });

    testWidgets(
        'showcase.components-composer — denied microphone permission warns and never starts the recorder',
        (tester) async {
      recorder.permission = false;
      await pumpView(tester);

      await tester.tap(micGlyph);
      await tester.pumpAndSettle();

      expect(recorder.startedPaths, isEmpty,
          reason: 'permission was requested through the kit and denied');
      expect(
        notifications.messages,
        contains('Microphone permission needed'),
        reason: 'the denial surfaces as the kit warning toast',
      );
      expect(find.textContaining('· voice note'), findsOneWidget,
          reason: 'nothing was recorded or sent');
      expect(micGlyph, findsOneWidget,
          reason: 'the button returns to the enabled idle mic');
    });

    testWidgets(
        'showcase.components-composer — the strip level dot breathes with the recorder amplitude',
        (tester) async {
      await pumpView(tester);

      await tester.tap(micGlyph);
      await tester.pumpAndSettle();

      final dot = find.byKey(const ValueKey('composer-level-dot'));
      expect(dot, findsOneWidget, reason: 'the strip shows a level dot');
      final double quiet =
          (tester.firstWidget<Container>(dot).constraints!.maxWidth);

      recorder.driveAmplitude(-3); // loud input
      await tester.pump();
      await tester.pump();
      final double loud =
          (tester.firstWidget<Container>(dot).constraints!.maxWidth);

      expect(loud, greaterThan(quiet),
          reason: 'the dot grows with the live amplitude stream');
      // Clean up through the real affordance: cancel discards the note.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('live thread', () {
    testWidgets(
        'showcase.components-composer — sending a draft shows the contact typing, then a live reply lands',
        (tester) async {
      await pumpView(tester);

      await tester.enterText(find.byType(EditableText), 'Hello there');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButtonM3E, Icons.send));
      await tester.pump();

      expect(find.text('typing…'), findsOneWidget,
          reason: 'the contact starts typing right after the send');
      expect(find.textContaining('On it'), findsNothing,
          reason: 'the reply has not landed yet');

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.textContaining('On it'), findsOneWidget,
          reason: 'the fake auto-reply lands in the thread');
      expect(find.text('typing…'), findsNothing,
          reason: 'the typing indicator clears once the reply lands');
      expect(find.text('Hello there'), findsOneWidget,
          reason: 'the user message is still there');
    });

    testWidgets(
        'showcase.components-composer — sending a voice note gets a reply that acknowledges the audio',
        (tester) async {
      await pumpView(tester);

      await tester.tap(micGlyph);
      await tester.pumpAndSettle();
      recorder.driveElapsed(const Duration(seconds: 2));
      await tester.pump();
      await tester.tap(stopGlyph);
      await tester.pump();

      expect(find.text('typing…'), findsOneWidget,
          reason: 'the voice send also triggers the live reply');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.textContaining('Voice note received'), findsOneWidget,
          reason: 'the reply acknowledges the audio by kind');
    });

    testWidgets(
        'showcase.components-composer — a landed reply scrolls the newest bubble into view',
        (tester) async {
      // Default-size surface on purpose: the conversation section starts
      // below the fold, so only the auto-scroll can bring the newest bubble
      // on-screen (hitTestable).
      await tester
          .pumpWidget(const MaterialApp(home: ShowcaseComponentsView()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(EditableText), 'Scroll check');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButtonM3E, Icons.send));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.textContaining('Scroll check').hitTestable(), findsOneWidget,
          reason: 'the sent bubble is scrolled into view');
      expect(find.textContaining('On it').hitTestable(), findsOneWidget,
          reason: 'the auto-reply is scrolled into view too');
    });
  });
}
