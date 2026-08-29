// Approvals list viewmodel — the approvals_shell goes live (grill D60:
// the full loop: list pending approvals, answer on the phone, the agent
// unblocks engine-side). Pull-based v1: refresh on model-ready, after each
// decision, and on pull-to-refresh; the repository exposes watch() for
// later reactive wiring.
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_studio_mobile/app/app.locator.dart';

import '../../../../data/approvals/approval.dart';
import '../../../../data/approvals/approvals_api_client.dart';
import '../../../../data/approvals/approvals_repository.dart';

/// Why the last refresh failed — the view maps these to l10n copy.
enum ApprovalsError { offline, remote }

class ApprovalsListViewModel extends BaseViewModel {
  ApprovalsListViewModel([ApprovalsRepository? repository])
      : _repository = repository ?? locator<ApprovalsRepository>();

  final ApprovalsRepository _repository;

  List<Approval> get approvals => _approvals;
  List<Approval> _approvals = const [];

  /// The last refresh failure (D62: loud, never a queue). Null after a
  /// successful refresh — the cached list still renders while set.
  /// (Named loadError: stacked's BaseViewModel already owns an error field.)
  ApprovalsError? get loadError => _error;
  ApprovalsError? _error;

  /// The approval id whose decision POST is in flight (disables its UI).
  String? get decidingId => _decidingId;
  String? _decidingId;

  Future<void> refresh() async {
    try {
      await _repository.refresh();
      _error = null;
    } on ApprovalsOfflineException {
      _error = ApprovalsError.offline;
    } on Exception {
      _error = ApprovalsError.remote;
    }
    _approvals = await _repository.list();
    notifyListeners();
  }

  /// Answer one approval. Returns true when accepted; false when refused
  /// (someone answered first) or offline — the view surfaces which, and a
  /// refresh follows either way.
  Future<bool> decide(Approval approval, List<ApprovalAnswer> answers) async {
    _decidingId = approval.id;
    notifyListeners();
    try {
      await _repository.decide(approval.id, answers);
      return true;
    } on ApprovalsConflictException {
      return false;
    } on ApprovalsOfflineException {
      _error = ApprovalsError.offline;
      return false;
    } finally {
      _decidingId = null;
      await refresh();
    }
  }
}
