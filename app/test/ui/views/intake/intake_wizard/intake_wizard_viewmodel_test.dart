import 'package:flutter_test/flutter_test.dart';
import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/config_service.dart';
import 'package:app_box/services/intake_runner_service.dart';
import 'package:app_box/ui/views/intake/intake_wizard/intake_wizard_viewmodel.dart';

/// 10.5 — the wizard viewmodel builds an answers document conforming to
/// intake.schema.json, with provenance on every field. The wizard NEVER
/// generates content — buildAnswers is a pure function of the form state.
/// DW1: the answers JSON the wizard produces is the same shape the headless
/// engine consumes.
void main() {
  setUp(() {
    final config = ConfigService()
      ..loadMap({
        'intake': {
          'command': 'python3',
          'script': 'skills/app-box-intake/intake.py',
        },
      });
    locator.registerSingleton<ConfigService>(config);
    locator.registerLazySingleton<IntakeRunnerService>(() => IntakeRunnerService());
  });
  tearDown(() => locator.reset());

  test('buildAnswers produces the intake.schema.json shape with provenance', () {
    final vm = IntakeWizardViewModel();
    vm.onProduct('Demo app');
    vm.onAudience('Indie devs');
    vm.onAppMustDo('list projects, run a build');
    vm.onBrand('none stated');
    vm.onBrandProv(Provenance.inferred);
    vm.onSurfaceId(0, 'projects.home');
    vm.onSurfaceLabel(0, 'Home');

    final answers = vm.buildAnswers();

    // required scalar fields with provenance
    expect(answers['product'], {'value': 'Demo app', 'provenance': 'client'});
    expect(answers['audience'], {'value': 'Indie devs', 'provenance': 'client'});
    // list field
    expect(answers['appMustDo'], {
      'value': ['list projects', 'run a build'],
      'provenance': 'client',
    });
    // targets from state
    expect(answers['targets'], {'value': ['macos'], 'provenance': 'client'});
    // brand with inferred provenance
    expect(answers['brand'], {'value': 'none stated', 'provenance': 'inferred'});
    // surfaces
    final surfaces = answers['surfaces'] as List;
    expect(surfaces.length, 1);
    expect(surfaces[0], {
      'id': 'projects.home',
      'label': 'Home',
      'tab': 'projects',
      'provenance': 'client',
    });
  });

  test('surfaces are optional — empty list when none are valid', () {
    final vm = IntakeWizardViewModel();
    vm.onProduct('Demo');
    vm.onAudience('Devs');
    // leave the default surface row empty (no valid id)

    final answers = vm.buildAnswers();
    expect(answers['surfaces'], isEmpty);
  });

  test('provenance is recorded per field — the whole point of §22', () {
    final vm = IntakeWizardViewModel();
    vm.onProduct('Inferred product');
    vm.onProductProv(Provenance.inferred);
    vm.onAudience('Stated audience');

    final answers = vm.buildAnswers();
    expect((answers['product'] as Map)['provenance'], 'inferred');
    expect((answers['audience'] as Map)['provenance'], 'client');
  });

  test('surfaces derive tab from id prefix (the engine invariant)', () {
    final vm = IntakeWizardViewModel();
    vm.onProduct('Demo');
    vm.onAudience('Devs');
    vm.onSurfaceId(0, 'shop.cart');
    vm.onSurfaceLabel(0, 'Cart');

    final surfaces = vm.buildAnswers()['surfaces'] as List;
    expect(surfaces[0]['tab'], 'shop'); // derived from id prefix
  });

  test('multiple surfaces can be added and each carries provenance', () {
    final vm = IntakeWizardViewModel();
    vm.onProduct('Demo');
    vm.onAudience('Devs');
    vm.onSurfaceId(0, 'projects.home');
    vm.onSurfaceLabel(0, 'Home');
    vm.addSurface();
    vm.onSurfaceId(1, 'projects.new');
    vm.onSurfaceLabel(1, 'New');
    vm.onSurfaceProv(1, Provenance.founder);

    final surfaces = vm.buildAnswers()['surfaces'] as List;
    expect(surfaces.length, 2);
    expect(surfaces[0]['provenance'], 'client');
    expect(surfaces[1]['provenance'], 'founder');
  });
}
