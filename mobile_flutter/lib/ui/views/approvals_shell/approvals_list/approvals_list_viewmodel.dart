// arxa-builder: skeleton. Notification-driven; data slice lands with the
// cairn approvals schema (Repository/Facade over ArxaKitRepository ports).
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

class ApprovalsListViewModel extends BaseViewModel {
  /// Placeholder until the approvals entity registers with cairn.
  List<String> get approvals => const [];

  Future<void> refresh() async {}
}
