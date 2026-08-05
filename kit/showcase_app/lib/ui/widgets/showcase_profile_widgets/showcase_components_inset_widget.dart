import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';

/// Horizontal inset for full-bleed ListView children (the carousel and the
/// list section carry their own 16dp margins).
class ShowcaseComponentsInsetWidget extends StatelessWidget {
  const ShowcaseComponentsInsetWidget({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: kSize16),
        child: child,
      );
}
