// arxa-scaffolder: mobile layout skeleton. STRUCTURE ONLY — builder fills this.
//   surface:       approvals_shell_approvals_view
//   comp:          ApprovalsListViewMobile
//   factor:        mobile   (derived from targets=[ios,android])
import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ViewModelWidget;

import 'approvals_list_viewmodel.dart';

class ApprovalsListViewMobile extends ViewModelWidget<ApprovalsListViewModel> {
  const ApprovalsListViewMobile({super.key});

  @override
  Widget build(context, viewModel) => const Scaffold(
        body: Center(child: Text('approvals.list · mobile')),
      );
}
