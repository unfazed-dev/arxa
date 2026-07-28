import 'package:flutter/widgets.dart';
import 'package:stacked/stacked.dart';

import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/credential_service.dart';

/// settings.credentials — the vault tier stated plainly (brief §4, J1).
///
/// Two unrelated things live on this surface and they are kept apart on
/// purpose:
///
///  * **A BYO API key** is how the app reaches an *LLM provider*. It sets the
///    tier.
///  * **A licence** is a purchase precondition (8.12). It sets no tier, and
///    nothing goes red for the lack of one.
///
/// They used to share a single text buffer, so `saveKey` stored whatever had
/// been typed into the licence field — and the surface offered no key field at
/// all, making it unreachable.
class SettingsCredentialsViewModel extends BaseViewModel {
  final _creds = locator<CredentialService>();

  /// Controllers rather than plain buffers so a saved secret is actually
  /// cleared from the field — leaving a key on screen after storing it is the
  /// kind of small dishonesty this surface exists to avoid.
  final licenceController = TextEditingController();
  final apiKeyIdController = TextEditingController();
  final apiKeyController = TextEditingController();

  String get _licence => licenceController.text;
  String get _apiKeyId => apiKeyIdController.text;
  String get _apiKey => apiKeyController.text;

  String get storageTierLabel => _creds.storageTierLabel;
  CredentialTier get tier => _creds.activeTier;
  List<StoredCredential> get credentials => _creds.credentials;
  bool get hasLicence => _creds.hasLicence;

  String get tierLabel => switch (tier) {
        CredentialTier.none => 'No provider credential stored',
        CredentialTier.byoKey => 'BYO key — stored in the $storageTierLabel',
        CredentialTier.harness => 'Harness CLI (app holds no token)',
        CredentialTier.oauth => 'OAuth token — stored in the $storageTierLabel',
      };

  String get licenceLabel =>
      hasLicence ? 'Licence stored in the $storageTierLabel' : 'No licence yet';

  /// Reads the vault back so a restart does not show an empty list over a full
  /// Keychain.
  Future<void> initialise() async {
    await _creds.hydrate();
    notifyListeners();
  }

  bool get canSaveLicence => _licence.trim().isNotEmpty;
  bool get canSaveApiKey =>
      _apiKeyId.trim().isNotEmpty && _apiKey.trim().isNotEmpty;

  Future<void> saveLicence() async {
    if (!canSaveLicence) return;
    await _creds.storeLicence(_licence.trim());
    licenceController.clear();
    notifyListeners();
  }

  Future<void> saveApiKey() async {
    if (!canSaveApiKey) return;
    await _creds.storeApiKey(id: _apiKeyId.trim(), key: _apiKey.trim());
    apiKeyIdController.clear();
    apiKeyController.clear();
    notifyListeners();
  }

  Future<void> deleteCredential(String id) async {
    await _creds.delete(id);
    notifyListeners();
  }

  @override
  void dispose() {
    licenceController.dispose();
    apiKeyIdController.dispose();
    apiKeyController.dispose();
    super.dispose();
  }
}
