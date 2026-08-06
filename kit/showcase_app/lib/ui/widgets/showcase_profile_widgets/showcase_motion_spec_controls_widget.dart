import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_motion/showcase_motion_viewmodel.dart';

/// Spec presets segmented control plus the motion master switch, bound to
/// the viewmodel's preset/enabled state.
class ShowcaseMotionSpecControlsWidget extends StatelessWidget {
  const ShowcaseMotionSpecControlsWidget({required this.viewModel, super.key});

  final ShowcaseMotionViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppBoxKitNativeSegmentedControl(
          segments: ShowcaseMotionViewModel.presetLabels,
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
