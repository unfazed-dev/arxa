---
name: appbox-lint
description: Use to health-check the appbox knowledge base — catch contradictions, stale claims, dead links, orphan pages, and docs that disagree with shipped code/catalogs. Run before a session handoff, after a behavior change, or on "lint the docs", "check knowledge consistency", "is the wiki still true?". Pairs with skills/refresh (which keeps one catalog current).
---

# appbox-lint — keep the knowledge base honest

## Core principle

The expensive failure isn't a missing doc — it's a **confidently wrong** one. This session a
single un-caught contradiction ("play button must be `lite`") propagated into `memory`, `HANDOFF`,
and `changelog (g)` while contradicting the catalog's own leaf=native rule, and cost a round-trip.
Lint exists to catch that class of rot. It has two halves: a **mechanical** pass (a script, cheap,
deterministic) and a **semantic** pass (you, reading — judgment the script can't do). Run both.

See `docs/KNOWLEDGE.md` for the source-of-truth hierarchy this skill enforces.

## Procedure

1. **Mechanical pass.** `appbox docs`
   - Flags: docs missing from `docs/index.md`, dead `.md` links, orphan pages, half-wired
     supersede pointers, unresolved memory `[[wikilinks]]`. Exit 1 = at least one ERROR.
   - Fix ERRORs before continuing (usually: add the page to `index.md`, or fix the link).
   - (`appbox docs` is the Dart port of `lint_kb.py` — it folds the KB-lint orphans/supersede/
     wikilink warnings on top of the dead-link + index-coverage contract. The synthetic-fixture
     `--self-test` did not carry over; the live `appbox docs` run against the real tree is the
     check.)

2. **Semantic pass — the part that matters.** For each topic touched recently (read the last few
   `changelog.md` entries; `grep "^## " docs/changelog.md | head`), cross-check the claim across
   **all four layers** and find disagreement:
   - `catalogs/*.json` (ENFORCED runtime truth) ↔ `docs/` (prose) ↔ `memory/` (cross-session
     facts) ↔ the relevant **code comment** (e.g. `stages/blueprint.py`).
   - Ask: does any layer state a rule that a higher layer (or the shipped code) contradicts?

3. **Resolve per the hierarchy** (`KNOWLEDGE.md`): the LOWER layer is the bug. Fix the doc/memory to
   match the catalog/code — never the reverse, unless you've primary-source-verified the catalog is
   itself wrong (then use `skills/refresh`).

4. **Record it.** Append a `changelog.md` entry (`## YYYY-MM-DD (x) — lint: …`). When a claim is
   superseded, leave a one-line `⚠️ SUPERSEDED by (y)` pointer on the old entry and write the new
   one — **append-only; never rewrite history.**

5. **Suggest follow-ups.** Note gaps the lint can't fix: a concept mentioned everywhere but lacking
   a page, a plan whose done/active status is unverified, a catalog that may be stale (→ `refresh`).

## Common mistakes

- **Trusting memory or a doc over a catalog/code.** Catalogs enforce; prose lags. On conflict the
  prose is wrong. (The play-button bug was exactly this — memory/changelog vs the catalog.)
- **Rewriting the changelog.** It's the append-only log. Supersede with a pointer + new entry.
- **Fixing only the file you noticed.** A wrong claim usually lives in 2–3 places (docs + memory +
  changelog). Grep the assertion across all layers and fix every copy.
- **Skipping the semantic pass** because the script went green. The script checks plumbing, not
  truth. A perfectly-linked, fully-indexed wiki can still be confidently wrong.
- **Letting the check rot.** If you change `appboxd/lib/docs_lint.dart`, keep `appbox docs` green
  against the real repo tree — there is no synthetic `--self-test` in the Dart port; the live run
  is the regression check.
