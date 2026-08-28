// arxa-scaffolder surface: approvals_shell_approvals_view (approvals.list)
// arxa-builder: skeleton — notification-driven; cairn data slice lands with
// the approvals schema.
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ArxaKitNativeAppBar, StackedView;
import 'package:flutter/material.dart';

import 'package:arxa_studio_mobile/l10n/app_localizations.dart';

import 'approvals_list_viewmodel.dart';

class ApprovalsListView extends StackedView<ApprovalsListViewModel> {
  const ApprovalsListView({super.key});

  @override
  Widget builder(
      BuildContext context, ApprovalsListViewModel viewModel, Widget? child) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: ArxaKitNativeAppBar(title: l10n.approvalsTitle),
      body: viewModel.approvals.isEmpty
          ? Center(child: Text(l10n.approvalsEmpty))
          : ListView.builder(
              itemCount: viewModel.approvals.length,
              itemBuilder: (context, i) =>
                  ListTile(title: Text(viewModel.approvals[i])),
            ),
    );
  }

  @override
  ApprovalsListViewModel viewModelBuilder(context) => ApprovalsListViewModel();
}
