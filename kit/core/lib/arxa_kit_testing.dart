/// Test doubles for arxa_kit_core.
///
/// Import this from tests to substitute the arxaKitLocator-resolved core services
/// without touching Talker, SharedPreferences, or SystemChrome:
///
/// ```dart
/// final errors = FakeArxaKitErrorService();
/// arxaKitLocator.registerSingleton<ArxaKitErrorService>(errors);
/// arxaKitLocator.registerSingleton<ArxaKitThemeService>(FakeArxaKitThemeService());
///
/// await viewModel.save();
/// expect(errors.errorCalls, hasLength(1));
/// expect(errors.lastCall!.message, contains('save failed'));
/// ```
///
/// Register [FakeArxaKitErrorService] FIRST: [FakeArxaKitThemeService]'s inherited
/// base resolves `arxaKitLocator<ArxaKitErrorService>()` at construction time.
library;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:rxdart/rxdart.dart';
import 'package:talker_flutter/talker_flutter.dart' show TalkerData;

import 'extensions/arxa_kit_to_title_case_extension.dart';
import 'services/error/arxa_kit_error_service.dart';
import 'services/theme/arxa_kit_theme_service.dart';

export 'services/error/arxa_kit_error_service.dart'
    show ArxaKitErrorType, ArxaKitErrorSeverity, ArxaKitErrorService;
export 'services/theme/arxa_kit_theme_service.dart' show ArxaKitThemeService;

/// One recorded logging call on [FakeArxaKitErrorService].
class ArxaKitErrorRecord {
  const ArxaKitErrorRecord({
    this.message,
    this.error,
    this.stackTrace,
    this.widgetId,
    this.context,
    this.type,
    this.severity,
    this.source,
  });

  /// The `message` argument (`null` only for `handle` calls made without one).
  final String? message;

  /// The `error` argument (`exception` for `handle` calls).
  final Object? error;

  /// The `stackTrace` argument.
  final StackTrace? stackTrace;

  /// The `widgetId` argument.
  final String? widgetId;

  /// The `context` argument.
  final String? context;

  /// The `type` argument.
  final ArxaKitErrorType? type;

  /// The `severity` argument.
  final ArxaKitErrorSeverity? severity;

  /// The `source` argument (`logEvent` calls only).
  final String? source;
}

/// A [ArxaKitErrorService] that records every logging call and keeps widget error
/// / loading / event state in memory. Talker is never initialized and nothing
/// touches the console or global Flutter error handlers.
///
/// The widget-state members ([setWidgetError], [hasWidgetError],
/// [isWidgetLoading], the `widget*$` streams, …) behave like the real
/// service, so code that reacts to them works unchanged. The Talker-backed
/// members stay inert: [history] is always empty and `latestError$` /
/// `allErrors$` / `unreadCount$` keep their seeded values — assert against the
/// recorded call lists instead.
class FakeArxaKitErrorService extends ArxaKitErrorService {
  /// Number of times [initialize] was called.
  int initializeCallCount = 0;

  /// Every [info] call, in call order.
  final List<ArxaKitErrorRecord> infoCalls = [];

  /// Every [warning] call, in call order.
  final List<ArxaKitErrorRecord> warningCalls = [];

  /// Every [error] call, in call order.
  final List<ArxaKitErrorRecord> errorCalls = [];

  /// Every [critical] call, in call order.
  final List<ArxaKitErrorRecord> criticalCalls = [];

  /// Every [handle] call, in call order.
  final List<ArxaKitErrorRecord> handleCalls = [];

  /// Every [logEvent] call, in call order.
  final List<ArxaKitErrorRecord> eventCalls = [];

  /// Chronological record across ALL logging methods (shared entries with the
  /// per-method lists above) — backs [lastCall] / [didLog].
  final List<ArxaKitErrorRecord> allCalls = [];

