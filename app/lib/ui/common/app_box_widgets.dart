import 'package:flutter/material.dart';

import 'package:app_box/ui/common/app_colors.dart';

/// Shared app_box surface widgets. Brief non-negotiables these enforce:
///  #1 — red means broken (licence is a precondition, never red).
///  #3 — stubs are labelled (never offer a target that throws).
///  #4 — the three gates are visually unmistakable (the gate orange).
///  #5 — empty states carry wording.

/// A labelled state chip: idle / running / green / red / pending / approved.
class StateChip extends StatelessWidget {
  const StateChip(this.label, {super.key, this.tone = ChipTone.neutral});
  final String label;
  final ChipTone tone;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tone == ChipTone.danger
            ? cs.errorContainer
            : tone == ChipTone.good
                ? cs.primaryContainer
                : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: tone == ChipTone.danger
                  ? cs.onErrorContainer
                  : tone == ChipTone.good
                      ? cs.onPrimaryContainer
                      : cs.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 12)),
    );
  }
}

enum ChipTone { neutral, good, danger }

/// A gate surface banner — the unmistakable orange (brief §3). Visually distinct
/// from anything an agent can do alone: approval is the product's core claim.
class GateBanner extends StatelessWidget {
  const GateBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.approved,
    this.confirmLabel = 'Approve',
    this.onConfirm,
  });
  final String title;
  final String subtitle;
  final bool approved;
  final String confirmLabel;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kcGateColor.withValues(alpha: 0.12),
        border: Border.all(color: kcGateColor, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        const Icon(Icons.gpp_maybe, color: kcGateColor, size: 40),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(
                    color: kcGateColor, fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(approved ? 'Approved — human confirmed.' : 'Pending — an agent cannot mint this.',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: approved ? kcGateColorDark : null)),
          ]),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: kcGateColor,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.check_circle_outline),
          label: Text(approved ? 'Approved' : confirmLabel),
          onPressed: approved ? null : onConfirm,
        ),
      ]),
    );
  }
}

/// Brief non-negotiable #5 — empty states carry wording (the htmx experiment
/// found empty-state copy simply absent). Never a bare "no items".
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.body});
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.inbox_outlined, size: 56, color: cs.outline),
            const SizedBox(height: 16),
            Text(title,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }
}

/// A wired/stubbed badge for settings.kits (done-when #4 — the honesty).
class ProviderBadge extends StatelessWidget {
  const ProviderBadge({super.key, required this.wired, required this.detail});
  final bool wired;
  final String? detail;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: wired ? 'Wired' : (detail ?? 'Stub — throws UnimplementedError'),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(wired ? Icons.check_circle : Icons.error_outline,
            size: 16, color: wired ? cs.primary : cs.error),
        const SizedBox(width: 6),
        Text(wired ? 'Wired' : 'Stub',
            style: TextStyle(
                color: wired ? cs.primary : cs.error,
                fontWeight: FontWeight.w600,
                fontSize: 12)),
      ]),
    );
  }
}
