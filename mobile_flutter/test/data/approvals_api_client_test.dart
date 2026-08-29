// ApprovalsApiClient: transport-level request failures (socket refused,
// connection closed mid-response, timeout) surface as the ONE offline
// exception the viewmodels already catch — not raw dart:io errors that
// escape the on-ApprovalsOfflineException clauses (memo 3b: the zombie
// link failed fast with "Connection closed before full header" and the
// inline offline copy never showed).
import 'package:arxa_studio_mobile/data/approvals/approvals_api_client.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a connection-level failure surfaces as ApprovalsOfflineException',
      () async {
    // Connected fake serving a loopback port nobody listens on: the request
    // fails at the socket layer, exactly like the zombie link.
    final transport = FakeTransportService();
    await transport.beginPairing('ticket');
    final api = ApprovalsApiClient(transport: transport);

    await expectLater(
      () => api.list(),
      throwsA(isA<ApprovalsOfflineException>()),
    );
  });

  test('no tunnel (studioUrl null) stays the plain offline exception', () async {
    final api = ApprovalsApiClient(transport: FakeTransportService());

    await expectLater(
      () => api.list(),
      throwsA(isA<ApprovalsOfflineException>()),
    );
  });
}
