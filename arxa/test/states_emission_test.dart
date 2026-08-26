// Task #43 — the loading/error mandate must have an EMISSION POINT, not just a
// contract, a lint, a taxonomy and a renderer.
//
// The gap this closes: ADR-0003 ("no async without a busy/error surface") was
// stated in skills/arxa-builder/SKILL.md and repeated in a comment inside the
// ViewModel that blueprint.dart generates — and produced by nothing. Every
// generated screen therefore began life violating a contract that no check
// enforced, and the violation was invisible because generator output is a
// STRING: `dart analyze` sees a string literal, not the Dart inside it.
//
// So these tests do two things analyze cannot:
//   1. Assert the branches are present in the emitted source.
//   2. Run the emitted source through `dart format --output=none`, which parses
//      it. That is the same gate task #45 added for generate_view, applied here
//      because a template edit is exactly how unparseable output gets shipped.
//
// WHAT IS DELIBERATELY NOT ASSERTED: an empty state. None of these templates
// binds a collection, so a generated `isEmpty` branch would be a check over
// nothing that can only ever pass — the vacuous assertion this codebase has
// been bitten by repeatedly. Empty belongs with the list, when the builder
// binds one.

import 'dart:io';

import 'package:arxa/blueprint.dart';
import 'package:arxa/scaffold.dart';
import 'package:test/test.dart';

/// Parse-check a snippet by wrapping it in a minimal compilation unit.
/// `dart format` parses and stops; `dart analyze` would also RESOLVE, and these
/// templates import package:stacked and sibling files that do not exist beside
/// a temp file — so analyze would drown in unresolved-import noise and say
/// nothing about syntax.
void expectParses(String source, String label) {
  final dir = Directory.systemTemp.createTempSync('states-emit-');
  try {
    final f = File('${dir.path}/out.dart')..writeAsStringSync(source);
    final r = Process.runSync(
        Platform.resolvedExecutable, ['format', '--output=none', f.path]);
    expect(r.exitCode, 0, reason: '$label emitted unparseable Dart:\n${r.stderr}');
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void main() {
  group('blueprint per-screen templates (the primary app generator)', () {
    final screen = <String, dynamic>{'id': 'order_history', 'name': 'Orders'};

    test('the view emits a loading branch and an error branch', () {
      final out = tplViewForTest(screen);
      expect(out, contains('viewModel.isBusy'));
      expect(out, contains('viewModel.hasError'));
    });

    test('the error branch offers a VISIBLE retry, not just a pull gesture', () {
      // An error screen whose only way forward is an undiscoverable pull is a
      // dead end for the user who most needs a way out.
      final out = tplViewForTest(screen);
      expect(out, contains('onPressed: viewModel.refresh'));
      expect(out, contains('Try again'));
    });

    test('the retry calls a method the paired ViewModel actually declares', () {
      // The whole reason this could be emitted at all: view and ViewModel come
      // from the same generator, so the button cannot point at a missing
      // method. If someone deletes refresh() from the VM template, this fails
      // here instead of in a downstream Flutter build.
      expect(tplViewForTest(screen), contains('viewModel.refresh'));
      expect(tplViewModelForTest(screen), contains('Future<void> refresh() async'));
    });

    test('the error surface shows a sentence, never the raw error object', () {
      // modelError carries internals; putting it on screen leaks them and reads
      // as a crash to the user.
      final out = tplViewForTest(screen);
      expect(out, contains('Something went wrong'));
      expect(out, isNot(contains('Text(viewModel.modelError')));
      expect(out, isNot(contains('\$viewModel.modelError')));
    });

    test('no empty state is invented for a body that binds no collection', () {
      // Comment lines are stripped first: the template EXPLAINS why it emits no
      // empty state, and that prose contains the very token being forbidden.
      // Asserting against raw source made this fail on its own documentation —
      // the assertion has to be about emitted CODE, not about words near it.
      final code = tplViewForTest(screen)
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('isEmpty')));
    });

    test('both templates parse', () {
      expectParses(tplViewForTest(screen), 'blueprint _tplView');
      expectParses(tplViewModelForTest(screen), 'blueprint _tplViewModel');
    });
  });

  group('scaffold surface skeletons', () {
    final screen = <String, dynamic>{
      'id': 'portalo.cart',
      'comp': 'Cart',
      'surface': 'cart',
      'shellDir': 'main_shell',
    };

    test('the skeleton view emits both states and a retry', () {
      final out = stubViewForTest(screen, const ['mobile'], const ['ios']);
      expect(out, contains('viewModel.isBusy'));
      expect(out, contains('viewModel.hasError'));
      expect(out, contains('onPressed: viewModel.refresh'));
    });

    test('the skeleton ViewModel declares the refresh the view calls', () {
      expect(stubViewModelForTest(screen),
          contains('Future<void> refresh() async'));
    });

    test('both skeletons parse', () {
      expectParses(
          stubViewForTest(screen, const ['mobile'], const ['ios']),
          'scaffold _stubView');
      expectParses(stubViewModelForTest(screen), 'scaffold _stubViewmodel');
    });
  });
}
