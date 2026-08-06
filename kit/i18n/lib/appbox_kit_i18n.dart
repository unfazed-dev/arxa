/// appbox_kit_i18n — locale machinery for appbox_kit apps.
///
/// [AppBoxKitI18n] resolves the effective locale from a persisted override, the
/// system locale, or English (in that order), extends `ChangeNotifier` so a
/// `MaterialApp` rebuilds live on [AppBoxKitI18n.setLocale], and formats
/// dates/numbers/currencies through `intl` in the current locale.
/// [AppBoxKitLocaleStore] is the persistence port ([SharedPreferencesAppBoxKitLocaleStore]
/// is the shipped default) and [AppBoxKitLanguage] the supported-language table.
/// Translation strings are deliberately NOT codegen'd here — the app owns its
/// gen-l10n `AppLocalizations`.
///
/// Test doubles live in `appbox_kit_i18n/appbox_kit_testing.dart`.
library;

export 'src/appbox_kit_language.dart';
export 'src/appbox_kit_locale_store.dart';
export 'src/appbox_kit_i18n.dart';
