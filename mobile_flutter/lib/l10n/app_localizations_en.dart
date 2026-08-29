// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Arxa Studio';

  @override
  String get pairingScanTitle => 'Pair with Arxa Studio';

  @override
  String get pairingManualHint => 'Or paste a pairing ticket';

  @override
  String get connectingPairing => 'Pairing…';

  @override
  String get connectingConnecting => 'Connecting…';

  @override
  String get connectingConnected => 'Connected';

  @override
  String get connectingWaiting => 'Waiting…';

  @override
  String get connectingFailed => 'Could not connect to the studio.';

  @override
  String get tryAgain => 'Try again';

  @override
  String get pushTitle => 'Get approval requests as notifications';

  @override
  String get pushBody =>
      'Arxa Studio can notify you when a session needs your approval. You can change this later in Settings.';

  @override
  String get pushAllow => 'Allow notifications';

  @override
  String get pushSkip => 'Not now';

  @override
  String get studioNotConnected => 'Not connected — pair first.';

  @override
  String get settingsOpen => 'Settings';

  @override
  String get approvalsTitle => 'Approvals';

  @override
  String get approvalsEmpty => 'No pending approvals.';

  @override
  String get approvalsNotConnected =>
      'Not connected — pair with the studio to load approvals.';

  @override
  String get approvalsSend => 'Send answer';

  @override
  String get approvalsAnsweredElsewhere => 'Already answered elsewhere.';

  @override
  String get approvalsCustomHint => 'Type your answer';

  @override
  String get approvalsCustomOptionalHint => 'Add a note (optional)';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsUnpair => 'Unpair from studio';

  @override
  String get settingsUnpairSubtitle =>
      'Removes this device and stops notifications.';

  @override
  String get errorGeneric => 'Something went wrong loading this screen.';
}
