import 'dart:io';

import 'package:appboxd/fabric.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // Tests run from appboxd/; the catalog lives at the repo root.
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
}
