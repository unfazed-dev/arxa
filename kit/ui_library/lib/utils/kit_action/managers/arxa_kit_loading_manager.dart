import 'package:arxa_kit_core/arxa_kit_locator.dart';
import 'package:arxa_kit_core/services/error/arxa_kit_error_service.dart';
import '../arxa_kit_action_config.dart';
import 'package:talker_flutter/talker_flutter.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ArxaKitAction v2.0 - ArxaKitLoadingManager
// ═══════════════════════════════════════════════════════════════════════════════
//
// 📖 Technical Specification: docs/kit_action_technical_specification.md
//    - Section 4.2: Component Responsibilities - ArxaKitLoadingManager (lines 323-327)
//    - Section 5.2: Loading State Management (lines 669-698)
//
// Manages loading states with setBusy/setBusyForObject callbacks.
// ═══════════════════════════════════════════════════════════════════════════════

/// Manages loading state for operations
/// Handles setBusy and setBusyForObject callbacks with error logging
/// Includes state tracking and disposal error handling for navigation flows
class ArxaKitLoadingManager<T> {
  final ArxaKitActionConfig<T> config;
  static final _errorService = arxaKitLocator<ArxaKitErrorService>();
  static final _talker = arxaKitLocator<Talker>();

  /// Tracks whether loading has been cleared to prevent redundant calls
  bool _hasCleared = false;

  ArxaKitLoadingManager(this.config);

  /// Start loading state
  /// Sets loading state to true using the configured callback
  /// Resets the _hasCleared flag for new operation
  void start() {
    // Reset cleared flag for new operation
    _hasCleared = false;

    if (config.debugMode) {
      _talker.debug(
          '[ArxaKitAction] 🔄 ArxaKitLoadingManager: Starting loading for ${config.widgetId}');
    }

    try {
      if (config.busyObject != null &&
          config.setBusyForObjectCallback != null) {
        if (config.debugMode) {
          _talker.debug(
              '[ArxaKitAction] 📦 Setting busy for object: ${config.busyObject} (${config.widgetId})');
        }
        config.setBusyForObjectCallback!(config.busyObject!, true);
      } else if (config.setBusyCallback != null) {
        if (config.debugMode) {
          _talker.debug(
              '[ArxaKitAction] 🔄 Setting global busy state (${config.widgetId})');
        }
        config.setBusyCallback!(true);
      }

      // Call granular UI state callback if provided
      if (config.onLoadingStateCallback != null) {
        if (config.debugMode) {
          _talker.debug(
              '[ArxaKitAction] 📢 Calling onLoadingState callback (${config.widgetId})');
        }
        config.onLoadingStateCallback!(true, config.loadingSnackbarMessage);
      }
    } catch (e, s) {
      if (config.debugMode) {
        _talker.error(
            '[ArxaKitAction] ⚠️ ArxaKitLoadingManager error in start() (${config.widgetId})',
            e,
            s);
      }
      _errorService.warning(
        error: e,
        stackTrace: s,
        message: 'Failed to set loading state to true',
        widgetId: config.widgetId,
      );
    }
  }

  /// Stop loading state
  /// Sets loading state to false using the configured callback
  /// Includes defense-in-depth:
  /// - Skips redundant calls if already cleared
  /// - Catches view disposal errors for navigation flows
  /// - Marks as cleared to prevent double setBusy(false)
  void stop() {
    // Skip if already cleared (efficiency layer)
    if (_hasCleared) {
      if (config.debugMode) {
        _talker.debug(
            '[ArxaKitAction] ⏭️ ArxaKitLoadingManager: Already cleared for ${config.widgetId}, skipping');
      }
      return;
    }

    if (config.debugMode) {
      _talker.debug(
          '[ArxaKitAction] ✅ ArxaKitLoadingManager: Stopping loading for ${config.widgetId}');
    }

    try {
      if (config.busyObject != null &&
          config.setBusyForObjectCallback != null) {
        if (config.debugMode) {
          _talker.debug(
              '[ArxaKitAction] 📦 Clearing busy for object: ${config.busyObject} (${config.widgetId})');
        }
        config.setBusyForObjectCallback!(config.busyObject!, false);
      } else if (config.setBusyCallback != null) {
        if (config.debugMode) {
          _talker.debug(
              '[ArxaKitAction] ✅ Clearing global busy state (${config.widgetId})');
        }
        config.setBusyCallback!(false);
      }

      // Call granular UI state callback if provided
      if (config.onLoadingStateCallback != null) {
        if (config.debugMode) {
          _talker.debug(
              '[ArxaKitAction] 📢 Calling onLoadingState callback with false (${config.widgetId})');
        }
        config.onLoadingStateCallback!(false, null);
      }

      // Mark as cleared after successful clear
      _hasCleared = true;
    } catch (e, s) {
      // Check if this is a view disposal error (reactive layer)
      final errorString = e.toString();
      final isDisposalError = errorString.contains('disposed') ||
          errorString
              .contains('A ChangeNotifier was used after being disposed') ||
          errorString.contains('Null check operator used on a null value');

      if (isDisposalError) {
        // View disposed - this is expected for navigation flows
        if (config.debugMode) {
          _talker.debug(
              '[ArxaKitAction] 🔄 ArxaKitLoadingManager: View disposed for ${config.widgetId}, skipping cleanup');
        }
        // Still mark as cleared to prevent retries
        _hasCleared = true;
      } else {
        // Unexpected error - log it
        if (config.debugMode) {
          _talker.error(
              '[ArxaKitAction] ⚠️ ArxaKitLoadingManager error in stop() (${config.widgetId})',
              e,
              s);
        }
        _errorService.warning(
          error: e,
          stackTrace: s,
          message: 'Failed to set loading state to false',
          widgetId: config.widgetId,
        );
      }
    }
  }
}
