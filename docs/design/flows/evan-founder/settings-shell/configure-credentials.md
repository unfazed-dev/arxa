# Configure credentials — BYO key or harness shell-out

Actor: Evan (founder, setup mode) · Shell: settings-shell · Surfaces:
`settings.credentials` → `stage_shell_settings_credentials_view`
(none · harness · vault) · Decision refs: architecture.md §15 (credentials —
OS vault, harness shell-out, write→restart→read)

## Trigger

First run — the credentials fork the first-run journey presents (BYO key vs
harness). Or: Evan opens the settings tab on an already-configured machine to
review or rotate a credential.

## Entry / exit

- Entry criteria: app launched, settings shell reachable. No pipeline phase,
  gate, or design state required — credentials sit upstream of all of it.
- Exit states: **verified** — a credential is stored and the write→restart
  →read check passed; the active tier is stated on screen · **harness** — an
  authenticated CLI is detected, app_box holds no token, tier stated as
  `harness` · **unverified** — a key was stored but the read-back returned
  nothing; the screen states this plainly, never green.

## Happy path

1. `settings.credentials` renders. It shows the **current tier** read from
   credential state: `none` (nothing configured), `harness` (an authenticated
   CLI is present), or `vault` (a key is stored in the OS vault and verified).
   The tier is stated plainly — `harness`, or *“stored in the macOS Keychain”*
   — never a generic “configured” (architecture.md §15).
2. **Detection runs first.** The harness adapter probes the session for an
   already-authenticated CLI (`claude`, `kimi`). If one is found, app_box never
   asks for a key — it shells out to that CLI and holds no token. Tier becomes
   `harness`; the credential path is done (architecture.md §15).
3. **BYO key path** (no harness, or Evan overrides): the key-input field is
   offered. On submit the key is written to the OS vault via
   `flutter_secure_storage` → macOS Keychain. The UI states the storage tier:
   *“stored in the macOS Keychain.”*
4. **Verify — write → restart → read back.** The app writes the key, restarts,
   and reads it back, in a signed and notarised build. Only a successful
   read-back flips the tier to `vault` and marks the credential verified.
5. Tier stated on screen. The surface settles on `harness` or `vault`, with the
   storage location named. Downstream LLM stages read this tier from state.

## Decision points

- **Harness vs BYO key:** the harness adapter detects an authenticated CLI →
  `harness`, credential-free, app_box holds no token. No CLI → BYO key path,
  key lives in the vault. Evan may override to force BYO (architecture.md §15).
- **Vault available vs encrypted-file fallback:** `flutter_secure_storage` →
  Keychain is the default. The encrypted-file fallback runs **only where no
  vault exists**, and only if its file-encryption key itself lives in a vault —
  never a hand-rolled key on disk (architecture.md §15).
- **Static key vs OAuth token:** a static API key never expires; an OAuth
  subscription token has refresh, expiry, remote revocation. app_box owns a
  refresh loop **only** for the standalone buyer with no harness — the harness
  path is credential-free by design (§15).

## Edge cases

- **Silently-green vault failure — why write→restart→read exists:** two known
  macOS failure modes write successfully but read back empty — the App Group
  missing from `keychain-access-groups`, and hardened runtime after
  notarisation. Both fail *silently and green* under a naive write-only check.
  The write→restart→read in a signed+notarised build catches both: no read-back
  → tier stays `unverified`, screen states it plainly. This is never rendered
  green (architecture.md §15).
- **Encrypted-file fallback:** only on a platform with no OS vault. The key
  lives in the vault (where one exists at all); the file is the body, not the
  secret. The UI states this tier distinctly from `vault`.
- **Key rotation:** Evan overwrites the stored key. The overwrite re-runs the
  full write→restart→read verification — a rotated key is not trusted until the
  read-back confirms it.
- **Offline:** harness detection needs the session CLI, not the network; a BYO
  key write/read is local to the Keychain. Neither path blocks offline. An
  OAuth refresh that needs the network fails typed, not silent (§15).
- **No credential configured:** tier is `none`. Downstream LLM stages mark
  `blocked` until a credential exists — this is not an error, it is waiting for
  setup (architecture.md §7).

## Screens

| Step | Surface / sheet / dialog |
|---|---|
| 1 | `stage_shell_settings_credentials_view` — current tier (none / harness / vault) |
| 2 | `stage_shell_settings_credentials_view` — harness detected, credential-free |
| 3–4 | `stage_shell_settings_credentials_view` — key input, vault write, write→restart→read |
| 5 | `stage_shell_settings_credentials_view` — verified, tier + storage location stated |

## Notes

- Shell out to an already-authenticated harness CLI where one is present; hold
  tokens only for the standalone case. Owning a refresh loop for two vendors is
  permanent maintenance, and the only user who needs it is the buyer with no
  harness installed (architecture.md §15).
- The **secret** lives in the OS vault; the **tier status** is what the UI
  renders. Closing the app loses nothing — the vault persists; a stored-and-
  verified key is still verified next launch.
- Harness mode drives the whole pipeline: see `../chat-shell/drive-pipeline.md`
  — the MCP chat that shells out to the CLI this flow detects.
- Device pairing is a separate concern: `pair-device.md` (QR + TLS fingerprint).
  Credentials and pairing are independent settings.
- Michelle's first run hits the same fork — the buyer with no harness installed
  is the one user the BYO/vault path exists for (michelle-buyer journey).
