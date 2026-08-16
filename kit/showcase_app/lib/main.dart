import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart'
    show
        CNTransitionObserver,
        CNTabBarRouteObserver,
        AppBoxKitAction,
        AppBoxKitAccentSwatch,
        AppBoxKitErrorService,
        AppBoxKitThemeService,
        appBoxKitAccentByName,
        appBoxKitDarkTheme,
        appBoxKitDefaultGoogleFontFamily,
        appBoxKitLightTheme,
        setupAppBoxKitUiServices;
import 'package:appbox_kit_showcase_app/app/app.locator.dart';
import 'package:appbox_kit_showcase_app/app/kit_platform_router.dart';
import 'package:appbox_kit_showcase_app/ui/snackbars/snackbars.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:url_strategy/url_strategy.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // Branding handoff (kit/branding law): hold the native splash past the
  // first frame so boot never flashes a blank frame, then release it once the
  // startup view (same surface color + 80dp brand icon) has rendered — the
  // seam between OS splash and Flutter startup view is invisible.
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  setPathUrlStrategy();
  await setupLocator(stackedRouter: kitPlatformRouter);
  // Kit-owned stacked UI services (Dialog/Snackbar/BottomSheet/Talker).
  setupAppBoxKitUiServices();
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
  runApp(const ShowcaseApp());
  // First Flutter frame = the startup view's brand moment; release the
  // native splash the moment it is on screen.
  widgetsBinding.addPostFrameCallback((_) => FlutterNativeSplash.remove());
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

  /// The showcase's brand accent: the authored 'moss' swatch from the kit's
  /// theme.json SSOT. The kit default is the studio violet
  /// ([AppBoxKitColors.accent]); per the kit law a host uses that as-is or
  /// overrides the brand accent per mode via the theme constructors
  /// (appbox_kit_colors.dart header) — this app wears moss.
  static final AppBoxKitAccentSwatch _accent = appBoxKitAccentByName('moss');

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
    // Keyboard dismissal is NOT wired here anymore: the app-wide
    // Listener-based wrapper was the re-tap regression's root cause (a raw
    // pointer-down cannot tell an outside tap from a re-tap on the focused
    // field). Every kit input now carries the default itself
    // (AppBoxKitInputTapBehavior, a grouped TextFieldTapRegion) — scaffolded
    // apps inherit it per input, with nothing to wire in main.
    return AppBoxKitMotionScope(
      driver: _boot,
      spec: _bootSpec,
      child: StreamBuilder<ThemeMode>(
        stream: theme.themeMode$,
        initialData: theme.themeMode$.value,
        builder: (context, snapshot) => ResponsiveApp(
          builder: (_) => MaterialApp.router(
            debugShowCheckedModeBanner: false,
            // Route-transition occlusion: suppresses native iOS 26 glass
            // (app-bar popup menu, buttons, search bar, glass cards…) during
            // route slides so a hybrid-composition platform view can't leak
            // over the outgoing/incoming routes. See NATIVE_COMPONENTS.md.
            // CNTabBarRouteObserver is the modal half: it bumps
            // `anyModalDepth` while a sheet/dialog/popup route is up, which
            // is what makes every chrome-gated surface hide under modals.
            // Both are inherited by the nested tab routers
            // (StackedTabsRouter.inheritNavigatorObservers).
            routerDelegate: kitPlatformRouter.delegate(
              navigatorObservers: () => [
                CNTransitionObserver(),
                CNTabBarRouteObserver(),
              ],
            ),
            routeInformationParser: kitPlatformRouter.defaultRouteParser(),
            // Wire the root back dispatcher so the OS back gesture (Android 14+
            // predictive back) flows into the stacked Router — the legacy
            // routerDelegate API needs it explicit or back events don't reach the
            // router. iOS edge-swipe-back is handled by the cupertino page type
            // AppBoxKitPlatformRouter emits, not by this dispatcher.
            backButtonDispatcher: RootBackButtonDispatcher(),
            // Font law v2 demo: the kit catalogue's default `ui` face (Lexend)
            // resolved at runtime through google_fonts — the same wiring the
            // scaffolder emits from assets.manifest.json font roles.
            theme: appBoxKitLightTheme(
              accent: _accent.light.accent,
              fontFamily: appBoxKitDefaultGoogleFontFamily(),
            ),
            darkTheme: appBoxKitDarkTheme(
              accent: _accent.dark.accent,
              fontFamily: appBoxKitDefaultGoogleFontFamily(),
            ),
            themeMode: snapshot.data ?? ThemeMode.system,
            // Instant, because half this UI cannot participate in a theme
            // ANIMATION and the attempt is what made the glass look broken.
            //
            // `ThemeData.lerp` fades colours continuously but `brightness` is
            // a STEP at t=0.5. Flutter-painted surfaces therefore cross-fade
            // immediately while every native platform view — whose only
            // appearance lever is a boolean `setBrightness` — holds its OLD
            // appearance for half the duration and then snaps. That desync IS
            // the reported bug: a dark glass pill on an already-light page.
            //
            // Measured (probe, `CNButton`, one flip):
            //   default 200ms → `setBrightness` on the wire at 96ms, and 26
            //     channel round-trips for ONE widget, because the per-frame
            //     tint guard compares a value that is lerping, so every
            //     animation frame fires a fresh `setStyle`.
            //   Duration.zero → `setBrightness` at 0ms, 5 round-trips.
            // On device that per-frame storm is multiplied by every native
            // widget on screen, which is why the stale window read as seconds
            // rather than the ~100ms the step alone costs.
            //
            // Nothing is lost: the "smooth theme fade" was never coherent
            // here — it was half the screen fading while the other half
            // waited. Now both halves flip on the same frame.
            themeAnimationDuration: Duration.zero,
          ),
        ).wake(order: 0),
      ),
    );
  }
}
