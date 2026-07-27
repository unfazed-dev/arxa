import 'dart:convert';

import 'package:flutter/material.dart';

import '../channel/prototype_channel_service.dart';
import '../config/companion_config.dart';
import '../prototype/last_render_store.dart';
import '../prototype/prototype_session.dart';
import 'prototype_view.dart';

/// The companion home: pair with the desktop, then serve a prototype.
///
/// The primary path is QR pairing over a LAN-local, TLS-pinned channel (12.3).
/// That ceremony needs a real device + camera + Bonjour (env-blocked here).
/// The fallback path §15 names — "a plain LAN URL stays available as a
/// fallback for handing a client a link" — is wired below so the prototype
/// view, its FAB and the heartbeat are exercisable without the device stack.
///
/// Paste the desktop's ready-line JSON (the P09 contract) or a bare URL and
/// tap Serve.
class CompanionHomeView extends StatefulWidget {
  const CompanionHomeView({super.key, required this.config});

  final CompanionConfig config;

  @override
  State<CompanionHomeView> createState() => _CompanionHomeViewState();
}

class _CompanionHomeViewState extends State<CompanionHomeView> {
  final _ctrl = TextEditingController();
  late final PrototypeSession _session;

  @override
  void initState() {
    super.initState();
    _session = PrototypeSession(
      channel: PrototypeChannelService(config: widget.config),
      renderStore: LastRenderStore(),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _session.channel.dispose();
    super.dispose();
  }

  Future<void> _serve() async {
    final input = _ctrl.text.trim();
    if (input.isEmpty) return;
    // Accept either the ready-line JSON contract or a bare URL.
    Map<String, dynamic> payload;
    if (input.startsWith('{')) {
      payload = jsonDecode(input) as Map<String, dynamic>;
    } else {
      payload = {
        'tag': 'app-box-prototype-ready',
        'url': input,
        'port': Uri.tryParse(input)?.port ?? 0,
        'host': Uri.tryParse(input)?.host ?? '',
      };
    }
    final started = await _session.handleReadyLine(payload);
    if (!started || !mounted) {
      _show('Not the prototype-ready signal — expected the ready-line payload.');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrototypeView(
          session: _session,
          config: widget.config,
          onExit: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }

  void _show(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('app_box companion')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Serve a prototype',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Paste the desktop ready-line payload (the JSON the prototype '
              'server prints once it is listening) or a bare LAN URL, then tap '
              'Serve. The FAB carries the channel state — dead on kill, while '
              'the WebView keeps the last render.',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              minLines: 2,
              maxLines: 4,
              autocorrect: false,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Ready-line JSON or URL',
                hintText: '{"tag":"app-box-prototype-ready","url":...}',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _serve,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Serve'),
            ),
            const SizedBox(height: 24),
            const _EnvBlockedNote(),
          ],
        ),
      ),
    );
  }
}

class _EnvBlockedNote extends StatelessWidget {
  const _EnvBlockedNote();
  @override
  Widget build(BuildContext context) {
    return const Text(
      'QR pairing (12.3), Bonjour discovery (12.2) and on-device gate control '
      '(12.6) need a signed iOS build on real hardware — env-blocked in this '
      'run. The heartbeat + FAB channel-state proof does not; see the test '
      'suite.',
      style: TextStyle(fontSize: 12, color: Colors.black54),
    );
  }
}
