// DOM extraction (ports probe-runner web_dom): the DOMSnapshot path for
// structured layout/style capture, plus an outerHTML shortcut. Observation
// JSON — the lens records, consumers assert.
library;

import '../cdp.dart';

/// Capture a DOMSnapshot.captureSnapshot envelope at [url]. [computedStyles]
/// selects which computed-style names are included per node.
Future<Map<String, dynamic>> extractDom(
  String url, {
  int settleMs = 1500,
  Map<String, String> cookies = const {},
  List<String> computedStyles = const [
    'display',
    'position',
    'color',
    'background-color',
    'font-size',
  ],
}) async {
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.seedCookies(
        Uri.parse(url).replace(path: '/', query: '', fragment: ''), cookies);
    await tab.navigateAndSettle(url, settleMs: settleMs);
    final snapshot = await tab.captureDomSnapshot(computedStyles);
    final errors = [...tab.consoleErrors, ...tab.pageErrors];
    return {
      'url': url,
      'snapshot': snapshot,
      'consoleErrors': errors,
      'certified': errors.isEmpty,
    };
  } finally {
    await client.close();
  }
}

/// Outer-HTML shortcut (probe-runner's outerHTML path): one evaluate call.
Future<String> extractOuterHtml(String url,
    {int settleMs = 1500, Map<String, String> cookies = const {}}) async {
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.seedCookies(
        Uri.parse(url).replace(path: '/', query: '', fragment: ''), cookies);
    await tab.navigateAndSettle(url, settleMs: settleMs);
    return await tab.evaluate('document.documentElement.outerHTML') as String;
  } finally {
    await client.close();
  }
}
