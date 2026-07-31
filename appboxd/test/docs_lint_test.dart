// TDD tests for the KB-lint port of skills/appbox-lint/lint_kb.py.
// Covers the three WARN-class checks lint_kb.py adds on top of the existing
// validate_docs.dart (R1 dead links = fail; R2 unindexed = warn): orphans,
// supersede consistency, and memory wikilink integrity. The ERROR-class
// checks (index coverage, link integrity) are intentionally NOT duplicated
// here — they already live in validate_docs.dart.
import 'dart:io';

import 'package:appboxd/docs_lint.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('docs_lint_test');
    Directory('${tmp.path}/docs').createSync(recursive: true);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  void writeIndex([String content = '# index\n']) =>
      File('${tmp.path}/docs/INDEX.md').writeAsStringSync(content);
  void writeDoc(String rel, [String content = '# x']) =>
      File('${tmp.path}/docs/$rel').writeAsStringSync(content);

  // ── orphans (lint_kb.py check 3) ────────────────────────────────────

  test('orphan: unindexed doc with no inbound link warns', () {
    writeIndex('# index\n- [good](good.md)\n');
    writeDoc('good.md', '# good\nsee [g](good.md)\n'); // indexed + inbound
    writeDoc('lonely.md'); // not indexed, no inbound
    final w = lintKb(tmp.path);
    expect(
        w.any((i) =>
            i.file == 'docs/lonely.md' && i.message.contains('orphan')),
        isTrue);
    expect(w.any((i) => i.file == 'docs/good.md'), isFalse,
        reason: 'indexed + linked doc must not be flagged');
  });

  test('orphan: unindexed doc that is linked-to is not flagged', () {
    writeIndex('# index\n- [a](a.md)\n');
    writeDoc('a.md', '# a\nsee [hub](hub.md)\n'); // inbound link to hub
    writeDoc('hub.md'); // not indexed, but has an inbound link
    final w = lintKb(tmp.path);
    expect(w.any((i) => i.file == 'docs/hub.md'), isFalse,
        reason: 'an inbound link disqualifies the orphan check');
  });

  // ── supersede consistency (lint_kb.py check 4) ──────────────────────

  test('supersede: changelog with supersed* but no SUPERSEDED warns', () {
    writeIndex('# index\n[c](changelog.md)\n');
    writeDoc('changelog.md', '## 2024-01-01 (a) supersedes (b)\n');
    final w = lintKb(tmp.path);
    expect(w.any((i) => i.message.contains('SUPERSEDED')), isTrue);
  });

  test('supersede: SUPERSEDED back-pointer present -> no warning', () {
    writeIndex('# index\n[c](changelog.md)\n');
    writeDoc('changelog.md',
        '## (a) supersedes (b)\n<!-- SUPERSEDED by (a) -->\n');
    expect(lintKb(tmp.path).where((i) => i.message.contains('SUPERSEDED')),
        isEmpty);
  });

  // ── wikilink integrity (lint_kb.py check 5) ─────────────────────────

  test('wikilink: [[missing]] in memory warns; [[exists]] does not', () {
    Directory('${tmp.path}/memory').createSync();
    File('${tmp.path}/memory/note.md')
        .writeAsStringSync('see [[exists]] and [[ghost]]\n');
    File('${tmp.path}/memory/exists.md').writeAsStringSync('# exists\n');
    final w = lintKb(tmp.path);
    expect(w.any((i) => i.message.contains('[[ghost]]')), isTrue);
    expect(w.any((i) => i.message.contains('[[exists]]')), isFalse);
  });

  test('wikilink: alias form [[slug|label]] resolves by slug', () {
    Directory('${tmp.path}/memory').createSync();
    File('${tmp.path}/memory/note.md')
        .writeAsStringSync('see [[real|the real one]]\n');
    File('${tmp.path}/memory/real.md').writeAsStringSync('# real\n');
    expect(
        lintKb(tmp.path)
            .where((i) => i.message.contains('[[real')),
        isEmpty);
  });

  // ── guards ──────────────────────────────────────────────────────────

  test('no memory dir -> no wikilink warnings, no crash', () {
    writeIndex();
    expect(lintKb(tmp.path), isEmpty);
  });

  test('clean tree: indexed, linked docs -> no warnings', () {
    writeIndex('# index\n- [a](a.md)\n');
    writeDoc('a.md', '# a\nback [a](a.md)\n');
    expect(lintKb(tmp.path), isEmpty);
  });
}
