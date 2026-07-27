import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'package:app_box/ui/common/app_box_widgets.dart';
import 'design_approve_viewmodel.dart';

/// Gate 1 — design approval. Visually unmistakable (the gate orange). The
/// Approve button is a human gesture; nothing an agent calls can set this.
class DesignApproveView extends StackedView<DesignApproveViewModel> {
  const DesignApproveView({super.key});

  @override
  Widget builder(context, viewModel, child) {
    return Scaffold(
      appBar: AppBar(title: const Text('Approve design')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: GateBanner(
              title: 'Design approval',
              subtitle: 'Confirm the chosen prototype direction. This is a human '
                  'gate — an agent may prepare and present directions, but cannot '
                  'mint approval.',
              approved: viewModel.approved,
              confirmLabel: 'Approve design',
              onConfirm: viewModel.approve,
            ),
          ),
        ),
      ),
    );
  }

  @override
  DesignApproveViewModel viewModelBuilder(context) => DesignApproveViewModel();
}
