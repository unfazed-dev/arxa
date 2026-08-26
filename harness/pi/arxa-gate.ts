/**
 * arxa-gate.ts — Pi extension that routes every tool call through the shared
 * arxa guard (hooks/arxa-guard.js).
 *
 * Pi has no shell hooks; it has in-process TypeScript extensions, which are
 * strictly stronger — a `tool_call` handler can veto the call by RETURNING a
 * decision object (not by throwing).
 *
 * Verified API (packages/coding-agent/docs/extensions.md):
 *   default export: (pi: ExtensionAPI) => void
 *   pi.on("tool_call", async (event, ctx) => ...)
 *   event: { toolName, toolCallId, input }   // input is mutable
 *   return { block: true, reason?: string, terminate?: boolean } to veto
 * Fires after tool_execution_start and before the tool actually executes.
 *
 * Install: copy or symlink into ~/.pi/agent/extensions/ (global) or
 * <project>/.pi/extensions/ (project). Pi loads .ts directly via jiti — no
 * build step, no bundler.
 *
 * The guard is spawned as a subprocess rather than reimplemented here on
 * purpose: one policy file serves Claude Code, dsh and Pi, so a rule can never
 * mean three different things on three surfaces.
 */
import { spawn } from "node:child_process";
import { existsSync, realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

/** hooks/arxa-guard.js, resolved from this file's location in the checkout. */
function guardPath(): string {
  if (process.env.ARXA_GUARD_PATH) return process.env.ARXA_GUARD_PATH;
  // harness/pi/arxa-gate.ts -> <repo>/hooks/arxa-guard.js
  // realpath, NOT the raw URL: the install method is a symlink into
  // ~/.arxa/pi/extensions (or ~/.pi/agent/extensions), and jiti reports the
  // symlink's path — the 2026-08-21 booted Pi check silently ALLOWED a
  // protected write because the guard was sought under the extensions dir,
  // not found, and the fail-open design swallowed it.
  const here = dirname(realpathSync(fileURLToPath(import.meta.url)));
  return join(here, "..", "..", "hooks", "arxa-guard.js");
}

interface GuardVerdict {
  blocked: boolean;
  reason: string;
}

function askGuard(payload: unknown, timeoutMs = 5000): Promise<GuardVerdict> {
  return new Promise((resolve) => {
    let child;
    try {
      child = spawn(process.execPath, [guardPath()], {
        stdio: ["pipe", "pipe", "pipe"],
      });
    } catch (error) {
      // Cannot start the guard: fail OPEN. A guard that cannot run must not
      // wedge the operator's session — the Stop-level gates remain the backstop.
      resolve({ blocked: false, reason: `arxa-gate: ${String(error)}` });
      return;
    }

    let stderr = "";
    let settled = false;
    const finish = (v: GuardVerdict) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(v);
    };

    const timer = setTimeout(() => {
      try { child.kill("SIGKILL"); } catch { /* already gone */ }
      finish({ blocked: false, reason: "arxa-gate: guard timed out" });
    }, timeoutMs);

    child.stderr.on("data", (d) => { stderr += String(d); });
    child.on("error", (e) => finish({ blocked: false, reason: String(e) }));
    // Exit 2 is the deny signal (Claude Code's hook convention, adopted by the
    // guard). Every other code — including crashes — fails open by design.
    child.on("close", (code) => {
      finish({ blocked: code === 2, reason: stderr.trim() });
    });

    try {
      child.stdin.end(JSON.stringify(payload) + "\n");
    } catch (error) {
      finish({ blocked: false, reason: String(error) });
    }
  });
}

export default function (pi: any) {
  // Fail-open is deliberate (a broken guard must not wedge a session), but it
  // must never be SILENT — announce an unreachable guard at load time.
  const gp = guardPath();
  if (!existsSync(gp)) {
    console.error(`arxa-gate: guard not found at ${gp} — gate INACTIVE (fail-open)`);
  }
  pi.on("tool_call", async (event: any) => {
    const verdict = await askGuard({
      tool_name: event.toolName,
      tool_input: event.input,
      call_id: event.toolCallId,
      cwd: process.cwd(),
    });
    if (verdict.blocked) {
      return {
        block: true,
        reason: verdict.reason || "blocked by the arxa guard",
      };
    }
    // Returning nothing lets the call proceed.
    return undefined;
  });
}
