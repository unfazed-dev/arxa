import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Arxa Studio'**
  String get appTitle;

  /// No description provided for @pairingScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Pair with Arxa Studio'**
  String get pairingScanTitle;

  /// No description provided for @pairingManualHint.
  ///
  /// In en, this message translates to:
  /// **'Or paste a pairing ticket'**
  String get pairingManualHint;

  /// No description provided for @connectingPairing.
  ///
  /// In en, this message translates to:
  /// **'Pairing…'**
  String get connectingPairing;

  /// No description provided for @connectingConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connectingConnecting;

  /// No description provided for @connectingConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connectingConnected;

  /// No description provided for @connectingWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting…'**
  String get connectingWaiting;

  /// No description provided for @connectingFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the studio.'**
  String get connectingFailed;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @pushTitle.
  ///
  /// In en, this message translates to:
  /// **'Get approval requests as notifications'**
  String get pushTitle;

  /// No description provided for @pushBody.
  ///
  /// In en, this message translates to:
  /// **'Arxa Studio can notify you when a session needs your approval. You can change this later in Settings.'**
  String get pushBody;

  /// No description provided for @pushAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow notifications'**
  String get pushAllow;

  /// No description provided for @pushSkip.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get pushSkip;

  /// No description provided for @studioNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected — pair first.'**
  String get studioNotConnected;

  /// No description provided for @settingsOpen.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsOpen;

  /// No description provided for @approvalsTitle.
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get approvalsTitle;

  /// No description provided for @approvalsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No pending approvals.'**
  String get approvalsEmpty;

  /// No description provided for @approvalsNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected — pair with the studio to load approvals.'**
  String get approvalsNotConnected;

  /// No description provided for @approvalsPairCta.
  ///
  /// In en, this message translates to:
  /// **'Scan to pair'**
  String get approvalsPairCta;

  /// No description provided for @approvalsOpenStudio.
  ///
  /// In en, this message translates to:
  /// **'Open studio'**
  String get approvalsOpenStudio;

  /// No description provided for @approvalsSend.
  ///
  /// In en, this message translates to:
  /// **'Send answer'**
  String get approvalsSend;

  /// No description provided for @approvalsAnsweredElsewhere.
  ///
  /// In en, this message translates to:
  /// **'Already answered elsewhere.'**
  String get approvalsAnsweredElsewhere;

  /// No description provided for @approvalsCustomHint.
  ///
  /// In en, this message translates to:
  /// **'Type your answer'**
  String get approvalsCustomHint;

  /// No description provided for @approvalsCustomOptionalHint.
  ///
  /// In en, this message translates to:
  /// **'Add a note (optional)'**
  String get approvalsCustomOptionalHint;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsUnpair.
  ///
  /// In en, this message translates to:
  /// **'Unpair from studio'**
  String get settingsUnpair;

  /// No description provided for @settingsUnpairSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Removes this device and stops notifications.'**
  String get settingsUnpairSubtitle;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong loading this screen.'**
  String get errorGeneric;

  /// No description provided for @codeSessionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Code sessions'**
  String get codeSessionsTitle;

  /// No description provided for @codeSessionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No code sessions yet.'**
  String get codeSessionsEmpty;

  /// No description provided for @codeSessionsNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected — pair with the studio to load sessions.'**
  String get codeSessionsNotConnected;

  /// No description provided for @codeSessionsPairCta.
  ///
  /// In en, this message translates to:
  /// **'Scan to pair'**
  String get codeSessionsPairCta;

  /// No description provided for @codeFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get codeFilterAll;

  /// No description provided for @codeFilterBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get codeFilterBlocked;

  /// No description provided for @codeFilterInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get codeFilterInProgress;

  /// No description provided for @codeFilterDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get codeFilterDone;

  /// No description provided for @codeConversationTitle.
  ///
  /// In en, this message translates to:
  /// **'Conversation'**
  String get codeConversationTitle;

  /// No description provided for @codeConversationEmpty.
  ///
  /// In en, this message translates to:
  /// **'No messages yet.'**
  String get codeConversationEmpty;

  /// No description provided for @codeConversationOffline.
  ///
  /// In en, this message translates to:
  /// **'Not connected — messages can\'t reach the studio.'**
  String get codeConversationOffline;

  /// No description provided for @codeComposerHint.
  ///
  /// In en, this message translates to:
  /// **'Add feedback...'**
  String get codeComposerHint;

  /// No description provided for @codeSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get codeSend;

  /// No description provided for @codeJustNow.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get codeJustNow;

  /// No description provided for @codeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}m ago'**
  String codeMinutesAgo(int n);

  /// No description provided for @codeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}h ago'**
  String codeHoursAgo(int n);

  /// No description provided for @codeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}d ago'**
  String codeDaysAgo(int n);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