  final _widgetErrors$ = BehaviorSubject<Map<String, String>>.seeded({});
  final _loadingWidgets$ = BehaviorSubject<Set<String>>.seeded({});
  final _widgetEvents$ =
      BehaviorSubject<Map<String, List<String>>>.seeded({});
  final _widgetEventCounts$ = BehaviorSubject<Map<String, int>>.seeded({});

  @override
  Future<void> initialize() async {
    initializeCallCount++;
  }

  // ---- logging -------------------------------------------------------------

  @override
  void info({
    required String message,
    String? widgetId,
    String? context,
    ArxaKitErrorType? type = ArxaKitErrorType.info,
    ArxaKitErrorSeverity? severity = ArxaKitErrorSeverity.info,
    Object? error,
    StackTrace? stackTrace,
  }) {
    infoCalls.add(_tracked(ArxaKitErrorRecord(
      message: message,
      error: error,
      stackTrace: stackTrace,
      widgetId: widgetId,
      context: context,
      type: type,
      severity: severity,
    )));
  }

  /// Adds [record] to [allCalls] and returns it, so each logging method can
  /// file the same entry in its per-method list.
  ArxaKitErrorRecord _tracked(ArxaKitErrorRecord record) {
    allCalls.add(record);
    return record;
  }

  @override
  void warning({
    required String message,
    String? widgetId,
    String? context,
    ArxaKitErrorType? type = ArxaKitErrorType.warning,
    ArxaKitErrorSeverity? severity = ArxaKitErrorSeverity.warning,
    Object? error,
    StackTrace? stackTrace,
  }) {
    warningCalls.add(_tracked(ArxaKitErrorRecord(
      message: message,
      error: error,
      stackTrace: stackTrace,
      widgetId: widgetId,
      context: context,
      type: type,
      severity: severity,
    )));
  }

  @override
  void error({
    required String message,
    Object? error,
    StackTrace? stackTrace,
    String? widgetId,
    String? context,
    ArxaKitErrorType? type,
    ArxaKitErrorSeverity? severity,
  }) {
    errorCalls.add(_tracked(ArxaKitErrorRecord(
      message: message,
      error: error,
      stackTrace: stackTrace,
      widgetId: widgetId,
      context: context,
      type: type,
      severity: severity,
    )));
    if (widgetId != null) _setWidgetErrorState(widgetId, message, error);
  }

  @override
  void critical({
    required String message,
    Object? error,
    StackTrace? stackTrace,
    String? widgetId,
    String? context,
    ArxaKitErrorType? type,
    ArxaKitErrorSeverity? severity,
  }) {
    criticalCalls.add(_tracked(ArxaKitErrorRecord(
      message: message,
      error: error,
      stackTrace: stackTrace,
      widgetId: widgetId,
      context: context,
      type: type,
      severity: severity,
    )));
    if (widgetId != null) _setWidgetErrorState(widgetId, message, error);
  }

  @override
  void handle({
    required Object exception,
    StackTrace? stackTrace,
    String? message,
    String? widgetId,
    String? context,
    ArxaKitErrorType? type,
    ArxaKitErrorSeverity? severity,
  }) {
    handleCalls.add(_tracked(ArxaKitErrorRecord(
      message: message,
      error: exception,
      stackTrace: stackTrace,
      widgetId: widgetId,
      context: context,
      type: type,
      severity: severity,
    )));
    if (widgetId != null) {
      _setWidgetErrorState(widgetId, message ?? exception.toString(), exception);
    }
  }

