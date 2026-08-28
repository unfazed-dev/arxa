import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:flutter/material.dart';

import 'package:arxa_studio_mobile/l10n/app_localizations.dart';

import 'app/app.locator.dart';
import 'app/app_data.dart';
import 'app/kit_platform_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupLocator();
  await AppData.initialize();
  setupArxaKitUiServices();
  runApp(const ArxaStudioMobileApp());
}

class ArxaStudioMobileApp extends StatelessWidget {
  const ArxaStudioMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      theme: arxaKitLightTheme(),
      darkTheme: arxaKitDarkTheme(),
      themeMode: ThemeMode.system,
      routerDelegate: kitPlatformRouter.delegate(),
      routeInformationParser: kitPlatformRouter.defaultRouteParser(),
      // OS back gesture (Android predictive back) must reach the stacked
      // router explicitly under the routerDelegate API.
      backButtonDispatcher: RootBackButtonDispatcher(),
    );
  }
}
