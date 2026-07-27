import 'package:flutter/material.dart';

import 'package:app_box/services/kit_inventory_service.dart';
import 'package:app_box/ui/common/app_box_widgets.dart';

/// ship.targets — fastlane · shorebird · CF Pages (brief §4). Vercel is a STUB
/// (stub-inventory.md: VercelTarget throws) — rendered honestly as unavailable,
/// never offered (brief non-negotiable #3: never offer a target that throws).
class ShipTargetsView extends StatelessWidget {
  const ShipTargetsView({super.key});

  List<KitProvider> get _targets {
    final deploy = KitInventoryService().kits.firstWhere((k) => k.name == 'deploy');
    return deploy.providers;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ship targets')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            itemCount: _targets.length,
            itemBuilder: (_, i) {
              final t = _targets[i];
              final wired = t.state == ProviderState.wired;
              return Card(
                child: ListTile(
                  leading: Icon(wired ? Icons.check_circle : Icons.block,
                      color: wired ? cs.primary : cs.error),
                  title: Text(t.name),
                  subtitle: Text(wired
                      ? 'Wired — available'
                      : (t.detail ?? 'Stub — not available')),
                  trailing: ProviderBadge(wired: wired, detail: t.detail),
                  enabled: wired,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
