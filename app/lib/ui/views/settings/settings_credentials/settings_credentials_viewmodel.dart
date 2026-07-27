import 'package:stacked/stacked.dart';

import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/credential_service.dart';

/// settings.credentials — vault tier stated (brief §4, J1). The active tier is
/// shown plainly: "stored in the macOS Keychain". Never hand-rolled crypto.
class SettingsCredentialsViewModel extends BaseViewModel {
  final _creds = locator<CredentialService>();
  String _licence = '';

  String get storageTierLabel => _creds.storageTierLabel;
  CredentialTier get tier => _creds.activeTier;
  List<StoredCredential> get credentials => _creds.credentials;
  String get tierLabel => switch (tier) {
        CredentialTier.none => 'No credential stored',
        CredentialTier.byoKey => 'BYO key — stored in the $storageTierLabel',
        CredentialTier.harness => 'Harness CLI (app holds no token)',
        CredentialTier.oauth => 'OAuth token — stored in the $storageTierLabel',
      };

  void onLicence(String v) => _licence = v;

  Future<void> saveLicence() async {
    if (_licence.trim().isEmpty) return;
    await _creds.storeLicence(_licence.trim());
    _licence = '';
    notifyListeners();
  }

  Future<void> saveKey(String id) async {
    // Stores a BYO API key in the Keychain.
    await _creds.storeApiKey(id: id, key: _licence.trim());
    notifyListeners();
  }
}
