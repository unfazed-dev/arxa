// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get loading => 'Loading ...';

  @override
  String get appTitle => 'app_box companion';

  @override
  String counterLabel(int count) {
    return 'Counter is: $count';
  }

  @override
  String get homeDialogTitle => 'Stacked Rocks!';

  @override
  String homeDialogDescription(int count) {
    return 'Give stacked $count stars on Github';
  }

  @override
  String get homeBottomSheetTitle => 'Build Great Apps!';

  @override
  String get homeBottomSheetDescription =>
      'Stacked is built to help you build better apps. Give us a chance and we\'ll prove it to you. Check out stacked.filledstacks.com to learn more';

  @override
  String get homeGreetingMobile => 'Hello, MOBILE UI!';

  @override
  String get homeGreetingTablet => 'Hello, TABLET UI!';

  @override
  String get homeGreetingDesktop => 'Hello, DESKTOP UI!';

  @override
  String get homeShowDialog => 'Show Dialog';

  @override
  String get homeShowBottomSheet => 'Show Bottom Sheet';

  @override
  String get dialogGotIt => 'Got it';

  @override
  String get unknownPageNotFound => 'PAGE NOT FOUND';

  @override
  String get servePrototypeTitle => 'Serve a prototype';

  @override
  String get servePrototypeInstructions =>
      'Paste the desktop ready-line payload (the JSON the prototype server prints once it is listening) or a bare LAN URL, then tap Serve. The FAB carries the channel state — dead on kill, while the WebView keeps the last render.';

  @override
  String get readyLineFieldLabel => 'Ready-line JSON or URL';

  @override
  String get notReadySignal =>
      'Not the prototype-ready signal — expected the ready-line payload.';

  @override
  String get envBlockedNote =>
      'QR pairing (12.3), Bonjour discovery (12.2) and on-device gate control (12.6) need a signed iOS build on real hardware — env-blocked in this run. The heartbeat + FAB channel-state proof does not; see the test suite.';

  @override
  String get serve => 'Serve';

  @override
  String get channelLive => 'live';

  @override
  String get channelReconnecting => 'reconnecting';

  @override
  String get channelDead => 'dead';

  @override
  String get channelStop => 'Stop';

  @override
  String get channelBack => 'Back';

  @override
  String get languageLabel => 'Language';

  @override
  String get languageSystem => 'System';
}
