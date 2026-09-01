# Studio mirror rig — what runs where, and how to bring it back

| piece | where | restore |
|---|---|---|
| cairn-server (mirror, bearer, silent pushes) | `127.0.0.1:8190` | `bash arxa/tool/rig/restore-mirror.sh` (reads the keystore; log `/tmp/cairn-mirror.log`) |
| cairn-pushd (APNs/FCM rails) | `127.0.0.1:8090` | supervised by the desktop Tauri shell; manual: run its binary with the `pushd.env` keystore |
| arxa-studio engine (mux + approvals + /__cairn proxy) | profile `arxa`, loopback | `bash /tmp/arxa-d68/run-engine.sh` if present, else the desktop app |
| keystore (tokens, silent tables, mirror-out gate) | `~/Library/Application Support/solutions.arxadigital.arxa/cairn-server.env` | operator-owned; never commit |
| receipts (delivery evidence) | `…/cairn-pushd.db` | `sqlite3 … 'select seq,outcome,metadata from receipts order by seq desc limit 5'` |
| phone-leg demo (raise + watch + answer) | one command | `bash /tmp/arxa-d68/phone-leg-demo.sh` (recreate from git history if /tmp was wiped) |

Sanity after restore: mirror healthz `{"replicator_driver":"live",…}`,
engine `/__arxa/cairn-sync/_stats`, and a pushd receipt row on the next ask.

The mirror runs `NoWriteBack` BY DESIGN (ADR-0042: the engine is the sole
writer; phones read). Client cache-upsert rejections are permanent
(`retryable:false` since cairn e8f4e7a) — one rejection, then the DLQ.