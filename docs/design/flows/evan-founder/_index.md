# Evan (founder) — flow index

Every surface is his. 15 flows across 6 tab-group shells. Vocabulary per
[`architecture.md`](../../../plans/architecture.md); pipeline mechanics per §5–§6;
decisions per §11–§18. Flows marked ◆ depend on a surface **NEW — not yet
scaffolded** (the desktop app is hand-written v1; dogfooding starts at v2 per
§8). Journey narrative: [`journeys/evan-founder-journey.md`](../../journeys/evan-founder-journey.md).

## projects-shell

| Flow | Covers |
|---|---|
| `new-project.md` | name, brand, targets (consequence not flag); targets → pipeline state; brief seed |
| `project-list-home.md` | empty (wording) · list (pipeline phase per project) · loading |
| `showcase-first-run.md` | the dogfood — app_box shows itself; auto-launch on install |

## design-shell

| Flow | Covers |
|---|---|
| `prototype-directions.md` | 3-up directions in htmx; authored registry + surfaceId while designing |
| `approve-design.md` ◆ **(Gate 1)** | hash-bound approval; agent presents, person approves; pending · approved |
| `iterate-direction.md` | revise a direction; re-freeze; stale indicator when design moved |

## build-shell

| Flow | Covers |
|---|---|
| `run-build.md` | idle → running → green → red; stage timeline live; 💳 licence precondition before phase |
| `red-gate-recovery.md` ◆ | finding (SARIF: file/line/rule/fix); partialFingerprints; ESC_LIMIT=3 |
| `accept-build.md` ◆ **(Gate 2)** | accept the green build; reject → recovery; explicit human confirm |

## ship-shell

| Flow | Covers |
|---|---|
| `select-targets.md` | fastlane-ios/android, shorebird, cloudflare-pages; Vercel=stub (not advertised) |
| `confirm-ship.md` ◆ **(Gate 3)** | the triple: target + version + account; blast radius stated; irreversible |

## chat-shell

| Flow | Covers |
|---|---|
| `drive-pipeline.md` ◆ | idle → streaming → tool-call; MCP chat drives pipeline stages |

## settings-shell

| Flow | Covers |
|---|---|
| `configure-credentials.md` | BYO key → OS vault (tier stated); harness shell-out; write→restart→read |
| `pair-device.md` ◆ | QR pairing; TLS fingerprint; paired · revoke |
| `inspect-kits.md` | wired vs STUBBED for 23 kits; 5 partial (Stripe/PayPal/Vercel throw) |

## Cross-references

- Journey narrative: [`journeys/evan-founder-journey.md`](../../journeys/evan-founder-journey.md).
- Sibling actor: Michelle's flows at [`../michelle-buyer/_index.md`](../michelle-buyer/_index.md)
  — the same pipeline read through a legibility filter.
- CRUD operations (not per-shell flows): [`feature-crud.md`](../../../plans/feature-crud.md).
