import 'package:arxa_kit_data/arxa_kit_testing.dart';
import 'package:arxa_kit_data/repositories/seed/arxa_kit_seed_persistence.dart';
import 'package:arxa_kit_data/repositories/seed/arxa_kit_seed_repository.dart';
import 'package:arxa_kit_data/repositories/seed/arxa_kit_seed_store.dart';

/// ArxaKitSeedRepository runs the cross-backend repository behavior contract
/// ([runArxaKitRepositoryContract] in `arxa_kit_testing.dart`), backed by
/// [ArxaKitSeedStore] + [ArxaKitNoPersistence]. The same suite runs against
/// every backend kit's adapter — drift here is drift everywhere.
void main() {
  final idService = ArxaKitIdService();

  runArxaKitRepositoryContract(
    suite: 'kit.data.seed-repos',
    idService: idService,
    makeRepo: () async => ArxaKitSeedRepository<ArxaKitContractWidget>(
      store: ArxaKitSeedStore(persistence: ArxaKitNoPersistence()),
      registration: arxaKitContractRegistration,
      idService: idService,
    ),
  );
}
