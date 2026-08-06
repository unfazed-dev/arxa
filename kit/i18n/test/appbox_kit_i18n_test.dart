import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:appbox_kit_i18n/appbox_kit_testing.dart';

void main() {
  // In an app the flutter_localizations delegates load intl's date symbols;
  // in a bare test environment we initialize them ourselves.
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('pl');
  });

  group('override resolution', () {
    test('persisted override wins over the system locale', () async {
      final store = FakeAppBoxKitLocaleStore()..queueReads(['pl']);
      final i18n = AppBoxKitI18n(store: store, systemLocale: const Locale('en'));

      await i18n.load();

      expect(i18n.bcp47, 'pl');
      expect(i18n.locale, const Locale('pl'));
      expect(i18n.language, AppBoxKitLanguage.byTag('pl'));
      expect(store.readCalls, 1);
    });

    test('clearing the override falls back to the system locale', () async {
      final store = FakeAppBoxKitLocaleStore()..queueReads(['pl']);
      final i18n = AppBoxKitI18n(store: store, systemLocale: const Locale('en'));

      await i18n.load();
      await i18n.clearOverride();

      expect(i18n.bcp47, 'en');
      expect(i18n.locale, const Locale('en'));
      expect(store.clearCalls, 1);
    });

    test('no override and no system locale falls back to en', () async {
      final store = FakeAppBoxKitLocaleStore(); // empty queue → read() returns null
      final i18n = AppBoxKitI18n(store: store);

      await i18n.load();

      expect(i18n.bcp47, 'en');
      expect(i18n.locale, const Locale('en'));
      expect(i18n.language, AppBoxKitLanguage.fallback);
    });
  });

  group('AppBoxKitLanguage', () {
    test('supported ships en and pl', () {
      expect(AppBoxKitLanguage.supported.map((l) => l.tag), ['en', 'pl']);
    });

    test('byTag falls back to the base subtag (pl-PL → pl)', () {
      final lang = AppBoxKitLanguage.byTag('pl-PL');
      expect(lang, isNotNull);
      expect(lang!.tag, 'pl');
      expect(lang.nameEn, 'Polish');
      expect(lang.nameNative, 'polski');
    });

    test('equality is by tag', () {
      expect(
        const AppBoxKitLanguage(tag: 'pl', nameEn: 'Polish', nameNative: 'polski'),
        const AppBoxKitLanguage(tag: 'pl', nameEn: 'Polski', nameNative: 'polski'),
      );
    });
  });

  group('placeholderParity', () {
    final store = FakeAppBoxKitLocaleStore();
    final i18n = AppBoxKitI18n(store: store);

    test('case-SENSITIVE: {COUNT} vs {count} fails', () {
      expect(
        i18n.placeholderParity('You have {COUNT} items', 'Masz {count} rzeczy'),
        isFalse,
      );
    });

    test('same tokens reordered passes', () {
      expect(
        i18n.placeholderParity(
          '{name}, you have {count} messages',
          'Masz {count} wiadomości, {name}',
        ),
        isTrue,
      );
    });

    test('missing token fails', () {
      expect(
        i18n.placeholderParity('Hello {name}, {count} left', 'Hello {name}'),
        isFalse,
      );
    });
  });

  group('llmLocaleDirective', () {
    test('contains language names and literal placeholder tokens', () {
      final store = FakeAppBoxKitLocaleStore();
      final i18n = AppBoxKitI18n(store: store, systemLocale: const Locale('pl'));

      final directive = i18n.llmLocaleDirective();

      expect(directive, contains('Always respond in Polish (polski)'));
      expect(directive, contains('placeholder tokens like {name} or {count}'));
      expect(directive, contains('Do not translate these terms: (none).'));
    });

    test('doNotTranslate terms are interpolated', () {
      final store = FakeAppBoxKitLocaleStore();
      final i18n = AppBoxKitI18n(store: store)..doNotTranslate = ['Acme', 'ProPlan'];

      expect(
        i18n.llmLocaleDirective(),
        contains('Do not translate these terms: Acme, ProPlan.'),
      );
    });
  });

  group('setLocale', () {
    test('notifies listeners and persists the override', () async {
      final store = FakeAppBoxKitLocaleStore();
      final i18n = AppBoxKitI18n(store: store, systemLocale: const Locale('en'));
      var notified = 0;
      i18n.addListener(() => notified++);

      await i18n.setLocale('pl');

      expect(notified, 1);
      expect(store.writeCalls, 1);
      expect(store.lastWritten, 'pl');
      expect(i18n.bcp47, 'pl');
      expect(i18n.languageNameEn, 'Polish');
    });
  });

  group('formatting', () {
    test('date and number follow the effective locale', () {
      final store = FakeAppBoxKitLocaleStore();
      final pl = AppBoxKitI18n(store: store, systemLocale: const Locale('pl'));
      final en = AppBoxKitI18n(store: store, systemLocale: const Locale('en'));

      expect(en.formatDate(DateTime(2026, 7, 30)), 'Jul 30, 2026');
      expect(pl.formatDate(DateTime(2026, 7, 30)), contains('2026'));
      expect(en.formatNumber(1234.5), '1,234.5');
      expect(pl.formatNumber(1234.5), contains('234,5'));
      expect(pl.formatCurrency(12.5, 'PLN'), contains('zł'));
    });
  });
}
