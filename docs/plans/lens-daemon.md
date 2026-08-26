# Lens daemon — hold one warm Chrome across CLI invocations

**Status:** BUILT and shipped (`0d1039df`, `5edba1bd`). All four phases done;
the measured result corrected this plan's own premise — see below.
**Closes:** the last open item in W1 of
[rust-port-closure-and-surgical-lens.md](rust-port-closure-and-surgical-lens.md).

## Why — and the premise was overstated

Every lens verb launches its own Chrome and kills it on exit. This plan opened
by calling launch "the single largest fixed cost in the surgical-lens loop".
**Measured after building it, that is wrong**, and the correction matters more
than the daemon does.

`lens shot https://example.com 390 300`, three runs each, macOS headless:

| path | time | what it isolates |
|---|---|---|
| `dart run`, no daemon | 3.97s | how the lens is invoked today |
| `dart run`, daemon | 3.52s | |
| `dart run … lens --help` | 1.45s | Dart JIT floor, no Chrome at all |
| compiled exe, no daemon | 2.48s | |
| compiled exe, daemon | 2.02s | |
| compiled exe `--help` | 0.01s | |

So a `dart run` invocation is roughly **1.45s Dart JIT + 0.46s Chrome launch +
~2.0s capture** — and 1.5s of that last figure is `settleForCapture`'s
deliberate minimum-wait floor.

The daemon removes the 0.46s, which is real and is what it was built for. But
**`dart compile exe` removes 1.45s — three times more, for a build step.** The
JIT floor was never measured before the daemon was scoped, so the largest fixed
cost in the loop went unnamed while the second-largest got a design document.

Neither replaces the other and they compose: compiled + daemon is 2.02s against
3.97s today, a 49% cut. The daemon is worth having; shipping a compiled binary
is worth more and is cheaper. That belongs on the roadmap ahead of any further
daemon work.

The blocking unknown for the daemon — *does a reused browser render identically
to a fresh one?* — was closed on 2026-08-21 across four arms including animated
pages: zero drift, memory flat, at depth up to 700 captures / 21m39s.

## Shape: there is no daemon process

The obvious build is a long-lived Dart server with a CLI↔daemon protocol,
liveness beats and reconnect logic. None of that is needed, because two pieces
already exist:

- `CdpClient.connect(wsUrl)` — attach to an already-running browser.
- On macOS headless, `launch()` **already detaches**: it spawns Chrome via
  `open -g -n -a` and holds no child `Process` at all (`cdp.dart:150-166`),
  recovering the pid afterwards from `_pidsOwningProfile`.

So the "daemon" is **a detached Chrome plus a state file**, and CDP-over-
WebSocket is the protocol. No supervisor, no custom wire format, no reconnect
loop — a CLI run either connects or it doesn't.

State file records: `wsUrl`, `profileDir`, `browserPid`, `startedAt`,
`shotsServed`, `visible`. Liveness = the recorded pid still owns the recorded
profile dir (scoped `_pidsOwningProfile`, **never** a prefix match) **and** the
WebSocket connects. Anything else → treat as dead, reap, relaunch.

## Prerequisite: two defects, and the first reading of them was wrong

**The claim, initially:** `connect()` comments "The Process is null — close()
won't kill it", while `close()` branches on `_chrome == null` and sends
`Browser.close` — which is exactly the connect() case. So the first CLI verb to
connect and finish would shut the shared browser down.

**What measurement said:** it does not. A mutation removing the guest guard
left the test green. `close()` set `_closed = true` as its second statement,
and `send()` throws `StateError` when `_closed`, inside a bare `catch (_) {}`.
So the graceful `Browser.close` **threw on every call and was swallowed on
every call, for as long as it had existed.** It had never once run. The
pattern-kill it was paired with is the thing recorded as "did not always land";
the pid SIGKILL added later is what actually ends the browser.

So the real defects are:

