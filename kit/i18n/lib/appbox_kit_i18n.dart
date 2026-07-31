/// appbox_kit_i18n — locale machinery for appbox_kit apps.
///
/// [KitI18n] resolves the effective locale from a persisted override, the
/// system locale, or English (in that order), extends `ChangeNotifier` so a
/// `MaterialApp` rebuilds live on [KitI18n.setLocale], and formats
/// dates/numbers/currencies through `intl` in the current locale.
/// [KitLocaleStore] is the persistence port ([SharedPreferencesKitLocaleStore]
/// is the shipped default) and [KitLanguage] the supported-language table.
/// Translation strings are deliberately NOT codegen'd here — the app owns its
/// gen-l10n `AppLocalizations`.
///
/// Test doubles live in `appbox_kit_i18n/testing.dart`.
library;

export 'src/kit_language.dart';
export 'src/kit_locale_store.dart';
export 'src/kit_i18n.dart';
