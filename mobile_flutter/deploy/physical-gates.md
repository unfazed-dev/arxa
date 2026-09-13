# Physical-device gates — approvals E2E (AXS-018)

> **Execution is gated on physical devices + credentials. Owner: Task 16.**
> Writing this doc was unconditional (T12 brief Step 9); running it waits
> for hardware and accounts. Store-deployment mechanics — fastlane lanes,
> signing custody, the CI prepare-then-halt gate — live in `README.md` and
> are not repeated here.

## Prerequisites

### iOS / APNs

- Physical iPhone (push never fires on the simulator), USB-paired and
  trusted; `xcrun devicectl list devices` (or `flutter devices` from
  `mobile_flutter/`) must list it.
- Apple ID on team `43GNRCGQXQ` with a development profile that carries
  the Push Notifications capability. The committed
  `ios/Runner/Runner.entitlements` pins `aps-environment: development`;
  verify the profile actually grants it:

  ```sh
  security cms -D -i ~/Library/MobileDevice/Provisioning\ Profiles/<dev-profile>.mobileprovision \
    | grep -A1 aps-environment
  ```

- Credential presence (values never printed):
  `cd fastlane && bundle exec fastlane ios doctor`.

### Android / FCM

- Physical Android device with Google Play services, USB debugging on;
  `adb devices` must list it.
- FCM config is bring-your-own: the build is config-less by default
  (nothing calls Firebase until permission is requested). Generate
  `android/app/google-services.json` for your Firebase project
  (`flutterfire configure` or the console download) — never commit it;
  delete it after the run to restore the config-less tree.

## Harness — the real pairhost/iroh route

Same pairing core the Tauri shell runs (`desktop/src-tauri/examples/pairhost.rs`),
headless, from `desktop/` on the engine-hosting machine:

```sh
# LAN leg (phone on the same Wi-Fi) — relay-less is the default:
cargo run --example pairhost -- <engine-host:port>

# Cellular leg (phone off-network — tickets need the n0 relay):
ARXA_PAIRHOST_RELAY=1 cargo run --example pairhost -- <engine-host:port>
```

It prints `TICKET <arxa-pair:...>` on boot and re-mints on every stdin
line (tickets are single-use). Serve the fresh ticket to the phone:

```sh
mkdir -p /tmp/pair && echo '<ticket>' > /tmp/pair/ticket.txt
(cd /tmp/pair && python3 -m http.server 8899)  # http://<lan-ip>:8899/ticket.txt
```

## Legs

All runs from `mobile_flutter/`; `-d <device-id>` from `flutter devices`.

| Leg | How |
|---|---|
| Pair | `flutter test integration_test/approvals_e2e_test.dart -d <device-id> --dart-define=PHASE=smoke --dart-define=TICKET_URL=http://<lan-ip>:8899/ticket.txt` — scan view renders, manual ticket pairs, connected state reached |
| Reconnect | force-quit the app, toggle airplane mode, cold-restart the same run — persisted NodeId + session token must skip the QR and re-dial (`approvals_e2e_test.dart:312`; add `--dart-define=CELLULAR=true` for the relay route) |
| Push registration | same run — real APNs/FCM token case (`approvals_e2e_test.dart:316+`); engine-side log must show `set_push_token` → `OK` |
| Notification presentation + tap-through | raise an approval engine-side; notification presents with the app foregrounded AND backgrounded; tapping it opens the approvals route |
| Approval decision | `--dart-define=PHASE=e2e` — list renders pendings, answer on-device, list empties, refused second answer surfaces the conflict |
| Conversation send | with the tunnel up, send from the phone's conversation composer; confirm receipt engine-side |
| Unpair / revocation | revoke the session on the engine side; the phone's transport must drop; re-pairing must mint a fresh single-use ticket |

## Invocation shapes (`integration_test/approvals_e2e_test.dart`)

```sh
# Full e2e on a physical device, ticket served over the LAN:
flutter test integration_test/approvals_e2e_test.dart \
  -d <device-id> \
  --dart-define=TICKET_URL=http://<lan-ip>:8899/ticket.txt \
  --dart-define=PHASE=e2e

# Off-network / relay leg, ticket passed inline:
flutter test integration_test/approvals_e2e_test.dart \
  -d <device-id> \
  --dart-define=PAIR_TICKET=<fresh-ticket> \
  --dart-define=PHASE=e2e --dart-define=CELLULAR=true
```

`PHASE` = `smoke` (boot, pair, empty approvals state) · `e2e` (decisions +
conflict) · `pressure` (rapid refresh + repeated conflicts).

## Android APK leg

```sh
flutter build apk --release   # needs android/key.properties — see README.md
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb logcat -v time | tee ../evidence/physical-gates-<date>/adb-logcat-raw.txt
```

## Evidence capture + redaction

- Capture into `evidence/physical-gates-<date>/` — `e2e-*.txt` console
  captures plus screenshots, mirroring `evidence/lens-smoke-2026-08-29/`.
- **No tokens or device identifiers in anything committed.** Strip
  `arxa-pair:` tickets (spent or not), APNs/FCM tokens, node ids, and
  device UDIDs/serials before capture lands:

  ```sh
  sed -E -e 's/arxa-pair:[A-Za-z0-9]+/[REDACTED-TICKET]/g' \
         -e 's/[0-9a-fA-F]{64}/[REDACTED-TOKEN]/g' \
         -e 's/[0-9A-F]{8}-[0-9A-F]{16}/[REDACTED-UDID]/g' \
      adb-logcat-raw.txt > adb-logcat.txt
  ```

- Credential checks print present/ABSENT only (the fastlane `doctor` lane
  pattern); screenshots must not show the QR/ticket payload.