  @override
  void logEvent({
    required String message,
    String? source,
    String? widgetId,
    int maxEvents = 100,
    String? context,
    ArxaKitErrorType? type,
    ArxaKitErrorSeverity? severity,
  }) {
    eventCalls.add(_tracked(ArxaKitErrorRecord(
      message: message,
      widgetId: widgetId,
      context: context,
      type: type,
      severity: severity,
      source: source,
    )));

    if (widgetId != null) {
      final events =
          Map<String, List<String>>.from(_widgetEvents$.value);
      final list = events.putIfAbsent(widgetId, () => []);
      list.add(message);
      if (list.length > maxEvents) {
        events[widgetId] = list.sublist(list.length - maxEvents);
      }
      _widgetEvents$.add(events);

      final counts = Map<String, int>.from(_widgetEventCounts$.value);
      counts[widgetId] = (counts[widgetId] ?? 0) + 1;
      _widgetEventCounts$.add(counts);
    }
  }

  // ---- widget error / loading / event state --------------------------------

  @override
  Stream<Map<String, String>> get widgetErrors$ => _widgetErrors$.stream;

  @override
  Stream<Set<String>> get loadingWidgets$ => _loadingWidgets$.stream;

  @override
  Stream<Map<String, List<String>>> get widgetEvents$ =>
      _widgetEvents$.stream;

  @override
  Stream<Map<String, int>> get widgetEventCounts$ =>
      _widgetEventCounts$.stream;

  void _setWidgetErrorState(String widgetId, String message, Object? error) {
    final errors = Map<String, String>.from(_widgetErrors$.value);
    errors[widgetId] = error != null ? '$message: $error' : message;
    _widgetErrors$.add(errors);
    _setWidgetLoadingState(widgetId, false);
    notifyListeners();
  }

  void _setWidgetLoadingState(String widgetId, bool isLoading) {
    final loading = Set<String>.from(_loadingWidgets$.value);
    if (isLoading) {
      loading.add(widgetId);
    } else {
      loading.remove(widgetId);
    }
    _loadingWidgets$.add(loading);
  }

  @override
  void setWidgetError({
    required String widgetId,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    String? context,
    ArxaKitErrorType? type,
    ArxaKitErrorSeverity? severity,
  }) {
    _setWidgetErrorState(widgetId, message, error);
  }

  @override
  void clearWidgetError({required String widgetId}) {
    final errors = Map<String, String>.from(_widgetErrors$.value);
    if (errors.remove(widgetId) != null) {
      _widgetErrors$.add(errors);
      notifyListeners();
    }
  }

  @override
  void setWidgetLoading({required String widgetId, required bool isLoading}) {
    _setWidgetLoadingState(widgetId, isLoading);
    notifyListeners();
  }

  @override
  bool hasWidgetError({required String widgetId}) =>
      _widgetErrors$.value.containsKey(widgetId);

  @override
  String? getWidgetError({required String widgetId}) =>
      _widgetErrors$.value[widgetId];

  @override
  bool isWidgetLoading({required String widgetId}) =>
      _loadingWidgets$.value.contains(widgetId);

  @override
  List<String> getWidgetEvents({required String widgetId}) =>
      _widgetEvents$.value[widgetId] ?? [];

  @override
  void clearWidgetEvents({required String widgetId}) {
    final events =
        Map<String, List<String>>.from(_widgetEvents$.value);
    if (events.containsKey(widgetId)) {
      events[widgetId] = [];
      _widgetEvents$.add(events);

      final counts = Map<String, int>.from(_widgetEventCounts$.value);
      counts[widgetId] = 0;
      _widgetEventCounts$.add(counts);
    }
  }

  // ---- Talker-backed members (inert) ----------------------------------------

  /// Always empty — the fake keeps recorded calls, not Talker history.
  @override
  List<TalkerData> get history => const <TalkerData>[];

  /// Clears the recorded calls and widget state (the fake's analogue of
  /// clearing Talker history).
  @override
  void cleanHistory() {
    reset();
    notifyListeners();
  }

  // ---- query helpers ---------------------------------------------------------

  /// The most recently recorded call across all logging methods, or null.
  ArxaKitErrorRecord? get lastCall => allCalls.isEmpty ? null : allCalls.last;

  /// True if any logging call recorded a message containing [substring].
  bool didLog(String substring) {
    return allCalls.any((c) => c.message?.contains(substring) ?? false);
  }

