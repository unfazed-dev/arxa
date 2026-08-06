import 'package:stacked/stacked.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter/foundation.dart';

/// Enum to classify the type of error.
enum AppBoxKitErrorType {
  ui,
  network,
  database,
  businessLogic,
  authentication,
  payment,
  validation,
  thirdParty,
  fileSystem,
  permissions,
  unknown,
  info,
  warning
}

/// Enum to classify the severity of an error or log.
enum AppBoxKitErrorSeverity { low, medium, high, critical, info, warning }

/// ErrorService - A reactive service for error handling and logging
/// following Stacked architecture patterns.
class AppBoxKitErrorService with ListenableServiceMixin {
  // Late initialized talker instance
  late Talker _talker;

  // Public getter for the talker instance
  Talker get talker => _talker;

  // RxDart streams for error tracking
  final _latestErrorSubject$ = BehaviorSubject<TalkerError?>.seeded(null);
  final _allErrorsSubject$ = BehaviorSubject<List<TalkerData>>.seeded([]);
  final _unreadCountSubject$ = BehaviorSubject<int>.seeded(0);

  // Error state management streams
  final _widgetErrorsSubject$ = BehaviorSubject<Map<String, String>>.seeded({});
  final _loadingWidgetsSubject$ = BehaviorSubject<Set<String>>.seeded({});

  // Event log management streams
  final _widgetEventsSubject$ =
      BehaviorSubject<Map<String, List<String>>>.seeded({});
  final _widgetEventCountsSubject$ =
      BehaviorSubject<Map<String, int>>.seeded({});

  // Public streams
  Stream<TalkerError?> get latestError$ =>
      _latestErrorSubject$.stream.distinct();
  Stream<List<TalkerData>> get allErrors$ => _allErrorsSubject$.stream;
  Stream<int> get unreadCount$ => _unreadCountSubject$.stream.distinct();

  /// Stream of widget errors by widget ID
  Stream<Map<String, String>> get widgetErrors$ => _widgetErrorsSubject$.stream;

  /// Stream of widgets currently in loading state
  Stream<Set<String>> get loadingWidgets$ => _loadingWidgetsSubject$.stream;

  /// Stream of widget event logs by widget ID
  Stream<Map<String, List<String>>> get widgetEvents$ =>
      _widgetEventsSubject$.stream;

  /// Stream of widget event counts by widget ID
  Stream<Map<String, int>> get widgetEventCounts$ =>
      _widgetEventCountsSubject$.stream;

  String _formatMessageWithContext({
    required String originalMessage,
    String? context,
    AppBoxKitErrorType? type,
    AppBoxKitErrorSeverity? severity,
  }) {
    final parts = <String>[];
    if (severity != null) parts.add('Severity: ${severity.name}');
    if (type != null) parts.add('Type: ${type.name}');
    if (context != null && context.isNotEmpty) parts.add('Context: $context');

    if (parts.isEmpty) return originalMessage;
    // Ensure consistent formatting for the final message
    final details = parts.join(' | ');
    return '$details | Message: $originalMessage';
  }

  (int?, String?) _getFileInfo(StackTrace stackTrace) {
    try {
      final relevantLine = stackTrace.toString().split('\n').firstWhere(
            (line) =>
                !line.contains('package:talker_flutter') &&
                !line.contains('package:flutter/src/widgets') &&
                !line.contains('AppBoxKitErrorService._logWithTalker') &&
                !line.contains('AppBoxKitErrorService.debug') &&
                !line.contains('AppBoxKitErrorService.info') &&
                !line.contains('AppBoxKitErrorService.warning') &&
                !line.contains('AppBoxKitErrorService.error') &&
                !line.contains('AppBoxKitErrorService.critical') &&
                !line.contains('AppBoxKitErrorService.verbose') &&
                !line.contains('AppBoxKitErrorService.handle') &&
                !line.contains('AppBoxKitErrorService.logEvent') &&
                line.contains(':'),
            orElse: () => stackTrace
                .toString()
                .split('\n')
                .firstWhere((line) => line.contains(':'), orElse: () => ''),
          );

      if (relevantLine.isEmpty) return (null, null);

      final parts = relevantLine.split(RegExp(r'[:()]'));
      if (parts.length < 3) return (null, null);

      String? fileNamePart;
      String? lineNumberPart;

      for (int i = parts.length - 1; i >= 0; i--) {
        if (lineNumberPart == null && int.tryParse(parts[i].trim()) != null) {
          lineNumberPart = parts[i].trim();
        } else if (fileNamePart == null && parts[i].contains('.dart')) {
          fileNamePart = parts[i].split('/').last.trim();
          break;
        }
      }

      if (fileNamePart == null || lineNumberPart == null) return (null, null);

      return (int.tryParse(lineNumberPart), fileNamePart);
    } catch (e) {
      return (null, null);
    }
  }

