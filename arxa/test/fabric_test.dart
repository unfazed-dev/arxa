import 'dart:io';

import 'package:arxa/fabric.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // Tests run from arxa/; the catalog lives at the repo root.
  final fabric =
      ModelFabric.load(p.normalize(p.join(Directory.current.path, '..')));

  test('declares all 8 providers (7 + fugu)', () {
    expect(
      fabric.providers.map((pr) => pr.name),
      containsAll(
          ['kimi', 'zai', 'anthropic', 'openai', 'deepseek', 'gemini', 'xai', 'fugu']),
    );
    expect(fabric.providers, hasLength(8));
  });

  test('every tier candidate references a declared provider', () {
    final declared = fabric.providers.map((pr) => pr.name).toSet();
    for (final tierName in fabric.tiers.keys) {
      for (final candidate in fabric.tier(tierName)) {
        expect(declared, contains(candidate.provider),
            reason: '$tierName/${candidate.model}');
      }
    }
  });

  test('every stage maps to a valid tier (or none)', () {
    for (final stageName in fabric.stages.keys) {
      final stage = fabric.stage(stageName);
      if (stage.tier != null) {
        expect(fabric.tiers.keys, contains(stage.tier),
            reason: 'stage $stageName');
      }
    }
    // The plan's three neutral tiers all exist.
    expect(fabric.tiers.keys,
        containsAll(['frontier', 'standard', 'fast']));
  });

  test('param_policy values are from the known set', () {
    for (final provider in fabric.providers) {
      for (final policy in provider.paramPolicy) {
        expect(ModelFabric.knownParamPolicies, contains(policy),
            reason: '${provider.name}: $policy');
      }
    }
  });

  group('costFor', () {
    test('prices recorded usage at per-1M rates', () {
      // kimi-k2.7-code: $0.95 in / $4 out per 1M.
      expect(fabric.costFor('kimi-k2.7-code', 1000000, 500000),
          closeTo(0.95 + 2.0, 1e-12));
    });

    test('null when tokens, model, or pricing are absent', () {
      expect(fabric.costFor('kimi-k2.7-code', null, 5), isNull);
      expect(fabric.costFor('kimi-k2.7-code', 5, null), isNull);
      expect(fabric.costFor('no-such-model', 5, 5), isNull);
      // glm-4.7-flash is explicitly unpriced (free).
      expect(fabric.costFor('glm-4.7-flash', 5, 5), isNull);
    });
  });

  group('checkerFirst (maker/checker split)', () {
    test('demotes the maker provider behind the rest of the tier', () {
      final reordered = fabric.checkerFirst('frontier', 'kimi');
      expect(reordered.first.provider, isNot('kimi'));
      expect(reordered.last.provider, 'kimi',
          reason: 'the maker provider stays as the last resort');
      expect(reordered, hasLength(fabric.tier('frontier').length));
    });

    test('no collision → the identical list', () {
      final candidates = fabric.tier('frontier');
      expect(fabric.checkerFirst('frontier', 'no-such-provider'),
          same(candidates));
    });
  });
}
