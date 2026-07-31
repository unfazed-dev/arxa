import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:stacked/stacked.dart';

import 'showcase_notes_shell_view.desktop.dart';
import 'showcase_notes_shell_view.tablet.dart';
import 'showcase_notes_shell_view.mobile.dart';
import 'showcase_notes_shell_viewmodel.dart';

class ShowcaseNotesShellView extends StackedView<ShowcaseNotesShellViewModel> {
  const ShowcaseNotesShellView({super.key});

  @override
  Widget builder(
    BuildContext context,
    ShowcaseNotesShellViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseNotesShellViewMobile(),
      tablet: (_) => const ShowcaseNotesShellViewTablet(),
      desktop: (_) => const ShowcaseNotesShellViewDesktop(),
    );
  }

  @override
  ShowcaseNotesShellViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      ShowcaseNotesShellViewModel();
}
