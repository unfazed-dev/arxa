# Consolidation — one app-box app + daemon

**Status:** planned, **not started**. Documentation only; no implementation has
been done. Settled in the consolidation grill, 2026-07-28.
**Supersedes:** [`merge-companion-into-one-flutter-project.md`](merge-companion-into-one-flutter-project.md).
**Amends:** architecture §17 (payment gate moves from builder to first deploy).
**Inputs:** [`../design/story-map.json`](../design/story-map.json) ·
[`../design/brief.md`](../design/brief.md) ·
[`../design/story_map.html`](../design/story_map.html) ·
[`../moodboards/`](../moodboards/) (3 files) ·
[`../research/remote-control-and-chat.md`](../research/remote-control-and-chat.md).

## The shape

app-box becomes **one product, one codebase, four shells**, plus a daemon:

| piece | what it is |
|---|---|
| `appbox/` | one Stacked Flutter app — `stacked create app appbox --template=web --platforms=web,macos,ios,android`. Runner folders + locator/router skeleton; **the pipeline owns everything in `lib/ui/**` from then on** (the honest bootstrap — plan 12.1 finally done properly) |
| `appboxd/` | new pure-Dart daemon: executes pipeline phases/gates, holds credentials in the OS vault, serves the web builder UI, brokers the client channel. Runs on macOS/Windows/Linux |
| shells | web (browser, the universal builder UI), macOS (native shell embedding the daemon — the zero-friction .dmg install), iOS, Android |

**Full parity, literal, from R1.** There is no "remote app" and no "companion" —
every shell is app-box with every surface. The viewport ladder already designs
each surface at 390/744/1280 from targets alone, so parity is the pipeline's
natural output, not extra work. Phone-specific capabilities (push, biometric
approval, QR camera scan, widgets) are features under the epics, not a
separate app.

## Settled decisions (the grill)

1. **Scope** — the story map covers the whole consolidated app. Archived
   designs (`archives/design-v1|v2`) are dead context; `docs/` plans and
   research remain current.
2. **Web** — the web build is the full builder, because app-box must work on
   any desktop OS (macOS/Windows/Linux). A browser can't execute the pipeline
   (`dart:io Process`), so the daemon is a forced consequence, not a choice.
