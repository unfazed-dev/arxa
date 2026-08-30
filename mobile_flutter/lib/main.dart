import 'dart:async';

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
import 'services/accent_sync.dart';
import 'services/app_notifications_backend.dart';
import 'services/iroh_transport_service.dart';
import 'services/tap_routing.dart';
import 'services/transport_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupLocator(stackedRouter: kitPlatformRouter);
  // Cold start: kick the resume BEFORE the data boot — the B2 phase-1b
  // sync bootstrap (below) rides the link the resume establishes.
  unawaited(locator<TransportService>().resume());
  // Approvals slice (grill D60–D68): boot the cairn-backed data layer with
  // the Approval entity, then expose its repository behind the tunnel
  // client. Loud on purpose (D62): a boot failure crashes visibly rather
  // than silently degrading the approvals shell. With a stored pairing the
  // boot waits bounded for the tunnel and opens SYNC against the desktop's
  // mirror through the engine's cairn proxy (B2 phase-1b); anything else
  // boots localOnly (offline reads come from local SQLite either way).
  await AppData.initialize(
    transport: locator<TransportService>(),
    notifications: locator<ArxaKitNotificationsService>(),
  );
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
    notifications.apns?.taps.listen(_routeTap);
  }
  // iOS suspends QUIC in the background — redial the studio link whenever
  // the app returns to the foreground (no-op without a live session).
  WidgetsBinding.instance.addObserver(TransportLifecycleObserver());
  // Theme accent (desktop-driven): seed from the last synced value, then
  // follow the engine's choice on every connect while the app runs.
  final accentSync = AccentSync(locator<TransportService>());
  await accentSync.loadCached();
  accentSync.listen();
  // Startup route is state-aware: a stored pairing payload means the resume
  // above restores the link — land straight in the studio session instead
  // of flashing the QR scanner (the old '/' default) on every cold start.
  final startsInStudio = await IrohTransportService.storedPairingExists();
  runApp(ArxaStudioMobileApp(startsInStudio: startsInStudio, accentSync: accentSync));
}

/// Routes a notification tap by its push class: 'task:*' collapse keys land
/// on the studio root, everything else keeps the approvals deep link.
///
/// Cold-start ordering: the drained tap can arrive before the first frame
/// mounts the navigator, so wait for the router's navigator context before
/// replacing the route (navigating an unbuilt navigator throws).
Future<void> _routeTap(Map<String, dynamic> tap) async {
  final navigator = kitPlatformRouter.navigatorKey;
  while (navigator.currentContext == null) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  switch (routeForTap(tap['collapseKey'] as String?)) {
    case TapRoute.studioRoot:
      // The studio session view is the paired home: it waits for the boot
      // resume to bring the link up when the tap arrives on a cold start.
      locator<RouterService>().replaceWith(StudioSessionViewRoute());
    case TapRoute.approvals:
      locator<RouterService>().replaceWith(ApprovalsListViewRoute());
  }
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
  const ArxaStudioMobileApp({
    required this.startsInStudio,
    required this.accentSync,
    super.key,
  });

  /// main() read the stored pairing payload: true opens the studio session
  /// (the boot resume brings the link up in place), false opens the scanner.
  final bool startsInStudio;

  /// The desktop-driven accent — rebuilds the MaterialApp when it changes.
  final AccentSync accentSync;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color?>(
      valueListenable: accentSync.accent,
      builder: (context, accent, _) => MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      theme: arxaKitLightTheme(accent: accent ?? ArxaKitColors.accent),
      darkTheme: arxaKitDarkTheme(accent: accent ?? ArxaKitColors.accent),
      themeMode: ThemeMode.system,
      routerDelegate: kitPlatformRouter.delegate(
        initialRoutes: [
          if (startsInStudio)
            StudioSessionViewRoute()
          else
            PairingScanViewRoute(),
        ],
      ),
      routeInformationParser: kitPlatformRouter.defaultRouteParser(),
      // OS back gesture (Android predictive back) must reach the stacked
      // router explicitly under the routerDelegate API.
      backButtonDispatcher: RootBackButtonDispatcher(),
      ),
    );
  }
}
