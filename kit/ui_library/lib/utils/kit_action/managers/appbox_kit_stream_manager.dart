import 'package:appbox_kit_core/appbox_kit_locator.dart';
import 'package:appbox_kit_core/services/error/appbox_kit_error_service.dart';
import '../appbox_kit_action_config.dart';
import 'package:rxdart/rxdart.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AppBoxKitAction v2.0 - AppBoxKitStreamManager
// ═══════════════════════════════════════════════════════════════════════════════
//
// 📖 Technical Specification: docs/kit_action_technical_specification.md
//    - Section 4.2: Component Responsibilities - AppBoxKitStreamManager (lines 352-358)
//    - Section 5.2: Reactive Streams (lines 1095-1136)
//    - Section 9.1: Memory Management
//
// Manages reactive stream lifecycle with automatic cleanup.
// ═══════════════════════════════════════════════════════════════════════════════

/// Manages reactive stream lifecycle and auto-cleanup
/// Tracks active subjects by widgetId and provides cleanup mechanisms
class AppBoxKitStreamManager<T> {
  final AppBoxKitActionConfig<T> config;
  static final _errorService = appBoxKitLocator<AppBoxKitErrorService>();

  // Track active subjects by widgetId
  static final Map<String, List<BehaviorSubject>> _activeSubjects = {};

  AppBoxKitStreamManager(this.config);

  /// Create a BehaviorSubject with initial value and auto-cleanup support
  ///
  /// The subject is tracked by widgetId for later disposal.
  /// If autoCleanupTrigger is configured, the subject will be automatically closed
  /// when the trigger stream emits.
  BehaviorSubject<T> createSubject() {
    final subject = BehaviorSubject<T>();

    // Add initial value if provided
    if (config.streamInitialValue != null) {
      subject.add(config.streamInitialValue as T);
    }

    // Track subject
    _activeSubjects.putIfAbsent(config.widgetId, () => []).add(subject);

    // Setup auto-cleanup if configured
    if (config.autoCleanupTrigger != null) {
      config.autoCleanupTrigger!.listen((_) {
        if (!subject.isClosed) {
          _errorService.info(
            message: 'Auto-closing reactive stream for ${config.widgetId}',
            widgetId: config.widgetId,
          );
          subject.close();
          _removeSubject(config.widgetId, subject);
        }
      });
    }

    return subject;
  }

  /// Dispose all subjects for a specific widget
  ///
  /// This should be called in the widget's dispose method to prevent memory leaks.
  static void disposeWidget(String widgetId) {
    final subjects = _activeSubjects[widgetId];
    if (subjects != null) {
      for (final subject in subjects) {
        if (!subject.isClosed) {
          subject.close();
        }
      }
      _activeSubjects.remove(widgetId);

      _errorService.info(
        message: 'Disposed ${subjects.length} reactive streams for $widgetId',
        widgetId: widgetId,
      );
    }
  }

  /// Remove a specific subject from tracking
  static void _removeSubject(String widgetId, BehaviorSubject subject) {
    final subjects = _activeSubjects[widgetId];
    if (subjects != null) {
      subjects.remove(subject);
      if (subjects.isEmpty) {
        _activeSubjects.remove(widgetId);
      }
    }
  }

  /// Get count of active subjects for a widget (for testing/debugging)
  static int getActiveSubjectCount(String widgetId) {
    return _activeSubjects[widgetId]?.length ?? 0;
  }

  /// Clear all tracked subjects (for testing)
  static void clearAllSubjects() {
    _activeSubjects.clear();
  }
}
