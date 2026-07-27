import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'package:app_box/ui/common/app_box_widgets.dart';
import 'design_surface_viewmodel.dart';

class DesignSurfaceView extends StackedView<DesignSurfaceViewModel> {
  const DesignSurfaceView({super.key});

  @override
  Widget builder(context, viewModel, child) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prototype preview'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: StateChip(viewModel.stale ? 'Stale' : 'Live', tone: viewModel.stale ? ChipTone.danger : ChipTone.good)),
          ),
        ],
      ),
      body: Column(children: [
        if (viewModel.stale)
          MaterialBanner(
            content: const Text('The prototype changed since this preview rendered.'),
            backgroundColor: cs.errorContainer,
            actions: [TextButton(onPressed: viewModel.refresh, child: const Text('Refresh'))],
          ),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1.0,
              child: Container(
                margin: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: const Center(child: Text('Live htmx prototype')),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: viewModel.markStale,
            icon: const Icon(Icons.sync_problem),
            label: const Text('Simulate prototype change'),
          ),
        ),
      ]),
    );
  }

  @override
  DesignSurfaceViewModel viewModelBuilder(context) => DesignSurfaceViewModel();
}
