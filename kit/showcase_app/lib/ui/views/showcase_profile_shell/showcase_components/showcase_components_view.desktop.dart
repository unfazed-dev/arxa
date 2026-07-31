import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_components_view.mobile.dart';
import 'showcase_components_viewmodel.dart';

/// Desktop reuses the mobile components surface (same rationale as the
/// Motion showcase — the demos are form-factor-independent).
class ShowcaseComponentsViewDesktop
    extends ViewModelWidget<ShowcaseComponentsViewModel> {
  const ShowcaseComponentsViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseComponentsViewModel viewModel) =>
      const ShowcaseComponentsViewMobile();
}
