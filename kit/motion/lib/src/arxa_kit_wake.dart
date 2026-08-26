import 'package:flutter/material.dart';

import 'arxa_kit_motion_scope.dart';
import 'arxa_kit_motion_spec.dart';

/// Marks a child as *wake-choreographed*: it fades / slides / scales in on
/// its stagger slot as the enclosing [ArxaKitMotionScope]'s driver runs 0→1,
/// and scrubs back down symmetrically as the driver reverses.
///
/// Composition is pure Flutter transition widgets ([FadeTransition],
/// [SlideTransition], [ScaleTransition]) — cheap, reversible, and driven
/// without owning a ticker. For arbitrary flutter_animate effects on the
/// same timeline, see `ArxaKitMotionAdapter`.
///
/// Renders the child untouched when any of these hold:
/// - no [ArxaKitMotionScope] above it,
/// - `MediaQuery.disableAnimations` (reduce-motion) is set,
/// - the resolved [ArxaKitMotionSpec.enabled] is `false`.
class ArxaKitWake extends StatefulWidget {
  const ArxaKitWake({
    super.key,
    this.order,
    this.spec,
    required this.child,
  });

  /// Explicit stagger slot. When null, the next free slot is auto-claimed
  /// from the scope in build order (sticky across rebuilds).
  final int? order;

  /// Per-widget spec override (wins over scope + theme).
  final ArxaKitMotionSpec? spec;

  final Widget child;

  @override
  State<ArxaKitWake> createState() => _KitWakeState();
}

class _KitWakeState extends State<ArxaKitWake> {
  int? _claimedOrder;
  CurvedAnimation? _slice;
  Animation<double>? _sliceParent;
  int? _sliceOrder;
  ArxaKitMotionSpec? _sliceSpec;

  CurvedAnimation _resolveSlice(
      ArxaKitMotionScopeState scope, int order, ArxaKitMotionSpec spec) {
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
    final scope = ArxaKitMotionScope.maybeOf(context);
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
