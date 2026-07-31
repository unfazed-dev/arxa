import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_permissions/testing.dart';

void main() {
  test('permanentlyDenied triggers the settings escort', () async {
    final perms = FakeKitPermissionsService();
    perms.script(KitPermission.camera, [KitPermissionStatus.permanentlyDenied]);

    final status = await perms.request(KitPermission.camera);

    expect(status, KitPermissionStatus.permanentlyDenied);
    expect(status.requiresSettingsEscort, isTrue);

    if (status.requiresSettingsEscort) {
      await perms.openAppSettings();
    }
    expect(perms.openAppSettingsCallCount, 1);
  });

  test('a permanently-denied permission never re-prompts', () async {
    final perms = FakeKitPermissionsService(
      initial: {KitPermission.location: KitPermissionStatus.permanentlyDenied},
    );
    // No script queued → request must not silently "grant".
    expect(await perms.request(KitPermission.location),
        KitPermissionStatus.permanentlyDenied);
  });
}
