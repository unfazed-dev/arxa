import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A provider entry from config/model-fabric.json (plan E4).
class FabricProvider {
  FabricProvider({
    required this.name,
    required this.baseUrl,
    required this.protocol,
    required this.keyRef,
    required this.paramPolicy,
    this.anthropicUrl,
    this.notes,
    this.optional = false,
  });

  final String name;

  /// Null only for `optional` entries with no endpoint yet (e.g. fugu).
  final String? baseUrl;
  final String? anthropicUrl;
  final String protocol;

  /// Vault key name holding this provider's credential.
  final String keyRef;
  final List<String> paramPolicy;
  final String? notes;
  final bool optional;
}

/// One ordered candidate in a tier list (runner takes first with a vault key).
class FabricModel {
  FabricModel({
    required this.model,
    required this.provider,
    this.priceIn,
    this.priceOut,
    this.notes,
  });

  final String model;
  final String provider;

  /// USD per 1M input/output tokens; null when unpriced (free, quota-only,
  /// or unverified pricing).
  final double? priceIn;
  final double? priceOut;
  final String? notes;
}

/// A stage → tier default. [tier] is null for stages that run no LLM.
class FabricStage {
  FabricStage({required this.stage, required this.tier, this.notes});

  final String stage;
  final String? tier;
  final String? notes;
}

/// The model fabric catalog (plan E4): providers, neutral tier candidate
/// lists, stage → tier defaults, and the escalation rule. Schema-versioned;
/// this is the canonical schema owner — the gateway and the engine both
/// load the catalog through this class.
class ModelFabric {
  ModelFabric._({
    required this.providers,
    required this.tiers,
    required this.stages,
    required this.escalation,
  });

  static const schemaVersion = 1;

  /// Every param_policy value the gateway knows how to honor. The catalog
  /// must not invent others.
  static const knownParamPolicies = {
    'omit_temperature',
    'omit_sampling',
    'json_object_only',
    'echo_reasoning_content',
  };

  final List<FabricProvider> providers;
  final Map<String, List<FabricModel>> tiers;
  final Map<String, FabricStage> stages;

  /// Escalation policy (raw object): `rule`, `bounded`, `downgrade`.
  final Map<String, Object?> escalation;

  /// Loads config/model-fabric.json under [repoRoot].
  static ModelFabric load(String repoRoot) =>
      parse(File(p.join(repoRoot, 'config', 'model-fabric.json'))
          .readAsStringSync());

  /// Parses and validates the catalog; throws [FormatException] on a wrong
  /// schema version or a missing/mistyped required field.
  static ModelFabric parse(String source) {
    final json = jsonDecode(source);
    if (json is! Map) {
      throw const FormatException('model-fabric: root must be an object');
    }
    if (json['schema_version'] != schemaVersion) {
      throw FormatException(
          'model-fabric: unsupported schema_version ${json['schema_version']}');
    }

    final providers = [
      for (final entry in _list(json, 'providers')) _provider(_map(entry, 'providers[]')),
    ];

    final rawTiers = _map(json['tiers'], 'tiers');
    final tiers = <String, List<FabricModel>>{
      for (final name in rawTiers.keys)
        name as String: [
          for (final entry in _list(rawTiers, name))
            _model(_map(entry, 'tiers.$name[]')),
        ],
    };

    final rawStages = _map(json['stages'], 'stages');
    final stages = <String, FabricStage>{
      for (final name in rawStages.keys)
        name as String: _stage(name, _map(rawStages[name], 'stages.$name')),
    };

    final escalation = _map(json['escalation'], 'escalation');

    return ModelFabric._(
      providers: providers,
      tiers: tiers,
      stages: stages,
      escalation: escalation.cast<String, Object?>(),
    );
  }

  FabricProvider provider(String name) => providers.firstWhere(
        (pr) => pr.name == name,
        orElse: () => throw ArgumentError('unknown provider: $name'),
      );

  /// Ordered candidate list for [name]; throws on an unknown tier.
  List<FabricModel> tier(String name) =>
      tiers[name] ?? (throw ArgumentError('unknown tier: $name'));

  FabricStage stage(String name) =>
      stages[name] ?? (throw ArgumentError('unknown stage: $name'));

  /// USD cost of [tokensIn]/[tokensOut] on [modelName] at the catalog's
  /// per-1M-token prices (E4 scorecard feed). Null when the model is unknown
  /// or unpriced, or when either token count is null — cost is measured or
  /// absent, never estimated.
  double? costFor(String modelName, int? tokensIn, int? tokensOut) {
    if (tokensIn == null || tokensOut == null) return null;
    for (final candidates in tiers.values) {
      for (final c in candidates) {
        if (c.model != modelName) continue;
        final priceIn = c.priceIn, priceOut = c.priceOut;
        if (priceIn == null || priceOut == null) return null;
        return tokensIn * priceIn / 1e6 + tokensOut * priceOut / 1e6;
      }
    }
    return null;
  }

  /// Maker/checker split (E4, stages.review.notes): the review stage must not
  /// be served by the build stage's provider. Returns [name]'s candidates
  /// with any on [makerProvider] moved behind the rest — the identical list
  /// when nothing collides, so behavior is unchanged when review ≠ build
  /// already. The maker provider stays in the list: with no keyed
  /// alternative it still serves (a 503 helps nobody).
  List<FabricModel> checkerFirst(String name, String makerProvider) {
    final candidates = tier(name);
    if (!candidates.any((c) => c.provider == makerProvider)) return candidates;
    return [
      ...candidates.where((c) => c.provider != makerProvider),
      ...candidates.where((c) => c.provider == makerProvider),
    ];
  }

  List<String> paramPolicy(String providerName) =>
      provider(providerName).paramPolicy;

  static FabricProvider _provider(Map m) {
    final optional = m['optional'] == true;
    final baseUrl = m['base_url'];
    if (!optional && baseUrl is! String) {
      throw FormatException(
          'model-fabric: provider "${m['name']}" requires base_url');
    }
    return FabricProvider(
      name: _str(m, 'name'),
      baseUrl: baseUrl as String?,
      anthropicUrl: m['anthropic_url'] as String?,
      protocol: _str(m, 'protocol'),
      keyRef: _str(m, 'key_ref'),
      paramPolicy: [
        for (final v in (m['param_policy'] as List? ?? const [])) v as String,
      ],
      notes: m['notes'] as String?,
      optional: optional,
    );
  }

  static FabricModel _model(Map m) => FabricModel(
        model: _str(m, 'model'),
        provider: _str(m, 'provider'),
        priceIn: (m['price_in'] as num?)?.toDouble(),
        priceOut: (m['price_out'] as num?)?.toDouble(),
        notes: m['notes'] as String?,
      );

  static FabricStage _stage(String name, Map m) {
    final tier = m['tier'];
    if (tier != null && tier is! String) {
      throw FormatException('model-fabric: stage "$name" tier must be a string or null');
    }
    return FabricStage(
      stage: name,
      tier: tier as String?,
      notes: m['notes'] as String?,
    );
  }

  static String _str(Map m, String key) {
    final v = m[key];
    if (v is! String || v.isEmpty) {
      throw FormatException('model-fabric: missing required field "$key"');
    }
    return v;
  }

  static Map _map(Object? v, String path) {
    if (v is! Map) throw FormatException('model-fabric: "$path" must be an object');
    return v;
  }

  static List _list(Map m, String key) {
    final v = m[key];
    if (v is! List) throw FormatException('model-fabric: "$key" must be a list');
    return v;
  }
}
