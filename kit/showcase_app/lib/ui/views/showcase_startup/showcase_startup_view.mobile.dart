import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:appbox_kit_showcase_app/ui/common/ui_helpers.dart';

import 'showcase_startup_viewmodel.dart';

class ShowcaseStartupViewMobile
    extends ViewModelWidget<ShowcaseStartupViewModel> {
  const ShowcaseStartupViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseStartupViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'KIT SHOWCASE',
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Loading ...', style: TextStyle(fontSize: 16)),
                horizontalSpaceSmall,
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 6),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
