# deploy

The DEPLOY gate (plan 11 stub). Asserts the three deployment prerequisites are
confirmed in pipeline state before a target ships — the build **target**, the
release **version**, and the releasing **account**. Plan 11 owns the release
mechanics; this gate owns the confirmation contract, so the pipeline cannot ship
a build whose target/version/account is unset.

## Licence precondition (decision 11, amends architecture §17)

The paywall sits at **first deploy** — design, prototype, build, gates and
preview are all free; you pay when you ship. `licence.sh` runs BEFORE the gate
and halts the deploy unless a licence is confirmed, printing what is missing
and how to activate — a named precondition, never a red gate discovered
mid-deploy. Licence state is config/env only (the check, not the store; no
payment provider integration):

- `APPBOX_LICENCE_KEY` set to a non-empty value, or
- `"licence": { "key": "<non-empty>" }` in `config/app-box.config.json`
  (`APPBOX_CONFIG` overrides the path).

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
licence.sh                                # 0 licensed / 1 NOT LICENSED (prints how to activate)
deploy.sh                                 # 0 pass / 1 FAIL (2 env) — licence precondition first
APPBOX_STATE=pipeline/state/run.state.json deploy.sh
bash deploy/selftest.sh                   # R5: happy + NEGATIVE cases (incl. unlicensed halt)
```
