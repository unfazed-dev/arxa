import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'package:app_box/ui/common/app_box_widgets.dart';
import 'projects_home_viewmodel.dart';

/// projects.home — empty · list · loading (brief §4).
class ProjectsHomeView extends StackedView<ProjectsHomeViewModel> {
  const ProjectsHomeView({super.key});

  @override
  Widget builder(context, viewModel, child) {
    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New project'),
        onPressed: () {}, // routes to projects.new via the design intake shell
      ),
      body: switch (viewModel.state) {
        ProjectsHomeState.loading => const Center(child: CircularProgressIndicator()),
        ProjectsHomeState.empty => const EmptyState(
            title: 'No projects yet',
            body: 'Start a conversation or intake form to design your first app. '
                'app_box takes it from a brief to a shipped Flutter app — designed, '
                'gated, scaffolded and deployed.'),
        ProjectsHomeState.list => ListView.builder(
            itemCount: viewModel.projects.length,
            itemBuilder: (_, i) {
              final p = viewModel.projects[i];
              return ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(p.name),
                subtitle: Text(p.targets.join(' · ')),
              );
            },
          ),
      },
    );
  }

  @override
  ProjectsHomeViewModel viewModelBuilder(context) =>
      ProjectsHomeViewModel()..load();

  @override
  void onViewModelReady(ProjectsHomeViewModel viewModel) => viewModel.load();
}
