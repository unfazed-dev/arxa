import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'app_shell_viewmodel.dart';

/// The app_box root shell — a desktop sidebar (NavigationRail) over a nested
/// router outlet that hosts the 14 product surfaces (brief §4). The dogfood
/// target is macOS desktop, so this is a sidebar layout, not the mobile tab bar
/// the kit exemplar carried. Six sections map to the brief’s tabs.
class AppShellView extends StackedView<AppShellViewModel> {
  const AppShellView({super.key});

  @override
  Widget builder(context, viewModel, child) {
    return Scaffold(
      body: Row(children: [
        _AppSidebar(selection: viewModel.section, onTap: viewModel.goTo),
        const VerticalDivider(width: 1),
        const Expanded(child: NestedRouter()),
      ]),
    );
  }

  @override
  AppShellViewModel viewModelBuilder(context) => AppShellViewModel();
}

class _AppSidebar extends StatelessWidget {
  const _AppSidebar({required this.selection, required this.onTap});
  final AppSection selection;
  final void Function(AppSection) onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 220,
      color: cs.surfaceContainerLow,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Row(children: [
            Icon(Icons.widgets, color: cs.primary, size: 28),
            const SizedBox(width: 10),
            const Text('app_box',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ]),
        ),
        Expanded(
          child: ListView(children: [
            for (final s in AppSection.values)
              _RailItem(
                section: s,
                selected: s == selection,
                onTap: () => onTap(s),
              ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Totem Labs',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({required this.section, required this.selected, required this.onTap});
  final AppSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            Icon(section.icon, size: 20, color: selected ? cs.onPrimaryContainer : null),
            const SizedBox(width: 12),
            Text(section.label,
                style: TextStyle(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? cs.onPrimaryContainer : null)),
          ]),
        ),
      ),
    );
  }
}
