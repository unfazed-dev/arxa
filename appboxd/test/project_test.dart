// `appbox project` tests — layout resolver over a temp APPBOX_HOME:
// init creates the four shell dirs + deterministic project.json, use/list
// round-trip `current`, bad names and unknown projects are rejected.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/project.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('appbox_project_test');
    appboxHomeOverride = '${tmp.path}/.appbox';
  });

  tearDown(() {
    appboxHomeOverride = null;
    tmp.deleteSync(recursive: true);
  });

  test('init creates the shell layout + deterministic settings', () {
    ensureProject('portalo');
    for (final shell in projectShells) {
      expect(Directory(shellDir('portalo', shell)).existsSync(), isTrue,
          reason: 'missing shell dir $shell');
    }
    final settings = readProjectSettings('portalo')!;
    expect(settings['name'], 'portalo');
    expect(settings['targets'], ['ios', 'android', 'macos']);
    expect(settings['locales'], ['en', 'pl']);
    // determinism: no clock fields, byte-stable content
    expect(settings.keys.toList(), ['name', 'targets', 'locales']);
    final again = File(projectSettingsPath('portalo')).readAsStringSync();
    ensureProject('portalo'); // idempotent, no clobber
    expect(File(projectSettingsPath('portalo')).readAsStringSync(), again);
  });

  test('use/list round-trip current; default is portalo', () {
    expect(currentProject(), 'portalo');
    ensureProject('portalo');
    ensureProject('foxglove');
    expect(listProjects(), ['foxglove', 'portalo']);
    useProject('foxglove');
    expect(currentProject(), 'foxglove');
  });

  test('use rejects unknown projects; init rejects bad names', () {
    expect(() => useProject('ghost'), throwsArgumentError);
    expect(() => ensureProject('Bad Name'), throwsArgumentError);
    expect(validProjectName('media-demo'), isTrue);
    expect(validProjectName('1up'), isFalse);
  });

  test('readProjectSettings is null for foreign dirs', () {
    Directory(projectDir('stray')).createSync(recursive: true);
    expect(readProjectSettings('stray'), isNull);
    // ...but the dir still lists (the dashboard marks it Intake-stage)
    expect(listProjects(), ['stray']);
    expect(jsonDecode('{}'), isA<Map>());
  });
}
