import 'dart:async';

import '../appbox_kit_locator.dart';
import '../services/error/appbox_kit_error_service.dart';
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:rxdart/rxdart.dart';

/// Enum for checkbox position
enum AppBoxKitSelectablePosition {
  topLeft,
  topCenter,
  topRight,
  center,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

/// Configuration for AppBoxKitSelectable
class AppBoxKitSelectableOptions {
  /// Border color when selected
  final Color? borderColor;

  /// Border width when selected
  final double borderWidth;

  /// Border radius
  final BorderRadius? borderRadius;

  /// Position of the checkbox
  final AppBoxKitSelectablePosition position;

  /// Callback when selection changes
  final Function(bool)? onSelectionChanged;

  /// Constructor with default values
  const AppBoxKitSelectableOptions({
    this.borderColor,
    this.borderWidth = 3.0,
    this.borderRadius,
    this.position = AppBoxKitSelectablePosition.topRight,
    this.onSelectionChanged,
  });
}

/// Service to manage selectable widgets state
class AppBoxKitSelectableService with ListenableServiceMixin {
  static const String widgetId = 'kit_selectable_service';

  AppBoxKitSelectableService() {
    // Setup stream listener for reactive updates
    _selectedIDs$.listen((_) => notifyListeners());
  }

  final _errorService = appBoxKitLocator<AppBoxKitErrorService>();

  // Stream for currently selected widget IDs
  final _selectedIDs$ = BehaviorSubject<Set<String>>.seeded({});

  /// Get the stream of selected IDs
  Stream<Set<String>> get selectedIDs$ => _selectedIDs$.stream;

  /// Get the current selected IDs
  Set<String> get selectedIDs => _selectedIDs$.value;

  /// Toggle selection state for a widget
  void toggleSelection(String widgetId, bool isSelected) {
    try {
      final currentSelections = Set<String>.from(_selectedIDs$.value);

      if (isSelected) {
        currentSelections.add(widgetId);
      } else {
        currentSelections.remove(widgetId);
      }

      _selectedIDs$.add(currentSelections);
    } catch (e, stackTrace) {
      _errorService.handle(
        exception: e,
        stackTrace: stackTrace,
        message: 'Failed to toggle selection',
        widgetId: widgetId,
      );
    }
  }

  /// Clear all selections
  void clearSelections() {
    _selectedIDs$.add({});
  }

  /// Select or deselect all registered widgets
  ///
  /// If [select] is true, selects all widgets. If false, deselects all widgets.
  /// If [select] is null, it toggles the current state (selects all if none are
  /// selected, deselects all if at least one is selected).
  void toggleSelectAll(Set<String> widgetIds, {bool? select}) {
    try {
      final currentSelections = _selectedIDs$.value;
      final bool allSelected =
          widgetIds.every((id) => currentSelections.contains(id));

      // Determine the new selection state
      final shouldSelect = select ?? !allSelected;

      final newSelections = Set<String>.from(currentSelections);

      if (shouldSelect) {
        newSelections.addAll(widgetIds);
      } else {
        newSelections.removeAll(widgetIds);
      }

      _selectedIDs$.add(newSelections);
    } catch (e, stackTrace) {
      _errorService.handle(
        exception: e,
        stackTrace: stackTrace,
        message: 'Failed to toggle all selections',
        widgetId: widgetId,
      );
    }
  }

  /// Check if a widget is selected
  bool isSelected(String widgetId) {
    return _selectedIDs$.value.contains(widgetId);
  }

  /// Dispose resources
  void dispose() {
    _selectedIDs$.close();
  }
}

/// Extension method for making widgets selectable
extension AppBoxKitSelectableExtension on Widget {
  /// Make this widget selectable with a checkbox
  Widget withSelectable({
    required String id,
    AppBoxKitSelectableOptions options = const AppBoxKitSelectableOptions(),
  }) {
    return _KitSelectableWidget(
      id: id,
      options: options,
      child: this,
    );
  }
}

/// ViewModel for the selectable widget that follows Stacked architecture
class _KitSelectableViewModel extends ReactiveViewModel {
  static const String widgetId = 'kit_selectable_view_model';
  final _errorService = appBoxKitLocator<AppBoxKitErrorService>();
  final _selectableService = appBoxKitLocator<AppBoxKitSelectableService>();

