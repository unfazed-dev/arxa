import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:stacked_kit_motion/stacked_kit_motion.dart';
import 'package:ui_library/ui_library.dart'
    show
        CNTransitionObserver,
        KitThemeService,
        kitDarkTheme,
        kitLightTheme,
        setupKitSnackbars;
import 'package:app_box/app/app.bottomsheets.dart';
import 'package:app_box/app/app.dialogs.dart';
import 'package:app_box/app/app.locator.dart';
import 'package:app_box/app/kit_platform_router.dart';
import 'package:app_box/ui/common/generated/brand_colors.dart';
import 'package:url_strategy/url_strategy.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setPathUrlStrategy();
  await setupLocator(stackedRouter: kitPlatformRouter);
  // App boot (stacked_kit_data seed backend + fake auth) happens in
  // ShowcaseStartupViewModel.runStartupLogic() — the canonical Stacked startup flow.
  // Restore the persisted ThemeMode (defaults to `system`) and sync the status
  // bar before the first frame. KitThemeService owns ThemeMode + system UI.
  await locator<KitThemeService>().initialize();
  setupKitSnackbars();
  setupDialogUi();
  setupBottomSheetUi();
  runApp(const AppBoxApp());
}

class AppBoxApp extends StatefulWidget {
  const AppBoxApp({super.key});

  @override
  State<AppBoxApp> createState() => _AppBoxAppState();
}

class _AppBoxAppState extends State<AppBoxApp>
    with SingleTickerProviderStateMixin {
  /// One-shot boot driver — there's no route above [MaterialApp.router], so
  /// the root scope can't be route-driven. Runs 0→1 once after first boot.
  late final AnimationController _boot = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  /// Fade-only: a rise/slide at the app root would shift the entire UI.
  static const _bootSpec = KitMotionSpec(offset: Offset.zero);

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
    final theme = locator<KitThemeService>();
    return KitMotionScope(
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
            // KitPlatformRouter emits, not by this dispatcher.
            backButtonDispatcher: RootBackButtonDispatcher(),
            theme: kitLightTheme(accent: BrandColors.accent),
            darkTheme: kitDarkTheme(accent: BrandColors.accent),
            themeMode: snapshot.data ?? ThemeMode.system,
          ),
        ),
      ).wake(order: 0),
    );
  }
}
