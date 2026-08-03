// The two rules that exist because they were once broken get tests that fail
// if they are broken again. Both are pure functions precisely so this file can
// exercise them without a server, a browser or a subprocess.

import 'package:appboxd/probes/probe_base.dart';
import 'package:appboxd/probes/registry.dart';
import 'package:test/test.dart';

Future<void> _noop(ProbeContext ctx) async {}

void main() {
  group('resolveTarget — rule 1: an argument that cannot be honoured is a hard error', () {
    test('an unsupported flag refuses the run rather than silently defaulting', () {
      final t = resolveTarget(['--bogus', '1'], env: {});
      expect(t.ok, isFalse);
      expect(t.base, isNull);
      expect(t.error, contains('unsupported argument "--bogus"'));
      // The refusal must name what it would otherwise have hit — that is the
      // whole content of the original incident.
      expect(t.error, contains(kDefaultBase));
    });

    test('a known flag with no value is a hard error, not an empty target', () {
      expect(resolveTarget(['--port'], env: {}).error, contains('--port needs a value'));
      expect(resolveTarget(['--base', '--port'], env: {}).error,
          contains('--base needs a value'));
    });

    test('--base and --port together is a hard error, not a silent precedence', () {
      final t = resolveTarget(['--base', 'http://x', '--port', '1'], env: {});
      expect(t.ok, isFalse);
      expect(t.error, contains('not both'));
    });
  });

  group('resolveTarget — rule 3: --base/--port beat APPBOX_BASE beats the default', () {
    test('--port wins over APPBOX_BASE', () {
      final t = resolveTarget(['--port', '4371'],
          env: {'APPBOX_BASE': 'http://localhost:9999'});
      expect(t.base, 'http://localhost:4371');
      expect(t.via, '--port');
    });

    test('--base wins over APPBOX_BASE', () {
      final t = resolveTarget(['--base', 'http://example:1'],
          env: {'APPBOX_BASE': 'http://localhost:9999'});
      expect(t.base, 'http://example:1');
      expect(t.via, '--base');
    });

    test('APPBOX_BASE wins over the default', () {
      final t = resolveTarget([], env: {'APPBOX_BASE': 'http://localhost:9999'});
      expect(t.base, 'http://localhost:9999');
      expect(t.via, 'APPBOX_BASE');
    });

    test('inline --port=N is honoured, not treated as unknown', () {
      final t = resolveTarget(['--port=4371'], env: {});
      expect(t.base, 'http://localhost:4371');
      expect(t.via, '--port');
    });

    test('-p and -b are the documented short forms', () {
      expect(resolveTarget(['-p', '4371'], env: {}).base, 'http://localhost:4371');
      expect(resolveTarget(['-b', 'http://x'], env: {}).base, 'http://x');
    });
  });

  group('resolveTarget — rule 2: the target is printed before any check runs', () {
    test('the first note names the target and how it was resolved', () {
      final t = resolveTarget(['--port', '4371'], env: {});
      expect(t.notes.first, 'probe target: http://localhost:4371  (via --port)');
    });

    test('the default fallback is loud — it exists, but never silently', () {
      final t = resolveTarget([], env: {});
      expect(t.base, kDefaultBase);
      expect(t.via, 'default');
      expect(t.notes.length, 2);
      expect(t.notes[1], contains('shared dev server'));
      expect(t.notes[1], contains('--port'));
    });

    test('an explicit target gets no shared-dev-server note', () {
      expect(resolveTarget(['--port', '4371'], env: {}).notes.length, 1);
    });
  });

  group('disposableVerdict — refusing to mutate a project that is not disposable', () {
    test('rejects a project whose name does not end in -probe or -test', () {
      final v = disposableVerdict({'boundProject': 'portalo'}, 'http://x');
      expect(v.ok, isFalse);
      expect(v.message, contains('not\n       disposable'));
      // The refusal has to be actionable: it prints the copy command.
      expect(v.message, contains('cp -R ~/.appbox/projects/portalo'));
    });

    test('accepts -probe and -test suffixes', () {
      for (final name in ['portalo-probe', 'portalo-test', 'a-b-c-probe']) {
        final v = disposableVerdict({'boundProject': name}, 'http://x');
        expect(v.ok, isTrue, reason: name);
        expect(v.message, contains('confirmed disposable project "$name"'));
      }
    });

    test('a name merely containing probe/test is not disposable', () {
      for (final name in ['probe-portalo', 'portalo-probe-live', 'testing']) {
        expect(disposableVerdict({'boundProject': name}, 'http://x').ok, isFalse,
            reason: name);
      }
    });

    test('reads boundProject and never current — current lies in the safe direction', () {
      // The live case that proved this: a server booted --project
      // portalo-probe reported current: "portalo". Trusting `current` here
      // would refuse a safe run; trusting it the other way (a marker flipped
      // to a disposable name while the server stays bound to the real project)
      // would permit a corrupting one.
      final v = disposableVerdict(
          {'current': 'portalo', 'boundProject': 'portalo-probe'}, 'http://x');
      expect(v.ok, isTrue);

      final w = disposableVerdict(
          {'current': 'portalo-probe', 'boundProject': 'portalo'}, 'http://x');
      expect(w.ok, isFalse, reason: 'a disposable-looking marker must not unlock a real project');
    });

    test('an unreachable or non-JSON target fails closed', () {
      final v = disposableVerdict(null, 'http://x', fetchError: 'Connection refused');
      expect(v.ok, isFalse);
      expect(v.message, contains('could not confirm'));
      expect(v.message, contains('Connection refused'));
    });

    test('a server binary with no boundProject field is unknown, not "none bound"', () {
      final v = disposableVerdict({'current': 'portalo'}, 'http://x');
      expect(v.ok, isFalse);
      expect(v.message, contains('predates that field'));
    });

    test('boundProject: null is a stated fact — nothing overlaid, nothing to corrupt', () {
      final v = disposableVerdict({'boundProject': null}, 'http://x');
      expect(v.ok, isTrue);
      expect(v.message, contains('artifact-only'));
    });
  });

  group('ProbeReport — the output shape the parity diff depends on', () {
    test('sections, checks and the trailer match the .mjs shape byte for byte', () {
      final buf = StringBuffer();
      final r = ProbeReport(out: buf)
        ..section('/design')
        ..check('draft survives an unrelated swap', true)
        ..check('textarea clears after send', true, '""');
      expect(r.finish(), 0);
      expect(buf.toString(),
          '\n=== /design ===\n'
          '  [PASS] draft survives an unrelated swap\n'
          '  [PASS] textarea clears after send — ""\n'
          '\n==== ALL PASSED ====\n');
    });

    test('a failure is counted, named, and turns the trailer and exit code', () {
      final buf = StringBuffer();
      final r = ProbeReport(out: buf)
        ..check('a', false)
        ..check('b', true)
        ..check('c', false, 'why');
      expect(r.fails, 2);
      expect(r.finish(), 1);
      expect(buf.toString(), contains('  [FAIL] a\n'));
      expect(buf.toString(), contains('  [FAIL] c — why\n'));
      expect(buf.toString(), endsWith('\n==== 2 FAILED ====\n'));
    });

    test('skip and warn are neither passes nor failures', () {
      final buf = StringBuffer();
      final r = ProbeReport(out: buf)
        ..skip('no pin control on this shell')
        ..warn('the DOM never went quiet');
      expect(r.fails, 0);
      expect(r.finish(), 0);
      expect(buf.toString(), contains('  [skip] no pin control on this shell\n'));
      expect(buf.toString(), contains('  [warn] the DOM never went quiet\n'));
    });

    test('bareVerdicts prints flowwalk\'s unbracketed shape', () {
      final buf = StringBuffer();
      ProbeReport(out: buf, bareVerdicts: true)
        ..check('flows lens offers the walk control', true)
        ..check('exactly one tile is the current step', true, 'S1')
        ..check('the source tile is no longer the active step', false);
      // probe-flowwalk.mjs line 35: two spaces, the word, TWO spaces, label.
      expect(
          buf.toString(),
          '  PASS  flows lens offers the walk control\n'
          '  PASS  exactly one tile is the current step — S1\n'
          '  FAIL  the source tile is no longer the active step\n');
    });

    test('bareVerdicts is opt-in — the bracketed shape is unchanged', () {
      final buf = StringBuffer();
      ProbeReport(out: buf).check('a', true, 'd');
      expect(buf.toString(), '  [PASS] a — d\n');
    });

    test('bare mode still counts failures and still exits non-zero', () {
      // The reason this is a flag rather than "write to out yourself": a probe
      // that bypasses check() to get the shape it wants also bypasses the
      // count, and then prints FAIL while exiting 0. That is the one outcome a
      // probe suite must never produce, so it gets pinned here.
      final buf = StringBuffer();
      final r = ProbeReport(out: buf, bareVerdicts: true)
        ..check('a', false)
        ..check('b', true)
        ..check('c', false);
      expect(r.fails, 2);
      expect(r.finish(), 1);
      expect(buf.toString(), contains('  FAIL  a\n'));
      expect(buf.toString(), endsWith('\n==== 2 FAILED ====\n'));
    });

    test('the trailer stays harness-owned under bareVerdicts', () {
      // flowwalk's original ends `ALL CHECKS PASSED`; the ports do not follow,
      // so `probe all` has one scannable closing line rather than one per probe.
      final buf = StringBuffer();
      final r = ProbeReport(out: buf, bareVerdicts: true)..check('a', true);
      expect(r.finish(), 0);
      expect(buf.toString(), endsWith('\n==== ALL PASSED ====\n'));
    });

    test('skip and warn keep harness shape even in bare mode', () {
      final buf = StringBuffer();
      ProbeReport(out: buf, bareVerdicts: true)
        ..skip('not on this shell')
        ..warn('did not settle');
      expect(buf.toString(), contains('  [skip] not on this shell\n'));
      expect(buf.toString(), contains('  [warn] did not settle\n'));
    });

    test('a thrown probe still counts as a failure', () {
      final buf = StringBuffer();
      final r = ProbeReport(out: buf)..error(StateError('boom'));
      expect(r.fails, 1);
      expect(r.finish(), 1);
      expect(buf.toString(), startsWith('ERR '));
    });
  });

  group('wait reporting — the one string ported by hand', () {
    test('the timeout line names the label, matching the .mjs wording', () {
      expect(
          waitTimeoutMessage(
              const Duration(seconds: 8), 'the composer textarea to clear'),
          'timed out after 8000ms waiting for the composer textarea to clear'
          ' — the check below reports the real state');
    });

    test('an unlabelled wait still reads as a sentence', () {
      expect(waitTimeoutMessage(const Duration(milliseconds: 50), ''),
          startsWith('timed out after 50ms waiting for a condition'));
    });

    test('the timeout line goes through warn — it is not a failed check', () {
      final buf = StringBuffer();
      final r = ProbeReport(out: buf)
        ..warn(waitTimeoutMessage(const Duration(seconds: 8), 'a swap'));
      expect(r.fails, 0,
          reason: 'a slow condition must not fail the check behind it — that '
              'check reports the real state and fails on its own terms');
      expect(buf.toString(), startsWith('  [warn] timed out after 8000ms'));
    });
  });

  group('registry', () {
    test('every probe has a unique name and a summary', () {
      final names = kProbes.map((p) => p.name).toList();
      expect(names.toSet().length, names.length, reason: 'duplicate probe name');
      for (final p in kProbes) {
        expect(p.summary, isNotEmpty, reason: p.name);
        // `all` is the suite keyword; a probe cannot claim it.
        expect(p.name, isNot('all'));
      }
    });

    test('a browserless probe gets no browser, and says so if it reaches', () {
      // context-sync is pure HTTP; the harness must not boot Chrome for it.
      final ctx = ProbeContext(
          base: 'http://x', browser: null, report: ProbeReport(out: StringBuffer()));
      expect(ctx.hasBrowser, isFalse);
      expect(ctx.browser, isNull);
      // The page helpers are the path probes actually take, and they explain
      // themselves rather than throwing a null-dereference three frames away.
      expect(
          ctx.newPage(),
          throwsA(predicate((e) => '$e'.contains('needsBrowser: false'),
              'names the declaration that caused it')));
    });

    test('the runner forwards each probe\'s verdict shape', () {
      // The flag lives on Probe so the CLI can construct the report correctly
      // before the body runs; a probe cannot reach back and re-shape it later.
      for (final p in kProbes) {
        expect(ProbeReport(out: StringBuffer(), bareVerdicts: p.bareVerdicts)
            .bareVerdicts, p.bareVerdicts, reason: p.name);
      }
      expect(
          const Probe(name: 'x', summary: 's', mutates: false, body: _noop)
              .bareVerdicts,
          isFalse,
          reason: 'bracketed is the house shape; bare is the exception');
    });

    test('a probe context carries the isolated browser context it opens in', () {
      // Pages open in this context, not the default one. `probe all` was
      // order-dependent without it: the studio keys its session off kdh_sid,
      // so a shared cookie jar carried viewer lens and walk position from one
      // probe into the next.
      final ctx = ProbeContext(
        base: 'http://x',
        browser: null,
        report: ProbeReport(out: StringBuffer()),
        browserContextId: 'BC-1',
      );
      expect(ctx.browserContextId, 'BC-1');
      // Browserless probes have no browser and so no context to open in.
      expect(
          ProbeContext(
                  base: 'http://x',
                  browser: null,
                  report: ProbeReport(out: StringBuffer()))
              .browserContextId,
          isNull);
    });

    test('probes default to needing a browser', () {
      expect(
          const Probe(name: 'x', summary: 's', mutates: false, body: _noop)
              .needsBrowser,
          isTrue);
      expect(
          const Probe(
                  name: 'x',
                  summary: 's',
                  mutates: false,
                  needsBrowser: false,
                  body: _noop)
              .needsBrowser,
          isFalse);
    });

    test('probeByName finds registered probes and nothing else', () {
      expect(probeByName('composer-draft'), isNotNull);
      expect(probeByName('composer-draft')!.mutates, isTrue,
          reason: 'it submits the composer, which POSTs into the served project');
      expect(probeByName('no-such-probe'), isNull);
    });
  });
}
