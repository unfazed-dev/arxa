# tools/studio-probes

The ten Node/playwright-core contract probes for the `appbox-studio` design,
plus the `_probe_base.mjs` they shared. Retired **2026-08-03**; they lived at
`tools/probe-*.mjs` in the repo root until then.

**Replaced by:** `appbox design probe <names…|all> --port N --project P`
(`appboxd/lib/probes/`, over the one CDP engine in `appboxd/lib/cdp.dart`).

**Why:** two browser engines drove one design — playwright-core here, the lens's
CDP client in `appboxd`. The probes and the lens disagreed about waiting,
targeting and teardown, and every fix had to be made twice. The consolidation
plan is `docs/plans/one-browser-engine-studio-probes-to-lens.md`.

**Evidence that approved the swap:** `docs/probes-capability-map.md` — the full
audit trail. Every probe, section by section, with where each one went; the
final parity run (279 checks per suite, 10/10 probes agreeing, verdict lines
byte-identical bar one measured byte-count); and mutation equivalence, where
both suites were made to fail the same way on purpose. Agreement on a green
tree alone was not treated as sufficient: two suites that assert nothing would
also agree.

## Reading these files

They remain the reference for what each check *meant*. The Dart ports cite
their origin here by path, and several carry the original's reasoning verbatim
where it recorded an incident — notably `_probe_base.mjs`'s target rules
(explicit target, no silent default-port fallback, disposable-project guard),
which exist because probes once ran flow-mutating requests against a live
project.

## Running them (if you ever need to)

**They do not run from this directory.** Each probe resolves the repo root as
`../` from its own location and loads playwright-core from
`skills/appbox-designer/runtime/node_modules/`. That was correct while they
lived in `tools/`; from here `../` is `archives/tooling-pre-dart/tools`, and
the import fails. Verified, not assumed.

They are deliberately left **exactly as they were retired** rather than patched
to work from the archive — an archive that has been edited is no longer the
thing it is an archive of, and these files are the reference for what each
check meant.

To run one, copy it back beside its `_probe_base.mjs` first:

```
cp archives/tooling-pre-dart/tools/studio-probes/{probe-<name>.mjs,_probe_base.mjs} tools/
node tools/probe-<name>.mjs --port N
rm tools/probe-<name>.mjs tools/_probe_base.mjs
```

**The invocation is NOT symmetric with the Dart suite.** These probes *reject*
`--project` — it is an unsupported argument, and `_probe_base.mjs`'s first rule
makes an argument that cannot be honoured a hard error (exit 2) rather than a
silent no-op. The Dart suite *requires* it. So the correct pairing is:

```
node <here>/probe-X.mjs --port N
appbox design probe X --port N --project P
```

Boot the target yourself, against a **disposable** project (a name ending
`-probe` or `-test`) — the guard enforces that, and it exists because a live
`portalo` was corrupted three times before it did.

## Known defects in this suite, fixed in the ports

Recorded so nobody restores these files expecting them to gate anything:

1. **Four of the ten exit 0 while printing a failure trailer** —
   `probe-boost.mjs`, `probe-composer-draft.mjs`, `probe-explode.mjs`,
   `probe-shell-chrome.mjs` call neither `process.exit` nor `process.exitCode`,
   so node exits 0 no matter what was printed. They cannot fail a CI gate. The
   Dart ports all exit non-zero on any failure.
2. **The disposable-project guard is applied inconsistently** — several probes
   mutate the served project without calling `requireDisposableProject`. Every
   mutating port declares `mutates: true` and the harness enforces it uniformly.

Neither was reproduced for the sake of byte parity. Both divergences are
recorded in the capability map as deliberate strengthening.
