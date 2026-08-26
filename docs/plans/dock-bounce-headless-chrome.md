# Dock bounce from headless Chrome — investigation

**Status: NOT REPRODUCED in headless.** 60 launches across every launcher arxa
has, zero bounces. `--visible` *does* bounce — measured at 780ms — so the
question for the reporter is whether that flag was in play. Three unrelated real
defects were found on the way and are recorded at the bottom. No speculative fix
was shipped, because there is nothing yet to prove a fix against.

## What a Dock bounce actually is, and how it was measured

A bounce requires a Dock **tile**; a tile requires membership in
`lsappinfo visibleProcessList`. That list is the measurement — not a person
watching the Dock, and not `lsappinfo info -only ApplicationType` sampled after
boot (the first detector did that and was worthless, because the bounce is over
before the sample lands).

Detector: `scratchpad/dock-watch.sh`, `dock-flags.sh`, `storm-clean.sh` — poll
the tile list every 20ms across the whole launch.

**Calibrated against a known-real bounce.** Chrome launched with no `--headless`
at all: **49 consecutive samples (~1s), `LSApplicationType=Foreground`**. That
number is the yardstick — a detector that has never seen a positive proves
nothing, which is the trap the first two rounds fell into.

## The three launchers, and what each passes

| launcher | file | mechanism | headless flag |
|---|---|---|---|
| lens (`CdpClient.launch`) | `cdp.dart:150` | `open -g -n -a` on macOS | `--headless=new` |
| design worker (`_ChromeHandle.launch`) | `worker.dart:608` | `Process.start` direct | `--headless=new` |
| probes | `tools/probe-*.mjs` | playwright | `--headless=new` (verified at runtime, playwright-core 1.61.1) |

All three pass `--headless=new`. **No `--headless=new` launch ever produced a
tile**, in any launcher, in any configuration tried.

## What was tried, and the count

| trial | n | real bounces |
|---|---|---|
| direct exec, synthetic flags | 15 | 0 |
| `open -g -n -a`, synthetic flags | 15 | 0 |
| direct exec, overlapping instances | 6 | 0 |
| `open -g -n -a`, overlapping instances | 6 | 0 |
| exact `worker.dart` flag set | 1 | 0 |
| exact worker flags + `--no-startup-window` | 1 | 0 |
| **real `arxa lens shot`/`dom`, clean state** | **10** | **0** |
| no `--headless` (control) | 1 | **1 — 49 samples** |

## The one apparent hit, and why it was thrown out

An early storm logged **1 sample** of a `Google_Chrome` tile. It was
contamination, on two independent grounds:

1. **Duration.** One sample ≈ 20ms. The calibrated real bounce is 49 samples
   ≈ 1s, and a user-visible bounce is ≥250ms ≈ 12 samples. A single sample is a
   registration blip or a dying process, not a bounce.
2. **Provenance.** That storm ran after the deliberately non-headless control
   Chrome, and its own leak check found **2 Chrome processes still alive**. A
   leaked foreground Chrome dying mid-storm emits exactly that artifact.

Re-run from verified-clean (asserting the tile list is Chrome-free before
starting, which is the same signal being measured — argv-sniffing got the
cleanliness check wrong twice, counting the studio's own worker and Chrome's
crashpad handler as contamination), 5 rounds: `longestRun=0` every time.

## The measurement that matters, with numbers

A second, more sensitive detector (`tools/dock-bounce-detect.sh`) polls
`lsappinfo info -only ApplicationType <our pid>` rather than the tile list, and
sees a transient `Foreground` registration the tile list misses.

| launch | Foreground samples | longest run | verdict |
|---|---|---|---|
| headless via `open -g -n -a` | 9 over 6 launches (**6/6**) | 40ms | blip |
| headless via direct `Process.start` | 2 over 6 launches (2/6) | 20ms | blip |
| real `arxa lens shot`, headless | 2 | 40ms | blip |
| **real `arxa lens shot --visible`** | **39** | **780ms** | **BOUNCES** |
| no `--headless` (control) | 49 | ~1000ms | BOUNCES |

Two things follow, and the second is the one that matters:

1. `open` **does** register Foreground more consistently than direct exec —
   every launch rather than one in three, and for twice as long. That is a real,
   measured difference and the LaunchServices mechanism is presumably why.
2. **40ms is ~6× below the ~250ms a visible bounce needs**, and 20× below the
   calibrated real bounce. So the difference, while real, does not convict
   `open` of causing a bounce. Swapping the launcher on this evidence would be
   fixing a symptom that has not been shown to produce the reported behaviour.

`--visible` is the only arxa path measured to actually bounce: **780ms**,
reproducible, and correct by design (it asks for a real window).

## Boundary of this claim — read before trusting it

**Chrome was never already running during any of these trials.** Every baseline
tile list read `Brave_Browser, Code, Finder, Terminal`. If the reporter had
Chrome open when they saw the bounce, `open -g -n -a "Google Chrome"` against an
app LaunchServices has already registered as `Foreground` is a materially
different path, and nothing here covers it. The "overlapping instances" trials
overlapped *arxa headless* Chromes, not a user's GUI Chrome.

