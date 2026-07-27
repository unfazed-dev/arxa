import 'package:flutter/material.dart';

import 'package:app_box/services/kit_inventory_service.dart';
import 'package:app_box/ui/common/app_box_widgets.dart';

/// settings.kits — wired vs stubbed (brief §4, done-when #4).
///
/// THE load-bearing honesty surface: a buyer (Michelle) who picks a stubbed
/// provider and meets `UnimplementedError` at build time has been misled. Every
/// stub is labelled with what throws — never offered as available.
class SettingsKitsView extends StatelessWidget {
  const SettingsKitsView({super.key});

  @override
  Widget build(BuildContext context) {
    final inventory = KitInventoryService();
    final kits = inventory.kits;
    return Scaffold(
      appBar: AppBar(title: const Text('Kits')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: kits.length,
            itemBuilder: (_, i) {
              final kit = kits[i];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ExpansionTile(
                  leading: Icon(kit.hasStub ? Icons.warning_amber : Icons.check_circle,
                      color: kit.hasStub ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary),
                  title: Text(kit.name),
                  subtitle: Text(_phaseLabel(kit.phase)),
                  children: [
                    for (final p in kit.providers)
                      ListTile(
                        dense: true,
                        title: Text(p.name),
                        trailing: ProviderBadge(
                            wired: p.state == ProviderState.wired, detail: p.detail),
                        subtitle: p.state == ProviderState.stub
                            ? Text(p.detail ?? 'Stub', style: const TextStyle(fontSize: 12))
                            : null,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _phaseLabel(KitPhase p) => switch (p) {
        KitPhase.stable => 'stable — wired',
        KitPhase.nativeFirst => 'native-first',
        KitPhase.nativeFirstPartial => 'native-first-partial',
      };
}
