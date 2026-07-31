import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'kit_native_chrome_gate.dart';

/// Adaptive toggle switch. Thinly wraps [CNSwitch], which renders native
/// Liquid Glass on iOS/macOS 26+ and self-degrades to a Cupertino/Material
/// [Switch] elsewhere — including Android, where there is deliberately **no
/// M3E branch** (Cupertino-native-better's Material fallback is the kit's
/// Android tier for switches).
///
/// The public surface is **primitives only** ([value], [onChanged],
/// [activeColor]) so hosts never import the underlying dep. [onChanged] is
/// nullable: `null` disables the control.
class KitNativeSwitch extends StatelessWidget {
  const KitNativeSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.activeColor,
    this.semanticLabel,
  });

  /// Whether the switch is on.
  final bool value;

  /// Notified on toggle. `null` disables the control.
  final ValueChanged<bool>? onChanged;

  /// Track/accent tint. Forwarded to [CNSwitch] as `color`.
  final Color? activeColor;

  /// VoiceOver/TalkBack label. Without it, iOS exposes the native switch as
  /// an **unlabeled** AX element (sweep evidence: `CheckBox ''`), so hosts
  /// with a visible text label SHOULD pass it here too.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    // ponytail: no M3E branch by design — CNSwitch's Material fallback IS the
    // Android tier (see plan). Add a SliderM3E-style gate only if a host ever
    // needs a Material 3 Expressive switch affordance Material Switch lacks.
    // Web: cupertino_native_better reads dart:io Platform, which throws on
    // web — take the Material tier directly (it IS CNSwitch's own fallback).
    if (kIsWeb) {
      return Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: activeColor ?? Theme.of(context).colorScheme.primary,
      );
    }
    return CNSwitch(
      value: value,
      // CNSwitch.onChanged is required-non-null: a kit `null` means "disabled",
      // so hand it a no-op and drop the enabled flag.
      onChanged: onChanged ?? (_) {},
      enabled: onChanged != null,
      // Explicitly wire the on-tint to the kit theme's accent so the CN switch
      // never falls back to the iOS system green in any host.
      color: activeColor ?? Theme.of(context).colorScheme.primary,
      semanticLabel: semanticLabel,
    ).chromeGated();
  }
}
