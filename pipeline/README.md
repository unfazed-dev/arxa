The FSM orchestrator — the Dart phase runner plus state/. Belongs: phase orchestration and pipeline state. Does not belong: assertions — those live in gates/.

**The orchestrator is Dart (2026-07-31, commit 4f9c458):** the
`pipeline/pipeline.sh` and `gates/run_all.sh` described here never landed in
this repo — the phase FSM is `arxa/lib/phases.dart` (+
`pipeline_fsm.dart`): intake → prototype → design → scaffold → review →
build → deploy, with the current phase tracked in
`pipeline/state/default.state.json`. `arxa/lib/engine.dart` derives the
deterministic stage runner from `gateOrder` (`arxa/lib/gate_runner.dart`).
Run one gate with `arxa gate <name>`, the full suite with
`arxa gate --all`.
