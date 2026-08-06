import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// Shared, value-based credential text field for the notes auth + create-account
/// forms. A thin pass-through to [AppBoxKitNativeTextField], which now owns the full
/// native tiering itself (iOS 26 Liquid Glass CNTextField / Android M3E
/// TextFieldM3E / Material fallback) — so this wrapper no longer branches per
/// platform. (Previously it hand-routed Android to `TextFieldM3E` because the kit
/// widget lacked an M3E tier; that gap is closed, so the workaround is gone.)
///
/// **Shared (shell-wide):** used by both the sign-in panel
/// (`showcase_notes_auth`) and the create-account panel
/// (`showcase_notes_create_account`) — extracted from the duplicated private
/// `_ShowcaseNotesAuthTextField` / `_CreateAccountTextField` that previously lived inline
/// in each view. Lives in the central `showcase_notes_widgets` home (the
/// in-shell `shared/widgets/` pattern was retired).
///
/// Value-based (onChanged), not controller-based: credential capture is
/// never-prefill, so the field holds no controller — the viewmodel owns the
/// string (forms_playbook.mdx: "forms that never prefill").
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
    return AppBoxKitNativeTextField(
      onChanged: onChanged,
      placeholder: placeholder,
      keyboardType: keyboardType,
      obscureText: obscureText,
      enabled: enabled,
    );
  }
}
