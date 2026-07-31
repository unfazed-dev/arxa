import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';

/// Shared, value-based credential text field for the notes auth + create-account
/// forms. A thin pass-through to [KitNativeTextField], which now owns the full
/// native tiering itself (iOS 26 Liquid Glass CNTextField / Android M3E
/// TextFieldM3E / Material fallback) — so this wrapper no longer branches per
/// platform. (Previously it hand-routed Android to `TextFieldM3E` because the kit
/// widget lacked an M3E tier; that gap is closed, so the workaround is gone.)
///
/// **Shared (shell-wide):** used by both the sign-in panel
/// (`showcase_notes_auth`) and the create-account panel
/// (`showcase_notes_create_account`) — extracted from the duplicated private
/// `_AuthTextField` / `_CreateAccountTextField` that previously lived inline
/// in each view (kit folder-org gate check D: reusable widgets live in
/// `<shell>/shared/widgets/`, not as private copies in view files).
///
/// Value-based (onChanged), not controller-based: credential capture is
/// never-prefill, so the field holds no controller — the viewmodel owns the
/// string (forms_playbook.mdx: "forms that never prefill").
class AuthTextField extends StatelessWidget {
  const AuthTextField({
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
    return KitNativeTextField(
      onChanged: onChanged,
      placeholder: placeholder,
      keyboardType: keyboardType,
      obscureText: obscureText,
      enabled: enabled,
    );
  }
}
