# appbox_kit_permissions

Plugin-neutral **port** for OS permissions. The app depends on
`KitPermissionsService` and two small value types; the concrete plumbing
(`permission_handler`) stays behind the seam.

Phase: **1 — fully implemented** (this is the root permissions kit that the
hardware kits will eventually consume; see *Non-goals*).

## Scope

- `KitPermission` — a neutral enum covering `camera`, `microphone`, `photos`,
  `bluetooth`, `location`, `notifications`.
- `KitPermissionStatus` — the four states a UI branches on: `granted`,
  `denied`, `permanentlyDenied`, `restricted`. iOS `limited`/`provisional`
  collapse to `granted` (usable access).
- `KitPermissionsService` — the port:
  - `status(permission)` — live query, no prompt.
  - `request(permission)` / `requestEach(permissions)` — prompt where allowed.
  - `shouldShowRationale(permission)` — Android rationale hint (`false` on iOS).
  - `openAppSettings()` — the **settings-escort** recovery path.
- `PermissionHandlerKitPermissionsService` — production binding over
  `permission_handler` **^12.0.3** (verified on pub.dev 2026-07-14).

### The escort contract

When a query or request returns `permanentlyDenied` (or `restricted`), the UI
must stop re-prompting and route the user to the system Settings screen via
`openAppSettings()`. `KitPermissionStatus.requiresSettingsEscort` is the
predicate for that branch.

## Testing

`package:appbox_kit_permissions/testing.dart` exports
`FakeKitPermissionsService`: script per-permission responses (including the
`permanentlyDenied → openAppSettings` escort scenario), then assert against
`requestLog` and `openAppSettingsCallCount`.

## Non-goals (deferred)

- **No path dependency is registered** from this or any hardware kit. The
  "root kit others consume" topology (wifi/bluetooth requesting permissions
  through this port) is wired by the downstream workspace-reconciliation pass,
  not here.
- No background-location / precise-vs-approximate split, no
  provisional-notification management, no per-permission usage-description
  copy. Add as the consuming apps need them.

## Native-first

`permission_handler` is a thin wrapper over the platform authorization APIs
(iOS `AVCaptureDevice`/`CLLocationManager`/`PHPhotoLibrary`/… and Android
runtime permissions). No custom native code ships in this package.
