import 'dart:async';
import 'dart:ui';

import 'package:flutter_animate/flutter_animate.dart';
import 'package:appbox_kit_core/kit_locator.dart';
import 'package:appbox_kit_core/common/kit_app_constants.dart';
import 'package:appbox_kit_core/enums/kit_app_common_enum.dart';
import 'package:appbox_kit_core/services/error/kit_error_service.dart';
import 'package:ui_library/utils/kit_action/kit_action.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'package:stacked/stacked.dart';

extension KitOverlayExtension on Widget {
  Widget withOverlay({
    required String id,
    KitOverlayOptions options = const KitOverlayOptions(),
    Widget? overlayChild,
  }) {
    return _KitOverlayWidget(
      id: id,
      options: options,
      overlayChild: overlayChild,
      child: this,
    );
  }
}

class KitOverlayService with ListenableServiceMixin {
  static const String widgetId = 'kit_overlay_service';

  final _openOverlays$ = BehaviorSubject<Set<String>>.seeded({});

  Stream<Set<String>> get openOverlays$ => _openOverlays$.stream;
  Set<String> get openOverlays => _openOverlays$.value;

  void openOverlay(String id) {
    KitAction.run<void>(
      operation: () {
        final currentOverlays = Set<String>.from(_openOverlays$.value);
        currentOverlays.add(id);
        _openOverlays$.add(currentOverlays);
      },
      widgetId: widgetId,
    ).withErrorFallback('Failed to open overlay').execute();
  }

  void closeOverlay(String id) {
    KitAction.run<void>(
      operation: () {
        final currentOverlays = Set<String>.from(_openOverlays$.value);
        currentOverlays.remove(id);
        _openOverlays$.add(currentOverlays);
      },
      widgetId: widgetId,
    ).withErrorFallback('Failed to close overlay').execute();
  }

  void toggleOverlay(String id) {
    KitAction.run<void>(
      operation: () {
        final currentOverlays = Set<String>.from(_openOverlays$.value);
        if (currentOverlays.contains(id)) {
          currentOverlays.remove(id);
        } else {
          currentOverlays.add(id);
        }
        _openOverlays$.add(currentOverlays);
      },
      widgetId: widgetId,
    ).withErrorFallback('Failed to toggle overlay').execute();
  }

  bool isOverlayOpen(String id) {
    return _openOverlays$.value.contains(id);
  }

  void closeAllOverlays() {
    _openOverlays$.add({});
  }

  void dispose() {
    _openOverlays$.close();
  }
}

class _KitOverlayViewModel extends ReactiveViewModel {
  static const String widgetId = 'kit_overlay_view_model';
  final _errorService = locator<KitErrorService>();
  final _overlayService = locator<KitOverlayService>();

  String _id = '';
  KitOverlayOptions _options = const KitOverlayOptions();

  final _animatingOut$ = BehaviorSubject<bool>.seeded(false);
  bool get animatingOut => _animatingOut$.value;

  final _visibleInWidget$ = BehaviorSubject<bool>.seeded(false);
  bool get visibleInWidget => _visibleInWidget$.value;

  // Use CompositeSubscription from RxDart for proper subscription management
  final _subscriptions = CompositeSubscription();

  final _isOpen$ = BehaviorSubject<bool>.seeded(false);
  bool get isOpen => _isOpen$.value;

  @override
  List<ListenableServiceMixin> get listenableServices => [_overlayService];

  void init(String id, KitOverlayOptions options) {
    _id = id;
    _options = options;
    _setupStreams();

    // Set up automatic UI updates based on subject changes
    KitAction.watch(
      widgetId: widgetId,
      subjects: [
        _isOpen$,
        _animatingOut$,
        _visibleInWidget$,
      ],
      callback: rebuildUi,
      errorMessage: 'Error in overlay subject listener',
    );
  }

  void _setupStreams() {
    KitAction.run<void>(
      operation: () {
        final isServiceOpen = _overlayService.isOverlayOpen(_id);
        _isOpen$.add(isServiceOpen);
        _animatingOut$.add(false);
        _visibleInWidget$.add(isServiceOpen);

        // Use proper RxDart pattern with CompositeSubscription
        // Cancel any existing subscriptions first
        _subscriptions.clear();

        // Add new subscription to CompositeSubscription for proper management
        _subscriptions.add(_overlayService.openOverlays$.listen(
          (openOverlays) {
            final isOpen = openOverlays.contains(_id);

            if (_isOpen$.value != isOpen) {
              if (!isOpen && _isOpen$.value) {
                _handleExitAnimation();
              } else {
                _isOpen$.add(isOpen);
                _animatingOut$.add(false);
                _visibleInWidget$.add(true);
              }
              if (isOpen) {
                _options.onOpened?.call();
              } else {
                _options.onClosed?.call();
              }
            }
          },
          onError: (error, stackTrace) {
            _errorService.handle(
              exception: error,
              stackTrace: stackTrace,
              message: 'Error in overlay subscription',
              widgetId: widgetId,
            );
          },
        ));
      },
      widgetId: widgetId,
    ).withErrorFallback('Failed to set up overlay streams').execute();
  }

