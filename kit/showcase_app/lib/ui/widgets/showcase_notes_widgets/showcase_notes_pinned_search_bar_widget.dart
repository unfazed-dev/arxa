import 'package:flutter/material.dart';

/// Pinned search-bar sliver: sticks [child] under the app bar while the list
/// scrolls beneath it. Min height keeps the bar tappable when collapsed; max
/// height gives it breathing room at the top of the scroll.
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
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SizedBox(height: _max, child: child),
    );
  }

  @override
  bool shouldRebuild(_PinnedSearchDelegate oldDelegate) =>
      child != oldDelegate.child;
}
