# harness/ — one policy, every agent CLI

The portable core's claim is that an appbox gate means the same thing no matter
which agent CLI is driving. That works because there is exactly **one** policy
file and the harnesses are thin adapters over it:

```
hooks/appbox-guard.js          ← THE policy. Claude Code hook protocol.
   ├── Claude Code   PreToolUse hook            (.claude/settings.json)
   ├── dsh           harness/dsh-external-gate  (cordis tools/pre-execute)
   └── Pi            harness/pi/appbox-gate.ts  (pi.on('tool_call'))
```

A rule added to the guard is live on all three at once. No surface can drift.

## The protocol

Every adapter feeds the guard one JSON object on stdin and reads its exit code:

| stream | contract |
|---|---|
| stdin | `{ tool_name, tool_input, call_id, session_id, cwd }` |
| exit 0 | allow |
| exit 2 | **deny** — the guard's stderr becomes the model-visible reason |
| other | adapter's choice; the dsh adapter fails **closed**, Pi fails **open** |

This is Claude Code's hook contract adopted verbatim, so existing hook scripts
port with little change.

> ### ⚠️ Exit code 2 means opposite things in the two layers
>
> | layer | `0` | `1` | `2` |
> |---|---|---|---|
> | **hook protocol** (this dir) | allow | *(caller's choice)* | **DENY** |
> | **appbox gates** (`gates.dart:19-21`) | pass | fail | **env / not-applicable** |
>
> Never wire `appbox gate <name>` directly as a `command:` verdict. A gate that
> is merely *not applicable* here exits 2, which the hook protocol reads as a
> hard **deny** — inverting the meaning. `appbox gate lens` exits 2 on this
> machine right now, so this is live, not theoretical. Always go through
> `harness/verdict.sh`, which speaks the hook protocol deliberately.

## Modes

`APPBOX_GUARD_MODE`, else `~/.appbox/guard-mode`, else `dev`:

> **Prefer the env var.** `~/.appbox/guard-mode` is machine-global, but
> "using-session vs appbox-dev session" is a *per-session* property — with
> concurrent sessions the last writer wins for all of them. The file is a
> convenience for a machine dedicated to one mode; anything else should set
> `APPBOX_GUARD_MODE` per session, which is per-session by construction.

- **`dev`** — appbox-dev session. Everything allowed. *Default*, so installing
  the guard never breaks the operator's own work.
- **`using`** — using-session. The appbox checkout is read-only **except**
  `docs/`, `designs/`, `logs/`, where findings can still be recorded.

  The scope is an **allowlist** (`WRITABLE` in `hooks/appbox-guard.js`), ratified
  2026-08-21. It replaced a nine-entry denylist of source dirs that left
  `appbox-studio/`, `deploy/`, `memory/`, `archives/` and every repo-root file
  writable — and would have admitted each future top-level dir writable by
  default. Inverted, there are no holes, and adding a fourth write target is a
  deliberate one-line change.

  Two consequences worth knowing:
  - This list is **not** the same as `appbox-doc-enforce.js`'s, and must not be
    re-synced with it. That one answers a different question ("which dirs'
    changes require a doc update") and is legitimately a denylist.
  - Because an unrecognized path now *denies*, `writeTargets()` discards shell
    candidates containing `$ \` * ? ~` — an unexpanded `> "$OUT"` was a guess,
    not a path, and under an allowlist a guess would become a false refusal.
  - Escape hatch for a legitimate one-off: `APPBOX_GUARD_MODE=dev <command>`.
- **`off`** — disabled.

## Wiring each harness

### Claude Code — already wired

`.claude/settings.json` registers the guard as a `PreToolUse` hook. Cost is
~20ms per tool call (the bare node startup floor). No action needed.

### dsh — `@deepseek-ai/dsh@0.1.0-rc.7` (pin exactly, no caret)

> **rc.7 has NO Claude-Code hooks bridge.** Verified absent from the installed
> tree: no `PreToolUse`/`PostToolUse` events anywhere, and nothing in
> `@deepseek-ai/*` spawns a user-configured command. `known-event-types.js`
> declares `hook/invoked` and `hook/result`, but that file is generated and
> nothing emits them — the subsystem exists upstream and is **not published in
> rc.7**. Do not plan against it.
>
> The seam that does exist is **`tools/pre-execute`**
> (`@deepseek-ai/dsh-tools/lib/types/index.d.ts:38`) — an async cordis waterfall
> returning `{kind:'allow'} | {kind:'deny',reason} | {kind:'ask',reason?}`.
> `ctx.tools.guard()` is the other registration API but is **synchronous**, so
> it can never await a subprocess. `permission.defaultPreset` is a declarative
> 3×2 matrix (SandboxMode × ApprovalPolicy) with no matchers and no shell-out.

```sh
# 1. install the plugin into the profile you boot
dsh plugin --profile web add /abs/path/to/app-box/harness/dsh-external-gate

# 2. add an insert row to ~/.dsh/profiles/<name>/cordis.patch.yml
- insert:
  - id: appbox-gate
    name: dsh-external-gate
    config:
      command: /abs/path/to/app-box/harness/verdict.sh
      tools: [Write, Edit, MultiEdit, Bash]   # omit to gate every tool
      timeoutMs: 5000
```

`reconcilePlugins` warns "installed as a plain dependency, not a profile layer".
That is expected — it only auto-promotes packages exporting a `dsh.bundle`, and
an insert row is what we want.

Limitation (verified): `tools/pre-execute` deliberately cannot rewrite
`exec.arguments`. Allow / deny / ask only — a gate may never edit the call.

**Skills reach dsh via `.agents/skills`, not `.claude/skills`.** dsh's skill
roots (`dsh-skill-filesystem/lib/index.js:150`, ascending precedence) are
`<root>/.dsh/skills`, `<root>/.agents/skills`, configured `customSkillDirs`,
`~/.dsh/skills`, `~/.agents/skills` — it **never scans `.claude/skills`**. Pi
scans `.pi/skills` and `.agents/skills`. The committed `.agents/skills -> skills`
symlink therefore serves both; without it dsh and Pi see zero appbox skills.
Both accept the `<name>/SKILL.md` directory form this repo uses.

**Instruction files — exclude `CLAUDE.md` on dsh.** dsh loads agent instructions
via `@deepseek-ai/dsh-agent-instructions`, whose `instructionFileCandidates`
defaults to `['AGENTS.md', 'CLAUDE.md']`. Both load in every project directory
from the project root down; byte-identical siblings dedupe, but genuinely
distinct ones **both apply**. This repo's `CLAUDE.md` is entirely context-mode
MCP routing rules for tools dsh does not have, so it should be excluded:

```yaml
# ~/.dsh/profiles/<name>/cordis.patch.yml
- id: agent-instructions
  config:
    instructionFileCandidates: [AGENTS.md]
```

The user-global file is always `$DSH_HOME/AGENTS.md` (`~/.dsh/AGENTS.md`) and is
not affected by that list.

### Pi — `@earendil-works/pi-coding-agent@0.84.2`

```sh
npm install -g @earendil-works/pi-coding-agent
mkdir -p ~/.pi/agent/extensions
ln -s /abs/path/to/app-box/harness/pi/appbox-gate.ts ~/.pi/agent/extensions/
```

Pi loads `.ts` extensions directly via jiti — no build step. Project-scoped
alternative: `<project>/.pi/extensions/`.

## Tests

```sh
node harness/dsh-external-gate/test.mjs   # real cordis kernel, real waterfall
node harness/pi/test.mjs                  # real jiti loader, real handler
./tools/portable-core-test.sh             # install.sh + wrapper + AOT binary
```

Each suite leads with a **proof-of-life** assertion — an observed *deny*, which
a no-op cannot produce. Allow-shaped assertions are indistinguishable from an
unmounted gate, so they are never the first check.

## Verified vs not

**Verified** — the guard's policy decisions; the dsh plugin registering on and
being dispatched by a real cordis `tools/pre-execute` waterfall; the Pi
extension compiling under jiti, registering on `tool_call`, and returning a
correctly-shaped `{block:true}`; fail-closed (dsh) and fail-open (Pi) paths.

**Not verified** — that a *booted* `dsh` or `pi` session routes its tool calls
through these seams end to end. Both need model credentials and would spend
tokens. To check by hand:

```sh
APPBOX_GUARD_MODE=using dsh --profile web   # then ask it to edit appboxd/lib/*.dart
APPBOX_GUARD_MODE=using pi                  # same request
```

Expect a refusal quoting the guard's reason. Until someone runs that, treat
end-to-end dispatch as **assumed**, not proven.
