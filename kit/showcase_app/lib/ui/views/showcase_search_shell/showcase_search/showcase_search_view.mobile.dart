import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_search_widgets/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_viewmodel.dart';

class ShowcaseSearchViewMobile
    extends ViewModelWidget<ShowcaseSearchViewModel> {
  const ShowcaseSearchViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseSearchViewModel viewModel) {
    return ListView(
      padding:
          const EdgeInsets.symmetric(horizontal: kSize16, vertical: kSize16),
      children: [
        // No controller: the bar manages its own field, and the submit value
        // arrives via onSubmitted — the VM holds no TextEditingController
        // (never-prefill query → onChanged/onSubmitted, per the forms playbook).
        KitNativeSearchBar(
          hint: 'Search places, cafes, parks…',
          onSubmitted: (s) => locator<KitNotificationService>()
              .show('Search: $s', context: context),
        ),
        verticalSpaceMedium,
        ShowcaseSearchFilterCardWidget(viewModel: viewModel),
        verticalSpaceMedium,
        ShowcaseSearchOptionsSectionWidget(viewModel: viewModel),
      ],
    );
  }
}
