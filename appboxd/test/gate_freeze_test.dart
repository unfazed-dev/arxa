// Freeze gate — TSX view templates. Post nunjucks→tsx migration a design
// carries zero *_view.html files; the shape check and the approval-stamp
// inputs hash must accept ui/views/**/*_view.tsx alongside *_view.html.
// The gate runs in a fixture subprocess (freeze_tsx_probe.dart) so
// FREEZE_RENDER=skip reaches the render pass — Platform.environment is
// unmodifiable in-process.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('tsx views pass shape and fold into the approval inputs hash',
      () async {
    final r = await Process.run(
      Platform.resolvedExecutable,
      ['test/fixtures/freeze_tsx_probe.dart'],
      environment: {'FREEZE_RENDER': 'skip'},
    );
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    final scenarios =
        (jsonDecode(r.stdout as String) as List).cast<Map<String, dynamic>>();
    Map<String, dynamic> byName(String n) =>
        scenarios.singleWhere((s) => s['name'] == n);

    final approve = byName('tsx-only approve');
    expect(approve['passed'], isTrue, reason: approve['details'] as String);
    expect(approve['details'], contains('shape: 1 view template(s)'));

    for (final n in ['tsx edit invalidates', 'html+tsx changes hash']) {
      final s = byName(n);
      expect(s['passed'], isFalse, reason: s['details'] as String);
      expect(s['details'], contains('frozen inputs changed since approval'));
    }

    final noViews = byName('no views');
    expect(noViews['passed'], isFalse);
    expect(noViews['details'], contains('no view templates'));
    expect(noViews['details'], contains('_view.{html,tsx}'));

    final htmlOnly = byName('html-only');
    expect(htmlOnly['passed'], isTrue, reason: htmlOnly['details'] as String);
    expect(htmlOnly['details'], contains('shape: 1 view template(s)'));
  });
}
