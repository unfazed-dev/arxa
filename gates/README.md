# gates

Every gate is isolated, self-tested, and **provably able to fail** (R5). One
folder per gate; a gate never imports a sibling gate (R4).

## Shape (R4)

```
gates/<name>/
  <name>.sh | .py | .dart     reads state + files, asserts, exits 0 or 1
  selftest.sh                 happy path AND at least one NEGATIVE case
  README.md                   what it asserts, and what it deliberately does not
```

- **One folder per gate.** A gate reads state/files, asserts, and exits `0`
  (pass), `1` (FAIL) or `2` (env / not-applicable). It never calls another gate
  and never imports from a sibling gate folder. (The bash-era `_common/`
  shared layer was never built; shared logic now lives in `appboxd/lib/`.)

## The gates

The gates are Dart. Ten live in `appboxd/lib/gate_*.dart` (intake, freeze,
structure, scaffold, coverage, memory, advertise, native_deps, lens, deploy),
orchestrated by `appboxd/lib/gate_runner.dart`; the review gate is
`gates/review/review.dart`, dispatched the same way. Run them from `appboxd/`:

```sh
dart run bin/appbox.dart gate <name>   # or: appbox gate <name>
dart run bin/appbox.dart gate --all    # the full suite, in dependency order
```

Two legacy folders remain in `gates/`:

| folder | status |
|---|---|
| `freeze/` | ⚠️ SUPERSEDED bash gate — retained for reference only; it shells out to the archived designer `serve.mjs` and is silently broken. The live freeze gate is the Dart one above. See `freeze/README.md`. |
| `review/` | the design judge — pure-Dart static analyzer over the scaffolded views (`review.dart` + `selftest.sh`), invoked via `appbox gate review` |

## R5 — every gate must be able to fail

Each gate carries a self-test with at least one NEGATIVE case: plant a
specific defect, assert the gate exits `1` **and** names the offending file.
Dart gates embed theirs behind `--self-test`; the review gate keeps
`selftest.sh`. Assert regenerated output with `git status --porcelain`, never
`git diff --exit-code`.