1. **A teardown step that never ran and could not report it** — the same
   family as the rest of this workstream, one layer deeper: not a check whose
   pass equals its did-not-run, but a *step* whose failure was structurally
   unobservable. Fixed by sending before the flag, with `_closing` split from
   `_closed` so reentrancy still works.
2. **Guest safety held only by accident.** With the graceful close repaired, a
   guest's `close()` genuinely does kill the host — measured at 163/163/169ms
   across three trials. `_ownsBrowser` (true from `launch()`, false from
   `connect()`) makes the property hold by construction.

The guest test needs one thing the rest of `cdp_teardown_test.dart` forbids: a
**wait**. That file is zero-grace on purpose — for "did close() finish its
job", waiting hides failures. This asserts the opposite, that something did NOT
happen, and an absence cannot be asserted without giving the thing time to
occur. The first draft had no wait, passed, and kept passing under mutation.

## Four things that bite

1. **The shared temp prefix.** `Directory.systemTemp.createTemp('arxa-cdp-')`
   means `pkill -f arxa-cdp-` kills *every* Chrome this repo started. A
   daemon holding one for hours is one stray script away from death. Reaping
   must use the scoped ownership check on the exact `--user-data-dir=<dir>`.
   A dir with no owning pid is a true orphan and safe to delete alone.

2. **Profile-dir lifetime is split.** `launch()` puts `_tmpDir` on the client
   and `close()` deletes it after `awaitProfileReleased`. The daemon's launcher
   exits while Chrome lives, so the client must **not** delete it — but
   `daemon stop` must. The dir's lifetime belongs to the state file, not to a
   client object, or the first `daemon start` leaves Chrome running against a
   deleted profile.

3. **The recycle counter must count screenshots, not captures.** The
   900–1000 threshold came from a screenshot-denominated measurement, and
   `settleForCapture` takes 4–6 shots per capture depending on the page. A
   CLI-side `captures++` undercounts by that factor and fires the policy an
   order of magnitude late. Increment by the returned `screenshots`.

4. **Render mode is baked into the launch args.** `LensSession.visible` decides
   `--headless=new` and `--window-size`. A daemon started headless cannot serve
   a `--visible` verb; connecting anyway silently returns the wrong render
   mode. The state file records the mode, and a mismatched verb bypasses the
   daemon rather than connecting to it.

Plus the standing one: **no CDP event reports full browser death** (only
`Target.targetCrashed`, for renderers). A closed socket is the only signal, and
it cannot distinguish "killed by an unrelated script" from "crashed". Design
for rebuild-on-failure and log the owned profile dir so the orphan is
attributable afterwards.

## Scope

macOS headless only — the path that already detaches. Other platforms and
`--visible` fall back to per-invocation launch with a stated reason. Widening
that is a separate decision, not a silent one.

## Phases

1. ~~`_ownsBrowser` + guest-close test~~ — `0d1039df`, and it found the
   graceful `Browser.close` had never once run.
2. ~~State file + `lens daemon start|status|stop`, scoped startup reaping~~ —
   `5edba1bd`.
3. ~~Verb integration~~ — `LensDaemon.acquire()`, 19 call sites by rename.
4. ~~Recycle on `shotsServed`~~ — counted at the CDP chokepoint, 900.

~~**Next, and it outranks more daemon work:** ship `arxa` as a compiled
binary. 1.45s per invocation, three times the daemon's saving, for a build
step.~~ — DONE in `fea797f0`: `install.sh` compiles to `.build/arxa` and
installs a `~/.local/bin/arxa` shim that rebuilds when any `.dart` source is
newer (and under `ARXA_FAST` fails/warns loudly instead of paying the compile
or running stale). Measured warm start 0.02s against the 1.45s `dart run`
floor.

Each phase leaves the CLI working with no daemon present — the fallback is the
current behaviour, so a broken daemon degrades to today rather than to nothing.
