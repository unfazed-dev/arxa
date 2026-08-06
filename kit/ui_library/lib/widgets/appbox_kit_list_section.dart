import 'package:flutter/material.dart';

import 'package:appbox_kit_core/common/appbox_kit_app_constants.dart';

import 'appbox_kit_glass_card.dart';

/// A grouped inset section: an optional header label over a glass-card-backed
/// group container holding rows (usually `AppBoxKitListTile`s), with hairline
/// dividers between them. Pure-Flutter on every tier — there is **no** native
/// (Liquid-Glass / M3-Expressive) grouped-list surface to wrap, so this
/// widget is named `AppBoxKitListSection` (a content widget), **not**
/// `AppBoxKitNativeListSection`. See `core/NATIVE_COMPONENTS.md` ("Content
/// widgets"). The group container is `AppBoxKitGlassCard`, per the kit's
/// content-surface rule (`no_raw_card_surface`) — on iOS 26 it renders real
/// Liquid Glass, elsewhere the themed Material card tier.
///
/// This is the grouped-list idiom for settings screens, drawer menus, and
/// plugin rows: stack several `AppBoxKitListSection`s in a scroll view, one per
/// logical group. The section owns its horizontal inset ([margin]) and its
/// dividers; the rows own their own padding, so they stay full-bleed inside
/// the card.
class AppBoxKitListSection extends StatelessWidget {
  const AppBoxKitListSection({
    super.key,
    required this.children,
    this.header,
    this.showDividers = true,
    this.margin = const EdgeInsets.symmetric(horizontal: axPad16),
    this.borderRadius,
  });

  /// The rows, typically `AppBoxKitListTile`s. Rendered full-bleed inside the
  /// group card in order, top to bottom.
  final List<Widget> children;

  /// Small subdued label above the group (e.g. "Account"). `null` = no
  /// header.
  final String? header;

  /// Whether to draw hairline dividers between rows. Defaults to `true`
  /// (settings idiom); set `false` for menu-style groups whose rows carry
  /// their own spacing.
  final bool showDividers;

  /// Inset around the group card. Defaults to 16dp horizontal — the grouped
  /// inset-list margin. The header label aligns to the card's leading edge
  /// plus the row padding.
  final EdgeInsetsGeometry margin;

  /// Corner radius forwarded to the backing `AppBoxKitGlassCard`. `null` = the
  /// card's own default (16dp / theme shape).
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final rows = <Widget>[
      for (var i = 0; i < children.length; i++) ...[
        children[i],
        if (showDividers && i < children.length - 1)
          const Divider(height: 1, indent: axPad16),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (header != null)
          Padding(
            padding: EdgeInsets.only(
              left: axPad16 + margin.horizontal / 2,
              right: axPad16 + margin.horizontal / 2,
              bottom: axPad8,
            ),
            child: Text(
              header!,
              style: textTheme.labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        Padding(
          padding: margin,
          child: AppBoxKitGlassCard(
            padding: EdgeInsets.zero,
            borderRadius: borderRadius,
            child: Column(mainAxisSize: MainAxisSize.min, children: rows),
          ),
        ),
      ],
    );
  }
}
