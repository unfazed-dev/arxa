import 'package:flutter/widgets.dart';

import 'arxa_kit_motion_spec.dart';
import 'arxa_kit_wake.dart';

/// Terse call-site sugar mirroring the kit's other widget extensions
/// (e.g. `withHapticFeedback()`).
extension ArxaKitWakeWidgetExtension on Widget {
  /// Wraps this widget in a [ArxaKitWake]: `Text('hi').wake()`.
  Widget wake({Key? key, int? order, ArxaKitMotionSpec? spec}) =>
      ArxaKitWake(key: key, order: order, spec: spec, child: this);
}

extension ArxaKitWakeListExtension on List<Widget> {
  /// Wakes every child with sequential explicit orders starting at [from] —
  /// the common `Column(children: [...].wakeAll())` case, immune to
  /// build-order surprises from lazy/sliver parents.
  List<Widget> wakeAll({int from = 0, ArxaKitMotionSpec? spec}) => <Widget>[
        for (var i = 0; i < length; i++)
          ArxaKitWake(order: from + i, spec: spec, child: this[i]),
      ];
}
