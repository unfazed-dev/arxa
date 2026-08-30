// Approvals list viewmodel — the approvals_shell goes live (grill D60:
// the full loop: list pending approvals, answer on the phone, the agent
// unblocks engine-side). Reactive (D68): refresh on model-ready, after each
// decision, on pull-to-refresh, AND whenever the tunnel (re)announces
// connected; a pull that finds the link down re-kicks the dial so a desktop
// that came back late is found without user action.
import 'dart:async';

import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_studio_mobile/app/app.locator.dart';
import 'package:arxa_studio_mobile/app/app.router.dart';

import '../../../../data/approvals/approval.dart';
import '../../../../data/approvals/approvals_api_client.dart';
import '../../../../data/approvals/approvals_repository.dart';
import '../../../../services/transport_service.dart';

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

  /// The last refresh found the link down with NOTHING stored to resume —
  /// the view offers the QR-scan route instead of a doomed dial.
  bool get needsPairing => _needsPairing;
  bool _needsPairing = false;

  StreamSubscription<ArxaConnectionStatus>? _statusSub;

  /// Lazy: unit tests construct the model without the app locator.
  RouterService get _router => locator<RouterService>();

  /// Auto-refresh (D68): re-pull whenever the tunnel (re)announces
  /// connected — the cold-start dial landing late, a foreground redial, and
  /// a recovered desktop all land here with no user action. Subscribes once.
  void listenTransport() {
    if (_statusSub != null) return;
    _statusSub = _repository.transport.status.listen((s) {
      if (s.state == ArxaConnectionState.connected) refresh();
    });
  }

  /// Straight to the QR scanner (the desktop mints the ticket — the user
  /// scans; the app never generates codes).
  void goToPairing() => _router.replaceWith(PairingScanViewRoute());

  /// The studio session is the paired home; the approvals deep link replaces
  /// it on a notification tap, so this pushes it back on top (back returns
  /// to approvals).
  void goToStudio() => _router.navigateTo(StudioSessionViewRoute());

  Future<void> refresh() async {
    try {
      await _repository.refresh();
      _error = null;
      _needsPairing = false;
    } on ApprovalsOfflineException {
      _error = ApprovalsError.offline;
      await _kickRedial();
    } on Exception {
      _error = ApprovalsError.remote;
    }
    _approvals = await _repository.list();
    notifyListeners();
  }

  /// A failed pull means the link is down: re-kick the dial so a desktop
  /// that came back late gets found — the connected announcement then
  /// triggers the auto-refresh. Nothing stored: surface the scanner instead.
  Future<void> _kickRedial() async {
    final transport = _repository.transport;
    if (!await transport.hasStoredPairing()) {
      _needsPairing = true;
      notifyListeners();
      return;
    }
    await transport.resume();
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

  @override
  void dispose() {
    unawaited(_statusSub?.cancel());
    super.dispose();
  }
}