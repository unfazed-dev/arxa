import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_motion/showcase_motion_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_motion/showcase_motion_viewmodel.dart';

/// Desktop reuses the mobile choreography surface — motion specs are
/// form-factor-independent (timeline fractions, not pixel timings).
class ShowcaseMotionViewDesktop
    extends ViewModelWidget<ShowcaseMotionViewModel> {
  const ShowcaseMotionViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseMotionViewModel viewModel) =>
      const ShowcaseMotionViewMobile();
}
