// Device-only verification of the native input composer — the gaps widget
// tests cannot reach: the CNTextField platform view (UiKitView cannot mount
// headless) on iOS and the TextFieldM3E tier with real touch on Android.
//
// Protocol: the test advances in numbered phases, writing 'phase<N>.done' into
// the app's tmp dir at each boundary, then waits for the host to drop
// 'phase<N>.go' (the host screenshots the device between the two). All
// measurements append to 'composer.log'. Run:
//   flutter test integration_test/input_composer_device_test.dart -d <device>
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ArxaKitNativeInputBar, ArxaKitNativeTextField, CNTextFieldFocus;

Future<void> _markDone(int n) async => _mark(n, 'ok');

Future<void> _mark(int n, String payload) async {
  await File('${Directory.systemTemp.path}/phase$n.done')
      .writeAsString(payload);
}

Future<void> _awaitGo(int n) async {
  final go = File('${Directory.systemTemp.path}/phase$n.go');
  final deadline = DateTime.now().add(const Duration(seconds: 120));
  while (!await go.exists()) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (DateTime.now().isAfter(deadline)) return;
  }
}

void _log(String line) {
  File('${Directory.systemTemp.path}/composer.log').writeAsStringSync(
    '$line\n',
    mode: FileMode.append,
  );
  // ignore: avoid_print
  print('COMPOSER $line');
}

Future<bool> _poll(Future<bool> Function() check,
    {Duration timeout = const Duration(seconds: 12)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await check()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
  return await check();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final controller = TextEditingController();
  final bool isIOS = Platform.isIOS;

  late WidgetTester tester0;
  RenderBox fieldBox() =>
      tester0.renderObject(find.byType(ArxaKitNativeTextField)) as RenderBox;
  Future<double> fieldHeight() async => fieldBox().size.height;
  Future<Offset> fieldCenter() async =>
      fieldBox().localToGlobal(fieldBox().size.center(Offset.zero));
  Future<bool> nativeFocused() async => isIOS
      ? CNTextFieldFocus.hasFocus
      : FocusManager.instance.primaryFocus?.hasFocus ?? false;

  testWidgets('native input composer — device gap verification', (tester) async {
    tester0 = tester;
    _log('START isIOS=$isIOS');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Column(
          children: [
            const Expanded(child: SizedBox(key: Key('outside'))),
            ArxaKitNativeInputBar(
              controller: controller,
              hintText: 'Message',
            ),
          ],
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));
    final double rest = await fieldHeight();
    _log('P1 rest height=$rest');
    await _markDone(1);
    await _awaitGo(1);

    // P2 focus — REAL touch (synthetic pointers never become UITouches, so
    // they cannot drive the engine's platform-view forwarding). The test
    // writes 'tap:<x>,<y>' device px into the marker; the host injects via
    // `idb ui tap`, screenshots, then releases the gate.
    // idb's accessibility tree (and its tap coordinates) are in POINTS —
    // describe-all reports 402x874 on this device — so forward logical
    // coordinates unconverted. Device px landed off-screen and focused nothing.
    String pt(Offset logical) =>
        '${logical.dx.round()},${logical.dy.round()}';
    final Offset fieldC = await fieldCenter();
    _log('P2 tap target pt=${pt(fieldC)}');
    await _mark(2, 'tap:${pt(fieldC)}');
    await _awaitGo(2);
    final bool focused = await _poll(nativeFocused);
    final double viewInsets = WidgetsBinding
        .instance.platformDispatcher.views.first.viewInsets.bottom;
    _log('P2 focused=$focused viewInsetsPx=$viewInsets');
    expect(focused, isTrue, reason: 'a real tap on the native field must focus it');
    final double afterFocus = await fieldHeight();
    _log(
        'P2 heightAfterFocus=$afterFocus rest=$rest firstFocusShrink=${afterFocus < rest - 1}');

    // P3 re-tap regression (real touch, same coordinates).
    await _mark(3, 'tap:${pt(await fieldCenter())}');
    await _awaitGo(3);
    final bool stillFocused = await _poll(nativeFocused);
    _log('P3 retap stillFocused=$stillFocused');
    expect(stillFocused, isTrue,
        reason: 're-tapping the focused native field must NOT dismiss');

    // P4 dismiss by outside tap.
    final Offset outside = tester.getCenter(find.byKey(const Key('outside')));
    await tester.tapAt(Offset(outside.dx, outside.dy - 40));
    await tester.pump(const Duration(milliseconds: 600));
    final bool dismissed = await _poll(() async => !(await nativeFocused()));
    _log('P4 outsideTap dismissed=$dismissed');
    expect(dismissed, isTrue,
        reason: 'tap outside must dismiss the native keyboard');
    await _markDone(4);
    await _awaitGo(4);

    // P5 refocus (real touch).
    await _mark(5, 'tap:${pt(await fieldCenter())}');
    await _awaitGo(5);
    final bool refocused = await _poll(nativeFocused);
    _log('P5 refocused=$refocused');
    expect(refocused, isTrue, reason: 'refocus after dismissal must work');

    // P6 growth.
    const String longText =
        'one two three four five six seven eight nine ten eleven twelve thirteen '
        'fourteen fifteen sixteen seventeen eighteen nineteen twenty twenty-one '
        'twenty-two twenty-three twenty-four twenty-five twenty-six twenty-seven '
        'twenty-eight twenty-nine thirty thirty-one thirty-two';
    if (isIOS) {
      controller.text = longText;
    } else {
      await tester.enterText(find.byType(TextField), longText);
    }
    await tester.pump(const Duration(milliseconds: 300));
    final bool grown = await _poll(() async => await fieldHeight() > rest + 30);
    final double grownHeight = await fieldHeight();
    _log('P6 grown=$grown height=$grownHeight rest=$rest');
    expect(grown, isTrue,
        reason: 'multiline text must grow the composer (heightChanged lockstep)');
    await _markDone(6);
    await _awaitGo(6);

    // P7 shrink.
    if (isIOS) {
      controller.text = '';
    } else {
      await tester.enterText(find.byType(TextField), '');
    }
    await tester.pump(const Duration(milliseconds: 400));
    final bool shrunk = await _poll(() async => await fieldHeight() <= rest + 6);
    final double shrunkHeight = await fieldHeight();
    _log('P7 shrunk=$shrunk height=$shrunkHeight');
    expect(shrunk, isTrue, reason: 'clearing text must shrink the composer back');
    await _markDone(7);
    await _awaitGo(7);

    // P8 selection menu over glass: text + focus + REAL long-press (the
    // native edit menu only rises for a real touch).
    if (isIOS) {
      controller.text = 'hello composer';
    } else {
      await tester.enterText(find.byType(TextField), 'hello composer');
    }
    await tester.pump(const Duration(milliseconds: 300));
    await _mark(8, 'long:${pt(await fieldCenter())}');
    await _awaitGo(8);
    _log('P8 longPress done (menu captured in p8 screenshot)');

    // P9 drag-dismiss.
    final Offset o = tester.getCenter(find.byKey(const Key('outside')));
    final TestGesture g2 = await tester.startGesture(Offset(o.dx, o.dy - 60));
    await g2.moveBy(const Offset(0, -180));
    await tester.pump(const Duration(milliseconds: 250));
    await g2.up();
    await tester.pump(const Duration(milliseconds: 600));
    final bool dragDismissed = await _poll(() async => !(await nativeFocused()));
    _log('P9 dragDismissed=$dragDismissed');
    expect(dragDismissed, isTrue,
        reason: 'a drag outside the field must dismiss the keyboard');
    await _markDone(9);
    _log('END');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
