import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart'
    show
        CNTransitionObserver,
        AppBoxKitAction,
        AppBoxKitErrorService,
        AppBoxKitThemeService,
        appBoxKitDarkTheme,
        appBoxKitLightTheme;
import 'package:appbox_kit_showcase_app/app/app.bottomsheets.dart';
import 'package:appbox_kit_showcase_app/app/app.dialogs.dart';
import 'package:appbox_kit_showcase_app/app/app.locator.dart';
import 'package:appbox_kit_showcase_app/app/kit_platform_router.dart';
import 'package:appbox_kit_showcase_app/ui/snackbars/snackbars.dart';
import 'package:url_strategy/url_strategy.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setPathUrlStrategy();
  await setupLocator(stackedRouter: kitPlatformRouter);
  // AppBoxKitAction's error/notification managers log through AppBoxKitErrorService —
  // initialize it first or the first handled error dies on the late Talker.
  await locator<AppBoxKitErrorService>().initialize();
  // App boot (appbox_kit_data seed backend + fake auth) happens in
  // ShowcaseStartupViewModel.runStartupLogic() — the canonical Stacked startup flow.
  // Restore the persisted ThemeMode (defaults to `system`) and sync the status
  // bar before the first frame. AppBoxKitThemeService owns ThemeMode + system UI.
  // Through AppBoxKitAction so a restore failure logs instead of killing main().
  await AppBoxKitAction.run<void>(
    () => locator<AppBoxKitThemeService>().initialize(),
    widgetId: 'main.themeInit',
  ).completeOnError('Theme restore failed');
  setupShowcaseSnackbars();
  setupDialogUi();
  setupBottomSheetUi();
  runApp(const ShowcaseApp());
}

class ShowcaseApp extends StatefulWidget {
  const ShowcaseApp({super.key});

  @override
  State<ShowcaseApp> createState() => _ShowcaseAppState();
}

class _ShowcaseAppState extends State<ShowcaseApp>
    with SingleTickerProviderStateMixin {
  /// One-shot boot driver — there's no route above [MaterialApp.router], so
  /// the root scope can't be route-driven. Runs 0→1 once after first boot.
  late final AnimationController _boot = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  /// Fade-only: a rise/slide at the app root would shift the entire UI.
  static const _bootSpec = AppBoxKitMotionSpec(offset: Offset.zero);

  @override
  void initState() {
    super.initState();
    _boot.forward();
  }

  @override
  void dispose() {
    _boot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = locator<AppBoxKitThemeService>();
    return AppBoxKitMotionScope(
      driver: _boot,
      spec: _bootSpec,
      child: StreamBuilder<ThemeMode>(
        stream: theme.themeMode$,
        initialData: theme.themeMode$.value,
        builder: (context, snapshot) => ResponsiveApp(
          builder: (_) => MaterialApp.router(
            // Route-transition occlusion: suppresses native iOS 26 glass
            // (app-bar popup menu, buttons, search bar, glass cards…) during
            // route slides so a hybrid-composition platform view can't leak
            // over the outgoing/incoming routes. See NATIVE_COMPONENTS.md.
            routerDelegate: kitPlatformRouter.delegate(
              navigatorObservers: () => [CNTransitionObserver()],
            ),
            routeInformationParser: kitPlatformRouter.defaultRouteParser(),
            // Wire the root back dispatcher so the OS back gesture (Android 14+
            // predictive back) flows into the stacked Router — the legacy
            // routerDelegate API needs it explicit or back events don't reach the
            // router. iOS edge-swipe-back is handled by the cupertino page type
            // AppBoxKitPlatformRouter emits, not by this dispatcher.
            backButtonDispatcher: RootBackButtonDispatcher(),
            theme: appBoxKitLightTheme(),
            darkTheme: appBoxKitDarkTheme(),
            themeMode: snapshot.data ?? ThemeMode.system,
          ),
        ),
      ).wake(order: 0),
    );
  }
}
