# First-run showcase — install to pitch

Actor: Michelle (buyer, P5) · Shell: projects-shell · Surfaces:
`projects.splash` → _null_ (first-run · onboarding) · `projects.showcase` →
_null_ (the dogfood — the pitch) · `projects.home` →
`stage_shell_projects_home_view` (empty) · Decision refs: architecture.md §1
(P5 — fresh machine, none of your paths/repos/conventions), §7 (LLM backends:
`api` vs `harness` vs `none`), §8 (desktop app — dogfood, bootstrap caveat),
§15 (credentials: OS vault with tier stated vs harness shell-out), §16 (macOS
→ one viewport, 3 files/surface)

## Trigger

First install and launch of the desktop app on a machine that has none of
app_box's paths, repos, or conventions (§1, P5). A local first-run preference
— not pipeline state in `work/` — gates the auto-launch.

## Entry / exit

- Entry criteria: the app binary is installed and launches on macOS; no prior
  first-run completion is recorded locally.
- Exit states: **showcase viewed** — dismissed the dogfood, lands on
  `projects.home` (empty, real wording) · **blocked at credentials** — no BYO
  key and no authenticated harness; the showcase does not fire · **showcase
  failed to launch** — bootstrap-time failure (§8); falls through to
  `projects.home` with a one-line note.

## Happy path

1. App launches. `projects.splash` (null surface) shows the brand splash —
   first-run onboarding that makes a promise, not a bare loading spinner.
2. **Credentials fork** (legibility-filtered). Two paths, Michelle's choice:
   - **BYO key** — one field, paste an API key. On save it is written to the
     macOS Keychain via `flutter_secure_storage`; the screen states the tier
     in plain words — "Stored in your Mac's Keychain" — never "tier 2" or the
     library name (§15). This selects `api` mode (§7).
   - **Harness detected** — a logged-in CLI is found on the machine (e.g.
     Claude Code). The screen names it — "Use the Claude Code you're already
     signed into" — and proceeds credential-free; app_box never sees a token
     (§15). This selects `harness` mode (§7).
3. The showcase app auto-launches as a separate macOS window:
   `projects.showcase` (null surface — the pitch). Michelle is looking at a
   real Flutter desktop app produced by the pipeline. `--targets macos` → one
   viewport (1280), three files per surface (§16). The launch IS the pitch;
   nothing she reads convinces her faster than the output on screen.
4. Michelle explores, then dismisses. The first-run flag clears (local
   preference).
5. Control lands on `projects.home` → `stage_shell_projects_home_view` in its
   **empty** state — no projects yet, with wording that orients her in one
   read (see `./new-project-first.md`).

## Decision points

- **BYO key vs harness:** her choice at the fork. Harness is the fast path
  (credential-free, no key to find); BYO key is the standalone path for a
  buyer with no CLI installed (§7 `api` mode). The screen reads as
  configuration, never as a signup wall.
- **First run vs subsequent:** first run → splash + fork + showcase
  auto-launch; every later launch skips all three and goes straight to
  `projects.home`. The auto-launch is gated only by the first-run flag.
- **Neither credential available:** no key entered and no harness detected →
  the fork blocks and the showcase does not fire. This is the failure exit,
  not a red gate.

## Edge cases

- **Empty Projects screen before any output — THE failure.** Landing on an
  empty `projects.home` with no wording, or wording that assumes she has read
  the docs, kills the evaluation in minute one. The empty state must say, in
  plain language, what to do next (start a project) — see
  `./new-project-first.md`. Red always means a gate broke; an empty list is
  neither red nor an error.
- **Credential wall that reads as signup, not config.** If the fork looks
  like account creation, Michelle bounces — she is evaluating against
  FlutterFlow, not signing up. Wording is "bring your own key" / "use a tool
  you're signed into", never "create an account" or "subscribe".
- **Showcase fails to launch.** The showcase is hand-written v1 UI (bootstrap
  caveat, §8 — app_box does not yet exist to generate itself). A launch
  failure (missing binary, macOS Gatekeeper quarantine, missing entitlements)
  is bootstrap-time, never a red gate. The flow falls through to
  `projects.home` with a one-line note that the showcase could not start. Red
  always means a gate broke; this is neither.
- **macOS desktop, not mobile.** The showcase renders at the macOS viewport
  (1280), not the 390×844 mobile default (§16). One viewport, because the
  target set is `macos` only.
- **Keychain write fails silently (§15).** Two known macOS failure modes
  (App Group missing from `keychain-access-groups`, hardened runtime after
  notarisation) fail *silently and green*. Verification standard is write →
  restart → read back, in a signed and notarised build. If read-back fails,
  the fork surfaces "couldn't store the key" — never a silent green that
  loses the key on next launch.
- **Re-install with preserved state.** If projects already exist from a prior
  install, the showcase still runs on this install's first run, then exits to
  `projects.home` in its **list** state rather than empty.

## Screens

| Step | Surface / sheet / dialog |
|---|---|
| 1 | `projects.splash` (null surface) — brand splash |
| 2 | Credentials fork (null surface — onboarding step, not a settings page) |
| 3–4 | `projects.showcase` (null surface) — the pitch, a launched macOS app |
| 5 | `projects.home` → `stage_shell_projects_home_view` — empty state with wording |

## Notes

- The showcase is the **dogfood**: app_box shows itself (§8). For Michelle it
  reads as the pitch — proof the output is real, take-away Flutter, not a
  locked-in builder export. Same surface, different meaning, than Evan's
  [`../../evan-founder/projects-shell/showcase-first-run.md`](../../evan-founder/projects-shell/showcase-first-run.md).
- **Legibility filter (§1, P5):** Michelle has 20 minutes and has read zero
  docs. Every surface here reads in plain language — no SARIF, no file/line,
  no "harness adapter" or "tier 2". The credentials fork states the storage
  tier in words a buyer recognises.
- The credentials fork is the buyer-specific addition Evan's first-run does
  not have — he is already configured. Full BYO-key flow:
  [`../settings-shell/byo-key-setup.md`](../settings-shell/byo-key-setup.md);
  the fork here is its first-run fast version.
- **Bootstrap caveat (§8):** v1 of the showcase is hand-written; true
  dogfooding (the showcase regenerated through app_box's own pipeline) starts
  at v2.
- Next flow: [`./new-project-first.md`](./new-project-first.md) — Michelle
  starts her first real project from the empty home.
- Supersedes a line in Evan's `showcase-first-run.md` that says Michelle does
  not get the auto-launch — for the buyer, the auto-launch is the pitch.
