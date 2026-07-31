import '../kit_deploy_target.dart';
import '../models/kit_deploy_config.dart';
import '../models/kit_deploy_result.dart';
import '../process/kit_process_runner.dart';

/// STUB — Vercel backend for static Flutter web builds, not yet wired.
///
/// TODO(appbox_kit_deploy): intended command shape is
/// `flutter build web --release` followed by
/// `vercel deploy build/web --prod --yes` with VERCEL_TOKEN in the
/// environment. Wire and de-stub [deploy] once a project needs Vercel.
class VercelTarget implements KitDeployTarget {
  const VercelTarget(this._runner);

  // Kept so wiring the stub later is a body-only change.
  // ignore: unused_field
  final KitProcessRunner _runner;

  @override
  String get name => 'vercel';

  @override
  Future<List<KitDoctorCheck>> doctor(KitDeployConfig config) async => const [
        KitDoctorCheck(
          name: 'vercel target',
          ok: false,
          detail: 'stub — not yet wired (planned: vercel deploy build/web '
              '--prod --yes)',
        ),
      ];

  @override
  Future<KitDeployResult> deploy(KitDeployConfig config) async {
    throw UnimplementedError(
      'VercelTarget is a stub. Planned shape: flutter build web --release, '
      'then `vercel deploy build/web --prod --yes` with VERCEL_TOKEN set.',
    );
  }
}
