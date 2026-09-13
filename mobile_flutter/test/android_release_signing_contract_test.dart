// The Android release-signing contract (migration spec §a box 11 + Task 12
// Step 4): the application id stays `solutions.arxadigital.arxa.mobile`,
// release signing loads from the gitignored android/key.properties (CI
// writes it from secrets), debug builds alone may use the debug key, and a
// release packaging task without signing inputs fails loudly instead of
// silently shipping a debug-signed artifact.
//
// This is a config contract test: it pins the gradle file's shape so a
// refactor cannot quietly reintroduce the debug-key fallback. The live
// behavior (bundleRelease fails without key.properties, signs with a real
// keystore when present) is exercised by the release smoke — PENDING: an
// external, credential-gated step owned by Task 16 that has not been run;
// until its evidence lands, this contract test is the only guard.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final gradle = File('android/app/build.gradle.kts').readAsLinesSync();
  final text = gradle.join('\n');
  final gitignore = File('android/.gitignore').readAsLinesSync();

  test(
    'kit.mobile.release: application id stays solutions.arxadigital.arxa.mobile',
    () {
      expect(
        text,
        contains('applicationId = "solutions.arxadigital.arxa.mobile"'),
      );
    },
  );

  test(
    'kit.mobile.release: signing inputs come from gitignored key.properties',
    () {
      expect(text, contains('rootProject.file("key.properties")'));
      // All four inputs are checked before any is used — a half-written
      // key.properties must not produce a half-signed build.
      expect(
        text,
        contains(
          'listOf("storeFile", "storePassword", "keyAlias", "keyPassword")',
        ),
      );
      expect(gitignore, contains('key.properties'));
    },
  );

  test(
    'kit.mobile.release: release never unconditionally signs with the debug key',
    () {
      // The pre-Task-12 shape was `signingConfig = signingConfigs.getByName("debug")`
      // inside the release buildType — a store artifact signed with the debug
      // key. It must not come back.
      expect(text, isNot(contains('getByName("debug")')));
      // The release config is wired only behind the readiness guard.
      expect(text, contains('if (releaseSigningReady)'));
    },
  );

  test(
    'kit.mobile.release: missing signing inputs fail a release build clearly',
    () {
      expect(text, contains('GradleException'));
      // The guard fires on packaging/bundling tasks, not on debug builds or
      // plain configuration (`gradle help` must stay green without a keystore).
      expect(text, contains('package'));
      expect(text, contains('bundle'));
    },
  );
}
