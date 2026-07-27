import 'package:flutter/material.dart';

/// settings.devices — paired · revoke (brief §4, J7 remote pairing).
class SettingsDevicesView extends StatelessWidget {
  const SettingsDevicesView({super.key});

  @override
  Widget build(BuildContext context) {
    // Paired devices come from the companion pairing state (plan 12). Until then
    // the empty state carries wording (brief non-negotiable #5).
    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(24), children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.phone_android),
                title: const Text('No paired device'),
                subtitle: const Text('Pair a phone by QR (journey J7) to drive the '
                    'pipeline remotely and serve the prototype fullscreen.'),
                trailing: FilledButton.tonal(
                  onPressed: () {},
                  child: const Text('Pair'),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
