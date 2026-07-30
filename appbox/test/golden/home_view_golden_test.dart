import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:appbox/app/app.locator.dart';
import 'package:appbox/l10n/app_localizations.dart';
import 'package:appbox/ui/views/home/home_view.dart';

import '../helpers/test_helpers.dart';

void main() {
  setUpAll(() => registerServices());
  tearDownAll(() => locator.reset());

  testGoldens('HomeView - default state', (tester) async {
    await loadAppFonts();

    // Set device pixel ratio and size for web
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(1920, 1080), devicePixelRatio: 1.0),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeView(),
        ),
      ),
    );

    await screenMatchesGolden(tester, 'home_view_default');
  });
}
