import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'appbox_kit_language.dart';
import 'appbox_kit_locale_store.dart';

/// Locale resolution, live switching, and locale-aware formatting.
///
/// Resolution order: persisted override → [systemLocale] → English.
/// Extends [ChangeNotifier] so a `MaterialApp` listening to it rebuilds live
/// when [setLocale] / [clearOverride] run.
class AppBoxKitI18n extends ChangeNotifier {
  AppBoxKitI18n({required AppBoxKitLocaleStore store, Locale? systemLocale})
    : _store = store,
      _systemLocale = systemLocale;

  final AppBoxKitLocaleStore _store;
  final Locale? _systemLocale;

  String? _override;
  List<String> _doNotTranslate = const [];

  static final RegExp _placeholderPattern = RegExp(r'\{([^{}]*)\}');

  /// Read the persisted override into memory. Call once before `runApp`.
  Future<void> load() async {
    _override = await _store.read();
  }

  /// The effective locale tag: override → system → `'en'`.
  String get bcp47 =>
      _override ?? _systemLocale?.toLanguageTag() ?? AppBoxKitLanguage.fallback.tag;

  /// The effective locale.
  Locale get locale {
    final parts = bcp47.split(RegExp('[-_]'));
    return Locale.fromSubtags(
      languageCode: parts.first,
      countryCode: parts.length > 1 ? parts[1] : null,
    );
  }

  /// The effective language, with base-tag fallback (`'pl-PL'` → `'pl'`),
  /// defaulting to English for unsupported tags.
  AppBoxKitLanguage get language =>
      AppBoxKitLanguage.byTag(bcp47) ?? AppBoxKitLanguage.fallback;

  /// English name of the effective language, e.g. `'Polish'`.
  String get languageNameEn => language.nameEn;

  /// Native name of the effective language, e.g. `'polski'`.
  String get languageNameNative => language.nameNative;

  /// Terms the LLM must never translate (brand names, product terms).
  List<String> get doNotTranslate => List.unmodifiable(_doNotTranslate);

  set doNotTranslate(List<String> value) => _doNotTranslate = value;

  /// Persist [tag] as the locale override and notify listeners.
  Future<void> setLocale(String tag) async {
    _override = tag;
    await _store.write(tag);
    notifyListeners();
  }

  /// Drop the override (fall back to the system locale) and notify listeners.
  Future<void> clearOverride() async {
    _override = null;
    await _store.clear();
    notifyListeners();
  }

  /// Locale-aware medium date, e.g. `Jul 30, 2026` / `30 lip 2026`.
  String formatDate(DateTime date) =>
      DateFormat.yMMMd(bcp47).format(date);

  /// Locale-aware number with grouping, e.g. `1,234.5` / `1 234,5`.
  String formatNumber(num value) =>
      NumberFormat.decimalPattern(bcp47).format(value);

  /// Locale-aware currency amount, e.g. `$1,234.50` / `1234,50 zł`.
  String formatCurrency(num value, String currencyCode) =>
      NumberFormat.simpleCurrency(locale: bcp47, name: currencyCode)
          .format(value);

  /// True when [source] and [candidate] use the same set of `{placeholder}`
  /// tokens — the translation-parity guard for ICU-flavoured strings.
  ///
  /// Comparison is case-SENSITIVE: `{COUNT}` and `{count}` do not match.
  bool placeholderParity(String source, String candidate) {
    Set<String> tokens(String s) =>
        _placeholderPattern.allMatches(s).map((m) => m.group(1)!).toSet();
    return setEquals(tokens(source), tokens(candidate));
  }

  /// System-prompt block steering an LLM to answer in the user's language,
  /// preserve placeholder tokens, and leave formatting to the app.
  String llmLocaleDirective() {
    final terms =
        _doNotTranslate.isEmpty ? '(none)' : _doNotTranslate.join(', ');
    return 'Always respond in $languageNameEn ($languageNameNative), '
        'using idiomatic speech as if you were a native speaker, regardless '
        'of the language the user writes in.\n'
        'Never translate or alter placeholder tokens like {name} or {count}.\n'
        'Never format dates, times, numbers, or currencies yourself — emit '
        "ISO 8601 dates and plain numbers; the application formats them for "
        "the user's locale.\n"
        'Do not translate these terms: $terms.';
  }
}
