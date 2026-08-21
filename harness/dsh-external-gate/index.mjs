/**
 * dsh-external-gate — a dsh cordis plugin that shells out to an external binary
 * for an allow/deny verdict on every tool call.
 *
 * This is the only verified way to make dsh 0.1.0-rc.7 run an external command at
 * tool-call time. rc.7 has NO Claude-Code hooks bridge: there is no PreToolUse /
 * PostToolUse anywhere in @deepseek-ai/*, and nothing in the tree spawns a
 * user-configured command.
 *
 * SEAM (verified): @deepseek-ai/dsh-tools/lib/types/index.d.ts:38
 *   'tools/pre-execute'(this: Scoped<ToolRuntime>, exec: ToolExecution,
 *                       next: () => Promise<PreToolDecision>): Promise<PreToolDecision>
 * A cordis WATERFALL — return a decision to claim the call, or call next() to
 * delegate to later gates. PreToolDecision (same file, :418-426):
 *   { kind: 'allow' } | { kind: 'deny', reason: string } | { kind: 'ask', reason?: string }
 *
 * Why not ctx.tools.guard()? That is the other registration API
 * (@deepseek-ai/dsh-tools/README.md:25) but it is documented as a MONOTONIC
 * SYNCHRONOUS guard — it cannot await a subprocess. An external binary therefore
 * has to be consulted from the async pre-execute waterfall.
 *
 * Protocol (mirrors Claude Code hooks so existing scripts port with little change):
 *   stdin  <- one JSON line: { tool_name, tool_input, call_id, session_id, cwd }
 *   exit 0            -> allow
 *   exit 2            -> deny; child's stderr becomes the model-visible reason
 *   other exit codes  -> deny (fail closed); stderr as reason
 *   stdout {"decision":"block"|"ask","reason":"..."} -> honored if emitted
 *
 * LIMITATION (verified): tools/pre-execute deliberately cannot rewrite
 * exec.arguments (@deepseek-ai/dsh-tools/README.md:193). A gate may only
 * allow / deny / ask — never edit the call.
 *
 * No import of @deepseek-ai/schemastery: config is hand-validated below so the
 * plugin has zero runtime dependencies and cannot fail to resolve one.
 */
import { spawn } from 'node:child_process'

export const name = 'external-gate'

/** Normalize and validate plugin config, throwing at mount on misconfiguration. */
function resolveConfig(config = {}) {
  const command = config.command
  if (typeof command !== 'string' || command.length === 0) {
    throw new Error('external-gate: "command" is required (absolute path to the verdict binary)')
  }
  const args = config.args ?? []
  if (!Array.isArray(args) || args.some((a) => typeof a !== 'string')) {
    throw new Error('external-gate: "args" must be a list of strings')
  }
  const tools = config.tools ?? []
  if (!Array.isArray(tools) || tools.some((t) => typeof t !== 'string')) {
    throw new Error('external-gate: "tools" must be a list of tool names')
  }
  const timeoutMs = config.timeoutMs ?? 5000
  if (typeof timeoutMs !== 'number' || !Number.isFinite(timeoutMs) || timeoutMs <= 0) {
    throw new Error('external-gate: "timeoutMs" must be a positive number')
  }
  return { command, args, tools, timeoutMs }
}

/** Run the verdict binary for one execution. Always resolves to a PreToolDecision. */
function askExternal(config, payload) {
  return new Promise((resolve) => {
    let child
    try {
      child = spawn(config.command, config.args, { stdio: ['pipe', 'pipe', 'pipe'] })
    } catch (error) {
      resolve({ kind: 'deny', reason: `external-gate: could not start ${config.command}: ${String(error)}` })
      return
    }

    let stdout = ''
    let stderr = ''
    let settled = false
    const finish = (decision) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      resolve(decision)
    }

    const timer = setTimeout(() => {
      try { child.kill('SIGKILL') } catch {}
      finish({ kind: 'deny', reason: `external-gate: ${config.command} timed out after ${String(config.timeoutMs)}ms` })
    }, config.timeoutMs)

    child.stdout.on('data', (d) => { stdout += d })
    child.stderr.on('data', (d) => { stderr += d })
    child.on('error', (e) => finish({ kind: 'deny', reason: `external-gate: ${String(e)}` }))

    child.on('close', (code) => {
      const trimmed = stdout.trim()
      if (trimmed.startsWith('{')) {
        try {
          const verdict = JSON.parse(trimmed)
          if (verdict.decision === 'block') {
            finish({ kind: 'deny', reason: verdict.reason ?? 'blocked by external-gate' })
            return
          }
          if (verdict.decision === 'ask') {
            finish({ kind: 'ask', reason: verdict.reason })
            return
          }
        } catch {
          // Not JSON after all — fall through to exit-code semantics.
        }
      }
      if (code === 0) finish({ kind: 'allow' })
      else finish({ kind: 'deny', reason: stderr.trim() || `external-gate: ${config.command} exited ${String(code)}` })
    })

    try {
      child.stdin.end(JSON.stringify(payload) + '\n')
    } catch (error) {
      finish({ kind: 'deny', reason: `external-gate: could not write payload: ${String(error)}` })
    }
  })
}

export function apply(ctx, rawConfig) {
  const config = resolveConfig(rawConfig)

  ctx.on('tools/pre-execute', async (exec, next) => {
    if (config.tools.length > 0 && !config.tools.includes(exec.name)) return next()

    // Session workspace root, when a sandbox policy is composed. process.cwd() is
    // the harness process cwd, NOT the session root, so it is not used here.
    // ctx.get() (not property access): cordis throws on ctx.<service> unless the
    // service is in `inject`, and sandboxPolicy is optional — the 2026-08-21
    // booted check crashed here with `cannot get property "sandboxPolicy"
    // without inject`.
    let cwd
    const session = exec.agent?.session
    const sandboxPolicy = typeof ctx.get === 'function' ? ctx.get('sandboxPolicy') : undefined
    if (session !== undefined && sandboxPolicy !== undefined) {
      try {
        cwd = (await sandboxPolicy.resolve({ session }))?.workspaceRoot
      } catch {
        cwd = undefined
      }
    }

    const decision = await askExternal(config, {
      tool_name: exec.name,
      tool_input: exec.arguments,
      call_id: exec.callId,
      session_id: session?.header.id,
      cwd,
    })

    // allow delegates onward so later gates and ctx.tools.guard() still run;
    // deny/ask claim the call immediately.
    return decision.kind === 'allow' ? next() : decision
  })
}
