/// A widget is a reusable piece of a view — it composes the kit's primitives
/// and holds no business logic; the view that places it owns the data.
///
/// This is the user interface for the 404 page. It shows a large "404" and a
/// "PAGE NOT FOUND" message when the router can't match a route.
///
/// Requirements:
/// 1. [Unknown route]
/// Displays a 404 screen for unmatched routes.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_unknown_widgets/showcase_unknown_body_widget.dart
library;

import 'package:arxa_kit_showcase_app/ui/common/arxa_kit_ui_helpers.dart';
import 'package:flutter/material.dart';

class ShowcaseUnknownBodyWidget extends StatelessWidget {
  const ShowcaseUnknownBodyWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '404',
              style: TextStyle(
                fontSize: 80,
                fontWeight: FontWeight.w800,
                height: 0.95,
                letterSpacing: 20.0,
              ),
            ),
            arxaKitVerticalSpaceSmall,
            Text(
              'PAGE NOT FOUND',
              style: TextStyle(
                fontSize: 20,
                letterSpacing: 20.0,
                wordSpacing: 10.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
