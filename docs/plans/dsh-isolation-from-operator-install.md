# dsh isolation: arxa must never execute the operator's dsh (2026-08-22)

Trigger: `npx @deepseek-ai/dsh web` failed to boot, and arxa studio failed at
the same time. Operator suspected contamination between the two.

## What was actually wrong

Two independent faults that surfaced together because one npx run changed
shared state.

### Fault 1 — arxa executes the operator's dsh binary (the isolation break)

`arxa-studio/bin/arxa.mjs:189-193` resolved the dsh entrypoint from two
candidates:

    1. arxa-studio/node_modules/@deepseek-ai/dsh/lib/bin.js
    2. ~/.dsh/profiles/node_modules/@deepseek-ai/dsh/lib/bin.js   <- the break

`arxa-studio/node_modules` **does not exist** — no `npm install` was ever run
there. So candidate 1 has never resolved and arxa has *always* booted from
candidate 2, the operator's install.

The in-file comment defended candidate 2 as "read-only reuse — arxa never
writes there". That defence is about *writing*. The leak is *reading*:
executing the operator's binary means arxa runs the operator's version.

Measured consequence:
- `arxa-studio/package.json` pins `@deepseek-ai/dsh` at **0.1.0-rc.7**.
- Version resolved under `~/.arxa/dsh/profiles/node_modules`: **0.1.1-rc.2**.

The pin has never once been honoured.

### Why one npx run broke both at the same instant

Every package in both profile trees is a symlink into a single npx cache slot:

    ~/.dsh/profiles/node_modules        529 of 530 symlinks -> _npx/1e7f6d9597241db0
    ~/.arxa/dsh/profiles/node_modules   510 of 510 symlinks -> _npx/1e7f6d9597241db0
    distinct slots referenced: 1  (all 1039 links)

`npx @deepseek-ai/dsh web` resolved `latest` = 0.1.1-rc.2 and rewrote that slot.
Both installs changed version simultaneously, because they are the same bytes
on disk. That slot is the same path in the operator's stack trace.

**Never `rm` `~/.npm/_npx/1e7f6d9597241db0`** while those links exist — it
would dangle 1039 symlinks and kill both installs at once.

### Fault 2 — ZAI_API_KEY is not in the environment (independent of the version flip)

`~/.dsh/profiles/web/cordis.patch.yml` declares, under `mcp-zai-vision`:

    env:
      Z_AI_API_KEY: !!js "process.env.ZAI_API_KEY"
      Z_AI_MODE: ZAI

There is **no `.env` layer anywhere** (`~/.dsh/.env`, `~/.dsh/profiles/web/.env`,
`~/.arxa/dsh/.env` all absent), and `ZAI_API_KEY` is not exported in the shell.
`dsh-app-boot/lib/index.js:733` (`loadLayeredEnv`) only injects values read from
`.env` layers — it does **not** read `.credentials.yaml`. So the expression
evaluates to `undefined`.

`dsh-mcp-client@0.1.1-rc.2/lib/index.js:743` declares `env: z.dict(String)`.
`undefined` is not a String, so validation fails and boot dies.

**Why the error message looks self-contradictory.** It prints "expected {...}
but got {...}" where the received object appears to satisfy the schema exactly.
That is because the received object is rendered with `JSON.stringify`, which
**drops keys whose value is `undefined`**. The offending key is invisible in the
error text. Do not trust a schemastery union error's printed value to be the
value that failed.

**This is NOT an upstream regression, and the version flip did not cause it.**
First pass said it was; that was wrong. rc.7's own mcp-client (0.1.0-rc.8) carries
the *identical* schema at the *same* line 743, `env: z.dict(String).default({})`.
The config would fail exactly the same way under rc.7. The only real cause is that
`ZAI_API_KEY` is absent from `process.env`, so the `!!js` expression yields
`undefined`. Nothing about arxa is involved.

Severity differs per expression, which is worth knowing before "fixing" them:

| line | expression | result | outcome |
|---|---|---|---|
| 22 | `process.env.ZAI_API_KEY` | `undefined` | **boot crashes** (not a String) |
| 32 | `'Bearer ' + process.env.ZAI_API_KEY` | `"Bearer undefined"` | boots, silently 401s |
| 42 | `'Bearer ' + process.env.ZAI_API_KEY` | `"Bearer undefined"` | boots, silently 401s |

Do **not** "fix" line 22 with `?? ''`. That converts a loud crash into the same
silent-401 failure as 32/42 and hides a real misconfiguration. The correct fix is
to put the key in the environment, which fixes all three at once.

## What was NOT true (recorded so it is not re-suspected)

- `mcp-zai-vision` and `vision-proxy.mjs` are the operator's own. `vision-proxy.mjs`
  is dated Aug 15; `~/.arxa` was created Aug 21 21:53. `mcp-zai-vision` appears in
  exactly one file on disk, `~/.dsh/profiles/web/cordis.patch.yml`, and nowhere in
  either repo.
- arxa did not write the vision entry, and arxa's own `cordis.patch.yml` declares
  no mcp-client entries at all (only commented examples).
- arxa shared **code**, not config. State the distinction plainly.
- `~/.dsh/.credentials.yaml` is **not** empty. A first probe anchored its pattern
  at column 0 and could not see keys nested under `refs:`. It holds `ZAI_API_KEY`
  and `DEEPSEEK_API_KEY`. Same failure shape as the `cat -A` incident: an
  instrument that cannot show presence reporting absence.
