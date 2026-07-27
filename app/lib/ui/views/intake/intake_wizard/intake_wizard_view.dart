import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'intake_wizard_viewmodel.dart';

/// intake.wizard — the desktop wizard that drives the ONE elicitation engine
/// (10.5). Collects the client's words with provenance per field, then shells
/// out to `intake.py emit` to produce `docs/design/brief.md` + a seeded
/// `registry.json`. The wizard NEVER generates design or code (§22) — it
/// elicits and records; the engine emits.
///
/// DW1: the wizard writes the same answers JSON the headless path uses and
/// invokes the same engine — output is byte-identical by construction.
class IntakeWizardView extends StackedView<IntakeWizardViewModel> {
  const IntakeWizardView({super.key});

  @override
  Widget builder(context, viewModel, child) {
    final cs = Theme.of(context).colorScheme;
    final busy = viewModel.state == IntakeWizardState.emitting;
    return Scaffold(
      appBar: AppBar(title: const Text('Intake wizard')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: switch (viewModel.state) {
            IntakeWizardState.done => _DoneView(viewModel),
            _ => ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text('Elicit the brief',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Record what the client said. Every field tracks who '
                    'supplied it. Inferred fields are flagged in the brief.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),

                  // product
                  _Field(
                    label: 'Product',
                    hint: 'One line: what the app is',
                    value: viewModel.product,
                    enabled: !busy,
                    onChanged: viewModel.onProduct,
                    provenance: viewModel.productProv,
                    onProvenance: viewModel.onProductProv,
                  ),
                  const SizedBox(height: 12),

                  // audience
                  _Field(
                    label: 'Audience',
                    hint: 'Who the app is for',
                    value: viewModel.audience,
                    enabled: !busy,
                    onChanged: viewModel.onAudience,
                    provenance: viewModel.audienceProv,
                    onProvenance: viewModel.onAudienceProv,
                  ),
                  const SizedBox(height: 12),

                  // appMustDo
                  _Field(
                    label: 'What the app must do',
                    hint: 'Comma-separated (up to three)',
                    value: viewModel.appMustDo,
                    enabled: !busy,
                    onChanged: viewModel.onAppMustDo,
                    provenance: viewModel.appMustDoProv,
                    onProvenance: viewModel.onAppMustDoProv,
                  ),
                  const SizedBox(height: 12),

                  // brand (optional)
                  _Field(
                    label: 'Brand (optional)',
                    hint: 'Name, colour, voice — only if stated',
                    value: viewModel.brand,
                    enabled: !busy,
                    onChanged: viewModel.onBrand,
                    provenance: viewModel.brandProv,
                    onProvenance: viewModel.onBrandProv,
                  ),
                  const SizedBox(height: 12),

                  // targets (from state)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Targets: ${viewModel.targets.join(", ")} '
                        '(§11 platform-only; viewports derive.)'),
                  ),
                  const SizedBox(height: 20),

                  // surfaces
                  _SectionHeader('Surfaces — what the client named'),
                  const SizedBox(height: 8),
                  for (var i = 0; i < viewModel.surfaces.length; i++)
                    _SurfaceRow(
                      index: i,
                      surface: viewModel.surfaces[i],
                      enabled: !busy,
                      canRemove: viewModel.surfaces.length > 1,
                      viewModel: viewModel,
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add surface'),
                      onPressed: busy ? null : viewModel.addSurface,
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (viewModel.state == IntakeWizardState.error)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(viewModel.formError ?? '',
                          style: TextStyle(
                              color: cs.error, fontWeight: FontWeight.w600)),
                    ),

                  FilledButton.icon(
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.play_arrow),
                    label: Text(busy ? 'Emitting…' : 'Emit brief + registry'),
                    onPressed: busy ? null : viewModel.emit,
                  ),
                ],
              ),
          },
        ),
      ),
    );
  }

  @override
  IntakeWizardViewModel viewModelBuilder(context) => IntakeWizardViewModel();
}

class _DoneView extends StatelessWidget {
  final IntakeWizardViewModel vm;
  const _DoneView(this.vm);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.check_circle,
              size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('Brief emitted',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'The engine produced docs/design/brief.md and a seeded '
            'docs/design/registry.json from the elicited answers. '
            'Every inferred field is marked in the brief.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (vm.emitSummary != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(vm.emitSummary!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: vm.reset,
            child: const Text('Run again'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _Field extends StatelessWidget {
  final String label;
  final String hint;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final Provenance provenance;
  final ValueChanged<Provenance> onProvenance;

  const _Field({
    required this.label,
    required this.hint,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.provenance,
    required this.onProvenance,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
            enabled: enabled,
            onChanged: onChanged,
            controller: TextEditingController(text: value)
              ..selection = TextSelection.collapsed(offset: value.length),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: _ProvenancePicker(
            value: provenance,
            enabled: enabled,
            onChanged: onProvenance,
          ),
        ),
      ],
    );
  }
}

class _SurfaceRow extends StatelessWidget {
  final int index;
  final SurfaceEntry surface;
  final bool enabled;
  final bool canRemove;
  final IntakeWizardViewModel viewModel;

  const _SurfaceRow({
    required this.index,
    required this.surface,
    required this.enabled,
    required this.canRemove,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'id (tab.short)',
                hintText: 'projects.home',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              enabled: enabled,
              onChanged: (v) => viewModel.onSurfaceId(index, v),
              controller: TextEditingController(text: surface.id)
                ..selection =
                    TextSelection.collapsed(offset: surface.id.length),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'label',
                hintText: 'Home',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              enabled: enabled,
              onChanged: (v) => viewModel.onSurfaceLabel(index, v),
              controller: TextEditingController(text: surface.label)
                ..selection = TextSelection.collapsed(
                    offset: surface.label.length),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: _ProvenancePicker(
              value: surface.provenance,
              enabled: enabled,
              onChanged: (p) => viewModel.onSurfaceProv(index, p),
            ),
          ),
          if (canRemove)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: enabled ? () => viewModel.removeSurface(index) : null,
            ),
        ],
      ),
    );
  }
}

class _ProvenancePicker extends StatelessWidget {
  final Provenance value;
  final bool enabled;
  final ValueChanged<Provenance> onChanged;
  const _ProvenancePicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<Provenance>(
      value: value, // ignore: deprecated_member_use
      isExpanded: true,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      items: const [
        DropdownMenuItem(value: Provenance.client, child: Text('client')),
        DropdownMenuItem(value: Provenance.founder, child: Text('founder')),
        DropdownMenuItem(value: Provenance.inferred, child: Text('inferred')),
      ],
      onChanged: enabled ? (Provenance? p) {
        if (p != null) onChanged(p);
      } : null,
    );
  }
}
