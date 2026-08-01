import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pl.dart';

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
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pl'),
  ];

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading ...'**
  String get loading;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'appbox companion'**
  String get appTitle;

  /// No description provided for @counterLabel.
  ///
  /// In en, this message translates to:
  /// **'Counter is: {count}'**
  String counterLabel(int count);

  /// No description provided for @homeDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Stacked Rocks!'**
  String get homeDialogTitle;

  /// No description provided for @homeDialogDescription.
  ///
  /// In en, this message translates to:
  /// **'Give stacked {count} stars on Github'**
  String homeDialogDescription(int count);

  /// No description provided for @homeBottomSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Build Great Apps!'**
  String get homeBottomSheetTitle;

  /// No description provided for @homeBottomSheetDescription.
  ///
  /// In en, this message translates to:
  /// **'Stacked is built to help you build better apps. Give us a chance and we\'ll prove it to you. Check out stacked.filledstacks.com to learn more'**
  String get homeBottomSheetDescription;

  /// No description provided for @homeGreetingMobile.
  ///
  /// In en, this message translates to:
  /// **'Hello, MOBILE UI!'**
  String get homeGreetingMobile;

  /// No description provided for @homeGreetingTablet.
  ///
  /// In en, this message translates to:
  /// **'Hello, TABLET UI!'**
  String get homeGreetingTablet;

  /// No description provided for @homeGreetingDesktop.
  ///
  /// In en, this message translates to:
  /// **'Hello, DESKTOP UI!'**
  String get homeGreetingDesktop;

  /// No description provided for @homeShowDialog.
  ///
  /// In en, this message translates to:
  /// **'Show Dialog'**
  String get homeShowDialog;

  /// No description provided for @homeShowBottomSheet.
  ///
  /// In en, this message translates to:
  /// **'Show Bottom Sheet'**
  String get homeShowBottomSheet;

  /// No description provided for @dialogGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get dialogGotIt;

  /// No description provided for @unknownPageNotFound.
  ///
  /// In en, this message translates to:
  /// **'PAGE NOT FOUND'**
  String get unknownPageNotFound;

  /// No description provided for @servePrototypeTitle.
  ///
  /// In en, this message translates to:
  /// **'Serve a prototype'**
  String get servePrototypeTitle;

  /// No description provided for @servePrototypeInstructions.
  ///
  /// In en, this message translates to:
  /// **'Paste the desktop ready-line payload (the JSON the prototype server prints once it is listening) or a bare LAN URL, then tap Serve. The FAB carries the channel state — dead on kill, while the WebView keeps the last render.'**
  String get servePrototypeInstructions;

  /// No description provided for @readyLineFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Ready-line JSON or URL'**
  String get readyLineFieldLabel;

  /// No description provided for @notReadySignal.
  ///
  /// In en, this message translates to:
  /// **'Not the prototype-ready signal — expected the ready-line payload.'**
  String get notReadySignal;

  /// No description provided for @envBlockedNote.
  ///
  /// In en, this message translates to:
  /// **'QR pairing (12.3), Bonjour discovery (12.2) and on-device gate control (12.6) need a signed iOS build on real hardware — env-blocked in this run. The heartbeat + FAB channel-state proof does not; see the test suite.'**
  String get envBlockedNote;

  /// No description provided for @serve.
  ///
  /// In en, this message translates to:
  /// **'Serve'**
  String get serve;

  /// No description provided for @channelLive.
  ///
  /// In en, this message translates to:
  /// **'live'**
  String get channelLive;

  /// No description provided for @channelReconnecting.
  ///
  /// In en, this message translates to:
  /// **'reconnecting'**
  String get channelReconnecting;

  /// No description provided for @channelDead.
  ///
  /// In en, this message translates to:
  /// **'dead'**
  String get channelDead;

  /// No description provided for @channelStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get channelStop;

  /// No description provided for @channelBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get channelBack;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;
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
      <String>['en', 'pl'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pl':
      return AppLocalizationsPl();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
