# arxa_kit_cairn

The cairn backend for arxa_kit apps. This package **owns the `cairn_flutter`
import** — apps never touch cairn directly; they configure
`ArxaKitDataConfig(backend: ArxaKitDataBackend.plugin, plugin: ArxaKitCairnBackend(...))`
and every cairn capability reaches them through kit types.

## Modes

| Mode | Env | Server | Notes |
| --- | --- | --- | --- |
| `localOnly` (default) | none | none | `CairnDatabase.local` — free-user parity: identical app code, zero infra |
| `sync` | `ARXA_CAIRN_URL` | self-hosted cairn | host-supplied token provider |
| `supabaseBridge` | `ARXA_CAIRN_URL` | cairn + Supabase | session JWTs from kit/data auth — **tokens are never env** |

## INTERIM prerequisite: Rust toolchain (D3)

`cairn_flutter` ships a native build hook (`hook/build.dart`) whose
`hook/prebuilt.json` artifact URLs are **all empty placeholders** at the pinned
ref — the cargo fallback is the active build path on every platform. Until
upstream populates prebuilt artifacts (tracked, non-blocking — "0c"), consumers
of this kit need:

- **All platforms:** a Rust toolchain (`rustup`, stable).
- **Android:** `cargo-ndk` + Android NDK, API level 24 (`cargo install cargo-ndk`;
  the hook throws a helpful error if either is missing).
- **CI:** the same installs must happen before `flutter build` / `flutter test`
  steps that compile the hook.

**Zero-toolchain flip:** when cairn's CI publishes sha256-verified prebuilt
binaries (candidate plumbing: pub `native_prebuilt`), this kit flips to
zero-toolchain at the pin bump after that lands. No consumer code changes —
only the pin and this section.

## Pin discipline (D1)

`cairn_flutter` is git-pinned by **full SHA** in `pubspec.yaml`:

- Current pin: `ed5205f5abfcdeae20401da6e6d30cf0ed45f881` — cairn `main`
  carrying sessionless `CairnDatabase.supabase` open, tenant-scoped CRDT
  merge, and the boot-time tenant-column audit. Flip to the `v0.2.0` tag as
  a one-line bump when cairn cuts it (no git tag has ever carried
  cairn_flutter; `v0.1.0` predates `sdk/`).
- Bumps are deliberate, never casual. Each bump records, in the commit message:
  1. what changed in cairn's `hook/` (native build surface),
  2. the flutter_rust_bridge pin,
  3. prebuilt-artifact availability (the zero-toolchain gate above).

  The "Current pin" line above rides the SAME commit as the pubspec bump — a
  README/pubspec mismatch is a bump bug (it happened once: this line sat at
  `d6e3de9` while the pubspec had already moved to `ed5205f5`).
- Pin history (trio verified against cairn git, 2026-08-29 — every pin is an
  ancestor of cairn's public `main`; the unpushed-SHA risk never bit):

  | date | pin | carried | `hook/` changes | FRB pin | prebuilt URLs |
  |---|---|---|---|---|---|
  | 2026-08-27 | `a25dafe6` | initial — D1's `fa1c5840` + ADR-0041 doc + `CairnDatabase.local` (0b landed upstream first) | — | `2.13.0-beta.5` | all 7 empty |
  | 2026-08-28 | `d6e3de9` | `AttachmentDatabase` barrel export | none | `2.13.0-beta.5` | all 7 empty |
  | 2026-08-28 | `93b93b8` | `CairnEngine` seam barrel export | none | `2.13.0-beta.5` | all 7 empty |
  | 2026-08-28 | `ed5205f5` | sessionless supabase open, tenant-scoped CRDT merge, `cairn dev` CRDT env forwarding | none | `2.13.0-beta.5` | all 7 empty |

## Storage (opt-in)

`ArxaKitCairnBackend(storage: true)` maps kit/data's `ArxaKitStorageService`
onto cairn attachments (ADR-0034, two-plane):

- The `attachments` metadata table is **auto-appended** to the emitted schema
  (an app entity named `attachments` fails loudly at boot — the driver owns
  that table). Server-side, `CAIRN_WRITE_TABLES` must include `attachments`;
  `CairnSchemaEmitter.emitServerCrdtEnv(..., includeAttachments: true)`
  documents it in the generated snippet.
- The attachment id is derived as `<bucket>/<path>` — per-call buckets coexist
  and the remote adapter routes on the prefix. Caller-built refs resolve
  identically (`ref.id` is never trusted).
- `upload` returns once bytes are durably queued (local cache + outbox row);
  the remote leg runs on the driver's online pump. `getUrl` uses
  `storageUrlFor` when given (supabaseBridge defaults to Supabase's public
  URL), otherwise a `data:` URL from the local blob — local-only parity.
- Remote plane per mode: `localOnly` → none needed; `supabaseBridge` →
  per-bucket Supabase adapter wired automatically; `sync` → **you must pass
  `storageAdapter`** (your bucket), or boot fails naming the param.

## Push (opt-in)

`ARXA_CAIRN_PUSH=true` (literal — `=1` is silently off) attaches an
`ArxaKitCairnPushBridge` after engine open: tokens from the
`arxa_kit_notifications` seam (`tokenStream` + `currentToken()`) register via
`CairnDatabase.registerPushToken`; every refresh re-registers (the SDK
deregisters session tokens on sign-out); `CairnPushTokenException` is
non-fatal and retries on the next attach/refresh. Requires the
`notifications:` param and a non-local mode — both fail loudly at boot.

**The provider rail is app-side** — the kit never imports Firebase:

- Mirror `firebase_core ^4.13.0` / `firebase_messaging ^16.5.0` (+ `web` for
  the VAPID leg) in the APP, with conditional init so builds stay green
  without operator config (`google-services.json` / `GoogleService-Info.plist`
  are never checked in).
- Background-isolate doorbell (FCM `onBackgroundMessage`, `@pragma
  ('vm:entry-point')`): read the creds file your foreground session persisted
  from `backend.currentAccessToken` next to the sqlite store →
  `CairnDatabase.connect` the **same** sqlite path → `subscribe` +
  `waitForFirstSync()` → `close()` — **never `signOut()`** (the local store
  must survive). A stale token's wake 401s into a harmless no-op.
- Web: VAPID — the public key pairs to the server's private key; register the
  service worker and pass the JSON `{endpoint, keys{p256dh, auth}}` as a
  `webpush` platform token.
- macOS: `firebase_messaging` has no macOS implementation — desktop is
  **sync-only** (the WS connection is the doorbell).
- Push is a doorbell, not a data channel: payloads carry at most
  `{table, lsn}`; row data always arrives over the sync connection.
