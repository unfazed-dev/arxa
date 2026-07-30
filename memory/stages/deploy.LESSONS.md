# deploy — lessons

Appended ONLY on observed gate failure — gate-triggered writes: the trigger is
an observed event, not an inference, so a lesson cannot hallucinate a
preference (the mem0 97.8%-junk audit is what unconstrained writes produce).
Human-editable: prune stale lessons by hand. Hard cap 200 lines; on overflow
the oldest lessons are dropped (appboxd/lib/memory_curate.dart enforces).
Format: one line per lesson — "gate X failed because Y; do Z".

## Lessons
