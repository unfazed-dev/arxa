# deploy

The DEPLOY gate (plan 11 stub). Asserts the three deployment prerequisites are
confirmed in pipeline state before a target ships — the build **target**, the
release **version**, and the releasing **account**. Plan 11 owns the release
mechanics; this gate owns the confirmation contract, so the pipeline cannot ship
a build whose target/version/account is unset.

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
deploy.sh                                 # 0 pass / 1 FAIL (2 env)
APPBOX_STATE=pipeline/state/run.state.json deploy.sh
bash deploy/selftest.sh                   # R5: happy + NEGATIVE cases
```
