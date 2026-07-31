# deploy

The DEPLOY gate (plan 11 stub). Asserts the three deployment prerequisites are
confirmed in pipeline state before a target ships — the build **target**, the
release **version**, and the releasing **account**. Plan 11 owns the release
mechanics; this gate owns the confirmation contract, so the pipeline cannot ship
a build whose target/version/account is unset.

## §17 licence assertion (P1: the deploy gate enforces the licence)

The paywall sits at **first deploy** — design, prototype, build, gates and
preview are all free; you pay when you ship. `licence_assert.sh` runs as the
gate's **FIRST** check and **fails closed**: it delegates to appboxd's
licence_tool (`cd appboxd && dart run bin/licence_tool.dart status` →
`{"status":"paid"|"free"|"none",...}` on stdout, exit 0 for paid). No paid
verdict → gate RED with a purchase message; tool missing or unparseable → RED
naming the reason (a paywall that fails open is the vacuous-PASS trap). A
named precondition, never a red gate discovered mid-deploy.

- **Dev/dogfood escape:** `APPBOX_DEV_LICENCE=1` bypasses the assertion with a
  loud stderr warning — exists so this repo's own pipeline can dogfood without
  a real licence. Never ship with it set.
- **Memory event (M1):** every run appends one JSON line to
  `pipeline/state/memory/events.jsonl`
  (`{ts, kind:"gate_run", actor:"deploy-gate", payload:{verdict,
  licence_status}}`) — best-effort; a logging failure warns, never blocks.
  `APPBOX_MEMORY_EVENTS` overrides the path (tests).
- Test seam: `APPBOX_APPBOXD_DIR` points the assertion at a fixture appboxd.

Reads state through `gates/_common/state_reader.sh` (`APPBOX_STATE` selects the
file; defaults to `pipeline/state/run.state.json` then `default.state.json`).
Findings route through `gates/_common/sarif.sh`.

## Asserts

- **target** — `state.targets` is a non-empty list.
- **version** — `approvalTokens.deploy.version` is set.
- **account** — `approvalTokens.deploy.account` is set.

## Does not assert

- Signing, notarisation, or store upload — plan 11's mechanics.
- That the build compiles — earlier gates.

## Run

```sh
licence_assert.sh                         # 0 paid / 1 NOT PAID (fail closed; APPBOX_DEV_LICENCE=1 bypasses, loudly)
deploy.sh                                 # 0 pass / 1 FAIL (2 env) — §17 licence assertion first
APPBOX_STATE=pipeline/state/run.state.json deploy.sh
bash deploy/selftest.sh                   # R5: happy + NEGATIVE cases (incl. unlicensed halt)
bash deploy/licence_assert.selftest.sh    # R5: paid/free/none/tool-missing/unparseable/dev-bypass + memory events
```
