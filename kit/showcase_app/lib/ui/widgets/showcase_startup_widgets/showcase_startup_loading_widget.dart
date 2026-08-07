/// A widget is a reusable piece of a view — it composes the kit's primitives
/// and holds no business logic; the view that places it owns the data.
///
/// This is the user interface for the startup loading screen. It shows the
/// app title and a spinner while the app initializes.
///
/// Requirements:
/// 1. [Startup loading]
/// Displays a branded loading screen during app startup.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_startup_widgets/showcase_startup_loading_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_showcase_app/ui/common/ui_helpers.dart';

class ShowcaseStartupLoadingWidget extends StatelessWidget {
  const ShowcaseStartupLoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
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
