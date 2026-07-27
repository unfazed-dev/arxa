import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:app_box/app/app.locator.dart';
import 'package:app_box/app/app.router.dart';
import 'package:app_box/ui/common/app_colors.dart';
import 'design_directions_viewmodel.dart';

class DesignDirectionsView extends StackedView<DesignDirectionsViewModel> {
  const DesignDirectionsView({super.key});

  @override
  Widget builder(context, viewModel, child) {
    return Scaffold(
      appBar: AppBar(title: const Text('Design directions')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Three directions. Approve one to proceed to the design gate.'),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.1,
              children: [
                for (var i = 0; i < viewModel.directions.length; i++)
                  _DirectionCard(
                    dir: viewModel.directions[i],
                    selected: viewModel.selected == i,
                    onTap: () => viewModel.select(i),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            FilledButton.icon(
              icon: const Icon(Icons.gpp_maybe),
              label: const Text('Approve direction → gate'),
              style: FilledButton.styleFrom(backgroundColor: kcGateColor, foregroundColor: Colors.white),
              onPressed: viewModel.selected == null
                  ? null
                  : () => locator<RouterService>().navigateTo(DesignApproveViewRoute()),
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  DesignDirectionsViewModel viewModelBuilder(context) => DesignDirectionsViewModel();
}

class _DirectionCard extends StatelessWidget {
  const _DirectionCard({required this.dir, required this.selected, required this.onTap});
  final dynamic dir;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Direction ${dir.id}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              const Spacer(),
              Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? cs.primary : cs.outline),
            ]),
            const Spacer(),
            Text(dir.blurb, style: Theme.of(context).textTheme.bodyMedium),
          ]),
        ),
      ),
    );
  }
}
