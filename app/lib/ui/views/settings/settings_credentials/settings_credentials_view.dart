import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'package:app_box/services/credential_service.dart';
import 'settings_credentials_viewmodel.dart';

/// settings.credentials.
///
/// The two sections are separate because the concepts are: a **BYO API key** is
/// how the app reaches an LLM provider (it sets the tier), a **licence** is a
/// purchase precondition (8.12) that sets no tier at all. Before this split the
/// surface had a licence field and no key field, while `saveKey` stored the
/// licence text as an API key.
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
                title: const Text('Provider auth'),
                subtitle: Text(viewModel.tierLabel),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: Icon(
                  viewModel.hasLicence
                      ? Icons.verified_outlined
                      : Icons.receipt_long_outlined,
                  color: cs.primary,
                ),
                title: const Text('Licence'),
                subtitle: Text(viewModel.licenceLabel),
              ),
            ),
            const SizedBox(height: 24),
            const Text('BYO provider API key',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Used to reach an LLM provider directly. Stored in the '
              '${viewModel.storageTierLabel}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: viewModel.apiKeyIdController,
              onChanged: (_) => viewModel.rebuildUi(),
              decoration: const InputDecoration(
                labelText: 'Provider',
                hintText: 'anthropic',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: viewModel.apiKeyController,
              onChanged: (_) => viewModel.rebuildUi(),
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API key',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.vpn_key),
              label: const Text('Store API key'),
              onPressed: viewModel.canSaveApiKey ? viewModel.saveApiKey : null,
            ),
            const SizedBox(height: 24),
            const Text('Licence (precondition for build)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Required before the builder phase runs. Nothing goes red for '
              'the lack of one.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: viewModel.licenceController,
              onChanged: (_) => viewModel.rebuildUi(),
              decoration: const InputDecoration(
                labelText: 'Licence string',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.receipt_long),
              label: const Text('Store licence'),
              onPressed:
                  viewModel.canSaveLicence ? viewModel.saveLicence : null,
            ),
            const SizedBox(height: 24),
            const Text('Stored provider credentials',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (viewModel.credentials.isEmpty)
              const Text('None yet.')
            else
              for (final c in viewModel.credentials)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.key),
                  title: Text(c.label),
                  subtitle: Text(_tierName(c.tier)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove ${c.label}',
                    onPressed: () => viewModel.deleteCredential(c.id),
                  ),
                ),
          ]),
        ),
      ),
    );
  }

  static String _tierName(CredentialTier t) => switch (t) {
        CredentialTier.byoKey => 'BYO key',
        CredentialTier.oauth => 'OAuth token',
        CredentialTier.harness => 'Harness CLI (no token held)',
        CredentialTier.none => '—',
      };

  @override
  void onViewModelReady(SettingsCredentialsViewModel viewModel) =>
      viewModel.initialise();

  @override
  SettingsCredentialsViewModel viewModelBuilder(context) =>
      SettingsCredentialsViewModel();
}
