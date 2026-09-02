// Route pushes are instant: threads and screens appear in place — no
// slide-in, no fade, no parallax on the outgoing page. The conversation's
// back chevron is the way back (the OS edge-swipe-back rides the removed
// transition and goes with it). Modal sheets and dialogs keep their own
// idiomatic entrances.
import 'package:flutter/material.dart';

/// Theme-level page transitions: every platform pushes with zero
/// entrance animation.
const arxaNoPushTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.iOS: NoEntranceTransitionsBuilder(),
    TargetPlatform.android: NoEntranceTransitionsBuilder(),
    TargetPlatform.macOS: NoEntranceTransitionsBuilder(),
    TargetPlatform.windows: NoEntranceTransitionsBuilder(),
    TargetPlatform.linux: NoEntranceTransitionsBuilder(),
    TargetPlatform.fuchsia: NoEntranceTransitionsBuilder(),
  },
);

/// A [PageTransitionsBuilder] that mounts the pushed route untouched —
/// the only page transition that is literally no transition.
class NoEntranceTransitionsBuilder extends PageTransitionsBuilder {
  const NoEntranceTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}
