import 'dart:convert';
import 'dart:io';

import 'package:arxa_kit_support/arxa_kit_support.dart';
import 'package:arxa_kit_support/arxa_kit_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talker_flutter/talker_flutter.dart';

void main() {
  // arxa_kit_support is standalone — no arxa_kit locator to reset
  // (canon static-state discipline does not apply; all state is per-test).

  group('ArxaKitSupportService', () {
    test('kit.support.submit — routes the submission to the configured sink', () async {
      // given
      final sink = RecordingArxaKitSubmissionSink();
      final service = ArxaKitSupportService(talker: Talker(), sink: sink);
      final submission = arxaKitFakeFeedbackSubmission();

      // when
      final result = await service.submit(submission);

      // then
      expect(sink.submissions, [submission]);
      expect(result.ok, isTrue);
      expect(result.location, 'memory');
    });

    test('kit.support.submit — surfaces the sink\'s failure result', () async {
      // given
      final sink = RecordingArxaKitSubmissionSink(
        result: const ArxaKitSubmissionResult.failure('disk full'),
      );
      final service = ArxaKitSupportService(talker: Talker(), sink: sink);

      // when
      final result = await service.submit(arxaKitFakeFeedbackSubmission());

      // then
      expect(result.ok, isFalse);
      expect(result.error, 'disk full');
    });

    test('kit.support.capture-diagnostics — exports the talker history into the bundle', () {
      // given
      final talker = Talker();
      final service = ArxaKitSupportService(
        talker: talker,
        sink: RecordingArxaKitSubmissionSink(),
        clock: () => DateTime(2026, 8, 6, 12),
      );
      talker.info('app started');
      talker.error('boom');

      // when
      final bundle = service.captureDiagnostics();

      // then
      expect(bundle.entryCount, 2);
      expect(bundle.talkerLog, contains('app started'));
      expect(bundle.talkerLog, contains('boom'));
      expect(bundle.capturedAt, DateTime(2026, 8, 6, 12));
    });

    test('kit.support.capture-diagnostics — keeps only the most recent entries past the cap', () {
      // given
      final talker = Talker();
      final service = ArxaKitSupportService(
        talker: talker,
        sink: RecordingArxaKitSubmissionSink(),
        maxDiagnosticEntries: 2,
      );
      talker.info('oldest entry');
      talker.info('middle entry');
      talker.info('newest entry');

      // when
      final bundle = service.captureDiagnostics();

      // then
      expect(bundle.entryCount, 2);
      expect(bundle.talkerLog, isNot(contains('oldest entry')));
      expect(bundle.talkerLog, contains('middle entry'));
      expect(bundle.talkerLog, contains('newest entry'));
    });

    test('kit.support.capture-diagnostics — empty history yields an empty bundle', () {
      // given
      final service = ArxaKitSupportService(
        talker: Talker(),
        sink: RecordingArxaKitSubmissionSink(),
      );

      // when
      final bundle = service.captureDiagnostics();

      // then
      expect(bundle.entryCount, 0);
      expect(bundle.talkerLog, isEmpty);
    });

    test('kit.support.with-diagnostics — attaches a fresh bundle, original untouched', () {
      // given
      final talker = Talker();
      final service = ArxaKitSupportService(
        talker: talker,
        sink: RecordingArxaKitSubmissionSink(),
      );
      talker.info('something logged');
      final original = arxaKitFakeFeedbackSubmission(text: 'broken screen');

      // when
      final withBundle = service.withDiagnostics(original);

      // then
      expect(original.diagnostics, isNull);
      expect(withBundle.diagnostics, isNotNull);
      expect(withBundle.text, 'broken screen');
      expect(withBundle.diagnostics!.entryCount, 1);
    });
  });

  group('ArxaKitLocalFileSubmissionSink', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('arxa_kit_support_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('kit.support.local-file-sink — writes screenshot, metadata, and diagnostics', () async {
      // given
      final sink = ArxaKitLocalFileSubmissionSink(
        directoryResolver: () async => tempDir,
      );
      final submission = arxaKitFakeFeedbackSubmission(
        text: 'crash on launch',
        extra: const {'route': '/home'},
        diagnostics: arxaKitCannedDiagnosticsBundle(),
        submittedAt: DateTime(2026, 8, 6, 10, 30),
      );

      // when
      final result = await sink.submit(submission);

      // then
      expect(result.ok, isTrue);
      final dir = Directory(result.location!);
      expect(dir.existsSync(), isTrue);

      final screenshot = File('${dir.path}/screenshot.png');
      expect(screenshot.readAsBytesSync(), submission.screenshot);

      final meta = jsonDecode(File('${dir.path}/feedback.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(meta['text'], 'crash on launch');
      expect(meta['submittedAt'], '2026-08-06T10:30:00.000');
      expect((meta['extra'] as Map)['route'], '/home');
      expect((meta['diagnostics'] as Map)['entryCount'], 3);

      final log = File('${dir.path}/diagnostics.log').readAsStringSync();
      expect(log, contains('boom: something went wrong'));
    });

    test('kit.support.local-file-sink — omits diagnostics.log when none attached', () async {
      // given
      final sink = ArxaKitLocalFileSubmissionSink(
        directoryResolver: () async => tempDir,
      );

      // when
      final result = await sink.submit(arxaKitFakeFeedbackSubmission());

      // then
      expect(result.ok, isTrue);
      final dir = Directory(result.location!);
      expect(File('${dir.path}/screenshot.png').existsSync(), isTrue);
      expect(File('${dir.path}/feedback.json').existsSync(), isTrue);
      expect(File('${dir.path}/diagnostics.log').existsSync(), isFalse);
    });

    test('kit.support.local-file-sink — returns a failure result instead of throwing', () async {
      // given
      final sink = ArxaKitLocalFileSubmissionSink(
        directoryResolver: () => throw StateError('no documents dir'),
      );

      // when
      final result = await sink.submit(arxaKitFakeFeedbackSubmission());

      // then
      expect(result.ok, isFalse);
      expect(result.error, isA<StateError>());
    });
  });

  group('stub sinks', () {
    test('kit.support.email-sink — throws UnimplementedError (stub)', () {
      // given
      final sink = ArxaKitEmailSubmissionSink(recipient: 'support@example.com');

      // when / then
      expect(
        () => sink.submit(arxaKitFakeFeedbackSubmission()),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('kit.support.github-issue-sink — throws UnimplementedError (stub)', () {
      // given
      final sink = ArxaKitGithubIssueSink(owner: 'arxa', repo: 'arxa');

      // when / then
      expect(
        () => sink.submit(arxaKitFakeFeedbackSubmission()),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });
}
