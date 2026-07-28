# Drive pipeline — MCP chat

Actor: Evan (founder, operator mode) · Shell: chat-shell · Surfaces:
`chat.home` → `stage_shell_chat_home_view` (idle · streaming · tool-call) ·
Decision refs: architecture.md §7 (LLM surface — hybrid), §15 (companion —
remote control), §11 (targets), §18 (CRUD writes registry, not code)

## Trigger

Evan opens the chat tab to drive the pipeline in natural language — start a
build, check status, request a design iteration, CRUD a feature. Or: resumes a
prior turn from the session transcript.

## Entry / exit

- Entry criteria: a project exists in state (targets set per §11); an LLM mode
  is configured — `harness` by default for Evan (in-session CLI, no key needed),
  `api` if a buyer key is in the OS vault, `none` for deterministic-only.
- Exit states: **completed** — command finished, pipeline state in `work/`
  updated, the relevant surface reflects the change · **rejected** — the turn
  resolved to a typed error (shown in the transcript, never silent) · **gated**
  — the action reached a human gate and the agent stopped to present (Gate 1
  approve / Gate 2 accept); the chat cannot mint the approval token (§12, §17).

## Happy path

1. `chat.home` is **idle**. The input box awaits; the transcript renders prior
   turns from the session log — not from painted state.
2. Evan types a command: "build the project", "what's the build status?",
   "iterate the dashboard toward a denser layout", "add a settings row".
3. `chat.home` enters **streaming**. The LLM processes the turn; tokens stream
   as they arrive. In `harness` mode this shells out to the in-session CLI
   (`claude`, `kimi`, …) — credential-free (§7, §15).
4. The LLM emits a tool-call against the pipeline's MCP stage interface —
   `pipeline.run(stage=build)`, `pipeline.status()`, `design.iterate(…)`,
   registry CRUD. `chat.home` enters **tool-call**, showing the **target stage
   name** and live progress read from `work/history.jsonl`.
5. The stage executes; its result returns to the LLM, which summarises.
   `chat.home` returns to **idle**. The relevant surface reflects the change
   (build view green/red; design view shows the new direction).
6. Where the action reaches a human gate, the agent stops and presents: a
   design iteration → **(Gate 1)** approve; a completed build → **(Gate 2)**
   accept. Approval is minted by the person, never the agent (§12, §17).

## Decision points

- **harness vs api vs none (§7):** `harness` shells out to the in-session CLI
  — Evan's path, no API key, no token stored (§15). `api` calls direct with the
  buyer's own key from the OS vault. `none` runs deterministic stages only; LLM
  stages are marked `blocked`. The mode is selected per run, not per message.
- **tool-call success vs failure:** success → result returned, idle; failure →
  typed error in the transcript, never silent. The LLM may retry an authored
  stage within `ESC_LIMIT=3`; deterministic stages never self-loop (§6).
- **mutation vs query:** reads (`pipeline.status()`, registry reads) write no
  state; mutations (`run`, `iterate`, CRUD) route through the same stage
  interface and write `work/` + `registry.json`, never the scaffolded code
  (§18).

## Edge cases

- **LLM stage fails:** typed error surfaced in the transcript; the stage is
  marked `failed` in `work/run.json`. Never silent, never a crash to the shell.
- **`none` mode:** deterministic stages run; LLM stages marked `blocked`. The
  fraction producible under `none` is the run's **determinism score** (§7) — a
  measurement, not degradation. Chat commands targeting an LLM stage return
  `blocked` with that score attached.
- **Session expired mid-tool-call:** the MCP session's auth (api-mode token, or
  the harness session) dropped while a mutation was in flight. In-flight
  mutations fail typed; `work/` is the recovery point — a re-run is
  content-hashed and idempotent (§6).
- **Companion-initiated (§15):** the same MCP stage interface is reachable from
  the paired companion over HTTP. Both writers go through `work/`, so there is
  no divergent state — the desktop chat is not the sole writer.
- **Red gate from a chat-launched build:** route to
  `../build-shell/red-gate-recovery.md`; the SARIF finding is linked in the
  transcript (file/line/rule/fix).
- **Offline:** `harness` mode needs the local CLI present; `api` mode needs the
  network. A missing harness CLI blocks with a clear message, not a silent
  failure; `none` mode is unaffected (deterministic, no network).

## Screens

| Step | Surface / sheet / dialog |
|---|---|
| 1–3 | `stage_shell_chat_home_view` — idle → streaming (tokens, harness shell-out) |
| 4 | `stage_shell_chat_home_view` — tool-call (target stage name + progress) |
| 5 | `stage_shell_chat_home_view` — idle; relevant surface updated (build view, design view) |
| 6 | Gate surface: `stage_shell_design_approve_view` **(Gate 1)** / `stage_shell_build_accept_view` **(Gate 2)** |

## Notes

- The chat is one of three surfaces that write targets to state — **GUI,
  skill, CLI** (§11); all three write `registry.json`, never scaffolded Dart
  (§18). The chat is the CLI/MCP writer.
- Transports: **stdio** (local harness shell-out, credential-free) and **HTTP**
  (remote / companion-paired per §15). One stage interface behind both, so a
  chat command and a companion command are the same write.
- MEM-A feeds prior failure notes into the LLM's error context (§4).
- Sibling flows: `../build-shell/run-build.md` (the build a chat command
  launches), `../settings-shell/configure-credentials.md` (key / harness
  selection, OS-vault tier stated).
- Michelle has no chat-shell counterpart — the chat is Evan's operator surface;
  Michelle reads pipeline output through legibility-filtered views, never
  drives it.
