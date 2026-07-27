# 07 — Feature CRUD and the delete gap

**Goal.** Features can be added, renamed and removed with no orphans, and one
test proves it.

**Blocks:** 14. **Depends on:** 04. **Runs parallel to 05 and 06.**

Contract: [`../feature-crud.md`](../feature-crud.md). Decision: §18.

## The gap

**The pipeline only writes.** The coverage gate catches a surface claimed by no
screen. It does **not** catch the reverse — a scaffolded view directory whose
registry entry is gone. That orphan compiles, passes, and ships.

## Steps

- [ ] **7.1** Add the **orphan assertion** to `gates/coverage/`, symmetrical
      with the existing check: a directory under `lib/ui/views/<shell>/` mapping
      to no registry entry is a **FAIL**, naming the directory and the missing
      id. Assert with `git status --porcelain`.
      _(OUT OF FENCE for plan 07: `gates/` is owned by P04/P05. The authored-layer
      orphan assertion — a view pair whose `surfaceId` maps to no registry entry —
      is implemented in `tools/crud/crud.py verify`. The scaffolded-layer
      assertion over `lib/ui/views/` belongs here once P05 derives
      `structure.json` from the registry.)_
- [x] **7.2** Make `id` a **stable key**. Add a registry validation: an `id` may
      never be reused for a different surface. Reusing one silently re-points
      every generated artifact that referenced it.
      _(delivered in `tools/crud/crud.py`: duplicate-id create is rejected; an
      entry's `surface` is immutable via `update`; rename requires a fresh id.)_
- [x] **7.3** Implement rename as **new id + explicit migration entry**, not an
      in-place edit. The migration entry is what lets the delete path know which
      scaffolded directory is now stale.
      _(delivered: rename appends to `migrations.json` {from→to}; old pair removed
      only after the new one exists.)_
- [x] **7.4** Add the **delete path** to the fixer. It is the one fixer
      operation behind a **human confirm** — removing code is not recoverable by
      re-running a stage.
      _(delivered: `delete --id --confirm TOK` refuses without a non-empty token.)_
- [x] **7.5** Constrain the delete implementation by two prior failures:
      - **Never delete before the replacement exists.** A fixer that deleted
        first once left a project with no service locator at all.
      - **Guard idempotence on the desired end state**, never on "was this
        touched" — and explicitly delete paths that *older revisions* emitted,
        or renames leave debris the orphan assertion then flags forever.
      _(delivered: rename writes new before removing old; delete converges on the
      end state regardless of starting point, sweeps orphan pairs, and prunes
      stale migrations whose `to` is no longer live.)_
- [x] **7.6** Keep `surface: null` meaning **declared exclusion**, distinct from
      deletion. The entry stays in the registry and is deliberately not frozen.
      _(delivered: `--surface null` creates an entry with no pair, tagged
      `[exclude]` by `list`; delete removes it cleanly.)_
- [x] **7.7** Route every CRUD surface — GUI, chat, companion, designer —
      through one write path into the authored layer. **Nothing writes
      `structure.json` or `lib/**`.**
      _(delivered: `tools/crud/crud.py` is the one write path; the selftest guards
      that no op ever creates `structure.json` or `lib/`.)_

## The test that is the whole contract

- [x] **7.8** Implement the round-trip test:

      > Create a feature, delete it, regenerate. The tree must be
      > **byte-identical** to before the create.

      It needs no fixtures and catches orphans, stale renames and partial
      deletes in a single assertion.
      _(delivered in `tools/crud/selftest.sh`: create→delete asserted with
      `git status --porcelain -uall` + an empty-dir check inside a temp repo;
      the rename round-trip and every negative case are in the same suite.)_

## Done-when

1. Round-trip test passes.
2. Deleting a registry entry **without** running the fixer makes
   `gates/coverage/` fail, naming the orphaned directory.
3. Reusing an `id` fails validation.
4. Rename produces no debris — assert by round-tripping a rename too.
5. The delete path refuses to run unattended: with no confirmation token it
   exits non-zero and changes nothing.
6. Simulated crash **mid-delete** leaves a tree the next run repairs — prove it,
   because the never-delete-before-write rule exists precisely for this case.