  void _handleExitAnimation() {
    KitAction.run<bool>(
      operation: () {
        _animatingOut$.add(true);
        _isOpen$.add(false);
        _visibleInWidget$.add(true);

        // Cancel any existing animation timer subscriptions
        // We don't need to store references to individual subscriptions
        // when using CompositeSubscription pattern

        // Create and add the delayed timer subscription to CompositeSubscription
        final animationSub = Stream.fromFuture(
                Future.delayed(_options.animationDuration.duration))
            .listen((_) {
          _animatingOut$.add(false);
          _visibleInWidget$.add(false);
          rebuildUi(); // Explicitly call rebuildUi for state changes
        }, onError: (error, stackTrace) {
          _errorService.handle(
            exception: error,
            stackTrace: stackTrace,
            message: 'Error in animation timer',
            widgetId: widgetId,
          );
        });

        // Add to CompositeSubscription for proper RxDart subscription management
        _subscriptions.add(animationSub);

        return true;
      },
      widgetId: widgetId,
    )
        .withErrorFallback('Failed to handle exit animation', fallback: false)
        .execute();
  }

  void toggleOverlay() {
    KitAction.run<void>(
      operation: () => _overlayService.toggleOverlay(_id),
      widgetId: widgetId,
    ).withErrorFallback('Failed to toggle overlay in ViewModel').execute();
  }

  void openOverlay() {
    KitAction.run<void>(
      operation: () => _overlayService.openOverlay(_id),
      widgetId: widgetId,
    ).withErrorFallback('Failed to open overlay in ViewModel').execute();
  }

  void closeOverlay() {
    KitAction.run<void>(
      operation: () => _overlayService.closeOverlay(_id),
      widgetId: widgetId,
    ).withErrorFallback('Failed to close overlay in ViewModel').execute();
  }

  @override
  void dispose() {
    // First dispose the auto-managed subscriptions from KitAutoProcess.listener
    KitAction.dispose(widgetId: widgetId);
    if (!_subscriptions.isDisposed) {
      _subscriptions.dispose();
    }

    super.dispose();
  }
}

class _KitOverlayWidget extends StackedView<_KitOverlayViewModel> {
  final Widget child;
  final String id;
  final KitOverlayOptions options;
  final Widget? overlayChild;

  const _KitOverlayWidget({
    required this.child,
    required this.id,
    required this.options,
    this.overlayChild,
  });