That is the first thing to establish with the reporter.

## Hypotheses eliminated

- **`open -g` causes a visible bounce.** Not supported: 21 `open` launches, zero
  Dock tiles, max 40ms of Foreground. The blip is real; a bounce is not shown.
  The existing code comment claiming `open -g` is the *cure* is equally
  unproven — measured over 60 launches, neither launcher bounces headless.
- **Instance overlap** (`open -n` while a Chrome already lives). 6 overlapping, 0.
- **GPU/ANGLE init promoting the process** (`--use-gl=angle` etc., which only
  `worker.dart` passes). 0.
- **`LensSession.visible` leaking true.** `_isVisibleFlag` is exact-match on
  `--visible`/`--glow`/`--show` (`lens_cli.dart:162`); no URL or path can trip
  it, and it is set once per process.

## What would settle it

Two things from the reporter:

1. **Was `--visible`/`--glow`/`--show` in the command?** Those drop
   `--headless=new` by design, and a `--visible` run was **measured** at 39
   samples / **780ms** of Dock tile — a bounce anyone would see. This is the
   single most likely explanation and it is not a defect.
2. **Was Chrome already running?** See the boundary section — every trial here
   ran with no Chrome resident, and that is the one materially different
   LaunchServices path left untested.

Reproduce with the committed detector, which works with Chrome open (it scopes
to arxa's own pid):

```
tools/dock-bounce-detect.sh <the exact command you ran>
```

It prints a sample count and a verdict against the calibrated ~250ms threshold,
so the answer is a number rather than an impression.

---

# Two real defects found on the way (unrelated to the bounce — do not bundle)

## A. Worker Chrome death kills the whole server process

Reproduced on demand: SIGKILL the design worker's Chrome and the server dies
with

```
Unhandled exception:
TimeoutException: CDP command "Runtime.evaluate" timed out (30s)
  JsWorker.dispatch (worker.dart:313)
  DesignServer._dispatch (design_server.dart:530)
```

This is #51's own family and #51's fix does **not** cover it. `_isLostRealm`
matches `__dispatch is not a function`, `Execution context was destroyed` and
`Cannot find context with specified id` — a dead Chrome produces none of those,
it produces a CDP **timeout**, which is rethrown and unhandled, so the process
exits. The original #51 report ("it killed your studio earlier") is therefore
only half closed.

## B. The `open` path leaks Chrome processes

`CdpClient.launch` on macOS uses `open`, so it has no `Process` handle and
constructs `CdpClient._(null, ws)`. `close()` can then only ask Chrome to exit
over CDP, and that evidently does not always land: 2 Chromes were left resident
after a 6-launch storm. The direct-exec path has a real handle and can SIGKILL.
This is also why `sweepOrphans` exists — it is compensating for a hole this
would not have.

## C. portalo lost an `element` field during this turn — source NOT identified

Mid-investigation the real project's `intake/flows.json` changed from
`5a9426d5…` to `20929b05…`. Flow order was intact; one edge had lost
`"element": "button:Continue"` — the #29 signature (a dual-write regenerating
flows.json from answers.json and dropping the field). Restored from snapshot,
verified byte-identical.

It then drifted a **second** time, later in the same turn, and was restored
again. Both times the damage was identical: the same edge, the same lost field.

Eliminated by direct test, each measured against a checksum:

| candidate | window | result |
|---|---|---|
| plain `GET /design` | 2s | read-only |
| `arxa lens shot` | 2s | read-only |
| `arxa lens dom` | **60s** | read-only |
| `arxa lens shot --visible` | 2s | read-only |
| `design serve --project <p>` boot | 3s | read-only (tested on a copy) |
| server running, fully idle | **75s** | stable |
| `touch` a file outside the design | 4s | stable |
| `touch` a file inside the design | 5s | stable |
| rewrite a design file (real watcher event) | 6s | stable |

The 60s and 75s windows exist because the first isolation pass used a 2s window
and reported "read-only" for verbs that were then followed by drift — a window
too short to see a delayed write is indistinguishable from no write. Re-testing
with 60s did not reproduce it either, so delay alone is not the explanation.

**Source not identified.** What is now established:

- It is **not** the lens verbs, not a plain GET, not server boot, not the file
  watcher, and not idle time. The standing assumption behind #62 — "probes
  corrupt portalo" — is at minimum incomplete, and every read path is cleared.
- It **is** real, it has been observed four times across sessions, it is always
  the same signature (#29: a dual-write regenerating `flows.json` from
  `answers.json` and dropping `element`), and it is silent.

The one event in this turn not covered above is the **server crash** (defect A):
the worker Chrome was SIGKILLed and the process died with an unhandled
exception. A dual-write interrupted mid-flight is the leading remaining
candidate, and it is worth testing directly once A is fixed — which is another
reason to fix A first.

Until then, `flows.json` should be checksummed before and after any studio
session, and the `element` field specifically watched: it is the field that
disappears, and nothing currently notices when it does.
