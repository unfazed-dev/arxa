import 'package:cairn_flutter/cairn_flutter.dart';
import 'package:arxa_kit_cairn/arxa_kit_cairn.dart';
import 'package:arxa_kit_data/arxa_kit_testing.dart';

import '../support/fake_cairn_engine.dart';

/// Phase 5a: the cross-backend repository behavior contract (extracted from
/// kit/data's seed suite into `arxa_kit_testing.dart`) running against
/// [CairnKitRepository] over the fake engine's REAL local-open path. If the
/// seed backend and the cairn adapter ever drift on canonicalization, query
/// semantics (nulls-last ordering!), watch replay, or patch rules, this suite
/// is where it surfaces.
void main() {
  final idService = ArxaKitIdService();

  runArxaKitRepositoryContract(
    suite: 'kit.cairn.repo-contract',
    idService: idService,
    makeRepo: () async {
      final engine = FakeCairnEngine();
      // ignore: invalid_use_of_visible_for_testing_member
      final cairn = Cairn.withEngine(engine);
      // ignore: invalid_use_of_visible_for_testing_member
      final db = await CairnDatabase.localForTest(
        cairn,
        CairnSchemaEmitter().schemaFor([arxaKitContractSchema]),
      );
      return CairnKitRepository<ArxaKitContractWidget>(
        db: db,
        registration: arxaKitContractRegistration,
        idService: idService,
      );
    },
  );
}
