The FSM orchestrator. pipeline.sh (plan 03) plus state/. Belongs: phase orchestration and pipeline state. Does not belong: assertions — those live in gates/.

**Two orchestrators, two scopes (2026-07-30):** `pipeline/pipeline.sh` is the
stacked_kit skill-constellation FSM (prototype → design → scaffold → review over
kit surfaces); it never invokes `gates/*`. `gates/run_all.sh` is the appbox gate
orchestrator (intake → … → deploy over an emitted target) and the stage order the
appboxd engine derives its registry from. Drive the one your smoke test means.
