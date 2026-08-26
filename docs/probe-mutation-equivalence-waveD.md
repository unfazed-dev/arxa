================================================================================
MUTATION-EQUIVALENCE REPORT — arxa probe consolidation (wave D)
Node suite (tools/probe-*.mjs)  vs  Dart suite (arxa design probe <name>)
Date: 2026-08-03
================================================================================

VERDICT SUMMARY
--------------------------------------------------------------------------------
Mutation 1 (chip contract kill / panel-contract section L):
    IDENTICAL FAILURE — YES. Byte-identical FAIL lines. Exit 1 / Exit 1.

Mutation 2 (composer hx-preserve kill / composer-draft):
    IDENTICAL FAILURE — YES. Byte-identical FAIL lines.
    EXIT CODES DIVERGE: Dart exit 1, Node exit 0 (prints "2 FAILED", exits 0).
    ^ This is the empirical confirmation of the static exit-code finding.
      Reproduced twice, on two independently created servers/projects.

ACTIONABLE, not just provenance: the .mjs probes REJECT --project (hard error,
exit 2); the Dart probes require it. Whatever retirement/CI script rewrites one
invocation into the other must DROP the flag, not pass it through. Details in
section 0 under INVOCATION DIVERGENCE.

Two anomalies were hit. Neither was CAUSED by the mutations, but ANOMALY B
(teammates editing probe sources mid-verification) bears directly on the
VALIDITY of these results — it is the reason the md5 pin exists, and it is not
environmental noise to skim past. Both are written up at the bottom. Read them.


================================================================================
0. ENVIRONMENT / PROVENANCE
================================================================================
Repo:      /Volumes/developer_ssd/Developer/totem_labs/arxa
HEAD:      4c7d8fbfa9b27f659f39feecfe8a244f66bf81c1  (unchanged start -> end)
Server:    arxa design serve arxa-studio --port 4381 --project mutation-probe
Project:   mutation-probe — created by this run as `cp -R ~/.arxa/projects/portalo`
           (portalo itself never written to; mtime unchanged Aug 2 10:39)
           Removed at teardown.
