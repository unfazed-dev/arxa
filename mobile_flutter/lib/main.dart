import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:flutter/material.dart';

import 'package:arxa_studio_mobile/l10n/app_localizations.dart';

import 'app/app.locator.dart';
import 'app/app_data.dart';
import 'app/kit_platform_router.dart';
import 'services/transport_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupLocator(stackedRouter: kitPlatformRouter);
  // lens-smoke unblock (2026-08-29): CairnDatabase.local throws with zero
  // declared entities ("Entities land with the approvals data slice"), which
  // aborted main() before runApp. Shell surfaces don't touch the data layer
  // yet, so log-and-continue until the approvals slice registers entities.
  try {
    await AppData.initialize();
  } catch (e) {
    debugPrint('AppData.initialize failed (known scaffold gap): $e');
  }
  setupArxaKitUiServices();
  // iOS suspends QUIC in the background — redial the studio link whenever
  // the app returns to the foreground (no-op without a live session).
  WidgetsBinding.instance.addObserver(TransportLifecycleObserver());
  runApp(const ArxaStudioMobileApp());
}

/// Calls [TransportService.resume] on every return to the foreground.
class TransportLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      locator<TransportService>().resume();
    }
  }
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
