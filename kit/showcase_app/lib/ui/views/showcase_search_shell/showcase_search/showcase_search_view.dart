import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_viewmodel.dart';

/// Search-tab showcase: [AppBoxKitNativeSearchBar], [AppBoxKitNativeSlider],
/// [AppBoxKitNativeRangeSlider], [AppBoxKitNativeSwitch] — all state-driven so the native
/// controls actually respond.
class ShowcaseSearchView extends StackedView<ShowcaseSearchViewModel> {
  const ShowcaseSearchView({super.key});

  @override
  ShowcaseSearchViewModel viewModelBuilder(BuildContext context) =>
      ShowcaseSearchViewModel();

  @override
  Widget builder(
    BuildContext context,
    ShowcaseSearchViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseSearchViewMobile(),
      tablet: (_) => const ShowcaseSearchViewTablet(),
      desktop: (_) => const ShowcaseSearchViewDesktop(),
    );
  }
}
