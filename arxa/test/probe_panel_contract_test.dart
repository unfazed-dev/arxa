// The panel-contract port's parity contract with JavaScript.
//
// Sections A–L are browser-driven and are verified by running the probe against
// a served tree and diffing its output against `archives/tooling-pre-dart/tools/studio-probes/probe-panel-contract.mjs`
// (see docs/probes-capability-map.md). What IS unit-testable is the handful of
// pure functions the port needed because the obvious Dart equivalent is subtly
// different from the JS the `.mjs` relies on — and each difference reaches the
// printed output, so a silent regression here is a silent parity break.

import 'package:arxa/probes/studio/probe_panel_contract.dart';
import 'package:arxa/probes/registry.dart';
import 'package:test/test.dart';

void main() {
  group('jsParseFloat', () {
    test('reads the numeric prefix of a CSS value', () {
      // The bug this exists to prevent: `double.tryParse('0px')` is null, so a
      // naive port turns `parseFloat(min) === 0` — "the panel released its
      // floor" — into a permanent false, and section I fails below 840px for a
      // reason that has nothing to do with the layout.
      expect(jsParseFloat('0px'), 0);
      expect(jsParseFloat('9.6px'), 9.6);
      expect(jsParseFloat('700px'), 700);
      expect(jsParseFloat('.5rem'), 0.5);
      expect(jsParseFloat('-3.5px'), -3.5);
    });

    test('is null where JS is NaN', () {
      expect(jsParseFloat('none'), isNull);
      expect(jsParseFloat('auto'), isNull);
      expect(jsParseFloat(''), isNull);
      expect(jsParseFloat(null), isNull);
      expect(jsParseFloat(true), isNull);
    });

    test('passes numbers through', () {
      expect(jsParseFloat(12), 12.0);
      expect(jsParseFloat(0.5), 0.5);
    });
  });

  group('jsNum', () {
    test('prints a whole double the way JS does', () {
      // Dart's `'${640.0}'` is `640.0`; JS's is `640`. Details are compared
      // textually against the .mjs, so the `.0` is a diff.
      expect(jsNum(640.0), '640');
      expect(jsNum(1106), '1106');
      expect(jsNum(0.0), '0');
      expect(jsNum(-9.0), '-9');
    });

    test('keeps a real fraction', () {
      expect(jsNum(9.6), '9.6');
      expect(jsNum(0.5), '0.5');
    });
  });

  group('jsUndefined', () {
    test('renders an optional-chain miss as the word JS prints', () {
      // `geo.top?.w` where `geo.top` is null evaluates to `undefined`, and the
      // .mjs template literal prints that word into the failure detail.
      expect(jsUndefined(null), 'undefined');
    });

    test('otherwise formats as a JS number', () {
      expect(jsUndefined(977.0), '977');
      expect(jsUndefined(9.6), '9.6');
      expect(jsUndefined('0px'), '0px');
    });
  });

  group('jsTruthy', () {
    test('treats JS falsy values as falsy', () {
      // `check(name, ok, x)` in the .mjs prints the detail only when `x` is
      // truthy, and section A/E/F use the same truthiness for the predicate.
      expect(jsTruthy(null), isFalse);
      expect(jsTruthy(false), isFalse);
      expect(jsTruthy(0), isFalse);
      expect(jsTruthy(0.0), isFalse);
      expect(jsTruthy(''), isFalse);
    });

    test('treats everything else as truthy', () {
      expect(jsTruthy('none'), isTrue);
      expect(jsTruthy('0.75rem'), isTrue);
      expect(jsTruthy(true), isTrue);
      expect(jsTruthy(1), isTrue);
    });
  });

  group('registration', () {
    test('is reachable by its CLI name', () {
      expect(probeByName('panel-contract'), same(panelContractProbe));
    });

    test('declares the disposable-project guard', () {
      // Section G follows a file link and leaves the served project on that
      // surface — server-side session state. The .mjs never guarded; the port
      // does, and the guard runs off this declaration before Chrome launches.
      expect(panelContractProbe.mutates, isTrue);
      expect(panelContractProbe.needsBrowser, isTrue);
    });
  });
}
