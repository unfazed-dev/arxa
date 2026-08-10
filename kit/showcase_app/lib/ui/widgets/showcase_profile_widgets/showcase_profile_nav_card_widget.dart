/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for a gallery link card — a section-labeled card
/// with a single button that pushes a named route. The profile tab uses it for
/// its Motion, Maps, and Components showcase links.
///
/// Requirements:
/// 1. [Gallery link] — view-the-profile-surface
/// A card with a button that pushes a named showcase route.
///
/// Relationships: a self-contained presentational widget — no viewmodel
/// binding; the route name is passed in.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_profile_nav_card_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';

class ShowcaseProfileNavCardWidget extends StatelessWidget {
  const ShowcaseProfileNavCardWidget({
    required this.title,
    required this.buttonLabel,
    required this.routeName,
    super.key,
  });

  final String title;
  final String buttonLabel;
  final String routeName;

  @override
  Widget build(BuildContext context) {
    return AppBoxKitGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShowcaseSectionLabelWidget(title),
          appBoxKitVerticalSpaceSmall,
          SizedBox(
            height: abxButtonHeightMedium,
            child: AppBoxKitNativeButton(
              label: buttonLabel,
              onPressed: () => context.router.pushNamed(routeName),
            ),
          ),
        ],
      ),
    );
    // Edge treatment belongs to the enclosing AppBoxKitEdgeAwareListView.
  }
}
