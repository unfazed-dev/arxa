import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_maps/showcase_maps_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_maps/showcase_maps_viewmodel.dart';

/// Desktop reuses the mobile surface — the map fills any form factor.
class ShowcaseMapsViewDesktop extends ViewModelWidget<ShowcaseMapsViewModel> {
  const ShowcaseMapsViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseMapsViewModel viewModel) =>
      const ShowcaseMapsViewMobile();
}
