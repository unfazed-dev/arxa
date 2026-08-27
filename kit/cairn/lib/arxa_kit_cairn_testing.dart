/// Test support for arxa_kit_cairn consumers: a store-backed fake cairn
/// engine (no native library) plus a ready-made [ArxaKitCairnOpenDatabase]
/// that opens `CairnDatabase.localForTest` over it. Apps testing cairn-backed
/// features inject these through `ArxaKitCairnBackend(openDatabase: …)` —
/// the whole kit stack runs in pure Dart.
///
/// ```dart
/// final engine = FakeCairnEngine();
/// final backend = ArxaKitCairnBackend(
///   config: const ArxaKitCairnConfig(),
///   openDatabase: cairnLocalOpenForTest(engine),
/// );
/// ```
library;

import 'package:cairn_flutter/cairn_flutter.dart';

import '../arxa_kit_cairn_backend.dart';
import 'testing/fake_cairn_engine.dart';

export 'testing/fake_cairn_engine.dart';

/// An [ArxaKitCairnOpenDatabase] that runs the REAL local-open path (apply
/// schema → subscribe → pause sync) over [engine], honoring the config's CRDT
/// table sets exactly like the production default.
ArxaKitCairnOpenDatabase cairnLocalOpenForTest(FakeCairnEngine engine) =>
    (config, schema, token) async {
      // Test seams from cairn_flutter — the pure-Dart path engine.dart
      // documents; production opens go through the native library.
      // ignore: invalid_use_of_visible_for_testing_member
      final cairn = Cairn.withEngine(
        engine,
        orSetTables: config.orSetTables,
        counterTables: config.counterTables,
      );
      // ignore: invalid_use_of_visible_for_testing_member
      return CairnDatabase.localForTest(cairn, schema);
    };
