# Assembly, verify, and score

## Assembly format

`moodboard/boards/<slice-slug>.md`:

```markdown
# Moodboard — {{epic}}

## <Reference name> — <URL>
![<screen>](shots/<slice-slug>/<ref>__<screen>.png)
- Steal: <pattern> — <why it fits the stories>
- Grade: 🔥/🌡️/❄️

…
## Patterns this slice must have
1. …  (top-10, each traceable to a reference above)
```

## Verify (runnable)

```bash
# every embedded shot resolves (run from the app dir)
grep -o 'shots/[^)]*' moodboard/boards/*.md | while read -r p; do
  [ -f "moodboard/$p" ] || echo "MISSING: $p"
done
```

Zero MISSING lines = pass.

## Score (the selection seam — do not skip)

Every reference is scored **0–5 per criterion** against the INTAKE-derived
rubric. This is where intake feeds moodboarding: the rubric comes from the
answers, never from taste alone.

Derive the criteria from `intake/answers.json` + `intake/direction.json`:

- each **direction adjective** → a criterion (weight 1); an adjective that
  names a concrete visual requirement — motion, 3D, animation, video — is
  **`locked: true`** and weight 3 (founder-signed, non-negotiable downstream);
- the **layoutTemplate** answer → a criterion (weight 2);
- each **avoid** → scored inverted (a reference embodying an avoid scores 0
  on the adjective it cheapens).

Each gathering/scoring subagent scores its slice's references and records
`scores` + a one-line `why` per reference. Judgment is the subagent's;
arithmetic and gates are the CLI's (`appbox moodboard check` recomputes
weighted totals — Σ(score×weight)/Σweight — and refuses lies).

**Locked criteria are scored on proof, not recall.** A score ≥ 3 on a
`locked` criterion must cite lens evidence naming that criterion on the
reference's `evidence` list — two settle-state captures that differ, burst
frames, or a recorded probe — with files under `moodboard/evidence/…`. A
reference you cannot capture or measure (login-gated, gone, unreachable)
scores ≤ 2 on the lock: still selectable for its patterns, but it cannot be
what feeds a founder-signed requirement. Weight-1 adjectives stay judgment.
`appbox moodboard check` enforces this on new-style records (suitors
recorded); memory alone never feeds a lock.