  void _logWithTalker(LogLevel level, String originalMessage,
      {Object? error,
      StackTrace? stackTrace,
      String? context,
      AppBoxKitErrorType? type,
      AppBoxKitErrorSeverity? severity,
      String? widgetId}) {
    final st = stackTrace ?? StackTrace.current;
    final (lineNumber, fileName) = _getFileInfo(st);

    String baseFormattedMessage = _formatMessageWithContext(
        originalMessage: originalMessage,
        context: context,
        type: type,
        severity: severity);

    final filePrefix = fileName != null ? '$fileName:' : '';
    final linePrefix = lineNumber != null ? '$lineNumber ' : '';
    final widgetPrefixForLog = widgetId != null ? '($widgetId) ' : '';
    final timestamp = DateTime.now().toString().split('.').first;

    String finalMessageToLog =
        '[$timestamp] $filePrefix$linePrefix$widgetPrefixForLog-> $baseFormattedMessage';

    _talker.log(finalMessageToLog,
        logLevel: level, exception: error, stackTrace: st);
    notifyListeners();
  }

  // Constructor
  AppBoxKitErrorService() {
    listenToReactiveValues([]);
  }

  /// Initialize the Error service with appropriate settings
  /// and set up global error handlers
  Future<void> initialize() async {
    _talker = TalkerFlutter.init(
      settings: TalkerSettings(
        maxHistoryItems: 100,
        useConsoleLogs: false,
      ),
    );

    // Set up listeners for error tracking
    _talker.stream.listen((event) {
      if (event is TalkerError || event is TalkerException) {
        _processError(event);
      }
    });

    // Set up global error handling
    FlutterError.onError = (details) {
      try {
        _talker.handle(details.exception, details.stack, 'Flutter Error');
      } catch (e, st) {
        // Defensive fallback: use critical logging if handle fails
        try {
          critical(
              message: 'ErrorService FlutterError.onError failed',
              error: e,
              stackTrace: st);
        } catch (_) {
          // As a last resort, use Flutter's default error reporting
          FlutterError.dumpErrorToConsole(details, forceReport: true);
        }
      }
    };
  }

  void _processError(TalkerData error) {
    // Update latest error
    if (error is TalkerError) {
      _latestErrorSubject$.add(error);
    }

    // Update all errors
    final current = _allErrorsSubject$.value;
    _allErrorsSubject$.add([...current, error]);

    // Update unread count
    _unreadCountSubject$.add(_unreadCountSubject$.value + 1);

    // Notify listeners
    notifyListeners();
  }

  /// Sets error state for a widget and logs to talker service
  ///
  /// Parameters:
  /// - widgetId: Unique identifier for the widget (e.g., 'rive_animation', 'login_form')
  /// - message: Error message to display
  /// - error: Optional error object
  /// - stackTrace: Optional stack trace
  void setWidgetError(
      {required String widgetId,
      required String message,
      Object? error,
      StackTrace? stackTrace,
      String? context,
      AppBoxKitErrorType? type,
      AppBoxKitErrorSeverity? severity}) {
    // Log the error to talker without recursively calling error()
    _talker.error(
        _formatMessageWithContext(
            originalMessage: message,
            context: context,
            type: type,
            severity: severity),
        error,
        stackTrace);

    // Store the error for the widget
    final errors = Map<String, String>.from(_widgetErrorsSubject$.value);
    errors[widgetId] = error != null ? '$message: $error' : message;
    _widgetErrorsSubject$.add(errors);

    // Remove the widget from loading state if it was loading
    setWidgetLoading(widgetId: widgetId, isLoading: false);

    // Notify listeners
    notifyListeners();
  }

  /// Clears error state for a widget
  ///
  /// Parameters:
  /// - widgetId: Unique identifier for the widget
  void clearWidgetError({required String widgetId}) {
    final errors = Map<String, String>.from(_widgetErrorsSubject$.value);
    if (errors.containsKey(widgetId)) {
      errors.remove(widgetId);
      _widgetErrorsSubject$.add(errors);
      notifyListeners();
    }
  }

