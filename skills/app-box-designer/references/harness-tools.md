# Harness tool map

app_box is **harness-agnostic**. This file names the *capability* you need; the
right-hand column lists the tool names commonly used for it. If your harness
names a tool differently, use its equivalent — the capability is the contract,
the tool name is not.

| Capability | Typical tool |
|---|---|
| Ask the user a question | `AskUserQuestion` |
| Run a command | `Bash` (or the harness's shell tool) |
| Show / preview a page | serve via the Runtime, hand back `http://localhost:<port>/…` |
| Screenshot a page | shell → `node <skill>/runtime/shoot.mjs <url>` |
| Read a screenshot / image | `Read` / `ReadMediaFile` — any tool that accepts an image |
| Console / DOM debug | shell (node or playwright one-off scripts) |
| Verification subagent | `Agent` / `Task` with a read-only subagent type |
| Parallel design variations | several subagent calls dispatched in one message |
| Progress tracking | the harness's todo/task tool |
| Web knowledge | `WebSearch` / `WebFetch` |
| Deliver an export | file path (+ served URL if it previews in a browser) |

**If a capability is unavailable in your harness, say so plainly rather than
silently skipping the check it backs.** A skipped verification reported as a
pass is the failure mode this whole project is built to avoid.

## Asking questions

- 1–4 questions per call; each needs 2–4 options (`label` + `description`), an
  optional short `header`, and must end with `?`. An "Other" free-text option is
  usually auto-appended — never add your own.
- Multi-select for the design-system pick (none / one / several).
- Batch the clarifying round into one call; follow up if you need more. For a
  new project expect 10+ questions across a couple of rounds.
- Clarifying rounds are blocking by nature — do not background them.

## Showing files & preview

Assume the harness has **no user-visible browser or preview pane**. Surface a
deliverable as the local file path plus the served URL; the user opens it in
their own browser.

Serve each artifact through the Runtime and reuse it for that project:

```sh
# background; skip if already running for this artifact
node <skill>/runtime/serve.mjs designs/<project> --port 4319
```

Then reference `http://localhost:4319/…` (routes come from the artifact's
`app.routes.js`). **Never open from `file://`, and never use
`python3 -m http.server` for artifacts** — htmx needs the server for Named
Fragment swaps, POSTs, and boosted navigation, so a static server silently
degrades the artifact.

## Screenshots & vision

The screenshot-verify loop is the **default** verify path, not an optional
extra. Screenshot **every width in the active ladder** (see
[`viewport-ladder.md`](viewport-ladder.md)) — widths come from config, never
hardcoded here:

```sh
# every rung in the active ladder, in one pass
node <skill>/runtime/shoot.mjs http://localhost:4319/<route> --out /tmp/shots

# a derived subset (e.g. targets: ios -> compact + medium)
node <skill>/runtime/shoot.mjs http://localhost:4319/<route> --rungs compact,medium
```

Widths come from `runtime/ladder.json`; **never pass a pixel value**. `shoot.mjs`
also fails on console errors, failed requests, 4xx/5xx and horizontal overflow —
things a screenshot alone will not show you. It exits non-zero when any rung has
a problem.

Then **read the images back**. A clean exit means nothing broke; it does not
mean the layout is good.

Inspect for layout, contrast and alignment; fix; re-shoot. Use region crops for
fine detail on dense pages.

**If the session model has no image input:** spawn one probe subagent per
session using the prompt in `agents/vision-probe-agent.md` against
`agents/assets/vision-probe.png`; the exact verdict string is `VISION_OK`. If
vision is genuinely unavailable, save screenshots to disk without reading them
back, verify via text/DOM checks only (`innerText`, element counts,
`getBoundingClientRect` through a node/playwright one-off), and **say plainly
that visual review was skipped**.

## Verification & debug

- **No-JS lint:** `node <skill>/runtime/lint.mjs <artifact-dir>` — the
  zero-custom-client-JS check (ADR-0002). Must pass before surfacing.
- **Console errors:** `node <skill>/runtime/console-check.mjs
  http://localhost:4319/<route>` loads pages headless and fails on any console
  error or pageerror. Check for zero page errors before surfacing.
- **Structure:** `node <skill>/selftest.sh`-style checks — the registry parses,
  every viewmodel declares a `surfaceId`, `tabRoots` is non-empty. See
  [`app-architecture.md`](app-architecture.md).
- **Thorough or directed checks:** spawn the read-only verification subagent
  with the prompt in `agents/fork-verifier-agent.md`. Its verdict is
  `done` / `needs_work` only and it never edits.
- **Design-system checking:** run the `agents/check-design-system.mjs` CLI, or
  spawn the `agents/design-system-checker.md` subagent read-only.

## Parallel variations

For "show me 3 directions" exploration: dispatch one subagent per direction in a
**single message** so they run in parallel. Each gets the same spec and design
context, works independently, and must not see the others' output — that is what
keeps the directions divergent. Present the results side-by-side;
`starter-partials/artboards.html` artboards in one document beat N loose files.

## Ejecting an artifact

To ship or share an artifact, eject it into a self-contained Hono app:
`node <skill>/runtime/eject.mjs <artifact-dir> <out-dir>` — see
`built-in-skills/productionize.md`. Delivery = the output directory path.

## Operating notes

- **Reasoning effort:** high fits design work; max is worth it for a full-brief
  hi-fi direction pass. Keep one effort level per session — switching
  mid-session invalidates the prompt cache.
- **Long context:** read `system-prompt.md` and any bound design system's
  `_ds_prompt.md` **fully**. Don't skim to save tokens — the craft rules are the
  product.
- **Vision-first:** prefer reading a real screenshot over reasoning about what
  the page "should" look like. A static read of the HTML is not verification.
- **Parallelism:** fire independent reads/searches in one message; fan
  independent design directions out to subagents instead of serializing them.
