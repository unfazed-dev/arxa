import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'settings_credentials_viewmodel.dart';

class SettingsCredentialsView extends StackedView<SettingsCredentialsViewModel> {
  const SettingsCredentialsView({super.key});

  @override
  Widget builder(context, viewModel, child) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Credentials')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(24), children: [
            Card(
              child: ListTile(
                leading: Icon(Icons.lock, color: cs.primary),
                title: const Text('Active tier'),
                subtitle: Text(viewModel.tierLabel),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Licence (precondition for build)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                  labelText: 'Licence string', border: OutlineInputBorder()),
              onChanged: viewModel.onLicence,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.vpn_key),
              label: const Text('Store licence in Keychain'),
              onPressed: viewModel.saveLicence,
            ),
            const SizedBox(height: 24),
            const Text('Stored credentials', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (viewModel.credentials.isEmpty)
              const Text('None yet.')
            else
              for (final c in viewModel.credentials)
                ListTile(dense: true, leading: const Icon(Icons.key), title: Text('${c.label} (${c.id})')),
          ]),
        ),
      ),
    );
  }

  @override
  SettingsCredentialsViewModel viewModelBuilder(context) => SettingsCredentialsViewModel();
}
