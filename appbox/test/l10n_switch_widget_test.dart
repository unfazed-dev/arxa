import 'package:appbox/app/app.locator.dart';
import 'package:appbox/l10n/app_localizations.dart';
import 'package:appbox/ui/views/startup/startup_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stacked_kit_i18n/testing.dart';

import 'helpers/test_helpers.dart';

/// Pumps StartupView with the real localization delegates and asserts the
/// visible string follows KitI18n live: English first, Polish after
/// setLocale('pl') + pump.
void main() {
  setUp(() => registerServices());
  tearDown(() => locator.reset());

  testWidgets('StartupView switches loading text en → pl live', (tester) async {
    final i18n = KitI18n(store: FakeKitLocaleStore());
    await i18n.load();

    await tester.pumpWidget(
      ListenableBuilder(
        listenable: i18n,
        builder: (context, _) => MaterialApp(
          locale: i18n.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const StartupView(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Loading ...'), findsOneWidget);

    await i18n.setLocale('pl');
    await tester.pump();

    expect(find.text('Ładowanie…'), findsOneWidget);
    expect(find.text('Loading ...'), findsNothing);
  });
}