  late String _id;
  late AppBoxKitSelectableOptions _options;
  StreamSubscription<Set<String>>? _selectionSubscription;

  // BehaviorSubject for local selection state
  final _isSelected$ = BehaviorSubject<bool>.seeded(false);
  bool get isSelected => _isSelected$.value;

  // BehaviorSubject for checkbox visibility (delayed for staggered effect)
  final _showCheckbox$ = BehaviorSubject<bool>.seeded(false);
  bool get showCheckbox => _showCheckbox$.value;

  @override
  List<ListenableServiceMixin> get listenableServices => [_selectableService];

  void init(String id, AppBoxKitSelectableOptions options) {
    _id = id;
    _options = options;
    _setupStreams();
  }

  void _setupStreams() {
    try {
      // Initialize from service state
      final initialSelected = _selectableService.isSelected(_id);
      _isSelected$.add(initialSelected);
      _showCheckbox$.add(initialSelected);

      // Cancel any existing subscription
      _selectionSubscription?.cancel();

      // Listen to changes from service
      _selectionSubscription =
          _selectableService.selectedIDs$.listen((selectedIds) {
        final isSelected = selectedIds.contains(_id);
        if (_isSelected$.value != isSelected) {
          _isSelected$.add(isSelected);

          // Staggered effect - delay checkbox visibility change
          if (isSelected) {
            // If selected, show checkbox after delay
            Future.delayed(const Duration(milliseconds: 120), () {
              _showCheckbox$.add(true);
              rebuildUi();
            });
          } else {
            // If deselected, hide checkbox immediately
            _showCheckbox$.add(false);
          }

          rebuildUi();
        }
      }, onError: (error, stackTrace) {
        _errorService.handle(
          exception: error,
          stackTrace: stackTrace,
          message: 'Error in selection subscription',
          widgetId: widgetId,
        );
      });
    } catch (e, stackTrace) {
      _errorService.handle(
        exception: e,
        stackTrace: stackTrace,
        message: 'Failed to setup selection streams',
        widgetId: widgetId,
      );
    }
  }

  void toggleSelection() {
    try {
      final newState = !_isSelected$.value;
      _isSelected$.add(newState);

      // Update staggered state
      if (newState) {
        // Show border immediately, checkbox after delay
        Future.delayed(const Duration(milliseconds: 120), () {
          _showCheckbox$.add(true);
          rebuildUi();
        });
      } else {
        // Hide checkbox immediately
        _showCheckbox$.add(false);
      }

      _selectableService.toggleSelection(_id, newState);

      // Call the callback if provided
      _options.onSelectionChanged?.call(newState);
    } catch (e, stackTrace) {
      _errorService.handle(
        exception: e,
        stackTrace: stackTrace,
        message: 'Failed to toggle selection',
        widgetId: widgetId,
      );
    }
  }

  @override
  void dispose() {
    _selectionSubscription?.cancel();
    _isSelected$.close();
    _showCheckbox$.close();
    super.dispose();
  }
}

/// Widget that implements the selectable functionality using StackedView
class _KitSelectableWidget extends StackedView<_KitSelectableViewModel> {
  final Widget child;
  final String id;
  final AppBoxKitSelectableOptions options;

  const _KitSelectableWidget({
    required this.child,
    required this.id,
    required this.options,
  });

