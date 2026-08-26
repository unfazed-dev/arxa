/// A widget is a reusable piece of a view — it composes the kit's primitives
/// and holds no business logic; the view that places it owns the data.
///
/// This is the user interface for a progress-and-loading demo card. It shows
/// a determinate linear bar, an indeterminate circular spinner, and the kit's
/// loading indicator side by side inside a glass card.
///
/// Idle thermal discipline: the indeterminate demos spin for [_demoWindow]
/// on appearance, then freeze (TickerMode off); a Replay button restarts the
/// window. A perpetual spinner schedules a frame every vsync, and on the
/// hybrid-composition glass tier (iOS 26, 120 Hz) every frame recomposites
/// the whole scene of native views — a static gallery surface has no business
/// paying that while the phone sits idle. The demo shows the animation, then
/// stops it; the determinate bar is static and needs no gating.
///
/// Requirements:
/// 1. [Progress demo]
/// Displays linear, circular, and indicator loading states.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_home_widgets/showcase_progress_loading_card_widget.dart
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';

class ShowcaseProgressLoadingCardWidget extends StatefulWidget {
  const ShowcaseProgressLoadingCardWidget({super.key});

  @override
  State<ShowcaseProgressLoadingCardWidget> createState() =>
      _ShowcaseProgressLoadingCardWidgetState();
}

class _ShowcaseProgressLoadingCardWidgetState
    extends State<ShowcaseProgressLoadingCardWidget> {
  /// How long the indeterminate demos spin before going idle.
  static const Duration _demoWindow = Duration(seconds: 5);

  bool _spinning = true;

  // A one-shot view-local demo timer — not an async op, so the
  // ArxaKitAction convention (no bare Timer debounces) does not apply.
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _armIdleTimer();
  }

  void _armIdleTimer() {
    _idleTimer = Timer(_demoWindow, () {
      if (mounted) setState(() => _spinning = false);
    });
  }

  void _replay() {
    _idleTimer?.cancel();
    setState(() => _spinning = true);
    _armIdleTimer();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Edge treatment belongs to the enclosing ArxaKitEdgeAwareListView. The
    // old "content-only" carve-out here is exactly why the buttons/segmented
    // demos above went untreated.
    return ArxaKitGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ShowcaseSectionLabelWidget('Progress & loading'),
              const Spacer(),
              if (!_spinning)
                ArxaKitNativeButton(
                  style: ArxaKitButtonStyle.plain,
                  label: 'Replay',
                  onPressed: _replay,
                ),
            ],
          ),
          arxaKitVerticalSpaceSmall,
          Row(
            children: [
              Expanded(
                // ponytail: determinate 0.6 shows the fill; indeterminate
                // circular animates; loading indicator is the 3rd tier.
                child: ArxaKitNativeProgress.linear(value: 0.6),
              ),
              arxaKitHorizontalSpaceSmall,
              // The perpetual animators live under one TickerMode: muted they
              // hold their last frame and schedule nothing.
              TickerMode(
                enabled: _spinning,
                child: Row(
                  children: [
                    ArxaKitNativeProgress.circular(), // factory, not const-able
                    arxaKitHorizontalSpaceSmall,
                    const ArxaKitNativeLoadingIndicator(size: 32),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
