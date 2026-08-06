import 'package:flutter/material.dart';

import 'appbox_kit_motion_scope.dart';
import 'appbox_kit_motion_spec.dart';

/// Marks a child as *wake-choreographed*: it fades / slides / scales in on
/// its stagger slot as the enclosing [AppBoxKitMotionScope]'s driver runs 0→1,
/// and scrubs back down symmetrically as the driver reverses.
///
/// Composition is pure Flutter transition widgets ([FadeTransition],
/// [SlideTransition], [ScaleTransition]) — cheap, reversible, and driven
/// without owning a ticker. For arbitrary flutter_animate effects on the
/// same timeline, see `AppBoxKitMotionAdapter`.
///
/// Renders the child untouched when any of these hold:
/// - no [AppBoxKitMotionScope] above it,
/// - `MediaQuery.disableAnimations` (reduce-motion) is set,
/// - the resolved [AppBoxKitMotionSpec.enabled] is `false`.
class AppBoxKitWake extends StatefulWidget {
  const AppBoxKitWake({
    super.key,
    this.order,
    this.spec,
    required this.child,
  });

  /// Explicit stagger slot. When null, the next free slot is auto-claimed
  /// from the scope in build order (sticky across rebuilds).
  final int? order;

  /// Per-widget spec override (wins over scope + theme).
  final AppBoxKitMotionSpec? spec;

  final Widget child;

  @override
  State<AppBoxKitWake> createState() => _KitWakeState();
}

class _KitWakeState extends State<AppBoxKitWake> {
  int? _claimedOrder;
  CurvedAnimation? _slice;
  Animation<double>? _sliceParent;
  int? _sliceOrder;
  AppBoxKitMotionSpec? _sliceSpec;

  CurvedAnimation _resolveSlice(
      AppBoxKitMotionScopeState scope, int order, AppBoxKitMotionSpec spec) {
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
    final scope = AppBoxKitMotionScope.maybeOf(context);
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
