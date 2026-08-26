# appbox-guard findings — 2026-08-26

**Status: DOCUMENTED ONLY — no guard changes applied** (this session is a
using-session; `hooks/` is engine). Both findings observed live in a booted
session on 2026-08-26 while attempting a one-line comment append to
`appboxd/lib/cdp.dart` (the append itself is deferred — see the tail of this
file). Session mode source: `APPBOX_GUARD_MODE=using` in the harness process
env; no `~/.appbox/guard-mode` file exists.

Side note: this exchange incidentally closes harness/README.md:167-184 ("Not
verified — that a *booted* dsh session routes its tool calls through these
seams end to end"). The guard fired on real `edit` and `bash` calls in a
booted session, quoting its reason both times. End-to-end dispatch on this
stack is now **observed**, not assumed.

## F1 — false refusal: `}` after `>` in a read-only command

`hooks/appbox-guard.js:L139-158` extracts shell write-targets with
`/>>?\s*([^\s;|&]+)/g`, then discards only candidates matching `/[$`*?~]/`
(L156). A `}` — and by the same argument `{`, `(`, `)` — is never a path, but
it survives the discard and resolves against `cwd` to `<repoRoot>}`, whose top
segment is not in `WRITABLE`, so `isProtected()` returns true and a purely
read-only command is denied.

Reproduced: a diagnostic call whose command string contained
`echo "APPBOX_GUARD_MODE=${APPBOX_GUARD_MODE:-<unset>}"` was denied with
`blocked write: <repoRoot>}`. The `>` closing `<unset>` followed by `}` is the
bogus candidate.

Suggested fix (one line): extend the discard class to brace/paren characters,
e.g. `if (/[$`*?~{}()]/.test(cand)) continue;` — same rationale as the
existing discard (a candidate carrying those was a guess, not a path), and
`writeTargets()` already documents that guesses must not become refusals
(L152-155).

## F2 — the denial's override line cannot work from inside a session

The denial text (L71) and harness/README.md:72 both offer
`APPBOX_GUARD_MODE=dev <command>` as the escape hatch for a legitimate
one-off. Mechanically that only exists at **session-launch** time:
`resolveMode()` (L97-106) reads the guard process's own env, and the guard is
spawned by `harness/dsh-external-gate/index.mjs:L66` with no `env` option —
it inherits the harness process env fixed at boot. A command-level prefix
sets the variable only inside the command's shell, which runs *after* the
pre-execute verdict, so the guard never sees it.

Reproduced: `APPBOX_GUARD_MODE=dev printf '…' >> appboxd/lib/cdp.dart` was
denied in a `using` session. An agent that trusts the denial's last line
burns one deterministic-failure retry per blocked write (this session did).

Suggested fix: reword the denial's last line to name the real override, e.g.
`Override: relaunch this session with APPBOX_GUARD_MODE=dev, or apply the
write yourself outside the session.` No guard-logic change needed.

## The deferred edit

Requested: append a one-line comment to `appboxd/lib/cdp.dart`. The file was
clean at HEAD when the attempt was made. Ready to apply from an appbox-dev
session or the operator's own shell (the guard polices agent tool calls, not
the operator's terminal):

```sh
printf '\n// End of cdp.dart — substrate for the lens visual gate and the DOM extraction emitters.\n' >> appboxd/lib/cdp.dart
```

Wording paraphrases the file's own header (cdp.dart:L3-5); substitute freely.
