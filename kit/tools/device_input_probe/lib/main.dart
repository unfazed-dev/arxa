// Device-verification probe for the AppBoxKit native input composer
// (AppBoxKitNativeInputBar) and native text field (AppBoxKitNativeTextField).
//
// WHY THIS APP EXISTS (measured 2026-08): the `integration_test` harness does
// NOT deliver real touches to platform views — synthetic tester pointers never
// become UITouches, and idb HID taps are dropped there too — while the same
// code in a plain app works. Real-touch verification therefore runs THIS app
// on a booted iOS simulator / Android emulator while a host choreography
// script drives taps, IME typing, long-presses, drags and screenshots:
//
//   ios_choreo.sh UDID [BUNDLE]   — simctl screenshots + idb taps (POINTS)
//   android_choreo.sh [SERIAL]    — adb input taps (PIXELS) + screencap
//
// Protocol: per phase N the app writes <tmp>/phase<N>.done whose payload says
// what the host should do (e.g. tap coords), then blocks until the host
// writes <tmp>/phase<N>.go, then measures. iOS hosts exchange files through
// the simulator app container; Android hosts use adb shell run-as. All
// measurements land in <tmp>/composer.log and debugPrint (tag COMPOSER),
// which Android hosts can also follow via adb logcat -s flutter.
// Tap payloads are emitted in the HOST coordinate unit: points on iOS,
// pixels on Android (logical * devicePixelRatio).
import 'dart:io';

import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ProbeApp());

class ProbeApp extends StatelessWidget {
  const ProbeApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ProbeScreen(),
      );
}

class ProbeScreen extends StatefulWidget {
  const ProbeScreen({super.key});

  @override
  State<ProbeScreen> createState() => _ProbeScreenState();
}

class _ProbeScreenState extends State<ProbeScreen> {
  static const _longText =
      'one two three four five six seven eight nine ten eleven twelve thirteen '
      'fourteen fifteen sixteen seventeen eighteen nineteen twenty twenty-one '
      'twenty-two twenty-three twenty-four twenty-five twenty-six twenty-seven '
      'twenty-eight twenty-nine thirty thirty-one thirty-two';

  final controller = TextEditingController();
  final controller2 = TextEditingController();
  final _fieldKey = GlobalKey();
  final _field2Key = GlobalKey();
  final _addKey = GlobalKey();
  double _rest = 0;
  String _phase = 'boot';
  bool _pairVisible = false;

  String get _tmp => Directory.systemTemp.path;

  void _log(String line) {
    File('$_tmp/composer.log')
        .writeAsStringSync('$line\n', mode: FileMode.append);
    debugPrint('COMPOSER $line');
  }

  // Focus truth, per tier. The iOS native tier owns first responder inside the
  // platform view — only CNTextFieldFocus sees it. The Material/M3E tier is a
  // Flutter TextField — focus lives in the focus tree, and render-tree
  // containment tells us WHICH field holds it (needed once two fields coexist).
  bool get _composerFocused =>
      CNTextFieldFocus.hasFocus || _focusInside(_fieldKey);

  bool _focusInside(GlobalKey key) {
    final primary = FocusManager.instance.primaryFocus;
    final scope = key.currentContext?.findRenderObject();
    final probe = primary?.context?.findRenderObject();
    if (primary == null || scope == null || probe == null) return false;
    RenderObject? cur = probe;
    while (cur != null) {
      if (cur == scope) return true;
      cur = cur.parent;
    }
    return false;
  }

  double? _heightOf(GlobalKey key) {
    final ro = key.currentContext?.findRenderObject();
    return ro is RenderBox ? ro.size.height : null;
  }

  /// Height MINUS the keyboard-riding lift. The bar pads itself up by
  /// viewInsets.bottom when focused, so the raw Builder height is swamped by
  /// the keyboard (measured: 397 = 335 lift + 62 content) and a growth poll on
  /// the raw value passes/fails for the wrong reason. Growth claims must ride
  /// on THIS number (screenshots stay the visual ground truth).
  double _contentHeight() {
    final raw = _heightOf(_fieldKey) ?? 0;
    final lift = mounted ? MediaQuery.viewInsetsOf(context).bottom : 0.0;
    return (raw - lift).clamp(0, double.infinity);
  }

