import '../../appbox_kit_locator.dart' show appBoxKitLocator;
import '../error/appbox_kit_error_service.dart';
import 'package:flutter/material.dart' show Brightness, Colors, ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'
    show WidgetsBinding, WidgetsBindingObserver;
import 'package:stacked/stacked.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../extensions/appbox_kit_to_title_case_extension.dart';

class AppBoxKitThemeService with ListenableServiceMixin, WidgetsBindingObserver {
  static const _widgetId = 'kit_theme_service';

  final _themeModeController =
      BehaviorSubject<ThemeMode>.seeded(ThemeMode.system);
  final _themeKeyController = BehaviorSubject<String>.seeded('theme_mode');
  final _isInitializedController = BehaviorSubject<bool>.seeded(false);

  // Service dependencies
  final _errorService = appBoxKitLocator<AppBoxKitErrorService>();

  // Expose streams as ValueStreams to ensure latest value is always available
  ValueStream<ThemeMode> get themeMode$ => _themeModeController.stream;
  ValueStream<bool> get isInitialized$ => _isInitializedController.stream;
  // Expose theme key as ValueStream
  ValueStream<String> get themeKey$ => _themeKeyController.stream;

  // Stream of toggle states for each theme mode
  Stream<Map<ThemeMode, bool>> get toggleStates$ => _themeModeController
          .map((mode) => {
                for (var themeMode in ThemeMode.values)
                  themeMode: themeMode == mode
              })
          .onErrorReturn({
        ThemeMode.system: true,
        ThemeMode.light: false,
        ThemeMode.dark: false,
      }).distinct();

  // Stream for individual toggle states
  Stream<bool> isThemeActive$(ThemeMode mode) =>
      toggleStates$.map((states) => states[mode] ?? false).distinct();

  Stream<String> get currentThemeModeLabel$ => _themeModeController
      .map((mode) {
        final themeModeLabel = mode.toString().split('.').last;
        return themeModeLabel == 'system' ? 'auto' : themeModeLabel;
      })
      .map((str) => str.toTitleCase())
      .distinct();

  // ponytail: ThemeMode persistence + reactive streams + system UI overlay live
  // here; this service stays free of color values. ThemeData is built from the
  // kit's generic palette — see appbox_kit_colors.dart (appBoxKitLightTheme / appBoxKitDarkTheme);
  // the host just passes those to MaterialApp.

// Initialize and set theme
  AppBoxKitThemeService() {
    listenToReactiveValues([
      _themeModeController,
      _themeKeyController,
      _isInitializedController,
    ]);
  }

  Future<void> initialize() async {
    if (_isInitializedController.value) return;

    // Observe OS-level light/dark flips so `system` mode stays in sync.
    WidgetsBinding.instance.addObserver(this);

    final prefs = await SharedPreferences.getInstance();
    final savedThemeModeLabel = prefs.getString(_themeKeyController.value);
    final initialTheme = _currentThemeMode(savedThemeModeLabel);

    _themeModeController.add(initialTheme);
    _isInitializedController.add(true);
    _applySystemUiOverlayStyle();
  }

  Future<void> setTheme(ThemeMode mode) async {
    if (!_isInitializedController.value) {
      _errorService.info(
        message: 'ThemeService not initialized',
        widgetId: _widgetId,
      );
      return;
    }

    if (_themeModeController.value != mode) {
      _themeModeController.add(mode);
      _applySystemUiOverlayStyle();
      await _saveTheme();
    }
  }

  Future<void> _saveTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeLabel =
        _themeModeController.value.toString().split('.').last;
    await prefs.setString(_themeKeyController.value, themeModeLabel);
  }

  ThemeMode _currentThemeMode(String? themeModeLabel) {
    switch (themeModeLabel?.toLowerCase()) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  // OS flipped light/dark — only `system` mode visibly changes, but the
  // resolved overlay must follow. Cheap to apply unconditionally when in system.
  @override
  void didChangePlatformBrightness() {
    if (_themeModeController.value == ThemeMode.system) {
      _applySystemUiOverlayStyle();
    }
  }

  /// Resolves the active surface brightness: explicit light/dark, or the OS
  /// brightness for `system` (the seeded default).
  Brightness _effectiveBrightness() {
    switch (_themeModeController.value) {
      case ThemeMode.light:
        return Brightness.light;
      case ThemeMode.dark:
        return Brightness.dark;
      case ThemeMode.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness;
    }
  }

  // Note the inversion: SystemUiOverlayStyle.light = light-colored icons
  // (for dark surfaces), .dark = dark icons (for light surfaces). Transparent
  // bars + contrast off keeps things edge-to-edge friendly on Android 15+.
  void _applySystemUiOverlayStyle() {
    final isDark = _effectiveBrightness() == Brightness.dark;
    final base =
        isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;
    SystemChrome.setSystemUIOverlayStyle(
      base.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }

// Dispose services
  void disposeService() {
    WidgetsBinding.instance.removeObserver(this);
    _themeModeController.close();
    _isInitializedController.close();
    _themeKeyController.close();
  }
}
