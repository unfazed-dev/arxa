# review

The REVIEW gate — a pure-Dart static analyzer (vendored from
`enforce_design.dart`, plan 03) the pipeline runs over a scaffolded app's view
files. It does NOT replace `flutter analyze` (compile/types) or `flutter run`
(perceptual checks); it catches the kit-specific slop the compiler accepts but
the design contract forbids.

Runs via `appbox gate review` → `gates/review/review.dart`, dispatched by
`appboxd/lib/gate_runner.dart` like the other gates. Emits JSON (`--json`).

## Asserts (per `*_view.dart`)

no stock `Icons.*`, no hardcoded `Color(0x…)`/`CupertinoColors.*`/`Colors.*`
literals, no raw `dart:io`/`Platform`, no hardcoded user-visible strings in
view files (`Text('…')`/`label: '…'` copy comes from the ARB catalogs via
AppLocalizations — scaffolder STRUCTURE ONLY stubs exempt), the 5-file form-factor set
(view + mobile + tablet + desktop + viewmodel) exists, `design-system.md`
present with palette + forbidden sections, no cross-shell view imports, no
ad-hoc spacing `SizedBox`, no layout-swapping in shared widgets, and the
leaf/shell app-bar contract.

## Does not assert

- Compile correctness or widget behaviour — `flutter analyze` / `flutter run`.
- Shell structure or surface coverage — scaffold/coverage's job.

## Run

```sh
dart review.dart <surface-dir-or-view-file>            # 0 pass / 1 FAIL / 2 env
dart review.dart <path> --json                          # machine-readable findings
bash review/selftest.sh                                 # R5: happy + NEGATIVE cases
```
