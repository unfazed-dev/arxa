# Decision grill

## 1. Grill the decisions (ask_user_question / grill, ONE at a time)

Each question carries a recommendation + tradeoff. The decision tree, in
dependency order — every later answer depends on earlier ones:

1. **Deliverable** — what does this repo ship? (marketing site / app / ops
   tool / docs-only; determines whether gates are code gates or doc gates)
2. **Repo shape** — monorepo vs per-deliverable; if monorepo, business-domain
   top-level dirs (no `apps/` cargo-cult unless the client wants it).
3. **Stack** — for arxa-built targets: designer artifact (htmx+Dart) vs
   Flutter; for foreign stacks, whatever they use. The stack picks the gate
   commands, runner OS, and caching.
4. **Hosting & visibility** — where, and **private vs public**. Self-hosted
   runners are ONLY safe on private repos ("a stranger's PR would run
   arbitrary code on your machine" — the t3ci CI analysis, finding 03; external
   engagement notes, not a repo path). Public → GitHub-hosted,
   full stop.
5. **Runner** — self-hosted Mac (zero minutes, warm caches, real macOS;
   cost: CI queues when the machine sleeps) vs ubuntu-latest vs hybrid.
6. **Day-one gates** — lean: analyze + test + commit-convention, behind ONE
   root command (`scripts/check.sh`). Every job gets `timeout-minutes`
   and the workflow gets concurrency cancel-in-progress (the two gaps the
   t3ci analysis found in the arxa workflow). Commit convention REQUIRED
   from day one when the repo has no legacy commits — advisory only when
   measured history excuses it.
7. **Trunk & protection** — rename master→main before first push (free at 0
   commits); required checks = the real job names; `strict: true`; reviews
   only when a team exists; forbid force-push/delete.
8. **Agent letter** — AGENTS.md adapted to THIS repo (mandates = the check
   script + conventions; blast radius = real production targets);
   CLAUDE.md as pointer; file-pr/babysit-pr rewritten to this repo's check
   names; model-routing table EMPTY until the project's own audit fills it.
9. **CD timing** — defer deploy automation until a deployable artifact +
   target exist; when wired, the deploy job PREPARES and HALTS at the
   approval gate (it can never mint the token).

Record every answer in `docs/ci/decisions.md` — inside the organized
`docs/ci/` folder, created first if the repo has no `docs/` yet. The table
IS the shared understanding; confirm it before generating anything.