  /// Sets loading state for a widget
  ///
  /// Parameters:
  /// - widgetId: Unique identifier for the widget
  /// - isLoading: Whether the widget is in loading state
  void setWidgetLoading({required String widgetId, required bool isLoading}) {
    final loadingWidgets = Set<String>.from(_loadingWidgetsSubject$.value);

    if (isLoading) {
      loadingWidgets.add(widgetId);
    } else {
      loadingWidgets.remove(widgetId);
    }

    _loadingWidgetsSubject$.add(loadingWidgets);
    notifyListeners();
  }

  /// Checks if a widget has an error
  ///
  /// Parameters:
  /// - widgetId: Unique identifier for the widget
  bool hasWidgetError({required String widgetId}) {
    return _widgetErrorsSubject$.value.containsKey(widgetId);
  }

  /// Gets the error message for a widget
  ///
  /// Parameters:
  /// - widgetId: Unique identifier for the widget
  String? getWidgetError({required String widgetId}) {
    return _widgetErrorsSubject$.value[widgetId];
  }

  /// Checks if a widget is in loading state
  ///
  /// Parameters:
  /// - widgetId: Unique identifier for the widget
  bool isWidgetLoading({required String widgetId}) {
    return _loadingWidgetsSubject$.value.contains(widgetId);
  }

  /// Log info message
  ///
  /// Parameters:
  /// - message: Info message to log
  /// - widgetId: Optional widget ID for widget-specific info logging
  void info(
      {required String message,
      String? widgetId,
      String? context,
      AppBoxKitErrorType? type = AppBoxKitErrorType.info,
      AppBoxKitErrorSeverity? severity = AppBoxKitErrorSeverity.info,
      Object? error, // Added optional error
      StackTrace? stackTrace // Added optional stackTrace
      }) {
    _logWithTalker(LogLevel.info, message,
        error: error,
        stackTrace: stackTrace,
        widgetId: widgetId,
        context: context,
        type: type,
        severity: severity);
  }

  /// Log warning message
  ///
  /// Parameters:
  /// - message: Warning message to log
  /// - widgetId: Optional widget ID for widget-specific warning logging
  void warning(
      {required String message,
      String? widgetId,
      String? context,
      AppBoxKitErrorType? type = AppBoxKitErrorType.warning,
      AppBoxKitErrorSeverity? severity = AppBoxKitErrorSeverity.warning,
      Object? error, // Added optional error
      StackTrace? stackTrace // Added optional stackTrace
      }) {
    _logWithTalker(LogLevel.warning, message,
        error: error,
        stackTrace: stackTrace,
        widgetId: widgetId,
        context: context,
        type: type,
        severity: severity);
  }

  /// Log error with optional exception and stack trace
  ///
  /// If widgetId is provided, this will also update the widget error state
  void error(
      {required String message,
      Object? error,
      StackTrace? stackTrace,
      String? widgetId,
      String? context,
      AppBoxKitErrorType? type,
      AppBoxKitErrorSeverity? severity}) {
    _logWithTalker(LogLevel.error, message,
        error: error,
        stackTrace: stackTrace,
        context: context,
        type: type,
        severity: severity);

    // If widgetId is provided, also set widget error
    if (widgetId != null) {
      setWidgetError(
          widgetId: widgetId,
          message: message,
          error: error,
          stackTrace: stackTrace,
          context: context,
          type: type,
          severity: severity);
    }
  }

  /// Log event with optional source and widget ID
  ///
  /// Parameters:
  /// - message: Event message to log
  /// - source: Optional source of the event (e.g., 'Debug Panel', 'User Action')
  /// - widgetId: Optional widget ID for widget-specific event logging
  /// - maxEvents: Optional maximum number of events to keep for the widget (default: 100)
  /// - context: Optional context for the message
  /// - type: Optional type of message
  /// - severity: Optional severity of message
  void logEvent(
      {required String message,
      String? source,
      String? widgetId,
      int maxEvents = 100,
      String? context,
      AppBoxKitErrorType? type,
      AppBoxKitErrorSeverity? severity}) {
    final timestamp = DateTime.now().toString().split('.').first;

    // Capture stack trace to get line number
    final stackTrace = StackTrace.current;
    final (lineNumber, fileName) = _getFileInfo(stackTrace);

    // Format the log entry, including widgetId and line number if provided
    final filePrefix = fileName != null ? '[$fileName]' : '';
    final widgetPrefix = widgetId != null ? ' | [$widgetId]' : '';
    final linePrefix = lineNumber != null ? ' | [@ line $lineNumber]' : '';
    final sourcePrefix = source != null ? '$source: ' : '';

    final logEntry =
        '[$timestamp] $filePrefix$widgetPrefix$linePrefix -> $sourcePrefix$message';

    // Log directly to talker instead of calling info() which would format again
    _logWithTalker(LogLevel.info, logEntry,
        context: context, type: type, severity: severity);

    // If widgetId is provided, store the event for that widget
    if (widgetId != null) {
      final events =
          Map<String, List<String>>.from(_widgetEventsSubject$.value);

      // Create list for widget if it doesn't exist
      if (!events.containsKey(widgetId)) {
        events[widgetId] = [];
      }

      // Add event to widget's event list
      events[widgetId]!.add(logEntry);

      // Trim event list if it exceeds maxEvents
      if (events[widgetId]!.length > maxEvents) {
        events[widgetId] =
            events[widgetId]!.sublist(events[widgetId]!.length - maxEvents);
      }

      _widgetEventsSubject$.add(events);

      // Update event counts
      final counts = Map<String, int>.from(_widgetEventCountsSubject$.value);
      counts[widgetId] = (counts[widgetId] ?? 0) + 1;
      _widgetEventCountsSubject$.add(counts);
    }
  }

