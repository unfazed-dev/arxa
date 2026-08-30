// arxa-scaffolder surface: approvals_shell_approvals_view (approvals.list)
// arxa-builder: LIVE (grill D60–D68) — each pending approval renders as a
// card with its questions; options answer directly, free-text questions
// get a field; one Submit answers the whole batch (the engine validates
// exactly that shape).
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ArxaKitGlyphs, ArxaKitNativeAppBar, ArxaKitNativeIconButton, StackedView;
import 'package:flutter/material.dart';

import 'package:arxa_studio_mobile/l10n/app_localizations.dart';

import '../../../../data/approvals/approval.dart';
import 'approvals_list_viewmodel.dart';

class ApprovalsListView extends StackedView<ApprovalsListViewModel> {
  const ApprovalsListView({super.key});

  @override
  Widget builder(
      BuildContext context, ApprovalsListViewModel viewModel, Widget? child) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: ArxaKitNativeAppBar(
        title: l10n.approvalsTitle,
        actions: [
          // The studio session is the paired home; this is the way back from
          // the approvals deep link (both the offline and list states).
          Tooltip(
            message: l10n.approvalsOpenStudio,
            child: ArxaKitNativeIconButton(
              glyph: ArxaKitGlyphs.home,
              onPressed: viewModel.goToStudio,
            ),
          ),
        ],
      ),
      body: viewModel.approvals.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.approvalsEmpty),
                  if (viewModel.loadError == ApprovalsError.offline) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(l10n.approvalsNotConnected),
                    ),
                    if (viewModel.needsPairing)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: FilledButton.icon(
                          onPressed: viewModel.goToPairing,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text(l10n.approvalsPairCta),
                        ),
                      ),
                  ],
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: viewModel.refresh,
              child: ListView.builder(
                itemCount: viewModel.approvals.length,
                itemBuilder: (context, i) => _ApprovalCard(
                  key: ValueKey(viewModel.approvals[i].id),
                  approval: viewModel.approvals[i],
                  busy: viewModel.decidingId == viewModel.approvals[i].id,
                  onDecide: (answers) =>
                      viewModel.decide(viewModel.approvals[i], answers),
                ),
              ),
            ),
    );
  }

  @override
  ApprovalsListViewModel viewModelBuilder(context) => ApprovalsListViewModel();

  @override
  void onViewModelReady(ApprovalsListViewModel viewModel) {
    viewModel
      ..listenTransport()
      ..refresh();
  }
}

/// One pending approval: summary line + every question with its options
/// (chips, single- or multi-select) or a free-text field, and a submit
/// button enabled only when every question has an answer — the engine
/// accepts complete batches only.
class _ApprovalCard extends StatefulWidget {
  const _ApprovalCard({
    super.key,
    required this.approval,
    required this.busy,
    required this.onDecide,
  });

  final Approval approval;
  final bool busy;
  final Future<bool> Function(List<ApprovalAnswer> answers) onDecide;

  @override
  State<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<_ApprovalCard> {
  final Map<String, Set<String>> _selected = {};
  final Map<String, TextEditingController> _custom = {};
  bool _sending = false;
  String? _refused;

  @override
  void dispose() {
    for (final controller in _custom.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _customFor(ApprovalQuestion question) =>
      _custom.putIfAbsent(question.id, TextEditingController.new);

  /// A question is answered when at least one option is selected or the
  /// custom field has text (free-text questions need the field; single-select
  /// custom replaces the selection — kept mutually exclusive below).
  bool _answered(ApprovalQuestion question) {
    if (question.options.isEmpty) {
      return _customFor(question).text.trim().isNotEmpty;
    }
    return (_selected[question.id]?.isNotEmpty ?? false) ||
        _customFor(question).text.trim().isNotEmpty;
  }

  bool get _complete =>
      widget.approval.questions.every(_answered) && !_sending;

  Future<void> _submit() async {
    setState(() {
      _sending = true;
      _refused = null;
    });
    final answers = [
      for (final question in widget.approval.questions)
        ApprovalAnswer(
          questionId: question.id,
          selected: (_selected[question.id] ?? const {}).toList(),
          custom: _customFor(question).text.trim().isEmpty
              ? null
              : _customFor(question).text,
        ),
    ];
    final accepted = await widget.onDecide(answers);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (!accepted) {
        _refused = AppLocalizations.of(context).approvalsAnsweredElsewhere;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.approval.summary, style: theme.textTheme.titleMedium),
            if (_refused != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_refused!,
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
            for (final question in widget.approval.questions) ...[
              const SizedBox(height: 12),
              if (question.header != null)
                Text(question.header!, style: theme.textTheme.labelSmall),
              Text(question.question),
              if (question.options.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final option in question.options)
                      FilterChip(
                        label: Text(option.label),
                        selected:
                            _selected[question.id]?.contains(option.label) ?? false,
                        onSelected: widget.busy || _sending
                            ? null
                            : (value) => setState(() {
                                  final set = _selected.putIfAbsent(
                                      question.id, () => <String>{});
                                  if (question.multiSelect) {
                                    value ? set.add(option.label) : set.remove(option.label);
                                  } else {
                                    set
                                      ..clear()
                                      ..addAll(value ? [option.label] : const <String>{});
                                    if (value) {
                                      _customFor(question).clear();
                                    }
                                  }
                                }),
                      ),
                  ],
                ),
              if (question.options.isEmpty || question.multiSelect)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(
                    controller: _customFor(question),
                    enabled: !(widget.busy || _sending),
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      hintText: question.options.isEmpty
                          ? l10n.approvalsCustomHint
                          : l10n.approvalsCustomOptionalHint,
                    ),
                    onChanged: (value) => setState(() {
                      // Single-select: custom REPLACES a chip selection so
                      // the engine never receives both (it rejects that
                      // combination by contract).
                      if (!question.multiSelect && value.isNotEmpty) {
                        _selected[question.id]?.clear();
                      }
                    }),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _complete ? _submit : null,
                child: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.approvalsSend),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
