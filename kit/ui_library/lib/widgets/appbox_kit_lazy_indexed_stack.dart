import 'package:flutter/material.dart';

/// A lazy, keep-alive index switch: builds each child only on first visit, then
/// keeps it mounted (offstage) so its state survives tab switches.
// ponytail: Offstage-in-a-Stack keeps visited children mounted + findable while
// hiding the inactive ones — the standard lazy bottom-nav pattern.
//
// The reason is NOT that `IndexedStack` unmounts offstage children; it doesn't.
// `RenderIndexedStack` overrides only paint/hit-test/semantics, so unselected
// children stay laid out AND mounted — proved next door by
// `appbox_kit_native_chrome_gate_test.dart`, which toggles a gate five times and
// still sees exactly one `initState`. The real footgun is this widget's LAZY
// shape: it grows its children list as tabs are first visited, and changing an
// `IndexedStack`'s child-list length/order disposes and re-creates the
// subsequent children even with stable keys (flutter#182303, OPEN). A
// fixed-length list toggling only `index` is safe — that is what the chrome gate
// relies on — but a lazily grown one is not, which is why this widget exists.
class AppBoxKitLazyIndexedStack extends StatefulWidget {
  const AppBoxKitLazyIndexedStack({
    super.key,
    required this.index,
    required this.builders,
    this.alignment,
    this.fit,
  }) : assert(builders.length > 0, 'need at least one tab builder');

  final int index;
  final List<WidgetBuilder> builders;
  final AlignmentGeometry? alignment;
  final StackFit? fit;

  @override
  State<AppBoxKitLazyIndexedStack> createState() => _KitLazyIndexedStackState();
}

class _KitLazyIndexedStackState extends State<AppBoxKitLazyIndexedStack> {
  final Set<int> _activated = {};

  @override
  void initState() {
    super.initState();
    _activated.add(widget.index);
  }

  @override
  void didUpdateWidget(covariant AppBoxKitLazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _activated.add(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: widget.fit ?? StackFit.expand,
      alignment: widget.alignment ?? Alignment.topCenter,
      children: [
        for (var i = 0; i < widget.builders.length; i++)
          if (_activated.contains(i))
            Offstage(
              offstage: i != widget.index,
              child: Builder(builder: widget.builders[i]),
            ),
      ],
    );
  }
}
