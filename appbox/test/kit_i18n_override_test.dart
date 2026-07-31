import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_i18n/testing.dart';

/// Locale override resolution: persisted override → system locale → English.
void main() {
  group('KitI18n override resolution -', () {
    test('persisted pl override resolves to pl', () async {
      final store = FakeKitLocaleStore()..queueReads(['pl']);
      final i18n = KitI18n(store: store);

      await i18n.load();

      expect(i18n.bcp47, 'pl');
      expect(i18n.locale, const Locale('pl'));
      expect(store.readCalls, 1);
    });

    test('setLocale persists and notifies; clearOverride drops the override',
        () async {
      final store = FakeKitLocaleStore()..queueReads(['pl']);
      final i18n = KitI18n(store: store);
      await i18n.load();

      await i18n.setLocale('en');
      expect(i18n.bcp47, 'en');
      expect(store.lastWritten, 'en');

      await i18n.clearOverride();
      // No system locale supplied → English fallback.
      expect(i18n.bcp47, 'en');
      expect(store.clearCalls, 1);
    });

    test('clearOverride falls back to the system locale when present',
        () async {
      final store = FakeKitLocaleStore()..queueReads(['en']);
      final i18n = KitI18n(store: store, systemLocale: const Locale('pl'));
      await i18n.load();
      expect(i18n.bcp47, 'en');

      await i18n.clearOverride();
      expect(i18n.bcp47, 'pl');
      expect(i18n.locale, const Locale('pl'));
    });

    test('no override and no system locale falls back to English', () async {
      final i18n = KitI18n(store: FakeKitLocaleStore());
      await i18n.load();
      expect(i18n.bcp47, 'en');
    });
  });
}