Guard:     /__projects reported boundProject=mutation-probe (satisfies the
           probes' disposable regex -(?:probe|test)$ in probe_base.dart:49)
~/.arxa/current: read "portalo" at START and at END. Never modified.

PROBE SOURCE PIN (md5) — captured BEFORE the graded runs and re-checked AFTER.
All six identical; the tree did not move under the verification.
  arxa/lib/probes/probe_panel_contract.dart  b5903bb9e2c8ac1bb84791eaaaa8df16
  arxa/lib/probes/probe_composer_draft.dart  8519464e54ecf449750237604e80896a
  arxa/lib/probes/probe_base.dart            2495f21d2880e193b6ae6f34ebb67815
  tools/probe-panel-contract.mjs                237c7489846fdc8bffd3904d5ff446ca
  tools/probe-composer-draft.mjs                491c4e32fefffa60fdcb8c5f829529c6
  tools/_probe_base.mjs                         f0c58d526caa149eafeb4bdef25d4630

INVOCATION DIVERGENCE (found during setup, worth recording):
  The .mjs probes DO NOT accept --project. Passing it is a hard error:
      probe: unsupported argument "--project".
             Supported: --base <url> | --port <n>. Or set ARXA_BASE.
             Refusing to run rather than silently target http://localhost:4319.
      exit 2
  This is _probe_base.mjs rule 1 ("an argument that cannot be honoured is a HARD
  ERROR") working as designed. The Dart probes DO accept --project. So the two
  suites are NOT drop-in interchangeable at the command line; correct pairing is
      dart:  arxa design probe <name> --port N --project P
      node:  node tools/probe-<name>.mjs --port N
  Any retirement script that mechanically rewrites one into the other must drop
  --project, not pass it through.

BASELINE (all four green on mutation-probe, before any mutation):
  dart panel-contract     exit 0   0 FAIL   ==== ALL PASSED ====
  node panel-contract     exit 0   0 FAIL   ==== ALL CHECKS PASSED ====
  dart composer-draft     exit 0   0 FAIL   ==== ALL PASSED ====
  node composer-draft     exit 0   0 FAIL   ==== ALL PASSED ====
  /design served 200, 25 .chip instances (matches the count the Dart section-L
  comment attributes to the .mjs, so the CDP-port isolation fix is holding).


================================================================================
1. MUTATION 1 — chip contract kill  (panel-contract, section L)
================================================================================
FILE: designs/arxa-studio/assets/css/widgets.css
EDIT: wrapped the entire base `.chip` rule block (lines 8-15) in a CSS comment,
      bracketed by markers. Tone hooks (.chip--muted, .probe-chip, ...) left
      intact, so only the SHARED base box model died — exactly the regression
      section L says it exists to catch.

      /* MUTATION-1-START (disposable; restore with git checkout)
      .chip {
        --chip-font: .72rem; --chip-pad-y: .16rem; --chip-pad-x: .6rem; --chip-gap: .35rem;
        display: inline-flex; align-items: center; gap: var(--chip-gap);
        font: inherit; font-size: var(--chip-font); font-weight: 400; line-height: 1.3;
        padding: var(--chip-pad-y) var(--chip-pad-x);
        border: 0; border-radius: 999px; white-space: nowrap; text-decoration: none;
        cursor: default;
      }
      MUTATION-1-END */

MUTATION VERIFIED LIVE, not assumed: fetched the served asset and confirmed the
base rule was absent after stripping CSS comments, while .chip--muted survived.
(A naive `grep '.chip {'` on the served file still matches — the text is inside
the comment. The check that matters is comment-stripped.)

RESULTS — both suites, same server, same moment:

  metric                 DART                        NODE
  --------------------   -------------------------   -------------------------
  exit code              1                           1
  FAIL count             2                           2
  summary banner         ==== 2 FAILED ====          ==== 2 CHECK(S) FAILED ====

  FAIL LINES: byte-identical (verified by `diff` of the grepped FAIL lines —
  no differences, including the JSON detail payloads and their element order).

  [FAIL] every .chip resolves to a flex box (inline-flex, blockified to flex when a flex/grid item)
         — ["chip status-pill status-frozen=block","chip dv-chip on=block","chip dv-chip =block", ...]
  [FAIL] every .chip is a full pill (radius: 999px)
         — ["chip status-pill status-frozen=0px","chip dv-chip on=0px","chip dv-chip =0px",
            "chip dv-chip =0px","chip type-badge tb-screen=0px","chip status-p...]

  Note on which checks did NOT fail, and why that is correct:
   - "at least one .chip renders" and the >=20 coverage check still PASS: the
     elements still render, they just lost their box model. That is the precise
     failure mode section L's header comment describes ("nothing throws; it just
     stops looking like a chip everywhere at once").
   - "no .chip carries a real border" still PASSES: borderW is 0px both with and
     without widgets.css, because the base rule set `border: 0` and the browser
     default for a <span> is also 0. Correctly not load-bearing on its own —
     which is exactly why the section pairs it with the flex/radius checks.
   - The in-probe "mutation test: killing widgets.css breaks the pill contract"
     check still PASSES in both suites (the stylesheet was already dead, so
     disabling it changes nothing and stillPills stays false).

  DETERMINISM: the node probe was re-run once under the same mutation; FAIL
  lines identical to the first node run. (Disclosed re-run; it was to capture an
  exit code lost to output indexing, not to re-roll a result.)

RESTORATION PROOF:
  git checkout -- designs/arxa-studio/assets/css/widgets.css
  Served asset re-verified to contain the live base rule again (comment-stripped
  check, landed on first poll).
  dart panel-contract  ->  exit 0, 0 FAIL, ==== ALL PASSED ====


================================================================================
2. MUTATION 2 — composer draft-preservation kill  (composer-draft)
================================================================================
FILE: designs/arxa-studio/ui/views/main_shell/shared/widgets/composer.html
      (line ~144 — file had NOT moved in the widget-tree reorg)
EDIT: removed the hx-preserve attribute and the conditional that exists solely
      to gate it. Nothing else on the tag touched.

  before:
    <textarea id="composer-text"{% if not c.draftSent %} hx-preserve="true"{% endif %} name="text" rows="1" ...>
  after:
    <textarea id="composer-text" name="text" rows="1" ...>

MUTATION VERIFIED LIVE: fetched /design and confirmed the served tag was
    <textarea id="composer-text" name="text" rows="1" placeholder="Refine the draft…" aria-label="Refine the draft…">
  with zero occurrences of hx-preserve anywhere on the page.

RESULTS — both suites, same server, same moment:

  metric                 DART                        NODE
  --------------------   -------------------------   -------------------------
  exit code              1                           0     <<< DIVERGENCE
  FAIL count             2                           2
  summary banner         ==== 2 FAILED ====          ==== 2 FAILED ====

  FAIL LINES: byte-identical (verified by diff):

    [FAIL] draft survives an unrelated swap          (shell /design)
    [FAIL] draft survives an unrelated swap          (shell /design/freeze)

  Two failures because both probes loop the same pair of shells that share the
  composer. The paired assertion "textarea clears after send" still PASSES in
  both suites — correct: removing hx-preserve kills preservation, it does not
  break clearing. The two assertions only mean anything together, and the
  mutation cleanly separated them.

*** THE EXIT-CODE DATUM (the point of this mutation) ***
  tools/probe-composer-draft.mjs printed "==== 2 FAILED ====" and still
  EXITED 0. Confirmed statically before the run and empirically during it:
    - static: grep for process.exit|exitCode over the file returns NOTHING.
      Its last statement is
        finally{if(b)await b.close();console.log(`\n==== ${fails?fails+' FAILED':'ALL PASSED'} ====`)}
      It counts failures into `fails`, prints the count, and never uses it to
      set an exit status.
    - empirical: EXIT_NODE:0 with 2 FAIL lines on stdout.
  For contrast, tools/probe-panel-contract.mjs DOES have one, at line 402:
      process.exit(fails ? 1 : 0);
  which is why mutation 1 showed 1/1 and mutation 2 showed 1/0.

  DETERMINISM OF THIS DATUM: reproduced twice. The second run was a full
  independent rebuild — disposable project re-created from portalo, a NEW serve
  process on 4381, mutation 2 re-applied and re-verified in the served markup —
  then `node tools/probe-composer-draft.mjs --port 4381` alone:
      EXIT_NODE_RERUN:0   FAILcount=2   ==== 2 FAILED ====
      FAIL lines identical to the first node run.
  So exit 0 is structural, not a flake: the file has no exit mechanism at all.

  CONSEQUENCE: any CI/gate wiring that shells out to probe-composer-draft.mjs
  and trusts $? has been GREEN THROUGH A REAL REGRESSION. The Dart port fixes
  this — it exits 1. This is a correctness IMPROVEMENT in the replacement, not a
  parity break, and it is an argument for retiring the .mjs sooner rather than
  later.

RESTORATION PROOF:
  git checkout -- designs/arxa-studio/ui/views/main_shell/shared/widgets/composer.html
  Served /design re-verified to contain hx-preserve again (landed first poll).
  dart composer-draft  ->  exit 0, 0 FAIL, ==== ALL PASSED ====


================================================================================
3. TEARDOWN CHECKLIST
================================================================================
  [x] serve process killed                    PID 64435 terminated
  [x] port 4381 free                          0 listeners after kill
  [x] designs/ git-clean                      `git status --short designs/` -> 0 lines
  [x]   widgets.css                           `git diff --stat` -> 0 lines
  [x]   composer.html                         `git diff --stat` -> 0 lines
  [x] ~/.arxa/current reads "portalo"       verified (also verified at start)
  [x] disposable project removed              ~/.arxa/projects/mutation-probe deleted
  [x] projects root left as                   foxglove-demo, portalo
  [x] portalo never written                   mtime still Aug 2 10:39
  [x] probe sources unchanged                 all six md5s match the pin
  [x] HEAD unchanged                          4c7d8fbfa9b27f659f39feecfe8a244f66bf81c1


================================================================================
4. ANOMALIES — both are gate risks for wave D. Neither was caused by the
   mutations; ANOMALY B bears on whether these results are valid at all.
================================================================================

ANOMALY A — a concurrent agent DELETED the shared disposable project mid-run.
  Sequence, with evidence:
   - Setup found ~/.arxa/projects/portalo-probe present and populated
     (10 surfaces / 3 flows, dir mtime Aug 3 19:12). The first serve was bound
     to it and all four baseline probes ran GREEN against it.
   - Partway through mutation 1's restoration step, the projects dir mtime
     changed to 19:26 and portalo-probe was GONE.
   - The server logged:
       [design-server] hot reload failed: PathNotFoundException: Directory
       listing failed, path = '/Users/unfazed-mac/.arxa/projects/portalo-probe/'
       (OS Error: No such file or directory, errno = 2)
     and /design began returning 404.
   - The Dart probe run that straddled this reported
       [FAIL] all three content panels carry a shadow
              — [".panel-composer=MISSING",".panel-viewer=MISSING",".panel-activity=MISSING"]
       ERR CdpException(null): TypeError: Cannot read properties of null
           (reading 'getBoundingClientRect')
     i.e. it CRASHED rather than returning a verdict.
  That run has been DISCARDED. It is evidence about a vanished project, not
  about either suite, and it is not counted anywhere in this report. Every
  graded result above was re-run from scratch on the freshly created, privately
  owned mutation-probe.
  RISK: portalo-probe is a SHARED disposable. Any two agents using it at once
  can destroy each other's runs, and the failure presents as a probe crash /
  bogus panel failure that looks like a real regression. Wave D should either
  give each runner its own copied project or serialize access.

ANOMALY B — probe sources were being edited concurrently during verification.
  At session start `git status` showed 5 modified files, none of them probes.
  Midway it showed 18, including arxa/lib/probes/probe_panel_contract.dart,
  probe_composer_draft.dart, probe_base.dart, cdp.dart and 6 other probe ports.
  Teammates are actively editing the exact code under test.
  MITIGATION APPLIED: all six relevant probe sources were md5-pinned before the
  graded runs and re-checked after; every hash matched, and HEAD did not move.
  The graded results in sections 1 and 2 are therefore internally consistent
  against one fixed tree. They are NOT, however, a statement about whatever the
  probe sources look like now if those edits are still landing — re-run the gate
  against the final tree before retiring the .mjs suite.

MINOR — summary-banner wording is not identical between suites for
panel-contract: dart says "ALL PASSED" / "2 FAILED", node says "ALL CHECKS
PASSED" / "2 CHECK(S) FAILED". composer-draft banners DO match exactly. The
per-check [PASS]/[FAIL] lines match byte-for-byte in all cases. If "byte-
identical verdicts" is a retirement criterion, the panel-contract BANNER is the
one string that does not meet it; the checks themselves do.

================================================================================
EVIDENCE FILES (same directory as this report)
================================================================================
  base2/{dart,node}-{panel,composer}.txt   baseline, all four green
  M1/dart.txt  M1/node.txt                 mutation 1, graded runs
  M1/dart-restored.txt                     mutation 1 restoration green
  M2/dart.txt  M2/node.txt                 mutation 2, graded runs
  M2/dart-restored.txt                     mutation 2 restoration green
  M2/node-rerun.txt                        mutation 2 exit-0 determinism recheck
  serve2.log                               second serve (determinism recheck)
  pin-before.txt                           HEAD + md5 pin
  serve.log                                server log incl. the PathNotFound
  base/, M1/node-panel-rerun.txt, M1/dart-panel-restored.txt
                                           discarded pre-anomaly runs, kept for audit
================================================================================
