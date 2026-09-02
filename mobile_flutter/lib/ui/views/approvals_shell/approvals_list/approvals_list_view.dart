// arxa-scaffolder surface: approvals_shell_approvals_view (approvals.list)
// arxa-builder: LIVE (grill D60–D68) — each pending approval renders as a
// card with its questions; options answer directly, free-text questions
// get a field; one Submit answers the whole batch (the engine validates
// exactly that shape). The card itself is the shared ApprovalCard
// (lib/ui/widgets/approval_card.dart) — the conversation transcript
// threads the same widget inline.
import "package:arxa_kit_ui_library/arxa_kit_ui_library.dart"
    show ArxaKitGlyphs, ArxaKitNativeAppBar, ArxaKitNativeIconButton, StackedView;
import "package:flutter/material.dart";

import "package:arxa_studio_mobile/l10n/app_localizations.dart";

import "../../../widgets/approval_card.dart";
import "approvals_list_viewmodel.dart";

class ApprovalsListView extends StackedView<ApprovalsListViewModel> {
  const ApprovalsListView({super.key});

  @override
  Widget builder(
      BuildContext context, ApprovalsListViewModel viewModel, Widget? child) {
    final l10n = AppLocalizations.of(context);
    final bootError = viewModel.bootError;
    return Scaffold(
      appBar: ArxaKitNativeAppBar(
        title: l10n.approvalsTitle,
        actions: [
          // The studio session is the paired home; this is the way back from
          // the approvals deep link (both the offline and list states).
          Tooltip(
            message: l10n.approvalsOpenStudio,
            child: ArxaKitNativeIconButton(
              glyph: ArxaKitGlyphs.home,
              onPressed: viewModel.goToStudio,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // B2 phase-1b: WHY sync is off, when the boot fell back to
          // localOnly — visible, not a silent degradation.
          if (bootError != null)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                dense: true,
                title: Text("Sync off",
                    style: Theme.of(context).textTheme.labelLarge),
                subtitle: Text(bootError,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
          Expanded(
            child: viewModel.approvals.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.approvalsEmpty),
                        if (viewModel.loadError == ApprovalsError.offline) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(l10n.approvalsNotConnected),
                          ),
                          if (viewModel.needsPairing)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: FilledButton.icon(
                                onPressed: viewModel.goToPairing,
                                icon: const Icon(Icons.qr_code_scanner),
                                label: Text(l10n.approvalsPairCta),
                              ),
                            ),
                        ],
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: viewModel.refresh,
                    child: ListView.builder(
                      itemCount: viewModel.approvals.length,
                      itemBuilder: (context, i) => ApprovalCard(
                        key: ValueKey(viewModel.approvals[i].id),
                        approval: viewModel.approvals[i],
                        busy: viewModel.decidingId ==
                            viewModel.approvals[i].id,
                        onDecide: (answers) =>
                            viewModel.decide(viewModel.approvals[i], answers),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void onViewModelReady(ApprovalsListViewModel viewModel) {
    viewModel
      ..listenTransport()
      ..refresh();
  }

  @override
  ApprovalsListViewModel viewModelBuilder(context) => ApprovalsListViewModel();
}
