import 'package:flutter/widgets.dart';

import 'kit_motion_spec.dart';
import 'kit_wake.dart';

/// Terse call-site sugar mirroring the kit's other widget extensions
/// (e.g. `withHapticFeedback()`).
extension KitWakeWidgetExtension on Widget {
  /// Wraps this widget in a [KitWake]: `Text('hi').wake()`.
  Widget wake({Key? key, int? order, KitMotionSpec? spec}) =>
      KitWake(key: key, order: order, spec: spec, child: this);
}

extension KitWakeListExtension on List<Widget> {
  /// Wakes every child with sequential explicit orders starting at [from] —
  /// the common `Column(children: [...].wakeAll())` case, immune to
  /// build-order surprises from lazy/sliver parents.
  List<Widget> wakeAll({int from = 0, KitMotionSpec? spec}) => <Widget>[
        for (var i = 0; i < length; i++)
          KitWake(order: from + i, spec: spec, child: this[i]),
      ];
}
