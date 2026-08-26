# arxa

The arxa daemon (see `docs/plans/consolidate-one-app-plus-daemon.md`).
Pure Dart, `dart:io` only — no third-party runtime dependencies.

It will eventually: execute pipeline phases/gates, serve the web builder UI,
broker client channels, and hold credentials in the OS vault. This skeleton
does the first two at their simplest.

## Tools first

For anything regarding arxa, use arxa's own tools before any external or
archived tooling: the `arxa` CLI (`bin/arxa.dart` — gate, crud, serve,
emit, lint, entitlement) and the **arxa lens** (`lib/lens.dart` over
`lib/cdp.dart`, the promoted probe-runner port). If a capability is missing,
extend the arxa tool — never reach back for the archived probe-runner
(`archives/tooling-pre-dart/`).

## arxa lens

The design-vs-built visual gate: golden capture + compare over headless Chrome
(CDP). Console/page errors fail the lens regardless of pixel match.

```sh
dart run tool/lens_shot.dart <url> <out.png> [width] [height] [settleMs]
```

Library API: `captureGolden` (save a golden), `compareGolden` (byte/pixel vs
golden; ssim planned), `runLensGate` (multi-surface). The `arxa lens` CLI
subcommand is wired as future work in `bin/arxa.dart`.

## Run

```sh
dart run bin/arxad.dart            # from the repo root (or arxa/)
dart run bin/arxad.dart --port 9000
```

Config: `config/arxa.config.json` may carry an optional
`"daemon": { "port": 8787, "webRoot": "arxa/build/web" }` object; anything
absent falls back to port 8787 and `arxa/build/web` relative to the repo
root. The repo root is found by walking up from the cwd until
`config/arxa.config.json` appears.

## Endpoints

| endpoint | method | what it does |
|---|---|---|
| `/api/health` | GET | `{"status":"ok", repoRoot, webRoot}` |
| `/api/phases` | GET | phase list (intake → deploy, per `pipeline/state/state.schema.json`) + current phase from `pipeline/state/default.state.json` |
| `/api/phases/<name>/run` | POST | runs the Dart gate runner from the repo root; returns `{phase, exitCode, stdout, stderr}` (502 when exit code ≠ 0, 404 for unknown phase) |
| `/<path>` | GET | static file from the web root; `index.html` for directories; path traversal outside the web root is refused (403) |

## Deliberately NOT in the skeleton (later releases per the plan)

- Client channel broker (pairing, sessions, nonce lifecycle) — comes with the
  companion security-module mining (49 tests pinned).
- OS vault credential storage.
- Tailnet / remote access (headscale self-host, mesh CA) — R2.
- Streaming phase output (SSE/WebSocket) — runs are captured whole and
  returned on completion.
- Auth — the daemon binds to loopback only; approvals/auth arrive with the
  channel broker.
