import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:appbox_kit_i18n/stacked_kit_i18n.dart';

import 'package:appbox/app/app.locator.dart';
import 'package:appbox/l10n/app_localizations.dart';

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
    if (!mounted) return;
    if (!started) {
      _show(AppLocalizations.of(context).notReadySignal);
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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: const [_LanguageMenu()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              l10n.servePrototypeTitle,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.servePrototypeInstructions,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              minLines: 2,
              maxLines: 4,
              autocorrect: false,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.readyLineFieldLabel,
                // Literal payload example — a code sample, not prose.
                hintText: '{"tag":"app-box-prototype-ready","url":...}',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _serve,
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.serve),
            ),
            const SizedBox(height: 24),
            const _EnvBlockedNote(),
          ],
        ),
      ),
    );
  }
}

/// Compact language switch: System (clears the persisted override) or one of
/// the kit's supported languages (persists an override via [KitI18n]).
class _LanguageMenu extends StatelessWidget {
  const _LanguageMenu();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kitI18n = locator<KitI18n>();
    return PopupMenuButton<String>(
      icon: const Icon(Icons.language),
      tooltip: l10n.languageLabel,
      onSelected: (tag) => tag == 'system'
          ? kitI18n.clearOverride()
          : kitI18n.setLocale(tag),
      itemBuilder: (context) => [
        PopupMenuItem(value: 'system', child: Text(l10n.languageSystem)),
        for (final lang in KitLanguage.supported)
          PopupMenuItem(value: lang.tag, child: Text(lang.nameNative)),
      ],
    );
  }
}

class _EnvBlockedNote extends StatelessWidget {
  const _EnvBlockedNote();
  @override
  Widget build(BuildContext context) {
    return Text(
      AppLocalizations.of(context).envBlockedNote,
      style: const TextStyle(fontSize: 12, color: Colors.black54),
    );
  }
}
