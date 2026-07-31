import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_gallery_chrome/showcase_gallery_chrome.dart';
import 'showcase_home_shell_viewmodel.dart';

class ShowcaseHomeShellViewMobile
    extends ViewModelWidget<ShowcaseHomeShellViewModel> {
  const ShowcaseHomeShellViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseHomeShellViewModel viewModel) {
    return const ShowcaseGalleryChrome(child: NestedRouter());
  }
}
