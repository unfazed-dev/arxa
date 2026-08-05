import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_components/showcase_components_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_components/showcase_components_viewmodel.dart';

/// Tablet reuses the mobile components surface (same rationale as the Motion
/// showcase — the demos are form-factor-independent).
class ShowcaseComponentsViewTablet
    extends ViewModelWidget<ShowcaseComponentsViewModel> {
  const ShowcaseComponentsViewTablet({super.key});

  @override
  Widget build(BuildContext context, ShowcaseComponentsViewModel viewModel) =>
      const ShowcaseComponentsViewMobile();
}
