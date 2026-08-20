/**
 * appbox-gate.ts — Pi extension that routes every tool call through the shared
 * appbox guard (hooks/appbox-guard.js).
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
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

/** hooks/appbox-guard.js, resolved from this file's location in the checkout. */
function guardPath(): string {
  if (process.env.APPBOX_GUARD_PATH) return process.env.APPBOX_GUARD_PATH;
  // harness/pi/appbox-gate.ts -> <repo>/hooks/appbox-guard.js
  const here = dirname(fileURLToPath(import.meta.url));
  return join(here, "..", "..", "hooks", "appbox-guard.js");
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
      resolve({ blocked: false, reason: `appbox-gate: ${String(error)}` });
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
      finish({ blocked: false, reason: "appbox-gate: guard timed out" });
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
        reason: verdict.reason || "blocked by the appbox guard",
      };
    }
    // Returning nothing lets the call proceed.
    return undefined;
  });
}
