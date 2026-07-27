# review

The REVIEW gate — a pure-Dart static analyzer (vendored from
`enforce_design.dart`, plan 03) the pipeline runs over a scaffolded app's view
files. It does NOT replace `flutter analyze` (compile/types) or `flutter run`
(perceptual checks); it catches the kit-specific slop the compiler accepts but
the design contract forbids.

Emits JSON (`--json`) which `run_all.sh` routes through `gates/_common/sarif.sh`
(one SARIF transport).

## Asserts (per `*_view.dart`)

no stock `Icons.*`, no hardcoded `Color(0x…)`/`CupertinoColors.*`/`Colors.*`
literals, no raw `dart:io`/`Platform`, the 5-file form-factor set
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
