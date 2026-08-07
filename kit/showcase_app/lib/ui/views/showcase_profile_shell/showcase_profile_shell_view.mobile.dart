import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_gallery_chrome/showcase_gallery_chrome_widget.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile_shell_viewmodel.dart';

class ShowcaseProfileShellViewMobile
    extends ViewModelWidget<ShowcaseProfileShellViewModel> {
  const ShowcaseProfileShellViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseProfileShellViewModel viewModel) {
    return const ShowcaseGalleryChromeWidget(child: NestedRouter());
  }
}
