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

- Current pin: `a25dafe6c8d62bb0db6ef5b717f2f7fdd4aaffe3` — cairn `main`
  including `CairnDatabase.local` (0b). Flip to the `v0.2.0` tag as a one-line
  bump when cairn cuts it (no git tag has ever carried cairn_flutter; `v0.1.0`
  predates `sdk/`).
- Bumps are deliberate, never casual. Each bump records, in the commit message:
  1. what changed in cairn's `hook/` (native build surface),
  2. the flutter_rust_bridge pin,
  3. prebuilt-artifact availability (the zero-toolchain gate above).
