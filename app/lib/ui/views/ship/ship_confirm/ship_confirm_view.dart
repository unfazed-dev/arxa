import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/gate_service.dart';
import 'package:app_box/ui/common/app_box_widgets.dart';

class ShipConfirmViewModel extends BaseViewModel {
  final _gates = locator<GateService>();
  String target = '';
  String version = '';
  String account = '';
  bool? _matched;

  ShipTriple? get declared => _gates.declaredShipTriple;
  bool get approved => _gates.allShipApproved;
  bool? get matched => _matched;

  /// Gate 3 — the strictest. Confirms the retyped triple matches the declared
  /// one exactly. A guess or an agent-supplied value cannot pass (returns false,
  /// never silently approves).
  void confirm() {
    final retyped = ShipTriple(target.trim(), version.trim(), account.trim());
    _matched = _gates.confirmShip(retyped);
    notifyListeners();
  }
}

/// Gate 3 — ship confirmation. Names target, version and account and requires
/// the human to confirm that exact triple (brief §4, J6). Every other gate is
/// read-only; this one writes to the outside world and cannot be undone.
class ShipConfirmView extends StackedView<ShipConfirmViewModel> {
  const ShipConfirmView({super.key});

  @override
  Widget builder(context, viewModel, child) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm ship')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const GateBanner(
                title: 'Ship gate — the triple',
                subtitle: 'Confirm the exact target, version and account. This is '
                    'the strictest gate: it writes to the outside world and cannot '
                    'be undone by re-running a stage.',
                approved: false,
                confirmLabel: 'Human-only',
              ),
              const SizedBox(height: 24),
              _TripleForm(vm: viewModel),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  ShipConfirmViewModel viewModelBuilder(context) => ShipConfirmViewModel();
}

class _TripleForm extends ViewModelWidget<ShipConfirmViewModel> {
  const _TripleForm({required this.vm});
  final ShipConfirmViewModel vm;
  @override
  Widget build(context, viewModel) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (vm.declared == null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('No ship triple declared yet — set the project target first.',
              style: TextStyle(color: cs.outline)),
        ),
      _Field(label: 'Target', onChanged: (v) => vm.target = v),
      const SizedBox(height: 12),
      _Field(label: 'Version', onChanged: (v) => vm.version = v),
      const SizedBox(height: 12),
      _Field(label: 'Account', onChanged: (v) => vm.account = v),
      const SizedBox(height: 16),
      if (vm.matched == false)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('Triple does not match the declared target+version+account.',
              style: TextStyle(color: cs.error, fontWeight: FontWeight.w600)),
        ),
      if (vm.approved)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: StateChip('Shipped — confirmed', tone: ChipTone.good),
        ),
      FilledButton.icon(
        icon: const Icon(Icons.rocket_launch),
        label: const Text('Confirm exact triple'),
        onPressed: vm.declared == null ? null : vm.confirm,
      ),
    ]);
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.onChanged});
  final String label;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => TextField(
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        onChanged: onChanged,
      );
}
