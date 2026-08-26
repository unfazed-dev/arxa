import 'dart:io';

import 'package:arxa/validate_docs.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('validate_docs_test');
    Directory('${tmp.path}/docs/plans').createSync(recursive: true);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  void writeIndex(String content) =>
      File('${tmp.path}/docs/INDEX.md').writeAsStringSync(content);
  void writeDoc(String rel, [String content = '# x']) =>
      File('${tmp.path}/docs/$rel').writeAsStringSync(content);

  test('clean tree passes: links resolve, no orphans', () {
    writeIndex('# idx\n\n[plan](plans/a.md) · [dir](plans/) · [web](https://x.test)\n');
    writeDoc('plans/a.md');
    final result = validateDocs(tmp.path);
    expect(result.ok, isTrue);
    expect(result.failures, isEmpty);
    expect(result.warnings, isEmpty);
  });

  test('dead relative link fails (R1)', () {
    writeIndex('[gone](plans/missing.md)\n');
    final result = validateDocs(tmp.path);
    expect(result.ok, isFalse);
    expect(result.failures.single.message, contains('plans/missing.md'));
  });

  test('anchors and external links are not checked', () {
    writeIndex('[s](#section) · [m](mailto:a@b.c) · [w](http://x.test/y)\n');
    final result = validateDocs(tmp.path);
    expect(result.ok, isTrue);
    expect(result.scanned, 0);
  });

  test('unindexed doc warns but does not fail (R2)', () {
    writeIndex('[a](plans/a.md)\n');
    writeDoc('plans/a.md');
    writeDoc('plans/orphan.md');
    final result = validateDocs(tmp.path);
    expect(result.ok, isTrue);
    expect(result.warnings.single.file, 'docs/plans/orphan.md');
  });

  test('missing INDEX.md fails loudly', () {
    final result = validateDocs(tmp.path);
    expect(result.ok, isFalse);
  });
}