3. **Host** — daemon + web everywhere; the native macOS shell survives as the
   double-click install (Michelle's 20-minute trial never sees a terminal).
4. **Target detection** — *design anywhere, build where possible.* Host matrix:
   macOS → ios/android/macos/web; Windows → android/windows/web; Linux →
   android/linux/web. Unbuildable targets are labelled at selection and
   hard-block build/ship as a named **precondition** — never a red gate
   (Michelle: "a limitation discovered at build time that was knowable at
   selection time").
5. **Parity** — literal, every shell, from R1 (above).
6. **Approvals** — a human on **any authenticated shell** can mint an approval;
   an agent never can. Every approval record is provenance-bound: shell type,
   device or WireGuard node identity (tsnet `whois` — strictly stronger than
   the old IP model), human-confirm method (biometric on phone, explicit
   named-action dialog elsewhere), timestamp, design/build hash. Agent
   sessions structurally cannot hold a human credential.
7. **Screen-scoped chat** — select one prototype screen; chat exclusively in
   that surfaceId's context with hard tool-gating (only this screen's tools);
   other screens dim; per-message per-screen checkpoints with rendered
   before/after, never diffs. Research: `design.chat` stories 2.4–2.10.
8. **Preview** — rendered design only (htmx); no built-binary install on
   devices. Built-app screenshots are captured by app-box itself
   (probe-runner) for the flows canvas.
9. **Releases** — R1 Dogfood (39 stories), R2 Anywhere (6), R3 Delight (1) +
   `access.remote` should/R2 ×2 — see `docs/design/story-map.json`.
10. **Remote access** — LAN-only QR pairing stays the default (trial
    untouched). Remote = **self-host**: shipped `docker-compose.yml`
    (headscale + Caddy + mesh-CA helper, the arxa enrollment-door shape) or
    hosted Tailscale; single-use short-lived ACL-tagged pre-auth key travels
    in the pairing QR. **No Totem Cloud at launch** — it buys one-switch UX
    and recurring revenue but costs a solo founder a production service;
    adding it later changes zero client code (`login-server` URL + key).
11. **Money** — **licence-only, flat, never per-seat, BYO-key.** The paywall
    sits at **first deploy**: design → prototype → build → gates → preview
    are all free; you pay when you ship. This amends §17 (payment gate at
    builder) — the licence precondition moves to the deployer, the only phase
    that writes to the outside world. Free tier is the full product on LAN
    with 1–2 active projects: *not crippled, merely smaller* (Michelle's
    trial is the product).
12. **Consolidation mechanics** — fresh stacked shell + daemon; mine `app/`
    (pipeline-integration logic → daemon) and `companion/` (the six security
    modules **with their 49 tests** — pin, no-relay, nonce lifecycle,
    agent-never-mints, revoke-drops-session, FAB-reads-channel); delete both
    in the commit that proves the new app green. The tree never carries two
    answers at once.

## Security model under the tailnet (reopened and re-settled)

Plan 12.5's "no cloud relay" analysis was reopened per its own clause. Verdict
(feasibility pass, 2026-07-28): `package:tailscale` (Dart/Flutter, embeds
tsnet, Headscale E2E-tested, no VPN entitlement) lets daemon + apps become
tailnet nodes in-process; Windows falls back to system tailscaled. All six
pairing properties **survive**: the fingerprint pin is transport-independent;
DERP relays forward ciphertext only; the nonce lifecycle moves from hardening
to primary defense; approvals can bind to WireGuard node identity; revoke gets
a transport-level kill; the FAB heartbeat is unchanged. New trust admitted:
the headscale operator controls node admission (sees pubkeys/IPs, never
traffic) — which is why the default stays LAN-only and self-host is the remote
path. **Private mesh CA** (arxa ADR-0036 pattern): wildcard `*.<slug>` leaf
certs give browser-trusted HTTPS origins over the mesh; CA root installs at
pairing (iOS: one-time config profile). A PWA cannot tunnel WireGuard — the
remote *web builder* from a desktop browser needs a system Tailscale client or
the native shell.

## probe-runner

`~/.claude/skills/probe-runner` (already app-box-tester's smoke/visual runner)
becomes the capture + fidelity engine: `design_golden` / `color_assert` /
`skeleton_diff` / `pixdiff` as **deterministic design↔built gates** in the
build loop (story 3.7), and `flutter_shot` / `*_shot` / `flutter_skeleton` as
the flows-canvas capture (story 4.1). Integration decision: vendor it (same
pattern as kit vendoring, O1); the daemon shells out to its scripts. Core
verbs run on Linux/Windows; desktop capture is macOS-gated — compatible with
daemon-anywhere.

## Dogfood sequencing

1. `stacked create app appbox --template=web --platforms=web,macos,ios,android`
   (by hand, once — the bootstrap).
2. `docs/design/brief.md` → `app-box-moodboarder` fans out per-epic reference
   gathering and captures screenshots into `docs/moodboards/` (orchestrator's
   first run: the three app-box boards themselves).
3. brief + moodboards → `app-box-designer` produces the whole-app design
   (D: 18 surfaces from the brief's table, every viewport derived).
4. Freeze → scaffold through the pipeline → build with gates → the
   consolidated app is the R1 dogfood: app-box designed and built by app-box.
5. `appboxd/` grows alongside as the orchestration home for `pipeline.sh` +
   `gates/` + `tools/`.

**The website is a separate design track.** E9 (`website.*`, 4 surfaces) is in
the main story map for visibility and release-laning, but it is designed
separately: its own designer run scoped to the `website.*` surfaces, its own
freeze, web-only. When that work starts, the Website epic **splits into its
own story map + brief** (the main map is at 64 stories, past the 50-story
advisory) so each project's intake gate sees a brief whose surface table its
registry fully covers — one brief per project, no cross-project orphans. The
app design scopes to the 18 non-website surfaces.

## What this does NOT change

The pipeline, gates, and skills stay as planned (plans 00–14). The htmx
producer, the freeze contract, the registry/traceability model, kit vendoring
(O1/O3), and the three human gates are untouched — this plan changes **where
the product's UI lives and how clients reach the daemon**, nothing else.

## Open

- O2 (price point) remains open — the *model* is now settled (flat licence,
  pay-at-deploy); the number is not chosen.
- The stacked shell's emitted structure vs the scaffolder's expectations
  (locator/router vs emitted surfaces) needs one reconciliation pass when the
  shell exists.
