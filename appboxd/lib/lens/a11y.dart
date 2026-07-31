// Accessibility-tree extraction (ports probe-runner web_a11y): one
// Accessibility.getFullAxTree call, flattened to role/name/ignored/children.
// Observation JSON — the lens records, consumers assert.
library;

import '../cdp.dart';

/// Extract the full accessibility tree at [url], one entry per node,
/// flattened to `{role, name, ignored, children}`. Children ids are passed
/// through as-is from the raw node map to preserve structure.
Future<Map<String, dynamic>> extractA11y(String url,
    {int settleMs = 1500}) async {
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.navigateAndSettle(url, settleMs: settleMs);
    final tree = await tab.getFullAxTree();
    final errors = [...tab.consoleErrors, ...tab.pageErrors];
    return {
      'url': url,
      'nodes': [
        for (final n in tree)
          {
            'role': (n['role'] as Map?)?['value'],
            'name': (n['name'] as Map?)?['value'],
            'ignored': n['ignored'] ?? false,
            'children': n['childIds'] ?? const <dynamic>[],
          },
      ],
      'consoleErrors': errors,
      'certified': errors.isEmpty,
    };
  } finally {
    await client.close();
  }
}
