import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'projects_new_viewmodel.dart';

/// projects.new — form · validating · error (brief §4). Targets chosen here are
/// written to pipeline state and read by every later gate (brief J2).
class ProjectsNewView extends StackedView<ProjectsNewViewModel> {
  const ProjectsNewView({super.key});

  @override
  Widget builder(context, viewModel, child) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New project')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Intake', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(labelText: 'Project name', border: OutlineInputBorder()),
                enabled: viewModel.state != ProjectsNewState.validating,
                onChanged: viewModel.onName,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(labelText: 'Brand (optional)', border: OutlineInputBorder()),
                enabled: viewModel.state != ProjectsNewState.validating,
                onChanged: viewModel.onBrand,
              ),
              const SizedBox(height: 12),
              const Text('Target: macOS (the dogfood target — §11 platform only; viewports derive.)'),
              const SizedBox(height: 16),
              if (viewModel.state == ProjectsNewState.error)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(viewModel.formError ?? '',
                      style: TextStyle(color: cs.error, fontWeight: FontWeight.w600)),
                ),
              FilledButton.icon(
                icon: viewModel.state == ProjectsNewState.validating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text(viewModel.state == ProjectsNewState.validating ? 'Validating…' : 'Create project'),
                onPressed: viewModel.state == ProjectsNewState.validating ? null : viewModel.create,
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  ProjectsNewViewModel viewModelBuilder(context) => ProjectsNewViewModel();
}
