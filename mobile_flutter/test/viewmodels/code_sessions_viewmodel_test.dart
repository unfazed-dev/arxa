// arxa-scaffolder: red-first behavior-test seed. Canon:
// skills/arxa-tester/behavior-tdd-rules.md — each skipped test cites its
// story id verbatim (gate T2) and stays green (T3) until the builder
// implements the behavior and removes the skip.
//   surface:       code_shell_sessions_view
//   comp:          CodeSessionsViewModel
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CodeSessionsViewModel', () {
    setUp(() {
      // builder: register kit fakes / port mocks here once the VM wires services.
    });

    tearDown(() {
      // builder: reset locator/static state here if the VM touches it.
    });

    // No story map found (intake/map.json, docs/intake/story-map.json) —
    // run `arxa intake` first, then re-scaffold to seed one test per story.
    test('placeholder — seed me from the story map', () async {
      // red-first: implement with CodeSessionsViewModel, then remove the skip.
    }, skip: 'red-first seed — implement with CodeSessionsViewModel');
  });
}
