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
import 'data/conversation/conversation.dart';
import 'data/conversation/conversation_api_client.dart';
import 'data/conversation/conversation_repository.dart';
import 'data/tasks/task.dart';
import 'services/accent_sync.dart';
import 'services/sync_doorbell.dart';
import 'services/app_notifications_backend.dart';
import 'services/iroh_transport_service.dart';
import 'services/tap_routing.dart';
import 'services/shot_extension.dart';
import 'services/transport_service.dart';

import 'ui/app_transitions.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupLocator(stackedRouter: kitPlatformRouter);
  // Cold start: kick the resume FIRST — everything downstream (the studio
  // view, the sync decision) rides the link it establishes.
  unawaited(locator<TransportService>().resume());
  // Approvals slice (grill D60–D68) + B2 phase-1b: the data boot runs in
  // the BACKGROUND — the app renders the studio session immediately (it
  // needs no data layer), and the boot waits a generous window for the
  // tunnel: when the phone's dial lands (observed ~80s through the relay)
  // the data layer engages SYNC against the desktop mirror; a timeout or
  // unpaired install falls back to localOnly. The approvals shell gates
  // on AppData.ready, so a late boot never crashes a locator lookup.
  final notifications = locator<ArxaKitNotificationsService>();
  unawaited(
    AppData.initialize(
      transport: locator<TransportService>(),
      notifications: notifications,
    ).then((_) {
      locator.registerLazySingleton(
        () => ApprovalsRepository(
          cache: arxaKitLocator<ArxaKitRepository<Approval>>(),
          api: ApprovalsApiClient(transport: locator<TransportService>()),
        ),
      );
      // The code-shell slice (sessions + transcripts), same pattern as the
      // approvals repository: kit caches + the tunnel client.
      locator.registerLazySingleton(
        () => ConversationRepository(
          sessionCache: arxaKitLocator<ArxaKitRepository<CodeSession>>(),
          messageCache: arxaKitLocator<ArxaKitRepository<ConversationMessage>>(),
          api: ConversationApiClient(transport: locator<TransportService>()),
        ),
      );
      // Task completions doorbell the same way (B3: everything the session
      // tools trigger rides the phone rail).
      TaskDoorbell(
        arxaKitLocator<ArxaKitRepository<Task>>(),
        notifications,
      ).listen();
      // The phone-local doorbell (B2 phase-1b): sync feeds the cache; one
      // local notification per newly-synced pending approval, collapsed
      // per id. The silent APNs wake + this = the visible→silent swap's
      // phone half.
      SyncDoorbell(
        locator<ApprovalsRepository>(),
        locator<ArxaKitNotificationsService>(),
      ).listen();
    }),
  );
  setupArxaKitUiServices();
  // D68: a buzz tap deep-links the approvals shell (native didReceive →
  // channel 'tap' event → stacked router). The APNs backend exists only on
  // iOS; elsewhere this is a no-op.
  if (notifications is AppNotificationsBackend) {
    notifications.apns?.taps.listen(_routeTap);
    // The silent doorbell wake (B2 phase-1b): APNs woke the app in the
    // background — bring the tunnel up (sync + the doorbell react
    // downstream), then free the fetch budget.
    notifications.apns?.silentWakes.listen((wake) async {
      await locator<TransportService>().resume();
      unawaited(notifications.apns?.completeSilentWake() ?? Future<void>.value());
    });
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
  // TEMPORARY diagnostic rail — see shot_extension.dart. REMOVE with it.
  ShotExtension.register(ArxaStudioMobileApp._appShotKey);
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
  /// TEMPORARY diagnostic rail — see shot_extension.dart. REMOVE with it.
  static final GlobalKey _appShotKey = GlobalKey();

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
      // TEMPORARY diagnostic rail boundary — see shot_extension.dart.
      builder: (context, accent, _) => RepaintBoundary(
        key: _appShotKey,
        child: MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      theme: arxaKitLightTheme(accent: accent ?? ArxaKitColors.accent)
          .copyWith(pageTransitionsTheme: arxaNoPushTransitionsTheme),
      darkTheme: arxaKitDarkTheme(accent: accent ?? ArxaKitColors.accent)
          .copyWith(pageTransitionsTheme: arxaNoPushTransitionsTheme),
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
      ),
    );
  }
}
