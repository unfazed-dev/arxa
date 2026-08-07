import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_components/showcase_components_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_components/showcase_components_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_components/showcase_components_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_components/showcase_components_viewmodel.dart';

/// Video-parity components showcase (ADR 0011) — one pushed surface proving
/// each wave-1/2 appbox_kit_ui_library capability: [AppBoxKitFrostedSurface], [AppBoxKitChip] +
/// [AppBoxKitChipCarousel], [AppBoxKitListSection] + [AppBoxKitListTile], [AppBoxKitDrawer]
/// (glassPeek), [appBoxKitShowNativeDialog], [appBoxKitShowNativeSheet]'s frosted body,
/// [AppBoxKitNativeInputBar], and the center toast via [AppBoxKitNotificationService].
class ShowcaseComponentsView extends StackedView<ShowcaseComponentsViewModel> {
  const ShowcaseComponentsView({super.key});

  @override
  Widget builder(
    BuildContext context,
    ShowcaseComponentsViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseComponentsViewMobile(),
      tablet: (_) => const ShowcaseComponentsViewTablet(),
      desktop: (_) => const ShowcaseComponentsViewDesktop(),
    );
  }

  @override
  ShowcaseComponentsViewModel viewModelBuilder(BuildContext context) =>
      ShowcaseComponentsViewModel();
}
