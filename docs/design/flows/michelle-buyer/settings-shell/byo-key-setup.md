# BYO key setup — the buyer's credential path

Actor: Michelle (buyer, first-run evaluation) · Shell: settings-shell ·
Surfaces: `settings.credentials` →
`stage_shell_settings_credentials_view` (none · vault — tier stated on screen)
· Decision refs: architecture.md §15 (credentials — OS vault, write→restart
→read), `docs/research/competitors-and-pricing.md` (BYO key is a structural
cost advantage, not a discount)

## Trigger

First run — the credentials fork the showcase flow presents once Michelle has
seen the auto-playing prototype. Or: she opens the settings tab mid-evaluation
to add a key before her own inference run.

## Entry / exit

- Entry criteria: app launched, settings shell reachable. No pipeline phase,
  gate, or design state required — credentials sit upstream of all of it.
- Exit states: **verified** — a key is stored in the macOS Keychain and the
  write→restart→read check passed; the tier is stated on screen as *“stored in
  the macOS Keychain”* · **unverified** — a key was stored but the read-back
  returned nothing; the screen states this plainly, never green · **deferred**
  — Michelle skips; tier stays `none`, downstream LLM stages wait marked
  `blocked`, not errored (architecture.md §7).

## Happy path

1. `settings.credentials` renders. It shows the **current tier** read from
   credential state. On Michelle's first run that is `none` — nothing
   configured yet. The surface names the next step in plain language, not
   “configure credentials”: *“Add your key to generate.”*
2. **Harness detection runs and finds nothing.** The harness adapter probes
   the session for an already-authenticated CLI (`claude`, `kimi`). Michelle
   has none installed — she is evaluating app_box, not running it inside an
   existing toolchain. Detection returns empty; the BYO key path is the only
   one offered. The harness option is Evan's, not hers
   (architecture.md §15).
3. **Key input.** Michelle pastes her API key into the field. The screen states
   where it will live before she submits: *“stored in the macOS Keychain.”* No
   hand-rolled crypto, no “secure cloud” euphemism — the storage location is
   named at its actual tier (architecture.md §15).
4. **Store.** On submit the key is written to the OS vault via
   `flutter_secure_storage` → macOS Keychain. The screen does not claim success
   on a write alone.
5. **Verify — write → restart → read back.** The app writes the key, restarts,
   and reads it back, in a signed and notarised build. Only a successful
   read-back flips the tier to `vault` and marks the credential verified. The
   round-trip exists because two macOS failure modes write green and read empty
   (see Edge cases) — Michelle never sees the mechanism, only its honest
   result.
6. **Tier stated on screen.** The surface settles on `vault` with the storage
   location named. The next downstream action — showcase, or her own first
   project — is offered.

## Decision points

- **BYO key vs harness — only BYO fires for Michelle.** The harness adapter
  detects an authenticated CLI only where one is installed. Michelle, the
  standalone buyer evaluating against FlutterFlow, has no CLI; she takes the
  BYO path by default, not by choice. The harness path is real but lives in
  Evan's flow (`../../evan-founder/settings-shell/configure-credentials.md`).
- **Vault available vs fallback.** macOS always has a Keychain, so
  `flutter_secure_storage` → Keychain is the path Michelle hits. The
  encrypted-file fallback is a no-vault-platform concern — irrelevant on her
  Mac, but the surface states whichever tier is actually active rather than
  assuming (architecture.md §15).
- **Static key vs OAuth token.** A static API key never expires; that is the
  shape Michelle pastes. app_box owns a refresh loop only for the rare
  standalone buyer on an OAuth vendor — and even then, only because the harness
  is absent (§15).

## Edge cases

- **Key invalid.** A malformed or rejected key fails the verify step with a
  clear, plain-language error: which step failed, that the key was not stored,
  and an offer to retry. Never a silent green, never a red gate — credentials
  are upstream of the gates entirely.
- **Silently-green vault failure — why write→restart→read exists.** Two known
  macOS failure modes write successfully but read back empty — the App Group
  missing from `keychain-access-groups`, and hardened runtime after
  notarisation. Both fail *silently and green* under a naive write-only check.
  The write→restart→read in a signed+notarised build catches both: no read-back
  → tier stays `unverified`, screen states it plainly. Michelle sees “we could
  not confirm your key round-trips,” not a false “configured”
  (architecture.md §15).
- **Key rotation.** Michelle overwrites the stored key. The overwrite re-runs
  the full write→restart→read verification — a rotated key is not trusted until
  the read-back confirms it.
- **Offline.** A BYO key write and read are local to the Keychain — neither
  blocks offline. Harness detection needs the session CLI, not the network, and
  finds nothing either way for Michelle.
- **No credential configured.** Tier is `none`. Downstream LLM stages mark
  `blocked` until a credential exists — this is waiting for setup, not an error
  (architecture.md §7).

## Screens

| Step | Surface / sheet / dialog |
|---|---|
| 1 | `stage_shell_settings_credentials_view` — tier `none`, plain-language prompt |
| 2 | `stage_shell_settings_credentials_view` — harness detection returns empty (inline) |
| 3–4 | `stage_shell_settings_credentials_view` — key input, storage tier stated pre-submit, Keychain write |
| 5 | `stage_shell_settings_credentials_view` — write→restart→read verify (result, not mechanism, rendered) |
| 6 | `stage_shell_settings_credentials_view` — `vault`, *“stored in the macOS Keychain”* |

## Notes

- **BYO key is a structural cost advantage, not a discount.** app_box carries
  no marginal inference cost — the key is Michelle's, the spend is hers, the
  control is hers. Competitors bundling generation into a subscription must
  price in model cost and margin; app_box does not. That argues for a flat
  licence over usage-based metering, and it means undercutting the incumbent is
  the actual cost structure, not a loss-leader
  (`docs/research/competitors-and-pricing.md`). Michelle is evaluating against
  FlutterFlow's per-seat tiers; the credential screen is where that economics
  becomes concrete to her.
- **The UI states the vault tier plainly — a small honesty that matters.**
  “Stored in the macOS Keychain” against a competitor's “securely stored in the
  cloud” is the kind of specificity a 20-minute evaluator files away. Naming
  the real tier is a design rule, not copy taste (architecture.md §15).
- The **secret** lives in the OS vault; the **tier status** is what the UI
  renders. Closing the app loses nothing — the vault persists; a stored-and-
  verified key is still verified next launch.
- Evan's counterpart: `../../evan-founder/settings-shell/configure-credentials.md`
  — the same surface from the operator's perspective, including the harness
  shell-out path that never fires for Michelle.
- Entry fork: `../projects-shell/first-run-showcase.md` — the showcase auto-play
  that precedes this credential fork on first run.
