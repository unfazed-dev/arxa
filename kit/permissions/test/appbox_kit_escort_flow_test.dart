import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_permissions/appbox_kit_testing.dart';

void main() {
  test('permanentlyDenied triggers the settings escort', () async {
    final perms = FakeAppBoxKitPermissionsService();
    perms.script(AppBoxKitPermission.camera, [AppBoxKitPermissionStatus.permanentlyDenied]);

    final status = await perms.request(AppBoxKitPermission.camera);

    expect(status, AppBoxKitPermissionStatus.permanentlyDenied);
    expect(status.requiresSettingsEscort, isTrue);

    if (status.requiresSettingsEscort) {
      await perms.openAppSettings();
    }
    expect(perms.openAppSettingsCallCount, 1);
  });

  test('a permanently-denied permission never re-prompts', () async {
    final perms = FakeAppBoxKitPermissionsService(
      initial: {AppBoxKitPermission.location: AppBoxKitPermissionStatus.permanentlyDenied},
    );
    // No script queued → request must not silently "grant".
    expect(await perms.request(AppBoxKitPermission.location),
        AppBoxKitPermissionStatus.permanentlyDenied);
  });
}
