// gate_kind_registry_test — red-first port of validate-registry.py (Q7/Q12).
//
// The Python original lives at
// skills/arxa-scaffolder/scripts/validate-registry.py; this suite pins the
// Dart port to the same contract: duplicate keys, vocabulary coverage, real
// kit targets, resolution.order shapes, escape completeness, and the Q12
// inspect-identity closure (declared vocabulary vs ids stamped under kit/).
import 'dart:io';

import 'package:arxa/gate_kind_registry.dart';
import 'package:arxa/gates.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('kind_registry_test');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  // Builds a CLEAN fixture tree (the smallest registry that passes every
  // check) and returns its paths. Every negative test mutates one thing.
  (String, String, String, String) buildFixture({String? registryJson}) {
    final registry = p.join(tmp.path, 'kind-resolution.registry.json');
    File(registry).writeAsStringSync(registryJson ??
        '''
{
  "registryVersion": "1.3.0",
  "kinds": {
    "button": { "widget": "ArxaKitButton" },
    "card": { "widget": "ArxaKitCard", "escape": { "reason": "r", "owner": "o", "expires": "2027-01-01" } }
  },
  "resolution": { "order": ["widget", "variants", "composedFrom", "presentation"] },
  "designVocabulary": { "inspectAttrs": "package:arxa_kit_core/common/inspect_attrs.dart" },
  "anatomyNodes": { "vocabulary": {
    "anatomy:root": "the root node",
    "anatomy:nav.item": "a nav item"
  } }
}
''');

    final partials = p.join(tmp.path, 'partials');
    Directory(partials).createSync();
    for (final k in ['button', 'card']) {
      File(p.join(partials, '_$k.tsx')).writeAsStringSync('export {}');
    }

    final kitLib = p.join(tmp.path, 'kit', 'ui_library', 'lib');
    Directory(kitLib).createSync(recursive: true);
    File(p.join(kitLib, 'buttons.dart')).writeAsStringSync('''
class ArxaKitButton {}
class ArxaKitButtonDense {}
class ArxaKitCard {}
''');

    final kitRoot = p.join(tmp.path, 'kit');
    final coreLib = p.join(kitRoot, 'core', 'lib');
    Directory(p.join(coreLib, 'common')).createSync(recursive: true);
    File(p.join(coreLib, 'common', 'inspect_attrs.dart'))
        .writeAsStringSync('''
class ArxaKitInspectAttrs {
  final String screenId;
  final String surfaceId;
  final String anatomyNodeId;
}
''');
    File(p.join(coreLib, 'arxa_kit_core.dart'))
        .writeAsStringSync("export 'common/inspect_attrs.dart'");
    // A stamped id that IS registered — clean fixture stays clean.
    File(p.join(coreLib, 'stamps.dart'))
        .writeAsStringSync("const x = 'anatomy:root';");

    return (registry, partials, kitLib, kitRoot);
  }

  KindRegistryReport run(String registry, String partials, String kitLib,
          String kitRoot) =>
      validateKindRegistry(
          registryPath: registry,
          partialsDir: partials,
          kitLibDir: kitLib,
          kitRoot: kitRoot);

  test('clean fixture passes with a summary mirroring the python output', () {
    final (r, pa, kl, kr) = buildFixture();
    final report = run(r, pa, kl, kr);
    expect(report.violations, isEmpty,
        reason: report.violations.join('; '));
    expect(report.registryVersion, '1.3.0');
    expect(report.kindCount, 2);
    expect(report.vocabCount, 2);
    expect(report.anatomyCount, 2);
  });

  test('DUPLICATE KEY — a silently-discarded entry is the founding failure',
      () {
    final (r, pa, kl, kr) = buildFixture(registryJson: '''
{
  "registryVersion": "1.3.0",
  "kinds": {
    "button": { "widget": "ArxaKitButton" },
    "button": { "widget": "ArxaKitButtonDense" },
    "card": { "widget": "ArxaKitCard" }
  },
  "resolution": { "order": ["widget", "variants", "composedFrom", "presentation"] },
  "designVocabulary": { "inspectAttrs": "package:arxa_kit_core/common/inspect_attrs.dart" },
  "anatomyNodes": { "vocabulary": { "anatomy:root": "the root node" } }
}
''');
    final report = run(r, pa, kl, kr);
    expect(report.violations,
        anyElement(contains("DUPLICATE KEY 'button'")));
  });

  test('UNCOVERED KIND — an authored partial with no registry entry', () {
    final (r, pa, kl, kr) = buildFixture();
    File(p.join(pa, '_tabs.tsx')).writeAsStringSync('export {}');
    final report = run(r, pa, kl, kr);
    expect(report.violations, anyElement(contains('UNCOVERED KIND')));
    expect(report.violations, anyElement(contains("'tabs'")));
  });

  test('ORPHAN ENTRY — registry maps a kind with no authored partial', () {
    final (r, pa, kl, kr) = buildFixture();
    final src = File(r).readAsStringSync();
    File(r).writeAsStringSync(src.replaceFirst('"card"',
        '"ghost": { "widget": "ArxaKitCard" }, "card"'));
    final report = run(r, pa, kl, kr);
    expect(report.violations, anyElement(contains('ORPHAN ENTRY')));
  });

  test('invented target — widget names a class kit does not declare', () {
    final (r, pa, kl, kr) = buildFixture();
    final src = File(r).readAsStringSync();
    File(r).writeAsStringSync(src.replaceAll('ArxaKitCard', 'ArxaKitNope'));
    final report = run(r, pa, kl, kr);
    expect(report.violations,
        anyElement(contains("'ArxaKitNope' is not a class")));
  });

  test('variants/companions/composedFrom refs are target-checked too', () {
    final (r, pa, kl, kr) = buildFixture();
    final src = File(r).readAsStringSync();
    File(r).writeAsStringSync(src.replaceFirst(
        '"button": { "widget": "ArxaKitButton" }',
        '"button": { "widget": "ArxaKitButton", "variants": { "dense": "ArxaKitPhantom" } }'));
    final report = run(r, pa, kl, kr);
    expect(report.violations,
        anyElement(contains("'ArxaKitPhantom' is not a class")));
  });

  test('SHAPE missing from resolution.order breaks designed kinds', () {
    final (r, pa, kl, kr) = buildFixture();
    final src = File(r).readAsStringSync();
    File(r).writeAsStringSync(src.replaceFirst(
        '"order": ["widget", "variants", "composedFrom", "presentation"]',
        '"order": ["widget", "composedFrom", "presentation"]'));
    final report = run(r, pa, kl, kr);
    expect(report.violations,
        anyElement(contains("'variants' NOT IN resolution.order")));
  });

  test('UNRESOLVABLE — entry carries none of the four shapes', () {
    final (r, pa, kl, kr) = buildFixture();
    final src = File(r).readAsStringSync();
    File(r).writeAsStringSync(src.replaceFirst(
        '"card": { "widget": "ArxaKitCard", "escape": { "reason": "r", "owner": "o", "expires": "2027-01-01" } }',
        '"card": { "escape": { "reason": "r", "owner": "o", "expires": "2027-01-01" } }'));
    final report = run(r, pa, kl, kr);
    expect(report.violations, anyElement(contains('UNRESOLVABLE')));
  });

  test('escape entry must carry reason, owner and expires', () {
    final (r, pa, kl, kr) = buildFixture();
    final src = File(r).readAsStringSync();
    File(r).writeAsStringSync(src.replaceFirst('"owner": "o", ', ''));
    final report = run(r, pa, kl, kr);
    expect(report.violations, anyElement(contains('escape entry must carry')));
  });

  test('inspectAttrs missing — the shape has no declared single home', () {
    final (r, pa, kl, kr) = buildFixture();
    final src = File(r).readAsStringSync();
    File(r).writeAsStringSync(src.replaceFirst(
        '"designVocabulary": { "inspectAttrs": "package:arxa_kit_core/common/inspect_attrs.dart" },',
        ''));
    final report = run(r, pa, kl, kr);
    expect(report.violations,
        anyElement(contains('designVocabulary.inspectAttrs missing')));
  });

  test('inspect shape must declare the class, the triple and the barrel export',
      () {
    final (r, pa, kl, kr) = buildFixture();
    final shape = p.join(kr, 'core', 'lib', 'common', 'inspect_attrs.dart');
    File(shape).writeAsStringSync('class SomethingElse {}');
    final report = run(r, pa, kl, kr);
    expect(report.violations,
        anyElement(contains('does not declare class ArxaKitInspectAttrs')));
    expect(report.violations, anyElement(contains("triple slot 'screenId'")));
    File(p.join(kr, 'core', 'lib', 'arxa_kit_core.dart'))
        .writeAsStringSync("export 'other.dart'");
    final report2 = run(r, pa, kl, kr);
    expect(report2.violations,
        anyElement(contains('not exported from arxa_kit_core.dart')));
  });

  test('anatomy vocabulary — malformed id, missing description, rogue stamp',
      () {
    final (r, pa, kl, kr) = buildFixture();
    final src = File(r).readAsStringSync();
    File(r).writeAsStringSync(src.replaceFirst('"anatomy:nav.item": "a nav item"',
        '"anatomy:nav.Item": "a nav item", "anatomy:blank": ""'));
    final report = run(r, pa, kl, kr);
    expect(report.violations, anyElement(contains('MALFORMED anatomy id')));
    expect(report.violations, anyElement(contains('no description')));
    File(p.join(kr, 'core', 'lib', 'stamps.dart'))
        .writeAsStringSync("const x = 'anatomy:rogue.id';");
    final report2 = run(r, pa, kl, kr);
    expect(report2.violations, anyElement(contains('UNREGISTERED anatomy id')));
    expect(report2.violations, anyElement(contains('anatomy:rogue.id')));
  });

  test('gate wrapper — GateResult wiring, sarif and exit codes', () {
    final (r, pa, kl, kr) = buildFixture();
    Directory(p.join(tmp.path, 'skills', 'arxa-scaffolder'))
        .createSync(recursive: true);
    File(p.join(tmp.path, 'skills', 'arxa-scaffolder',
            'kind-resolution.registry.json'))
        .writeAsStringSync(File(r).readAsStringSync());
    final widgetsDir = p.join(
        tmp.path, 'skills', 'arxa-designer', 'starter-partials', 'widgets');
    Directory(widgetsDir).createSync(recursive: true);
    for (final f in Directory(pa).listSync()) {
      if (f is File) f.copySync(p.join(widgetsDir, p.basename(f.path)));
    }
    final ctx = GateContext(repoRoot: tmp.path, sarif: SarifBuilder());
    final result = kindRegistryGate(ctx);
    expect(result.passed, isTrue);
    expect(result.exitCode, passExit);
    expect(result.summary, contains('registry OK'));

    File(p.join(widgetsDir, '_tabs.tsx')).writeAsStringSync('export {}');
    final result2 = kindRegistryGate(ctx);
    expect(result2.passed, isFalse);
    expect(result2.exitCode, failExit);
    expect(result2.details, anyElement(contains('UNCOVERED KIND')));
  });

  test('gate wrapper — absent registry is envExit 2 (not applicable)', () {
    final empty = Directory.systemTemp.createTempSync('kind_registry_absent');
    addTearDown(() => empty.deleteSync(recursive: true));
    final ctx = GateContext(repoRoot: empty.path, sarif: SarifBuilder());
    final result = kindRegistryGate(ctx);
    expect(result.exitCode, envExit);
    expect(result.passed, isFalse);
  });

  test('self-test — embedded negatives all fire and the clean case passes',
      () {
    final result = kindRegistryGate(GateContext(
        repoRoot: Directory.systemTemp.createTempSync('kr_selftest').path,
        sarif: SarifBuilder(),
        selfTest: true));
    expect(result.passed, isTrue, reason: result.details.join('; '));
    expect(result.summary, contains('self-test'));
  });
}

