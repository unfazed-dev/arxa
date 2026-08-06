import 'dart:convert';
import 'dart:io';

import 'package:appbox_kit_support/appbox_kit_support.dart';
import 'package:appbox_kit_support/appbox_kit_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talker_flutter/talker_flutter.dart';

void main() {
  // appbox_kit_support is standalone — no appbox_kit locator to reset
  // (canon static-state discipline does not apply; all state is per-test).

  group('AppBoxKitSupportService', () {
    test('kit.support.submit — routes the submission to the configured sink', () async {
      // given
      final sink = RecordingAppBoxKitSubmissionSink();
      final service = AppBoxKitSupportService(talker: Talker(), sink: sink);
      final submission = appBoxKitFakeFeedbackSubmission();

      // when
      final result = await service.submit(submission);

      // then
      expect(sink.submissions, [submission]);
      expect(result.ok, isTrue);
      expect(result.location, 'memory');
    });

    test('kit.support.submit — surfaces the sink\'s failure result', () async {
      // given
      final sink = RecordingAppBoxKitSubmissionSink(
        result: const AppBoxKitSubmissionResult.failure('disk full'),
      );
      final service = AppBoxKitSupportService(talker: Talker(), sink: sink);

      // when
      final result = await service.submit(appBoxKitFakeFeedbackSubmission());

      // then
      expect(result.ok, isFalse);
      expect(result.error, 'disk full');
    });

    test('kit.support.capture-diagnostics — exports the talker history into the bundle', () {
      // given
      final talker = Talker();
      final service = AppBoxKitSupportService(
        talker: talker,
        sink: RecordingAppBoxKitSubmissionSink(),
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
      final service = AppBoxKitSupportService(
        talker: talker,
        sink: RecordingAppBoxKitSubmissionSink(),
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
      final service = AppBoxKitSupportService(
        talker: Talker(),
        sink: RecordingAppBoxKitSubmissionSink(),
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
      final service = AppBoxKitSupportService(
        talker: talker,
        sink: RecordingAppBoxKitSubmissionSink(),
      );
      talker.info('something logged');
      final original = appBoxKitFakeFeedbackSubmission(text: 'broken screen');

      // when
      final withBundle = service.withDiagnostics(original);

      // then
      expect(original.diagnostics, isNull);
      expect(withBundle.diagnostics, isNotNull);
      expect(withBundle.text, 'broken screen');
      expect(withBundle.diagnostics!.entryCount, 1);
    });
  });

  group('AppBoxKitLocalFileSubmissionSink', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('appbox_kit_support_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('kit.support.local-file-sink — writes screenshot, metadata, and diagnostics', () async {
      // given
      final sink = AppBoxKitLocalFileSubmissionSink(
        directoryResolver: () async => tempDir,
      );
      final submission = appBoxKitFakeFeedbackSubmission(
        text: 'crash on launch',
        extra: const {'route': '/home'},
        diagnostics: appBoxKitCannedDiagnosticsBundle(),
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
      final sink = AppBoxKitLocalFileSubmissionSink(
        directoryResolver: () async => tempDir,
      );

      // when
      final result = await sink.submit(appBoxKitFakeFeedbackSubmission());

      // then
      expect(result.ok, isTrue);
      final dir = Directory(result.location!);
      expect(File('${dir.path}/screenshot.png').existsSync(), isTrue);
      expect(File('${dir.path}/feedback.json').existsSync(), isTrue);
      expect(File('${dir.path}/diagnostics.log').existsSync(), isFalse);
    });

    test('kit.support.local-file-sink — returns a failure result instead of throwing', () async {
      // given
      final sink = AppBoxKitLocalFileSubmissionSink(
        directoryResolver: () => throw StateError('no documents dir'),
      );

      // when
      final result = await sink.submit(appBoxKitFakeFeedbackSubmission());

      // then
      expect(result.ok, isFalse);
      expect(result.error, isA<StateError>());
    });
  });

  group('stub sinks', () {
    test('kit.support.email-sink — throws UnimplementedError (stub)', () {
      // given
      final sink = AppBoxKitEmailSubmissionSink(recipient: 'support@example.com');

      // when / then
      expect(
        () => sink.submit(appBoxKitFakeFeedbackSubmission()),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('kit.support.github-issue-sink — throws UnimplementedError (stub)', () {
      // given
      final sink = AppBoxKitGithubIssueSink(owner: 'appbox', repo: 'app-box');

      // when / then
      expect(
        () => sink.submit(appBoxKitFakeFeedbackSubmission()),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });
}
