import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_permissions/arxa_kit_testing.dart';

void main() {
  test('kit.permissions.escort — permanentlyDenied triggers the settings escort', () async {
    final perms = FakeArxaKitPermissionsService();
    perms.script(ArxaKitPermission.camera, [ArxaKitPermissionStatus.permanentlyDenied]);

    final status = await perms.request(ArxaKitPermission.camera);

    expect(status, ArxaKitPermissionStatus.permanentlyDenied);
    expect(status.requiresSettingsEscort, isTrue);

    if (status.requiresSettingsEscort) {
      await perms.openAppSettings();
    }
    expect(perms.openAppSettingsCallCount, 1);
  });

  test('kit.permissions.escort — a permanently-denied permission never re-prompts', () async {
    final perms = FakeArxaKitPermissionsService(
      initial: {ArxaKitPermission.location: ArxaKitPermissionStatus.permanentlyDenied},
    );
    // No script queued → request must not silently "grant".
    expect(await perms.request(ArxaKitPermission.location),
        ArxaKitPermissionStatus.permanentlyDenied);
  });
}
