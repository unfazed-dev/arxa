import 'package:arxa_kit_data/arxa_kit_data.dart';
import 'package:arxa_kit_notifications/arxa_kit_notifications.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:flutter/material.dart';

import 'package:arxa_studio_mobile/l10n/app_localizations.dart';

import 'app/app.locator.dart';
import 'app/app_data.dart';
import 'app/app.router.dart';
import 'app/kit_platform_router.dart';
import 'data/approvals/approval.dart';
import 'data/approvals/approvals_api_client.dart';
import 'data/approvals/approvals_repository.dart';
import 'services/app_notifications_backend.dart';
import 'services/transport_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupLocator(stackedRouter: kitPlatformRouter);
  // Approvals slice (grill D60–D68): boot the cairn-backed data layer with
  // the Approval entity, then expose its repository behind the tunnel
  // client. Loud on purpose (D62): a boot failure crashes visibly rather
  // than silently degrading the approvals shell.
  await AppData.initialize();
  locator.registerLazySingleton(
    () => ApprovalsRepository(
      cache: arxaKitLocator<ArxaKitRepository<Approval>>(),
      api: ApprovalsApiClient(transport: locator<TransportService>()),
    ),
  );
  setupArxaKitUiServices();
  // D68: a buzz tap deep-links the approvals shell (native didReceive →
  // channel 'tap' event → stacked router). The APNs backend exists only on
  // iOS; elsewhere this is a no-op.
  final notifications = locator<ArxaKitNotificationsService>();
  if (notifications is AppNotificationsBackend) {
    notifications.apns?.taps.listen((_) {
      locator<RouterService>().replaceWith(ApprovalsListViewRoute());
    });
  }
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
