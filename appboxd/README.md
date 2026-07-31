# appboxd

The appbox daemon (see `docs/plans/consolidate-one-app-plus-daemon.md`).
Pure Dart, `dart:io` only — no third-party runtime dependencies.

It will eventually: execute pipeline phases/gates, serve the web builder UI,
broker client channels, and hold credentials in the OS vault. This skeleton
does the first two at their simplest.

## Run

```sh
dart run bin/appboxd.dart            # from the repo root (or appboxd/)
dart run bin/appboxd.dart --port 9000
```

Config: `config/appbox.config.json` may carry an optional
`"daemon": { "port": 8787, "webRoot": "appbox/build/web" }` object; anything
absent falls back to port 8787 and `appbox/build/web` relative to the repo
root. The repo root is found by walking up from the cwd until
`pipeline/pipeline.sh` appears.

## Endpoints

| endpoint | method | what it does |
|---|---|---|
| `/api/health` | GET | `{"status":"ok", repoRoot, webRoot}` |
| `/api/phases` | GET | phase list (intake → deploy, per `pipeline/state/state.schema.json`) + current phase from `pipeline/state/default.state.json` |
| `/api/phases/<name>/run` | POST | runs `bash pipeline/pipeline.sh gate <name>` from the repo root; returns `{phase, exitCode, stdout, stderr}` (502 when exit code ≠ 0, 404 for unknown phase) |
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
