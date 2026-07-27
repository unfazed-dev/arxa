# gates

Every gate is isolated, self-tested, and **provably able to fail** (R5).

## Shape (R4)

```
gates/<name>/
  <name>.sh | .py | .dart     reads state + files, asserts, exits 0 or 1
  selftest.sh                happy path AND at least one negative case
  README.md                  what it asserts, and what it deliberately does not
```

- **One folder per gate.** A gate reads state and files, asserts, and exits `0`
  or `1`. It never calls another gate and never imports from a sibling gate
  folder.
- **Shared logic lives in `_common/` only.** If two gates need the same logic it
  moves to `_common/_`, not sideways between them.

## R5 — every gate must be able to fail

A gate that cannot go red for the right reason is not a gate. Each gate's
`selftest.sh` **must include a negative case**: plant the defect, assert the
gate exits `1` and names the offending file. A selftest that proves only the
happy path is rejected at review.

Assert regenerated output with `git status --porcelain`, **never**
`git diff --exit-code` — a generator that *adds* a file is the expected case and
`git diff` cannot see untracked files.

## Orchestration

`run_all.sh` (plan 04) runs each gate in dependency order, aggregates SARIF and
exits non-zero if any gate failed. It orchestrates; it contains no assertions of
its own.