  @override
  Widget builder(
      BuildContext context, _KitSelectableViewModel viewModel, Widget? _) {
    final theme = Theme.of(context);
    final borderColor = options.borderColor ?? theme.colorScheme.onSurface;

    // Duration constants for staggered animation
    const borderDuration = Duration(milliseconds: 200);
    const checkboxDuration = Duration(milliseconds: 250);

    return GestureDetector(
      onLongPress: viewModel.toggleSelection,
      // Allow tapping to deselect when already selected
      onTap: viewModel.isSelected ? viewModel.toggleSelection : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The child widget with animated border decoration
          AnimatedContainer(
            duration: borderDuration,
            curve: Curves.easeOutCubic,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: viewModel.isSelected
                    ? Border.all(
                        color: borderColor,
                        width: options.borderWidth,
                      )
                    : null,
                borderRadius: options.borderRadius,
              ),
              position: DecorationPosition.foreground,
              child: child,
            ),
          ),

          // Only add checkbox to the tree when the widget is selected
          if (viewModel.showCheckbox)
            Positioned(
              left: _getLeftPosition(options.position),
              right: _getRightPosition(options.position),
              top: _getTopPosition(options.position),
              bottom: _getBottomPosition(options.position),
              child: AnimatedOpacity(
                opacity: 1.0, // Always fully visible when in the tree
                duration: checkboxDuration,
                curve: Curves.easeOutCubic,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.5, end: 1.0),
                  duration: checkboxDuration,
                  curve: Curves.easeOutBack,
                  builder: (context, scale, child) => Transform.scale(
                    scale: scale,
                    child: child,
                  ),
                  child: Checkbox(
                    checkColor: theme.colorScheme.onSurface,
                    value: true,
                    onChanged: (_) => viewModel.toggleSelection(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  _KitSelectableViewModel viewModelBuilder(BuildContext context) =>
      _KitSelectableViewModel();

  @override
  void onViewModelReady(_KitSelectableViewModel viewModel) =>
      viewModel.init(id, options);

  double? _getLeftPosition(AppBoxKitSelectablePosition position) {
    switch (position) {
      case AppBoxKitSelectablePosition.topLeft:
      case AppBoxKitSelectablePosition.bottomLeft:
        return 4;
      case AppBoxKitSelectablePosition.topCenter:
      case AppBoxKitSelectablePosition.center:
      case AppBoxKitSelectablePosition.bottomCenter:
        return 0;
      case AppBoxKitSelectablePosition.topRight:
      case AppBoxKitSelectablePosition.bottomRight:
        return null;
    }
  }

  double? _getRightPosition(AppBoxKitSelectablePosition position) {
    switch (position) {
      case AppBoxKitSelectablePosition.topRight:
      case AppBoxKitSelectablePosition.bottomRight:
        return 4;
      case AppBoxKitSelectablePosition.topCenter:
      case AppBoxKitSelectablePosition.center:
      case AppBoxKitSelectablePosition.bottomCenter:
        return 0;
      case AppBoxKitSelectablePosition.topLeft:
      case AppBoxKitSelectablePosition.bottomLeft:
        return null;
    }
  }

  double? _getTopPosition(AppBoxKitSelectablePosition position) {
    switch (position) {
      case AppBoxKitSelectablePosition.topLeft:
      case AppBoxKitSelectablePosition.topCenter:
      case AppBoxKitSelectablePosition.topRight:
        return 4;
      case AppBoxKitSelectablePosition.center:
        return 0;
      case AppBoxKitSelectablePosition.bottomLeft:
      case AppBoxKitSelectablePosition.bottomCenter:
      case AppBoxKitSelectablePosition.bottomRight:
        return null;
    }
  }

  double? _getBottomPosition(AppBoxKitSelectablePosition position) {
    switch (position) {
      case AppBoxKitSelectablePosition.bottomLeft:
      case AppBoxKitSelectablePosition.bottomCenter:
      case AppBoxKitSelectablePosition.bottomRight:
        return 4;
      case AppBoxKitSelectablePosition.center:
        return 0;
      case AppBoxKitSelectablePosition.topLeft:
      case AppBoxKitSelectablePosition.topCenter:
      case AppBoxKitSelectablePosition.topRight:
        return null;
    }
  }
}