  /// Get all events for a specific widget
  ///
  /// Parameters:
  /// - widgetId: Widget ID to get events for
  List<String> getWidgetEvents({required String widgetId}) {
    return _widgetEventsSubject$.value[widgetId] ?? [];
  }

  /// Clear events for a specific widget
  ///
  /// Parameters:
  /// - widgetId: Widget ID to clear events for
  void clearWidgetEvents({required String widgetId}) {
    final events = Map<String, List<String>>.from(_widgetEventsSubject$.value);
    if (events.containsKey(widgetId)) {
      events[widgetId] = [];
      _widgetEventsSubject$.add(events);

      // Reset event count
      final counts = Map<String, int>.from(_widgetEventCountsSubject$.value);
      counts[widgetId] = 0;
      _widgetEventCountsSubject$.add(counts);
    }
  }

  /// Log critical error with optional exception and stack trace
  ///
  /// Parameters:
  /// - message: Critical error message to log
  /// - exception: Optional exception object
  /// - stackTrace: Optional stack trace
  /// - widgetId: Optional widget ID for widget-specific critical error logging
  /// - context: Optional context for the message
  /// - type: Optional type of message
  /// - severity: Optional severity of message
  void critical(
      {required String message,
      Object? error,
      StackTrace? stackTrace,
      String? widgetId,
      String? context,
      AppBoxKitErrorType? type,
      AppBoxKitErrorSeverity? severity}) {
    _logWithTalker(LogLevel.critical, message,
        error: error,
        stackTrace: stackTrace,
        context: context,
        type: type,
        severity: severity);

    // If widgetId is provided, also log this as an event and set error state
    if (widgetId != null) {
      setWidgetError(
          widgetId: widgetId,
          message: message,
          error: error,
          stackTrace: stackTrace,
          context: context,
          type: type,
          severity: severity);
    }
  }

  /// Directly handle an exception
  ///
  /// Parameters:
  /// - exception: The exception object to handle
  /// - stackTrace: Optional stack trace
  /// - message: Optional message providing more context
  /// - widgetId: Optional widget ID for widget-specific error handling
  /// - context: Optional context for the message
  /// - type: Optional type of message
  /// - severity: Optional severity of message
  void handle(
      {required Object exception,
      StackTrace? stackTrace,
      String? message,
      String? widgetId,
      String? context,
      AppBoxKitErrorType? type,
      AppBoxKitErrorSeverity? severity}) {
    // Format the message
    final String formattedMessage = _formatMessageWithContext(
        originalMessage: message ?? 'An error occurred',
        context: context,
        type: type,
        severity: severity);

    // Log to talker
    _talker.handle(
        exception, stackTrace ?? StackTrace.current, formattedMessage);

    // If widgetId is provided, set widget-specific error state
    if (widgetId != null) {
      setWidgetError(
          widgetId: widgetId,
          message: message ?? exception.toString(),
          error: exception,
          stackTrace: stackTrace,
          context: context,
          type: type,
          severity: severity);
    }
  }

  /// Get all logs history
  List<TalkerData> get history => _talker.history;

  /// Clean logs history
  void cleanHistory() {
    _talker.cleanHistory();
    _allErrorsSubject$.add([]);
    _unreadCountSubject$.add(0);
    notifyListeners();
  }

  void dispose() {
    _latestErrorSubject$.close();
    _allErrorsSubject$.close();
    _unreadCountSubject$.close();
    _widgetErrorsSubject$.close();
    _loadingWidgetsSubject$.close();
    _widgetEventsSubject$.close();
    _widgetEventCountsSubject$.close();
  }
}
