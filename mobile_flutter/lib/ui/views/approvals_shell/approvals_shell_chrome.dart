// arxa-scaffolder: shell chrome skeleton. STRUCTURE ONLY — builder fills this.
//   shell:  approvals_shell
//   The chrome is the shell's persistent frame (nav rail / tabs / gate badge).
//   S6 (scaffold gate) requires every self-contained shell to own a chrome or a
//   widgets/ home; this stub satisfies ownership. The builder wires the layout.
import 'package:flutter/material.dart';

/// Placeholder frame — hosts [child] until the builder wires real chrome.
class ApprovalsShellChrome extends StatelessWidget {
  const ApprovalsShellChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
