// GateContext.targets — a repo-mode app's arxa.json outranks the engine's
// pipeline state. Gating energize-studio used to read arxa's own
// default.state.json (`[macos]`) while the app declared four targets, so three
// went silently unchecked. See docs/plans/arxa-rename-handoff-response.md (A5c).

import 'dart:convert';
import 'dart:io';

import 'package:arxa/gates.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('arxa_targets_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// A fake engine checkout whose pipeline state declares [targets].
  String engine(List<String> targets) {
    final root = Directory('${tmp.path}/engine')..createSync(recursive: true);
    Directory('${root.path}/pipeline/state').createSync(recursive: true);
    File('${root.path}/pipeline/state/default.state.json').writeAsStringSync(
      jsonEncode({'phase': 'intake', 'targets': targets}),
    );
    return root.path;
  }

  /// A repo-mode app dir carrying an arxa.json marker.
  String app(List<String> targets) {
    final d = Directory('${tmp.path}/app')..createSync(recursive: true);
    File('${d.path}/arxa.json').writeAsStringSync(jsonEncode({
      'name': 'demo',
      'kind': 'app',
      'targets': targets,
      'locales': ['en'],
    }));
    return d.path;
  }

  group('GateContext.targets', () {
    test('the app marker wins over engine pipeline state', () {
      final ctx = GateContext(
        repoRoot: engine(['macos']),
        appRoot: app(['ios', 'android', 'macos', 'web']),
      );
      expect(ctx.targets, ['ios', 'android', 'macos', 'web'],
          reason: 'the repo owns its pipeline state — the arxa law');
      expect(ctx.state.targets, ['macos'],
          reason: 'engine state is untouched, just outranked');
    });

    test('no appRoot -> engine state, unchanged (gating arxa itself)', () {
      final ctx = GateContext(repoRoot: engine(['macos']));
      expect(ctx.targets, ['macos']);
    });

    test('appRoot with no marker -> engine state', () {
      final bare = Directory('${tmp.path}/bare')..createSync(recursive: true);
      final ctx = GateContext(repoRoot: engine(['macos']), appRoot: bare.path);
      expect(ctx.targets, ['macos']);
    });

    test('marker declaring no targets does not blank the run', () {
      final ctx = GateContext(
        repoRoot: engine(['macos']),
        appRoot: app([]),
      );
      expect(ctx.targets, ['macos'],
          reason: 'an empty marker list is "unset", not "gate nothing"');
    });
  });
}
