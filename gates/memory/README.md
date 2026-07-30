# gates/memory

The MEMORY hygiene gate: asserts the curated memory layer (`memory/` at the
repo root) stays consumable. Memory rots unless a gate consumes it
(`docs/plans/appbox-memory-and-payment.md`, M1) — this is that gate.

Checks:

1. **index** — `memory/MEMORY.md` exists, ≤100 lines.
2. **facts** — every `memory/facts/*.json` parses as an array of
   `{fact, source, ts}`.
3. **lessons** — every `memory/stages/*.LESSONS.md` ≤200 lines (the write-side
   cap lives in `appboxd/lib/memory_curate.dart`; this catches hand edits).
4. **abspath** — no forbidden absolute-path prefix
   (`config/forbidden_abs_prefixes.txt`, R3) anywhere under `memory/`.

Unlike the artifact gates this one takes the **repo root**, not an app root —
the curated layer documents the pipeline itself.

Usage: `memory.sh [--self-test] [repo-root]` — 0 pass / 1 FAIL / 2 env.
`selftest.sh` delegates to the embedded suite (R5).