  /// Center of the FREE area above the keyboard — the only outside-tap target
  /// guaranteed not to land on the keyboard/quicktype bar (an OS surface that
  /// legitimately keeps focus; a tap there is NOT a dismissal regression).
  Offset _freeAreaCenter(Offset fallback) {
    if (!mounted) return fallback;
    final size = MediaQuery.sizeOf(context);
    final lift = MediaQuery.viewInsetsOf(context).bottom;
    final free = (size.height - lift).clamp(0, size.height);
    return Offset(size.width / 2, free / 2);
  }

  Offset? _centerOf(GlobalKey key) {
    final ro = key.currentContext?.findRenderObject();
    if (ro is! RenderBox) return null;
    return ro.localToGlobal(ro.size.center(Offset.zero));
  }

  /// Host-tap coordinate string in the host unit (iOS points, Android px).
  String _tap(Offset c) {
    final scale =
        Platform.isAndroid ? MediaQuery.devicePixelRatioOf(context) : 1.0;
    return 'tap:${(c.dx * scale).round()},${(c.dy * scale).round()}';
  }

  @override
  void initState() {
    super.initState();
    CNTextFieldFocus; // keep the native focus tracker referenced on iOS
    WidgetsBinding.instance.addPostFrameCallback((_) => _runPhases());
  }

  Future<void> _runPhases() async {
    await _frame();
    setState(() => _phase = 'P1');
    _rest = _contentHeight();
    _log('P1 rest contentHeight=$_rest');
    await _host('1', 'ok');

    setState(() => _phase = 'P2');
    final c = _centerOf(_fieldKey) ?? const Offset(201, 809);
    await _host('2', _tap(c));
    // Poll instead of sampling once: the first read used to race the focus
    // notification and log a false focused=false (Gate-5 P2 timing artifact).
    await _waitFor(() => _composerFocused, const Duration(seconds: 2));
    final insets = mounted ? MediaQuery.viewInsetsOf(context).bottom : 0.0;
    _log('P2 focused=$_composerFocused cn=${CNTextFieldFocus.hasFocus} '
        'flutter=${_focusInside(_fieldKey)} insets=${insets.toStringAsFixed(1)} '
        'contentHeight=${_contentHeight().toStringAsFixed(1)} '
        'firstFocusShrink=${_contentHeight() < _rest - 1}');

    setState(() => _phase = 'P3');
    await _host('3', _tap(_centerOf(_fieldKey) ?? c));
    _log('P3 retap stillFocused=$_composerFocused');

    setState(() => _phase = 'P4');
    await _host('4', _tap(_freeAreaCenter(c)));
    _log('P4 outsideTap dismissed=${!_composerFocused}');

    setState(() => _phase = 'P5');
    // Fresh coords: the bar dropped back to rest after P4 dismissed.
    await _host('5', _tap(_centerOf(_fieldKey) ?? c));
    await _waitFor(() => _composerFocused, const Duration(seconds: 2));
    _log('P5 refocused=$_composerFocused');
    // P5b (Android): the host types through the real IME during this window;
    // the iOS host has no reliable text injection, so it logs a skip.
    final typed = await _waitFor(
        () => controller.text.isNotEmpty, const Duration(seconds: 10));
    _log('P5b imeTyped=$typed text="${controller.text}"');

    setState(() => _phase = 'P6');
    controller.text = _longText;
    await _pollHeight((h2) => h2 > _rest + 30,
        onDone: (h2) => _log(
            'P6 grown contentHeight=${h2.toStringAsFixed(1)} rest=$_rest '
            'insets=${(mounted ? MediaQuery.viewInsetsOf(context).bottom : 0).toStringAsFixed(1)}'));
    await _host('6', 'ok');

    setState(() => _phase = 'P7');
    controller.text = '';
    await _pollHeight((h2) => h2 <= _rest + 6,
        onDone: (h2) => _log(
            'P7 shrunk contentHeight=${h2.toStringAsFixed(1)} rest=$_rest'));
    await _host('7', 'ok');

    setState(() => _phase = 'P8');
    controller.text = 'hello composer';
    await _frame();
    // Fresh coords again: long-press must hit the resting bar.
    final tapStr = _tap(_centerOf(_fieldKey) ?? c);
    await _host('8', 'long:${tapStr.split(':').last}');
    _log('P8 longPress done');

    setState(() => _phase = 'P9');
    await _host('9', 'drag');
    _log('P9 dragDismissed=${!_composerFocused}');

    // P10 (glass pair): a SECOND native input appears above the composer; the
    // host taps it. On iOS two native glass surfaces render simultaneously
    // (seam/ghosting evidence for the GlassEffectContainer limitation) and the
    // screenshot caret shows focus moved; on Android per-field focus is read
    // directly from the focus tree.
    setState(() {
      _phase = 'P10';
      _pairVisible = true;
    });
    await _frame();
    await _frame();
    final c2 = _centerOf(_field2Key);
    await _host('10', c2 == null ? 'ok' : _tap(c2));
    _log('P10 pairShown cn=${CNTextFieldFocus.hasFocus} '
        'composerFlutter=${_focusInside(_fieldKey)} '
        'field2Flutter=${_focusInside(_field2Key)} '
        'restHeight=$_rest pairHeight=${_heightOf(_field2Key)}');

    // P11 (action-tap regression, 2026-08-16): refocus the composer (11a),
    // then tap the bar's leading add action (11b) — focus must SURVIVE the
    // tap (the bar's actions join the input tap group; pre-fix the tap
    // classified as outside and dismissed).
    final cRest = _centerOf(_fieldKey) ?? c;
    await _host('11a', _tap(cRest));
    await _waitFor(() => _composerFocused, const Duration(seconds: 2));
    _log('P11a refocused=$_composerFocused');
    final addCenter = _centerOf(_addKey);
    await _host('11b', addCenter == null ? 'ok' : _tap(addCenter));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _log('P11b addTapKeptFocus=$_composerFocused '
        'cn=${CNTextFieldFocus.hasFocus}');
    _log('END');
  }

