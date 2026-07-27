import 'dart:convert';
import 'dart:io';

import 'package:stacked/stacked.dart';

import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/intake_runner_service.dart';

/// The provenance the engine records per field (architecture §22): who
/// supplied this value — the client, the founder, or was it inferred? There is
/// no fourth value; unstated means inferred.
enum Provenance { client, founder, inferred }

String provenanceLabel(Provenance p) {
  switch (p) {
    case Provenance.client:
      return 'client';
    case Provenance.founder:
      return 'founder';
    case Provenance.inferred:
      return 'inferred';
  }
}

/// A surface the client named at intake. id is `<tab>.<short>` (lowercase
/// alnum); tab must equal the id's first segment (the engine enforces both).
class SurfaceEntry {
  SurfaceEntry({this.id = '', this.label = '', this.provenance = Provenance.client});
  String id;
  String label;
  Provenance provenance;

  String get tab {
    final parts = id.split('.');
    return parts.length == 2 ? parts[0] : '';
  }

  bool get isValid =>
      RegExp(r'^[a-z][a-z0-9]*\.[a-z][a-z0-9]*$').hasMatch(id) &&
      label.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'tab': tab,
        'provenance': provenanceLabel(provenance),
      };
}

enum IntakeWizardState { form, emitting, done, error }

/// 10.5 — the intake wizard viewmodel.
///
/// Collects elicited answers in the UI and drives the ONE engine
/// (`intake.py emit`) via [IntakeRunnerService]. The wizard NEVER generates
/// design or code (§22): it collects the client's words, marks provenance, and
/// hands the answers to the engine. The engine emits the brief + seeded
/// registry; the wizard does not.
///
/// DW1: the wizard writes the same answers JSON the headless path uses, then
/// invokes the same engine — output is byte-identical by construction (one
/// engine, two fronts).
class IntakeWizardViewModel extends BaseViewModel {
  final _intake = locator<IntakeRunnerService>();

  IntakeWizardState _state = IntakeWizardState.form;
  String? _formError;
  String? _emitSummary;

  // Form fields
  String _product = '';
  Provenance _productProv = Provenance.client;
  String _audience = '';
  Provenance _audienceProv = Provenance.client;
  String _appMustDo = '';
  Provenance _appMustDoProv = Provenance.client;
  final List<String> _targets = ['macos']; // the dogfood target (§11)
  String _brand = '';
  Provenance _brandProv = Provenance.inferred; // brand is often unstated
  final List<SurfaceEntry> _surfaces = [
    SurfaceEntry(id: '', label: ''),
  ];

  IntakeWizardState get state => _state;
  String? get formError => _formError;
  String? get emitSummary => _emitSummary;
  List<SurfaceEntry> get surfaces => _surfaces;
  List<String> get targets => List.unmodifiable(_targets);

  String get product => _product;
  Provenance get productProv => _productProv;
  String get audience => _audience;
  Provenance get audienceProv => _audienceProv;
  String get appMustDo => _appMustDo;
  Provenance get appMustDoProv => _appMustDoProv;
  String get brand => _brand;
  Provenance get brandProv => _brandProv;

  void onProduct(String v) { _product = v; notifyListeners(); }
  void onProductProv(Provenance p) { _productProv = p; notifyListeners(); }
  void onAudience(String v) { _audience = v; notifyListeners(); }
  void onAudienceProv(Provenance p) { _audienceProv = p; notifyListeners(); }
  void onAppMustDo(String v) { _appMustDo = v; notifyListeners(); }
  void onAppMustDoProv(Provenance p) { _appMustDoProv = p; notifyListeners(); }
  void onBrand(String v) { _brand = v; notifyListeners(); }
  void onBrandProv(Provenance p) { _brandProv = p; notifyListeners(); }

  void onSurfaceId(int i, String v) { _surfaces[i].id = v; notifyListeners(); }
  void onSurfaceLabel(int i, String v) { _surfaces[i].label = v; notifyListeners(); }
  void onSurfaceProv(int i, Provenance p) { _surfaces[i].provenance = p; notifyListeners(); }
  void addSurface() { _surfaces.add(SurfaceEntry()); notifyListeners(); }
  void removeSurface(int i) {
    if (_surfaces.length > 1) { _surfaces.removeAt(i); notifyListeners(); }
  }

  /// Builds the answers document conforming to intake.schema.json. Pure
  /// function of the form state — no content invented, no design authored.
  Map<String, dynamic> buildAnswers() {
    final answers = <String, dynamic>{
      'product': {'value': _product.trim(), 'provenance': provenanceLabel(_productProv)},
      'audience': {'value': _audience.trim(), 'provenance': provenanceLabel(_audienceProv)},
      'appMustDo': {
        'value': _appMustDo.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
        'provenance': provenanceLabel(_appMustDoProv),
      },
      'targets': {'value': _targets, 'provenance': 'client'},
    };
    if (_brand.trim().isNotEmpty) {
      answers['brand'] = {'value': _brand.trim(), 'provenance': provenanceLabel(_brandProv)};
    }
    final validSurfaces = _surfaces.where((s) => s.isValid).map((s) => s.toJson()).toList();
    if (validSurfaces.isNotEmpty) {
      answers['surfaces'] = validSurfaces;
    } else {
      answers['surfaces'] = <dynamic>[];
    }
    return answers;
  }

  /// Drives the engine: writes the answers JSON, shells out to intake.py emit.
  /// The engine validates, emits brief.md + registry.json, and returns. The
  /// wizard does not format, generate, or invent — it elicits and records.
  Future<void> emit() async {
    final answers = buildAnswers();

    // minimal client-side validation (the engine validates authoritatively)
    if ((answers['product'] as Map)['value'].toString().trim().isEmpty ||
        (answers['audience'] as Map)['value'].toString().trim().isEmpty) {
      _state = IntakeWizardState.error;
      _formError = 'Product name and audience are required.';
      notifyListeners();
      return;
    }

    _state = IntakeWizardState.emitting;
    _formError = null;
    notifyListeners();

    try {
      // Write the answers JSON to a temp file — the same file shape the
      // headless path uses (DW1: one engine, two fronts).
      final tmpDir = await Directory.systemTemp.createTemp('appbox_intake_');
      final answersPath = '${tmpDir.path}/answers.json';
      final file = File(answersPath);
      await file.writeAsString('${const JsonEncoder.withIndent("  ").convert(answers)}\n');

      final res = await _intake.emit(
        answersPath: answersPath,
        briefOut: 'docs/design/brief.md',
        registryOut: 'docs/design/registry.json',
      );

      if (res.ok) {
        _state = IntakeWizardState.done;
        _emitSummary = res.stdout.trim();
      } else {
        _state = IntakeWizardState.error;
        _formError = res.stderr.trim().isEmpty ? res.stdout.trim() : res.stderr.trim();
      }
    } catch (e) {
      _state = IntakeWizardState.error;
      _formError = 'Could not run the intake engine: $e';
    }
    notifyListeners();
  }

  void reset() {
    _state = IntakeWizardState.form;
    _formError = null;
    _emitSummary = null;
    notifyListeners();
  }
}
