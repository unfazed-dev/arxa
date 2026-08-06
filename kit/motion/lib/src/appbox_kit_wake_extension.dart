import 'package:flutter/widgets.dart';

import 'appbox_kit_motion_spec.dart';
import 'appbox_kit_wake.dart';

/// Terse call-site sugar mirroring the kit's other widget extensions
/// (e.g. `withHapticFeedback()`).
extension AppBoxKitWakeWidgetExtension on Widget {
  /// Wraps this widget in a [AppBoxKitWake]: `Text('hi').wake()`.
  Widget wake({Key? key, int? order, AppBoxKitMotionSpec? spec}) =>
      AppBoxKitWake(key: key, order: order, spec: spec, child: this);
}

extension AppBoxKitWakeListExtension on List<Widget> {
  /// Wakes every child with sequential explicit orders starting at [from] —
  /// the common `Column(children: [...].wakeAll())` case, immune to
  /// build-order surprises from lazy/sliver parents.
  List<Widget> wakeAll({int from = 0, AppBoxKitMotionSpec? spec}) => <Widget>[
        for (var i = 0; i < length; i++)
          AppBoxKitWake(order: from + i, spec: spec, child: this[i]),
      ];
}
