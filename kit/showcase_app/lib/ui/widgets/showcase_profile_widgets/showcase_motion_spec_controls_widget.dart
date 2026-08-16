/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for the motion spec controls — the segmented
/// control that swaps spec presets and the switch that flips motion enabled.
///
/// Requirements:
/// 1. [Spec presets] — view-the-motion-demo
/// A segmented control swaps the motion spec preset.
/// 2. [Master switch] — view-the-motion-demo
/// A switch flips motion enabled.
///
/// Relationships:
///
///    ┌─────────────────────────────┐
///    │ motion spec controls widget │
///    └─────────────────────────────┘
///         ACT ▼        ▲ STRM
///         [1-2]        [1-2]
///         ┌──────────────────┐
///         │ motion viewmodel │
///         └──────────────────┘
///      ════════ abxAction ════════
///
///   streams (STRM)            actions (ACT)
///     1. presetIndex            1. setPreset
///     2. enabled                2. setEnabled
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_motion_spec_controls_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/enums/showcase_profile_enums/enums.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_motion/showcase_motion_viewmodel.dart';

class ShowcaseMotionSpecControlsWidget extends StatelessWidget {
  const ShowcaseMotionSpecControlsWidget({required this.viewModel, super.key});

  final ShowcaseMotionViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppBoxKitNativeSegmentedControl(
          segments: [
            for (final preset in ShowcaseMotionPreset.values) preset.label
          ],
          selectedIndex: viewModel.presetIndex,
          onChanged: viewModel.setPreset,
        ),
        appBoxKitVerticalSpaceSmall,
        Row(
          children: [
            Expanded(
              child: Text(
                'Motion enabled',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            AppBoxKitNativeSwitch(
              value: viewModel.enabled,
              onChanged: viewModel.setEnabled,
              semanticLabel: 'Motion enabled',
            ),
          ],
        ),
      ],
    );
  }
}
