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

## Modes

`APPBOX_GUARD_MODE`, else `~/.appbox/guard-mode`, else `dev`:

- **`dev`** — appbox-dev session. Everything allowed. *Default*, so installing
  the guard never breaks the operator's own work.
- **`using`** — using-session. Writes into the appbox checkout's source dirs are
  denied (`appboxd kit pipeline gates tools skills config hooks harness`).
  `docs/`, `designs/`, `logs/` stay writable so findings can still be recorded.
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
