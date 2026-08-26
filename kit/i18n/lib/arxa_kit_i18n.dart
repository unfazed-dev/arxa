/// arxa_kit_i18n — locale machinery for arxa_kit apps.
///
/// [ArxaKitI18n] resolves the effective locale from a persisted override, the
/// system locale, or English (in that order), extends `ChangeNotifier` so a
/// `MaterialApp` rebuilds live on [ArxaKitI18n.setLocale], and formats
/// dates/numbers/currencies through `intl` in the current locale.
/// [ArxaKitLocaleStore] is the persistence port ([SharedPreferencesArxaKitLocaleStore]
/// is the shipped default) and [ArxaKitLanguage] the supported-language table.
/// Translation strings are deliberately NOT codegen'd here — the app owns its
/// gen-l10n `AppLocalizations`.
///
/// Test doubles live in `arxa_kit_i18n/arxa_kit_testing.dart`.
library;

export 'src/arxa_kit_language.dart';
export 'src/arxa_kit_locale_store.dart';
export 'src/arxa_kit_i18n.dart';
