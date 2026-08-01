// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get loading => 'Ładowanie…';

  @override
  String get appTitle => 'Towarzysz appbox';

  @override
  String counterLabel(int count) {
    return 'Licznik: $count';
  }

  @override
  String get homeDialogTitle => 'Stacked rządzi!';

  @override
  String homeDialogDescription(int count) {
    return 'Daj stacked $count gwiazdek na GitHubie';
  }

  @override
  String get homeBottomSheetTitle => 'Twórz świetne aplikacje!';

  @override
  String get homeBottomSheetDescription =>
      'Stacked powstał, by pomagać ci tworzyć lepsze aplikacje. Daj nam szansę, a ci to udowodnimy. Odwiedź stacked.filledstacks.com, aby dowiedzieć się więcej.';

  @override
  String get homeGreetingMobile => 'CZEŚĆ, MOBILNY UI!';

  @override
  String get homeGreetingTablet => 'CZEŚĆ, TABLETOWY UI!';

  @override
  String get homeGreetingDesktop => 'CZEŚĆ, DESKTOPOWY UI!';

  @override
  String get homeShowDialog => 'Pokaż dialog';

  @override
  String get homeShowBottomSheet => 'Pokaż dolny panel';

  @override
  String get dialogGotIt => 'Rozumiem';

  @override
  String get unknownPageNotFound => 'NIE ZNALEZIONO STRONY';

  @override
  String get servePrototypeTitle => 'Serwuj prototyp';

  @override
  String get servePrototypeInstructions =>
      'Wklej ładunek ready-line z desktopu (JSON, który serwer prototypu wypisuje, gdy zacznie nasłuchiwać) albo sam adres URL w sieci LAN, a następnie dotknij Serwuj. FAB pokazuje stan kanału — rozłączony po zakończeniu, podczas gdy WebView zachowuje ostatni render.';

  @override
  String get readyLineFieldLabel => 'JSON ready-line lub adres URL';

  @override
  String get notReadySignal =>
      'To nie jest sygnał prototype-ready — oczekiwano ładunku ready-line.';

  @override
  String get envBlockedNote =>
      'Parowanie QR (12.3), wykrywanie Bonjour (12.2) i sterowanie bramką na urządzeniu (12.6) wymagają podpisanej wersji iOS na prawdziwym sprzęcie — zablokowane w tym środowisku. Dowód heartbeatu i stanu kanału na FAB już nie; patrz zestaw testów.';

  @override
  String get serve => 'Serwuj';

  @override
  String get channelLive => 'na żywo';

  @override
  String get channelReconnecting => 'łączenie ponowne';

  @override
  String get channelDead => 'rozłączono';

  @override
  String get channelStop => 'Zatrzymaj';

  @override
  String get channelBack => 'Wstecz';

  @override
  String get languageLabel => 'Język';

  @override
  String get languageSystem => 'Systemowy';
}
