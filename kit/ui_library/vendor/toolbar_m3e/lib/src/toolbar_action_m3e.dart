import 'package:flutter/material.dart';
import 'package:icon_button_m3e/icon_button_m3e.dart';

class ToolbarActionM3E {
  const ToolbarActionM3E({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.semanticLabel,
    this.enabled = true,
    this.label, // used in overflow menu
    this.isDestructive = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final String? semanticLabel;
  final bool enabled;

  /// Optional label used in the overflow menu; if null, tooltip or semanticLabel will be used.
  final String? label;

  /// If true, the action is styled as destructive in overflow (e.g., error color).
  final bool isDestructive;
}

class ToolbarIconButtonM3E extends StatelessWidget {
  const ToolbarIconButtonM3E({
    super.key,
    required this.action,
    this.color,
    this.iconSize,
  });

  final ToolbarActionM3E action;
  final Color? color;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    // PATCH (vendored fork): render the real M3E icon button — shape-morphs on
    // press — instead of a plain Material IconButton, and honor isDestructive
    // inline (upstream only styles it in the overflow menu).
    final glyphColor = action.isDestructive
        ? Theme.of(context).colorScheme.error
        : color;
    return IconButtonM3E(
      icon: Icon(action.icon, size: iconSize, color: glyphColor),
      onPressed: action.enabled ? action.onPressed : null,
      tooltip: action.tooltip ?? action.label,
      semanticLabel: action.semanticLabel,
    );
  }
}
