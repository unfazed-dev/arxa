import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// Horizontal inset for full-bleed ListView children (the carousel and the
/// list section carry their own 16dp margins).
class ShowcaseComponentsInsetWidget extends StatelessWidget {
  const ShowcaseComponentsInsetWidget({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: axSize16),
        child: child,
      );
}