  Future<void> _frame() => Future.delayed(const Duration(milliseconds: 120));

  Future<bool> _waitFor(bool Function() test, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (!test()) {
      if (DateTime.now().isAfter(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return true;
  }

  Future<void> _pollHeight(bool Function(double) test,
      {required void Function(double) onDone,
      Duration timeout = const Duration(seconds: 12)}) async {
    final deadline = DateTime.now().add(timeout);
    double h = _contentHeight();
    while (!test(h) && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      h = _contentHeight();
    }
    onDone(h);
  }

  Future<void> _host(String phase, String payload) async {
    File('$_tmp/phase$phase.done').writeAsStringSync(payload);
    setState(() {});
    final go = File('$_tmp/phase$phase.go');
    final deadline = DateTime.now().add(const Duration(seconds: 240));
    while (!await go.exists()) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (DateTime.now().isAfter(deadline)) return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF112233),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: GestureDetector(
                  key: const Key('outside'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: const SizedBox.expand(),
                ),
              ),
              if (_pairVisible)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: AppBoxKitNativeTextField(
                    key: _field2Key,
                    controller: controller2,
                    hintText: 'Second native field',
                  ),
                ),
              Builder(
                key: _fieldKey,
                builder: (_) => AppBoxKitNativeInputBar(
                  controller: controller,
                  hintText: 'Message',
                  // P11's real target: a bar action whose tap must NOT dismiss.
                  leading: [
                    AppBoxKitNativeIconButton(
                      key: _addKey,
                      glyph: AppBoxKitGlyphs.add,
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: 12,
            top: 8,
            child: Text(
              ' $_phase ',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
