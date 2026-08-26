// `ps` elapsed-time parsing for the boot-time orphan Chrome sweep.
//
// This is the only signal separating a LIVE `arxa-cdp-` Chrome from a leaked
// one: CdpClient launches with --no-startup-window, so a healthy CDP browser
// legitimately reparents to init and ppid==1 proves nothing for that prefix.
// Getting this wrong is silent in both directions — too large and the sweep
// kills live browsers out from under concurrent work (this actually happened:
// four CDP test files went red), too small and reaping quietly never happens.
library;

import 'package:arxa/design_server/worker.dart';
import 'package:test/test.dart';

void main() {
  group('etimeSeconds', () {
    test('mm:ss — the short form a fresh process reports', () {
      expect(etimeSeconds('00:03'), 3);
      expect(etimeSeconds('05:23'), 5 * 60 + 23);
    });

    test('hh:mm:ss', () {
      expect(etimeSeconds('02:06:26'), 2 * 3600 + 6 * 60 + 26);
    });

    test('dd-hh:mm:ss — the day form, which is what a real orphan looks like', () {
      expect(etimeSeconds('01-02:59:19'), 86400 + 2 * 3600 + 59 * 60 + 19);
      expect(etimeSeconds('10-00:00:00'), 10 * 86400);
    });

    test('leading whitespace from a padded ps column is tolerated', () {
      expect(etimeSeconds('   02:06:26'), 2 * 3600 + 6 * 60 + 26);
    });

    test('unparseable input returns null, never a number', () {
      // Callers read null as "too young to touch". Any numeric fallback here
      // would be a licence to kill a browser we failed to measure.
      for (final bad in ['', 'abc', '??:??', '1-', 'x-01:02:03', '1:2:3:4']) {
        expect(etimeSeconds(bad), isNull, reason: 'input: "$bad"');
      }
    });

    test('the hour threshold the cdp sweep depends on falls the right way', () {
      // < 1h: a live session. > 1h: nothing legitimate is still holding it.
      expect(etimeSeconds('59:59')! > 3600, isFalse);
      expect(etimeSeconds('01:00:01')! > 3600, isTrue);
      expect(etimeSeconds('01-02:59:19')! > 3600, isTrue);
    });
  });
}