  @override
  Widget builder(
      BuildContext context, _KitOverlayViewModel viewModel, Widget? _) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: options.animationDuration.duration,
              reverseDuration: options.animationDuration.duration,
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
              child: viewModel.visibleInWidget
                  ? (viewModel.isOpen || viewModel.animatingOut
                      ? Container(
                          key: const ValueKey('overlay-content'),
                          child: _buildOverlayContent(context, viewModel),
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('overlay-empty-visible')))
                  : const SizedBox.shrink(key: ValueKey('overlay-not-visible')),
            ),
          ),
          if (viewModel.visibleInWidget && options.showCloseControl)
            Positioned(
              left: _getLeftPosition(options.controlPosition),
              right: _getRightPosition(options.controlPosition),
              top: _getTopPosition(options.controlPosition),
              bottom: _getBottomPosition(options.controlPosition),
              child: AnimatedOpacity(
                opacity: viewModel.isOpen ? 1.0 : 0.0,
                duration: options.animationDuration.duration,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    begin: 0.9,
                    end: viewModel.isOpen ? 1.0 : 0.9,
                  ),
                  duration: options.animationDuration.duration,
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Transform.scale(
                    scale: value,
                    child: child,
                  ),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: ElevatedButton(
                      onPressed: () => viewModel.closeOverlay(),
                      child: const Icon(Icons.close),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverlayContent(
      BuildContext context, _KitOverlayViewModel viewModel) {
    final Color overlayColor = options.color ??
        Theme.of(context).colorScheme.surface.withValues(
            alpha: options.isTransparent ? options.transparencyLevel : 1.0);

    final Widget baseContent = Container(
      height: options.height,
      width: options.width,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: options.borderRadius,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: ClipRRect(
        borderRadius: options.borderRadius ?? BorderRadius.zero,
        child: Container(
          padding: options.padding,
          color: Colors.transparent,
          child: options.isBlurred
              ? BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: options.blurEffect == KitBlurEffect.custom
                        ? options.blurrinessLevelX
                        : options.blurEffect.sigma,
                    sigmaY: options.blurEffect == KitBlurEffect.custom
                        ? options.blurrinessLevelY
                        : options.blurEffect.sigma,
                  ),
                  child: Container(
                    color: overlayColor,
                    child: AnimatedOpacity(
                      opacity: viewModel.animatingOut ? 0.0 : 1.0,
                      duration: options.animationDuration.duration,
                      child: Center(
                        child: overlayChild ?? const SizedBox.shrink(),
                      ),
                    ),
                  ),
                )
              : Container(
                  color: overlayColor,
                  child: AnimatedOpacity(
                    opacity: viewModel.animatingOut ? 0.0 : 1.0,
                    duration: options.animationDuration.duration,
                    child: Center(
                      child: overlayChild ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
        ),
      ),
    );

    final Widget content = baseContent
        .animate()
        .fadeIn(
            duration: options.animationDuration.duration,
            curve: Curves.easeOutCubic)
        .scale(
          duration: options.animationDuration.duration,
          curve: Curves.easeOutCubic,
          begin: const Offset(0.95, 0.95),
          end: const Offset(1, 1),
        )
        .moveY(
          begin: 5,
          end: 0,
          duration: options.animationDuration.duration,
          curve: Curves.easeOutCubic,
        );

    return options.showCloseControl
        ? GestureDetector(
            onTap: () => viewModel.closeOverlay(),
            child: content,
          )
        : content;
  }

  @override
  _KitOverlayViewModel viewModelBuilder(BuildContext context) =>
      _KitOverlayViewModel();

  @override
  void onViewModelReady(_KitOverlayViewModel viewModel) =>
      viewModel.init(id, options);

  double? _getLeftPosition(KitOverlayControlPosition position) {
    switch (position) {
      case KitOverlayControlPosition.topLeft:
      case KitOverlayControlPosition.bottomLeft:
        return kPad12;
      case KitOverlayControlPosition.topCenter:
      case KitOverlayControlPosition.center:
      case KitOverlayControlPosition.bottomCenter:
        return 0;
      case KitOverlayControlPosition.topRight:
      case KitOverlayControlPosition.bottomRight:
        return null;
    }
  }

  double? _getRightPosition(KitOverlayControlPosition position) {
    switch (position) {
      case KitOverlayControlPosition.topRight:
      case KitOverlayControlPosition.bottomRight:
        return kPad12;
      case KitOverlayControlPosition.topCenter:
      case KitOverlayControlPosition.center:
      case KitOverlayControlPosition.bottomCenter:
        return 0;
      case KitOverlayControlPosition.topLeft:
      case KitOverlayControlPosition.bottomLeft:
        return null;
    }
  }

  double? _getTopPosition(KitOverlayControlPosition position) {
    switch (position) {
      case KitOverlayControlPosition.topLeft:
      case KitOverlayControlPosition.topCenter:
      case KitOverlayControlPosition.topRight:
        return kPad12;
      case KitOverlayControlPosition.center:
        return 0;
      case KitOverlayControlPosition.bottomLeft:
      case KitOverlayControlPosition.bottomCenter:
      case KitOverlayControlPosition.bottomRight:
        return null;
    }
  }

  double? _getBottomPosition(KitOverlayControlPosition position) {
    switch (position) {
      case KitOverlayControlPosition.bottomLeft:
      case KitOverlayControlPosition.bottomCenter:
      case KitOverlayControlPosition.bottomRight:
        return kPad12;
      case KitOverlayControlPosition.center:
        return 0;
      case KitOverlayControlPosition.topLeft:
      case KitOverlayControlPosition.topCenter:
      case KitOverlayControlPosition.topRight:
        return null;
    }
  }
}

class KitOverlayOptions {
  final bool isBlurred;
  final KitBlurEffect blurEffect;
  final double blurrinessLevelX;
  final double blurrinessLevelY;
  final bool isTransparent;
  final bool isOpaque;
  final double transparencyLevel;
  final Color? color;
  final double? height;
  final double? width;
  final bool showCloseControl;
  final KitOverlayControlPosition controlPosition;
  final EdgeInsets padding;
  final KitAppCommonDuration animationDuration;
  final VoidCallback? onOpened;
  final VoidCallback? onClosed;
  final BorderRadius? borderRadius;

  const KitOverlayOptions({
    this.isBlurred = true,
    this.blurEffect = KitBlurEffect.extraLight,
    this.blurrinessLevelX = 10.0,
    this.blurrinessLevelY = 10.0,
    this.isTransparent = true,
    this.isOpaque = false,
    this.transparencyLevel = 0.7,
    this.color,
    this.height,
    this.width,
    this.showCloseControl = true,
    this.controlPosition = KitOverlayControlPosition.topRight,
    this.padding = EdgeInsets.zero,
    this.animationDuration = KitAppCommonDuration.medium,
    this.onOpened,
    this.onClosed,
    this.borderRadius,
  });
}

enum KitOverlayControlPosition {
  topLeft,
  topCenter,
  topRight,
  center,
  bottomLeft,
  bottomCenter,
  bottomRight,
}
