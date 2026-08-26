/// A widget is a reusable UI piece composed by views. It receives data via
/// constructor params or [ArxaKitStreamBuilder] bindings and renders its
/// slice of the surface — it holds no business logic and never decides when
/// an action runs.
///
/// This is the user interface for a shared credential text field — a thin
/// pass-through to [ArxaKitNativeTextField]. Value-based (onChanged), never
/// controller-based: credential capture is never-prefill.
///
/// Requirements:
/// 1. [Credential field]
/// Renders a native text field for email/password/code entry.
///
/// Relationships:
///
/// Standalone — no viewmodel binding.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_notes_widgets/showcase_notes_auth_text_field_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

class ShowcaseNotesAuthTextFieldWidget extends StatelessWidget {
  const ShowcaseNotesAuthTextFieldWidget({
    super.key,
    required this.onChanged,
    required this.placeholder,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
  });

  final ValueChanged<String> onChanged;
  final String placeholder;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ArxaKitNativeTextField(
      onChanged: onChanged,
      placeholder: placeholder,
      keyboardType: keyboardType,
      obscureText: obscureText,
      enabled: enabled,
    );
  }
}
