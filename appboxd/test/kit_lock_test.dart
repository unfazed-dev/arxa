// Tests for the kit.lock generator — determinism (byte-identical on re-run)
// and structure. Fixtures build a throwaway tree (core pubspec + skills +
// tools) and assert generateKitLock is stable and well-formed.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/kit_lock.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('kit_lock_test_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Writes [relPath] (repo-relative) with [contents], creating parent dirs.
  File f(String relPath, String contents) {
    final file = File(p.join(tmp.path, relPath))..createSync(recursive: true);
    file.writeAsStringSync(contents);
    return file;
  }

  String repoRoot() => tmp.path;
  String kitRoot() => p.join(tmp.path, 'kit');

  void seed() {
    f('kit/core/pubspec.yaml', "name: appbox_kit_core\nversion: 0.1.0\n");
    f('skills/appbox-builder/SKILL.md', '# Builder\n');
    f('skills/appbox-reviewer/SKILL.md', '# Reviewer\n');
    f('tools/phase5_kit_copy.sh', '#!/usr/bin/env bash\necho hi\n');
    f('tools/sweep_rename.sh', '#!/usr/bin/env bash\necho bye\n');
  }

  test('same input produces byte-identical output across two runs', () {
    seed();
    final a = generateKitLock(repoRoot(), kitRoot());
    final b = generateKitLock(repoRoot(), kitRoot());
    expect(a, equals(b));
  });

  test('pins the kit version read from core/pubspec.yaml', () {
    seed();
    final lock = jsonDecode(generateKitLock(repoRoot(), kitRoot()))
        as Map<String, dynamic>;
    expect(lock['kit'], {'name': 'appbox_kit', 'version': '0.1.0'});
  });

  test('discovers skills and tools, sorted, with sha256 content hashes', () {
    seed();
    final lock = jsonDecode(generateKitLock(repoRoot(), kitRoot()))
        as Map<String, dynamic>;
    final skills = (lock['skills']! as Map).cast<String, dynamic>();
    // Sorted: appbox-builder before appbox-reviewer.
    expect(skills.keys.toList(), ['appbox-builder', 'appbox-reviewer']);
    expect(skills['appbox-builder']!['path'], 'skills/appbox-builder/SKILL.md');
    expect(
        (skills['appbox-builder']!['sha256'] as String).length, 64); // hex

    final tools = (lock['tools']! as Map).cast<String, dynamic>();
    expect(tools.keys.toList(), ['phase5_kit_copy.sh', 'sweep_rename.sh']);
  });

  test('changing a SKILL.md changes its hash but not the structure', () {
    seed();
    final before =
        generateKitLock(repoRoot(), kitRoot());
    f('skills/appbox-builder/SKILL.md', '# Builder (edited)\n');
    final after = generateKitLock(repoRoot(), kitRoot());

    final b = jsonDecode(before) as Map<String, dynamic>;
    final a = jsonDecode(after) as Map<String, dynamic>;
    expect(
      (a['skills']! as Map)['appbox-builder'],
      isNot(equals((b['skills']! as Map)['appbox-builder'])),
    );
    // Reviewer hash unchanged, version unchanged.
    expect(
      (a['skills']! as Map)['appbox-reviewer'],
      equals((b['skills']! as Map)['appbox-reviewer']),
    );
    expect(a['kit'], equals(b['kit']));
  });

  test('output uses only repo-relative paths (no absolute paths)', () {
    seed();
    final out = generateKitLock(repoRoot(), kitRoot());
    expect(out.contains(tmp.path), isFalse);
    expect(out, contains('skills/appbox-builder/SKILL.md'));
    expect(out, contains('tools/phase5_kit_copy.sh'));
  });
}
