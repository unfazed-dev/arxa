import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_gallery_chrome/showcase_gallery_chrome_widget.dart';
import 'showcase_search_shell_viewmodel.dart';

class ShowcaseSearchShellViewMobile
    extends ViewModelWidget<ShowcaseSearchShellViewModel> {
  const ShowcaseSearchShellViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseSearchShellViewModel viewModel) {
    return const ShowcaseGalleryChromeWidget(child: NestedRouter());
  }
}