- PI has no equivalent hazard. `piHome` is unconditionally `~/.arxa/pi` with no
  fallback to `~/.pi`, and carries no `node_modules`.

## Fix

1. **Delete the fallback.** `arxa.mjs` resolves dsh only from arxa-studio's own
   `node_modules`. If absent, fail loudly telling the operator to `npm install`.
   A silent fallback that runs someone else's version is worse than not booting.
2. **Give arxa its own install** — `npm install` in `arxa-studio`, honouring the
   rc.7 pin.
3. **Rebuild `~/.arxa/dsh/profiles/node_modules`** so its links point at arxa's
   own install instead of the npx slot. Rename rather than delete, so it is
   reversible.
4. **Operator's config**: leave it alone. The expression is correct; the
   environment is empty. `dsh-app-boot/lib/index.js:733` (`loadLayeredEnv`) is the
   only env-injection site in *both* versions and it reads `.env` layers from
   DSH_HOME and cwd. So the supported fix is a `~/.dsh/.env` holding
   `ZAI_API_KEY=...`, mode 600. That is a secret value, so it is the operator's
   action and is never handled here.

## Standing rule this establishes

arxa owns `~/.arxa/{dsh,pi}` for state **and** owns its own `node_modules` for
code. Resolving an executable from a path the operator controls is an isolation
break even when nothing is written there. Reuse of an operator install must be
opt-in and explicit, never a silent fallback.

## Verified (2026-08-22)

- `arxa-studio/node_modules` installed: **433 packages, 0 links into `_npx`**.
- Resolved dsh in arxa's tree: **0.1.0-rc.7** (a real directory), matching the pin.
  Executes standalone: `node node_modules/@deepseek-ai/dsh/lib/bin.js --version`
  → `0.1.0-rc.7`, exit 0.
- `bin/arxa.mjs` no longer contains any `~/.dsh` resolution path.
- `~/.arxa/dsh/profiles/node_modules` (510 npx links) renamed to
  `node_modules.npx-poisoned-20260822`. Reversible; dsh re-links from arxa's own
  install on next boot.
- npm skipped 5 install scripts (`node-pty`, `koffi`, …). Checked rather than
  assumed: `node-pty` ships a `darwin-arm64` prebuild and `require('node-pty')`
  loads, and `koffi` is only pulled in by `dsh-sandbox-windows-acl`, which is
  Windows-only. No rebuild needed on this machine.
- `bin/isolation-check.mjs` added, 4 checks, **mutation-tested**: re-adding the
  fallback fails check 1; pointing the scanner at the poisoned backup reports all
  510 links. Restored, 4/4 pass.

PI needs no change: `piHome` is unconditionally `~/.arxa/pi`, there is no
fallback to `~/.pi`, and it carries no `node_modules` to share. `arxa.mjs:141`
does *read* `~/.dsh/.credentials.yaml` once to seed arxa's own store — a
deliberate one-time read, not a runtime coupling, and it is not a code path.

## Remaining, operator-owned

1. **Restart arxa studio.** PID 40350 has been up since ~12:30, so it loaded
   modules from the npx slot *before* npx overwrote it at 15:07 and has been
   serving a mixed rc.7/rc.2 process since. It also cannot survive the profile
   rename. Restart it to pick up the pinned tree.
2. **`ZAI_API_KEY` for the operator's own dsh.** It must reach `process.env`;
   `~/.dsh/.env` (mode 600) is the mechanism `loadLayeredEnv` supports. The value
   is a secret and was never read, printed, or copied here.

## Boot verified in the mode that matters (2026-08-22)

`--version` exiting 0 is **not** evidence the plugin tree loads — it only proves
the CLI entrypoint imports. Checked properly:

- `arxa --headless "…"` → **fails**: `plugin tree failed to load: 1 entry did not
  activate — arxa-gen-ui: pending (waiting for service: connection)`.
  Pre-existing and headless-only, unrelated to this incident:
  `plugins/gen-ui/lib/index.js:50` declares `inject = ['tools', 'connection']`,
  and `connection` is provided by `@deepseek-ai/dsh-web-app`, which headless does
  not load (`arxa.mjs` picks `[dsh-base, dsh-headless]` for `--headless`). If
  gen-ui should ever boot headless, take the service optionally via `ctx.get()`
  instead of `inject`. Not done here — out of scope.
- `arxa --port 7899` (web mode, the mode the studio runs) → **boots clean**, no
  pending entries, listening. All three plugins serve from the isolated tree:
  `arxa-gen-ui` 38081 b, `arxa-design-panel` 14344 b, `arxa-brand` 6472 b, all 200.
- Regenerated `~/.arxa/dsh/profiles/node_modules`: **413 symlinks, 0 into `_npx`**,
  411 pointing at `arxa-studio/node_modules`. Down from 510/510 npx-linked.

`--port <n>` passes through `arxa.mjs` untouched, so a second instance can be
booted for testing without disturbing the studio on 7891.

## The other `~/.dsh` edit, so it is not re-investigated

`~/.dsh/settings.yaml.pre-arxa-20260821-023953` proves an earlier session did edit
the operator's settings. Diffed: the change is **model routing only** — `baseURL`
moved to `https://api.z.ai/api/{paas,coding}/paas/v4`, plus `reasoning: max`,
`reasoningEfforts`, and `supportsReasoningEffort: true`. No plugin, profile, or
MCP entries. Unrelated to this failure. It is still an edit to the operator's
file, which the isolation rule above should have prevented.
