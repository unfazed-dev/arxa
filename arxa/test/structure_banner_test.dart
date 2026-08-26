// The `$schema` banner drifted across three names — `app-box/` -> `appbox/` ->
// `arxa/` — because nothing ever read the field. A live design still carries
// `appbox/structure@2`. loadStructure now names a stale banner; it does not
// reject the document (that would change what the scaffolder accepts).
// See docs/plans/arxa-rename-handoff-response.md (A6).

import 'package:arxa/scaffold.dart';
import 'package:test/test.dart';

void main() {
  group('legacyBanner', () {
    test('names both pre-rename prefixes', () {
      expect(legacyBanner('appbox/structure@2'), 'appbox/structure@2');
      expect(legacyBanner('app-box/structure@1'), 'app-box/structure@1');
    });

    test('quiet on the current banner', () {
      expect(legacyBanner('arxa/structure@2'), isNull);
    });

    test('quiet when absent or not a string', () {
      expect(legacyBanner(null), isNull);
      expect(legacyBanner(2), isNull);
    });

    test('does not fire on a name that merely contains a legacy word', () {
      expect(legacyBanner('arxa/appbox-compat@2'), isNull,
          reason: 'the rule is a PREFIX, not a substring — otherwise a '
              'legitimately-named schema would be flagged forever');
    });
  });

  group('renamedBanner', () {
    test('keeps the version, replaces the vendor', () {
      expect(renamedBanner('appbox/structure@2'), 'arxa/structure@2');
      expect(renamedBanner('app-box/structure@1'), 'arxa/structure@1');
    });
  });
}
