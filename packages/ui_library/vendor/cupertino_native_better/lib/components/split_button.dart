import 'package:flutter/widgets.dart';

import '../style/button_data.dart';
import '../style/button_style.dart';
import '../style/sf_symbol.dart';
import 'glass_button_group.dart';

/// A Cupertino-native split button: a primary action segment fused with a
/// chevron segment that opens a native menu, blended into one Liquid Glass
/// pill on iOS 26+ (Flutter fallback below, like every other CN widget).
///
/// Composed from the package's own native machinery — a [CNGlassButtonGroup]
/// whose two [CNButtonData] segments share a `glassEffectUnionId`. The popup
/// half's glass is hoisted onto its `Menu` on the native side
/// (GlassButtonGroupView.swift) so the union merges the two halves and keeps
/// them in sync; this widget is the supported way to get a split button.
///
/// ```dart
/// CNSplitButton(
///   label: 'Send',
///   icon: CNSymbol('paperplane.fill', size: 18),
///   onAction: () => send(),
///   items: [
///     CNButtonDataPopupItem(label: 'Send now', sfSymbol: 'paperplane.fill'),
///     CNButtonDataPopupItem(label: 'Schedule', sfSymbol: 'clock'),
///   ],
///   onSelected: (index) => ...,
/// )
/// ```
class CNSplitButton extends StatelessWidget {
  /// Creates a split button from an optional [label]/[icon] action face and
  /// a menu of [items].
  const CNSplitButton({
    super.key,
    this.label,
    this.icon,
    this.customIcon,
    this.onAction,
    required this.items,
    required this.onSelected,
    this.menuIcon,
    this.customMenuIcon,
  });

  /// Action-face label. At least one of [label], [icon], [customIcon] should
  /// be provided.
  final String? label;

  /// SF Symbol for the action face. Preferred on the Apple tier.
  final CNSymbol? icon;

  /// Material [IconData] fallback for the action face when no SF Symbol is
  /// available (rendered to bytes; used by the Flutter fallback too).
  final IconData? customIcon;

  /// Primary-action tap handler. `null` disables the action segment.
  final VoidCallback? onAction;

  /// Menu entries revealed by the chevron segment.
  final List<CNButtonDataPopupItem> items;

  /// Called with the index of the selected menu item.
  final ValueChanged<int> onSelected;

  /// SF Symbol for the chevron segment. Defaults to `chevron.down` when both
  /// [menuIcon] and [customMenuIcon] are null.
  final CNSymbol? menuIcon;

  /// Material [IconData] fallback for the chevron segment.
  final IconData? customMenuIcon;

  static const _union = 'cn-split-button';
  static const _config = CNButtonDataConfig(
    style: CNButtonStyle.glass,
    glassEffectUnionId: _union,
  );

  @override
  Widget build(BuildContext context) {
    final action = label != null
        ? CNButtonData(
            label: label!,
            icon: icon,
            customIcon: customIcon,
            onPressed: onAction,
            config: _config,
          )
        : CNButtonData.icon(
            icon: icon,
            customIcon: customIcon,
            onPressed: onAction,
            config: _config,
          );

    final menu = CNButtonData.popup(
      // ponytail: default chevron — a split button with no menu glyph would
      // read as a plain icon button.
      icon: (menuIcon == null && customMenuIcon == null)
          ? const CNSymbol('chevron.down', size: 18.0)
          : menuIcon,
      customIcon: menuIcon == null ? customMenuIcon : null,
      popupItems: items,
      onMenuSelected: onSelected,
      config: _config,
    );

    return CNGlassButtonGroup(buttons: [action, menu]);
  }
}