  /// Clear all recorded calls and widget state (reuse the same instance
  /// across cases). Initialization state is left untouched.
  void reset() {
    infoCalls.clear();
    warningCalls.clear();
    errorCalls.clear();
    criticalCalls.clear();
    handleCalls.clear();
    eventCalls.clear();
    allCalls.clear();
    initializeCallCount = 0;
    _widgetErrors$.add(const {});
    _loadingWidgets$.add(const {});
    _widgetEvents$.add(const {});
    _widgetEventCounts$.add(const {});
  }

  @override
  void dispose() {
    super.dispose();
    _widgetErrors$.close();
    _loadingWidgets$.close();
    _widgetEvents$.close();
    _widgetEventCounts$.close();
  }
}

/// A [ArxaKitThemeService] driven entirely in memory — no SharedPreferences, no
/// WidgetsBinding observer, no SystemChrome overlay writes.
///
/// Construction resolves `arxaKitLocator<ArxaKitErrorService>()` (an inherited base
/// field), so register an error service — e.g. [FakeArxaKitErrorService] — first.
///
/// Like the real service, [setTheme] is a no-op until [initialize] has run;
/// use [FakeArxaKitThemeService.initialized] to start ready. Assert against
/// [themeMode$] / [isInitialized$] and the [setThemeCalls] record.
class FakeArxaKitThemeService extends ArxaKitThemeService {
  FakeArxaKitThemeService({
    ThemeMode initialMode = ThemeMode.system,
    bool initialized = false,
  })  : _mode$ = BehaviorSubject<ThemeMode>.seeded(initialMode),
        _initialized$ = BehaviorSubject<bool>.seeded(initialized);

  /// Starts initialized (as if [initialize] already ran).
  factory FakeArxaKitThemeService.initialized({
    ThemeMode initialMode = ThemeMode.system,
  }) =>
      FakeArxaKitThemeService(initialMode: initialMode, initialized: true);

  final BehaviorSubject<ThemeMode> _mode$;
  final BehaviorSubject<bool> _initialized$;

  /// Number of times [initialize] was called.
  int initializeCallCount = 0;

  /// Every [ThemeMode] passed to [setTheme], in call order (including
  /// ignored pre-initialization calls, mirroring the real service's no-op).
  final List<ThemeMode> setThemeCalls = [];

  @override
  ValueStream<ThemeMode> get themeMode$ => _mode$.stream;

  @override
  ValueStream<bool> get isInitialized$ => _initialized$.stream;

  @override
  Stream<Map<ThemeMode, bool>> get toggleStates$ => _mode$
      .map((mode) => {for (final m in ThemeMode.values) m: m == mode})
      .distinct();

  @override
  Stream<bool> isThemeActive$(ThemeMode mode) =>
      toggleStates$.map((states) => states[mode] ?? false).distinct();

  @override
  Stream<String> get currentThemeModeLabel$ => _mode$
      .map((mode) => mode.toString().split('.').last)
      .map((label) => label == 'system' ? 'auto' : label)
      .map((str) => str.toTitleCase())
      .distinct();

  @override
  Future<void> initialize() async {
    initializeCallCount++;
    if (_initialized$.value) return;
    _initialized$.add(true);
  }

  @override
  Future<void> setTheme(ThemeMode mode) async {
    setThemeCalls.add(mode);
    if (!_initialized$.value) return; // real service no-ops pre-initialize
    if (_mode$.value != mode) _mode$.add(mode);
  }

  /// No-op — the fake never writes system UI overlay styles.
  @override
  void didChangePlatformBrightness() {}

  /// Clear the call records (theme state is left untouched).
  void reset() {
    initializeCallCount = 0;
    setThemeCalls.clear();
  }

  @override
  void disposeService() {
    super.disposeService();
    _mode$.close();
    _initialized$.close();
  }
}
