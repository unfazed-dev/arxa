import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:stacked/stacked.dart';

import 'showcase_components_view.desktop.dart';
import 'showcase_components_view.tablet.dart';
import 'showcase_components_view.mobile.dart';
import 'showcase_components_viewmodel.dart';

/// Video-parity components showcase (ADR 0011) — one pushed surface proving
/// each wave-1/2 ui_library capability: [KitFrostedSurface], [KitChip] +
/// [KitChipCarousel], [KitListSection] + [KitListTile], [KitDrawer]
/// (glassPeek), [kitShowNativeDialog], [kitShowNativeSheet]'s frosted body,
/// [KitNativeInputBar], and the center toast via [KitNotificationService].
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
