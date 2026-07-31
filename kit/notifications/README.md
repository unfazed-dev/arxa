# appbox_kit_notifications

The **device-notifications** port for `appbox_kit` apps — permission, push
token / foreground-message seams, local notifications, and badge.

## Naming: not the same as core's `KitNotificationService`

`appbox_kit` core already ships `lib/services/notifications/` with
**`KitNotificationService`** (singular) — that is the **in-app transient
feedback** surface (native toast on iOS / snackbar on Android). It is a
different concern and **stays in core**; this package neither moves nor imports
it.

This package's service is **`KitNotificationsService`** (plural) — **OS-level
device notifications and push**. Same word, opposite direction: core is about
drawing an in-app overlay; this is about the system notification center, APNs/
FCM tokens, and the app-icon badge.

## Scope

- **`KitNotificationsService`** (port): `initialize`, `requestPermission`
  (typed `KitNotificationPermissionResult`), `permissionStatus`, `tokenStream`,
  `currentToken`, `foregroundMessages`, `showLocalNotification`, `cancel`,
  `cancelAll`, `setBadgeCount`, `clearBadge`, `dispose`.
- **`LocalKitNotificationsService`** — the working default, wrapping
  flutter_local_notifications (native-first: UNUserNotificationCenter on
  iOS/macOS, NotificationManager on Android). Implements permission + local
  notifications + per-notification badge.
- **`KitOutboundMessageSink`** — a separate port for outbound one-to-one
  messages (SMS/email), with stub sinks.

## Non-goals & limitations

- **No dependency on `appbox_kit` core, `stacked`, or `stacked_services`.**
- **Push is a stub.** `tokenStream` / `foregroundMessages` are seams the FCM/APNs
  backend owns; the local default emits nothing on them. `FcmPushBackend`
  (`firebase_messaging: ^16.1.0`) is a real-signature stub — no `firebase_*`
  dependency is pulled by this package.
- **Standalone badge is unsupported by the local default.** flutter_local_
  notifications only sets the iOS badge as a side effect of a delivered
  notification (`DarwinNotificationDetails.badgeNumber`); there is no standalone
  setter in v21 and Android badges are launcher-specific. So
  `LocalKitNotificationsService.setBadgeCount` / `clearBadge` **throw
  `UnsupportedError`** — set `KitLocalNotification.badgeCount` on a shown
  notification, or own the badge from the push payload. A push backend may
  override these with a real implementation.
- **Outbound SMS/email are stubs** (`SmsBackend`, `EmailBackend`) — provider-side
  (Twilio/SendGrid over HTTPS) or native-send seams, wired only when a host
  opts in.

## Host-app native wiring (out of scope for this package)

- **iOS/macOS:** notification capability + (for push) APNs entitlement and the
  `AppDelegate` registration are the app's responsibility.
- **Android:** the `POST_NOTIFICATIONS` runtime permission (API 33+),
  notification channels, and any FCM `google-services.json` live in the host.

## Phase

**0.1.0 — priority implemented.** `LocalKitNotificationsService` (permission,
show/cancel, per-notification badge) is complete and analyzer-clean.
`FcmPushBackend`, `SmsBackend`, `EmailBackend` are real-signature stubs.

## Testing

`import 'package:appbox_kit_notifications/testing.dart';` for
`FakeKitNotificationsService` (scripted `permissionResult`, `emitToken` /
`emitMessage` stream drivers, recorded `shown` / `cancelled` / `badgeCounts`)
and `FakeOutboundMessageSink` (records `sent`, scriptable `failWith`).
