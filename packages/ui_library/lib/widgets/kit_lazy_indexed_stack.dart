import 'package:flutter/material.dart';

/// A lazy, keep-alive index switch: builds each child only on first visit, then
/// keeps it mounted (offstage) so its state survives tab switches.
// ponytail: IndexedStack unmounts its offstage children (verified in 3.44), so it
// can't keep tab state. Offstage-in-a-Stack keeps visited children mounted +
// findable while hiding the inactive ones — the standard lazy bottom-nav pattern.
class KitLazyIndexedStack extends StatefulWidget {
  const KitLazyIndexedStack({
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
  State<KitLazyIndexedStack> createState() => _KitLazyIndexedStackState();
}

class _KitLazyIndexedStackState extends State<KitLazyIndexedStack> {
  final Set<int> _activated = {};

  @override
  void initState() {
    super.initState();
    _activated.add(widget.index);
  }

  @override
  void didUpdateWidget(covariant KitLazyIndexedStack oldWidget) {
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
