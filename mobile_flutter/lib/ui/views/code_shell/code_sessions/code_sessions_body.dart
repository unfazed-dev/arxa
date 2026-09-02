// The code sessions body — shared by both form-factor siblings (mobile
// full-bleed, tablet centered at a readable width). Filter chips, session
// rows, pull-to-refresh, offline state with pairing/redial affordances.
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart' show ViewModelWidget;
import 'package:flutter/material.dart';

import 'package:arxa_studio_mobile/l10n/app_localizations.dart';

import '../../../../data/conversation/conversation.dart';
import 'code_sessions_viewmodel.dart';

class CodeSessionsBody extends ViewModelWidget<CodeSessionsViewModel> {
  const CodeSessionsBody({
    super.key,
    required this.viewModel,
    this.constrainWidth = false,
  });

  final CodeSessionsViewModel viewModel;

  /// Tablet wraps the list at a readable width; mobile runs full-bleed.
  final bool constrainWidth;

  @override
  Widget build(BuildContext context, _) {
    final l10n = AppLocalizations.of(context);
    Widget list = viewModel.filteredSessions.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.codeSessionsEmpty),
                if (viewModel.loadError == CodeSessionsError.offline) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(l10n.codeSessionsNotConnected),
                  ),
                  if (viewModel.needsPairing)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: FilledButton.icon(
                        onPressed: viewModel.goToPairing,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: Text(l10n.codeSessionsPairCta),
                      ),
                    ),
                ],
              ],
            ),
          )
        : RefreshIndicator(
            onRefresh: viewModel.refresh,
            child: ListView.builder(
              itemCount: viewModel.filteredSessions.length,
              itemBuilder: (context, i) {
                final session = viewModel.filteredSessions[i];
                return _SessionRow(
                  key: ValueKey(session.id),
                  session: session,
                  running: viewModel.isRunning(session),
                  // The list is newest-first: tile 0 IS the last-active
                  // session, marked even when no turn is running.
                  lastActive: i == 0,
                  onTap: () => viewModel.openSession(session),
                );
              },
            ),
          );
    if (constrainWidth) {
      list = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: list,
        ),
      );
    }
    return Column(
      children: [
        // Offline banner (loud, not silent) whenever the last pull failed.
        if (viewModel.loadError == CodeSessionsError.offline)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              dense: true,
              title: Text(l10n.codeSessionsNotConnected,
                  style: Theme.of(context).textTheme.labelLarge),
            ),
          ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final filter in CodeSessionsFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(switch (filter) {
                      CodeSessionsFilter.all => l10n.codeFilterAll,
                      CodeSessionsFilter.blocked => l10n.codeFilterBlocked,
                      CodeSessionsFilter.inProgress =>
                        l10n.codeFilterInProgress,
                      CodeSessionsFilter.done => l10n.codeFilterDone,
                    }),
                    selected: viewModel.filter == filter,
                    onSelected: (_) => viewModel.setFilter(filter),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: list),
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    super.key,
    required this.session,
    required this.running,
    required this.lastActive,
    required this.onTap,
  });

  final CodeSession session;

  /// The engine's live-turn flag — the row's pulsing green dot (the studio
  /// sidebar's "Running" pill, phone-sized).
  final bool running;

  /// The most recently active session (tile 0, newest-first) stays marked
  /// with a steady dot even when nothing is running.
  final bool lastActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      if (session.project != null || session.workspace != null)
        [session.project, session.workspace]
            .whereType<String>()
            .where((part) => part.isNotEmpty)
            .join(' · '),
      if (session.state != null && session.state!.isNotEmpty) session.state!,
      if (session.parkedReason != null) session.parkedReason!,
    ].where((part) => part.isNotEmpty).join(' — ');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        onTap: onTap,
        title: Text(session.displayTitle, style: theme.textTheme.titleMedium),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle.isNotEmpty) Text(subtitle),
            Text(relativeTime(context, session.updatedAt),
                style: theme.textTheme.labelSmall),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (running)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: _RunningDot(key: ValueKey('running-dot')),
              )
            else if (lastActive)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: _LastActiveDot(key: ValueKey('last-active-dot')),
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

/// The active-session indicator: a small green dot, gently pulsing so a
/// "running" glance reads at list speed. Steady when reduced motion is on.
class _RunningDot extends StatefulWidget {
  const _RunningDot({super.key});

  @override
  State<_RunningDot> createState() => _RunningDotState();
}

class _RunningDotState extends State<_RunningDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: 1,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Color(0xFF34C759),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// The last-active marker: the same green dot, steady — the most recently
/// active session stays visibly marked even when no turn is running.
class _LastActiveDot extends StatelessWidget {
  const _LastActiveDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: Color(0xFF34C759),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Epoch-milliseconds -> a coarse relative label ("now", "5m", "3h", "2d").
String relativeTime(BuildContext context, int epochMs) {
  final l10n = AppLocalizations.of(context);
  final delta = DateTime.now().millisecondsSinceEpoch - epochMs;
  if (delta < 60000) return l10n.codeJustNow;
  final minutes = delta ~/ 60000;
  if (minutes < 60) return l10n.codeMinutesAgo(minutes);
  final hours = minutes ~/ 60;
  if (hours < 24) return l10n.codeHoursAgo(hours);
  return l10n.codeDaysAgo(hours ~/ 24);
}
