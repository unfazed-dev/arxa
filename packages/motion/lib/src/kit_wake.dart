import 'package:flutter/material.dart';

import 'kit_motion_scope.dart';
import 'kit_motion_spec.dart';

/// Marks a child as *wake-choreographed*: it fades / slides / scales in on
/// its stagger slot as the enclosing [KitMotionScope]'s driver runs 0→1,
/// and scrubs back down symmetrically as the driver reverses.
///
/// Composition is pure Flutter transition widgets ([FadeTransition],
/// [SlideTransition], [ScaleTransition]) — cheap, reversible, and driven
/// without owning a ticker. For arbitrary flutter_animate effects on the
/// same timeline, see `KitMotionAdapter`.
///
/// Renders the child untouched when any of these hold:
/// - no [KitMotionScope] above it,
/// - `MediaQuery.disableAnimations` (reduce-motion) is set,
/// - the resolved [KitMotionSpec.enabled] is `false`.
class KitWake extends StatefulWidget {
  const KitWake({
    super.key,
    this.order,
    this.spec,
    required this.child,
  });

  /// Explicit stagger slot. When null, the next free slot is auto-claimed
  /// from the scope in build order (sticky across rebuilds).
  final int? order;

  /// Per-widget spec override (wins over scope + theme).
  final KitMotionSpec? spec;

  final Widget child;

  @override
  State<KitWake> createState() => _KitWakeState();
}

class _KitWakeState extends State<KitWake> {
  int? _claimedOrder;
  CurvedAnimation? _slice;
  Animation<double>? _sliceParent;
  int? _sliceOrder;
  KitMotionSpec? _sliceSpec;

  CurvedAnimation _resolveSlice(
      KitMotionScopeState scope, int order, KitMotionSpec spec) {
    if (_slice == null ||
        _sliceParent != scope.driver ||
        _sliceOrder != order ||
        _sliceSpec != spec) {
      _slice?.dispose();
      _slice = scope.slice(order, spec);
      _sliceParent = scope.driver;
      _sliceOrder = order;
      _sliceSpec = spec;
    }
    return _slice!;
  }

  @override
  void dispose() {
    _slice?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = KitMotionScope.maybeOf(context);
    if (scope == null) return widget.child;

    final spec = widget.spec ?? scope.specOf(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!spec.enabled || reduceMotion) return widget.child;

    final order = widget.order ?? (_claimedOrder ??= scope.claimOrder());
    final slice = _resolveSlice(scope, order, spec);

    Widget result = widget.child;
    if (spec.scale < 1.0) {
      result = ScaleTransition(
        scale: slice.drive(Tween<double>(begin: spec.scale, end: 1.0)),
        child: result,
      );
    }
    if (spec.offset != Offset.zero) {
      result = SlideTransition(
        position: slice.drive(
          Tween<Offset>(begin: spec.offset, end: Offset.zero),
        ),
        textDirection: Directionality.maybeOf(context),
        child: result,
      );
    }
    if (spec.fade) {
      result = FadeTransition(opacity: slice, child: result);
    }
    return result;
  }
}
