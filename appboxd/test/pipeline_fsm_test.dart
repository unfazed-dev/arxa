// Tests for pipeline_fsm — init, recordPhaseStatus, advance, approve, review.
import 'dart:io';

import 'package:appboxd/pipeline_fsm.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String root;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fsm-test-');
    root = tmp.path;
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('initPipeline', () {
    test('creates state with phase=intake, all gates ready/blocked', () {
      final s = initPipeline(root);
      expect(s['phase'], 'intake');
      final ps = s['phaseStatus'] as Map<String, dynamic>;
      expect(ps['intake']!['status'], 'ready');
      expect(ps['prototype']!['status'], 'blocked');
      expect(ps['deploy']!['status'], 'blocked');
      expect(s['dirty'], isFalse);
      expect(s['schema'], 4);
      expect(File(p.join(root, 'pipeline', 'state', 'default.state.json')).existsSync(), isTrue);
    });

    test('appends an init entry to runs.jsonl', () {
      initPipeline(root);
      final runs = readRuns(root);
      expect(runs.length, 1);
      expect(runs[0]['action'], 'init');
    });
  });

  group('recordPhaseStatus', () {
    test('sets phase status passed and bumps attempts', () {
      initPipeline(root);
      recordPhaseStatus(root, 'intake', true, exitCode: 0);
      final s = readState(root)!;
      final ps = s['phaseStatus'] as Map<String, dynamic>;
      expect(ps['intake']!['status'], 'passed');
      expect(ps['intake']!['attempts'], 1);
    });

    test('appends a gate entry to runs.jsonl', () {
      initPipeline(root);
      recordPhaseStatus(root, 'intake', false, exitCode: 1, failingSig: 'oops');
      final runs = readRuns(root);
      expect(runs.length, 2);
      expect(runs[1]['action'], 'gate');
      expect(runs[1]['result'], 'failed');
      expect(runs[1]['failingSignature'], 'oops');
    });
  });

  group('advance', () {
    test('advances when current phase passed', () {
      initPipeline(root);
      recordPhaseStatus(root, 'intake', true);
      final next = advance(root);
      expect(next, 'prototype');
      expect(readState(root)!['phase'], 'prototype');
    });

    test('refuses advance when current phase not passed', () {
      initPipeline(root);
      recordPhaseStatus(root, 'intake', false);
      expect(advance(root), isNull);
      expect(readState(root)!['phase'], 'intake');
    });

    test('prototype requires human approval before advancing', () {
      initPipeline(root);
      recordPhaseStatus(root, 'intake', true);
      advance(root); // → prototype
      recordPhaseStatus(root, 'prototype', true);
      // No human approval yet — advance refused.
      expect(advance(root), isNull);
      expect(readState(root)!['phase'], 'prototype');

      // Approve, then advance works.
      approvePrototype(root);
      expect(advance(root), 'design');
    });
  });

  group('reviewVerdict', () {
    test('approve sets done-eligible and clears dirty', () {
      initPipeline(root);
      markDirty(root);
      reviewVerdict(root, true);
      final s = readState(root)!;
      expect(s['review']!['approved'], isTrue);
      expect(s['dirty'], isFalse);
      expect(isDone(root), isTrue);
    });

    test('reject bumps rejections and clears approved', () {
      initPipeline(root);
      reviewVerdict(root, false, reason: 'needs work');
      final s = readState(root)!;
      expect(s['review']!['rejections'], 1);
      expect(s['review']!['approved'], isFalse);
    });
  });

  group('isDone', () {
    test('false on fresh init', () {
      initPipeline(root);
      expect(isDone(root), isFalse);
    });

    test('true after review approval', () {
      initPipeline(root);
      reviewVerdict(root, true);
      expect(isDone(root), isTrue);
    });

    test('false when dirty after approval', () {
      initPipeline(root);
      reviewVerdict(root, true);
      markDirty(root);
      expect(isDone(root), isFalse);
    });
  });

  group('readState', () {
    test('returns null when no state file exists', () {
      expect(readState(root), isNull);
    });
  });
}
