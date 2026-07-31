import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_motion_view.mobile.dart';
import 'showcase_motion_viewmodel.dart';

/// Tablet reuses the mobile choreography surface — motion specs are
/// form-factor-independent (timeline fractions, not pixel timings).
class ShowcaseMotionViewTablet
    extends ViewModelWidget<ShowcaseMotionViewModel> {
  const ShowcaseMotionViewTablet({super.key});

  @override
  Widget build(BuildContext context, ShowcaseMotionViewModel viewModel) =>
      const ShowcaseMotionViewMobile();
}
