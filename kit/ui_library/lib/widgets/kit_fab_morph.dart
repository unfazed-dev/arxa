import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

/// Round M3 Expressive FAB that **shape-morphs on press** — the corner-radius
/// morph `FabM3E` lacks (its `RawMaterialButton.shape` is static). Built as a
/// filled, elevated Material [IconButton] so it keeps the FAB's identity
/// (primary-container fill, drop shadow, 56pt size) while morphing exactly like
/// [KitNativeIconButton] (search / app bar): same motion token
/// ([IconButtonM3ETokens.morphDuration]), corners tighten on press.
///
/// Shape follows the M3 Expressive spec: a **rounded square** at rest (boxier
/// than the M2 circle), not a pill/circle. Colors follow the M3E tone rename
/// (primary → primary *container*).
class KitFabMorph extends StatelessWidget {
  const KitFabMorph({super.key, required this.icon, this.onPressed});

  final Widget icon;

  /// Tap handler. `null` disables the button.
  final VoidCallback? onPressed;

  // M3 FAB container shape = 16dp rounded square (boxier than a circle);
  // pressed tightens to 10dp for a visible expressive "squish". Motion reuses
  // the icon button's morph token so every kit surface morphs at one cadence.
  // ponytail: two literals, not a token map — the M3 FAB has one resting shape.
  static const double _radiusRest = 16;
  static const double _radiusPressed = 10;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    OutlinedBorder shapeFor(Set<WidgetState> states) => RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            states.contains(WidgetState.pressed) ? _radiusPressed : _radiusRest,
          ),
        );

    return IconButton(
      onPressed: onPressed,
      icon: icon,
      style: ButtonStyle(
        fixedSize: const WidgetStatePropertyAll(Size(56, 56)),
        iconSize: const WidgetStatePropertyAll(24),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: WidgetStatePropertyAll(scheme.primaryContainer),
        foregroundColor: WidgetStatePropertyAll(scheme.onPrimaryContainer),
        // FabM3E metrics: 6dp rest, 12dp pressed — the FAB stays "floating".
        elevation: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.pressed) ? 12.0 : 6.0,
        ),
        shadowColor: WidgetStatePropertyAll(scheme.shadow),
        shape: WidgetStateProperty.resolveWith(shapeFor),
        // Animate the pressed shape morph — matches KitNativeIconButton.
        animationDuration: IconButtonM3ETokens.morphDuration,
      ),
    );
  }
}
