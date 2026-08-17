/// A widget is a reusable UI piece composed by views. It receives data via
/// constructor params or [AppBoxKitStreamBuilder] bindings and renders its
/// slice of the surface — it holds no business logic and never decides when
/// an action runs.
///
/// This is the user interface for a pinned search-bar sliver that sticks under
/// the app bar while the list scrolls beneath it.
///
/// Requirements:
/// 1. [Pinned header]
/// Wraps a child in a SliverPersistentHeader that pins to the top of the scroll.
///
/// Relationships:
///
/// Standalone — no viewmodel binding.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_notes_widgets/showcase_notes_pinned_search_bar_widget.dart
library;

import 'package:flutter/material.dart';

class ShowcaseNotesPinnedSearchBarWidget extends StatelessWidget {
  const ShowcaseNotesPinnedSearchBarWidget({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _PinnedSearchDelegate(child: child),
    );
  }
}

class _PinnedSearchDelegate extends SliverPersistentHeaderDelegate {
  _PinnedSearchDelegate({required this.child});
  final Widget child;

  static const _min = 56.0;
  static const _max = 72.0;

  @override
  double get minExtent => _min;
  @override
  double get maxExtent => _max;
  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    // No backing panel: the child is the native Liquid Glass search bar (a
    // pinned sliver header counts as chrome — docs/liquid-glass-allowlist.md
    // class 1), and iOS 26 floats search chrome OVER the content its glass
    // samples. An opaque Flutter slab behind it defeated the glass and read
    // as a hard cut band across the scroll (device-observed seam).
    return SizedBox(height: _max, child: child);
  }

  @override
  bool shouldRebuild(_PinnedSearchDelegate oldDelegate) =>
      child != oldDelegate.child;
}
