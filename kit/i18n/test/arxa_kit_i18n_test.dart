import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:arxa_kit_i18n/arxa_kit_testing.dart';

void main() {
  // In an app the flutter_localizations delegates load intl's date symbols;
  // in a bare test environment we initialize them ourselves.
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('pl');
  });

  group('override resolution', () {
    test('kit.i18n.locale-resolution — persisted override wins over the system locale', () async {
      final store = FakeArxaKitLocaleStore()..queueReads(['pl']);
      final i18n = ArxaKitI18n(store: store, systemLocale: const Locale('en'));

      await i18n.load();

      expect(i18n.bcp47, 'pl');
      expect(i18n.locale, const Locale('pl'));
      expect(i18n.language, ArxaKitLanguage.byTag('pl'));
      expect(store.readCalls, 1);
    });

    test('kit.i18n.locale-resolution — clearing the override falls back to the system locale', () async {
      final store = FakeArxaKitLocaleStore()..queueReads(['pl']);
      final i18n = ArxaKitI18n(store: store, systemLocale: const Locale('en'));

      await i18n.load();
      await i18n.clearOverride();

      expect(i18n.bcp47, 'en');
      expect(i18n.locale, const Locale('en'));
      expect(store.clearCalls, 1);
    });

    test('kit.i18n.locale-resolution — no override and no system locale falls back to en', () async {
      final store = FakeArxaKitLocaleStore(); // empty queue → read() returns null
      final i18n = ArxaKitI18n(store: store);

      await i18n.load();

      expect(i18n.bcp47, 'en');
      expect(i18n.locale, const Locale('en'));
      expect(i18n.language, ArxaKitLanguage.fallback);
    });
  });

  group('ArxaKitLanguage', () {
    test('kit.i18n.language — supported ships en and pl', () {
      expect(ArxaKitLanguage.supported.map((l) => l.tag), ['en', 'pl']);
    });

    test('kit.i18n.language — byTag falls back to the base subtag (pl-PL → pl)', () {
      final lang = ArxaKitLanguage.byTag('pl-PL');
      expect(lang, isNotNull);
      expect(lang!.tag, 'pl');
      expect(lang.nameEn, 'Polish');
      expect(lang.nameNative, 'polski');
    });

    test('kit.i18n.language — equality is by tag', () {
      expect(
        const ArxaKitLanguage(tag: 'pl', nameEn: 'Polish', nameNative: 'polski'),
        const ArxaKitLanguage(tag: 'pl', nameEn: 'Polski', nameNative: 'polski'),
      );
    });
  });

  group('placeholderParity', () {
    final store = FakeArxaKitLocaleStore();
    final i18n = ArxaKitI18n(store: store);

    test('kit.i18n.placeholders — case-SENSITIVE: {COUNT} vs {count} fails', () {
      expect(
        i18n.placeholderParity('You have {COUNT} items', 'Masz {count} rzeczy'),
        isFalse,
      );
    });

    test('kit.i18n.placeholders — same tokens reordered passes', () {
      expect(
        i18n.placeholderParity(
          '{name}, you have {count} messages',
          'Masz {count} wiadomości, {name}',
        ),
        isTrue,
      );
    });

    test('kit.i18n.placeholders — missing token fails', () {
      expect(
        i18n.placeholderParity('Hello {name}, {count} left', 'Hello {name}'),
        isFalse,
      );
    });
  });

  group('llmLocaleDirective', () {
    test('kit.i18n.llm-directive — contains language names and literal placeholder tokens', () {
      final store = FakeArxaKitLocaleStore();
      final i18n = ArxaKitI18n(store: store, systemLocale: const Locale('pl'));

      final directive = i18n.llmLocaleDirective();

      expect(directive, contains('Always respond in Polish (polski)'));
      expect(directive, contains('placeholder tokens like {name} or {count}'));
      expect(directive, contains('Do not translate these terms: (none).'));
    });

    test('kit.i18n.llm-directive — doNotTranslate terms are interpolated', () {
      final store = FakeArxaKitLocaleStore();
      final i18n = ArxaKitI18n(store: store)..doNotTranslate = ['Acme', 'ProPlan'];

      expect(
        i18n.llmLocaleDirective(),
        contains('Do not translate these terms: Acme, ProPlan.'),
      );
    });
  });

  group('setLocale', () {
    test('kit.i18n.set-locale — notifies listeners and persists the override', () async {
      final store = FakeArxaKitLocaleStore();
      final i18n = ArxaKitI18n(store: store, systemLocale: const Locale('en'));
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
    test('kit.i18n.formatting — date and number follow the effective locale', () {
      final store = FakeArxaKitLocaleStore();
      final pl = ArxaKitI18n(store: store, systemLocale: const Locale('pl'));
      final en = ArxaKitI18n(store: store, systemLocale: const Locale('en'));

      expect(en.formatDate(DateTime(2026, 7, 30)), 'Jul 30, 2026');
      expect(pl.formatDate(DateTime(2026, 7, 30)), contains('2026'));
      expect(en.formatNumber(1234.5), '1,234.5');
      expect(pl.formatNumber(1234.5), contains('234,5'));
      expect(pl.formatCurrency(12.5, 'PLN'), contains('zł'));
    });
  });
}
