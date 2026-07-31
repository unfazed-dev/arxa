// Network trace (ports probe-runner web_net): traces Network domain events
// across a navigation, folding them into per-request records. Observation
// JSON — the lens records, consumers assert.
library;

import '../cdp.dart';

/// Trace network traffic while navigating to [url]. Network is enabled for
/// [traceMs] + [settleMs] so the trace spans the full load. Requests are
/// folded by requestId: url/method from requestWillBeSent, status/mimeType
/// from responseReceived, failed from loadingFailed.
Future<Map<String, dynamic>> traceNet(String url,
    {int settleMs = 1500, int traceMs = 3000}) async {
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    final trace =
        tab.traceNetwork(Duration(milliseconds: traceMs + settleMs));
    await tab.navigateAndSettle(url, settleMs: settleMs);
    final events = await trace;
    final errors = [...tab.consoleErrors, ...tab.pageErrors];

    final byId = <String, Map<String, dynamic>>{};
    for (final e in events) {
      final method = e['method'] as String;
      final params = e['params'] as Map<String, dynamic>;
      switch (method) {
        case 'Network.requestWillBeSent':
          final req = params['request'] as Map<String, dynamic>?;
          final id = params['requestId']?.toString();
          if (req != null && id != null) {
            byId[id] = {
              'url': req['url'],
              'method': req['method'],
              'status': null,
              'mimeType': null,
              'failed': false,
            };
          }
        case 'Network.responseReceived':
          final id = params['requestId']?.toString();
          final entry = byId[id];
          if (entry != null) {
            final resp = params['response'] as Map<String, dynamic>?;
            if (resp != null) {
              entry['status'] = resp['status'];
              entry['mimeType'] = resp['mimeType'];
            }
          }
        case 'Network.loadingFailed':
          final id = params['requestId']?.toString();
          final entry = byId[id];
          if (entry != null) {
            entry['failed'] = true;
          }
      }
    }

    return {
      'url': url,
      'requests': byId.values.toList(),
      'consoleErrors': errors,
      'certified': errors.isEmpty,
    };
  } finally {
    await client.close();
  }
}
