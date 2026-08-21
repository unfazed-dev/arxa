# Research index

Findings that led to appbox's architecture. Every claim here was measured by
running the thing, not inferred from reading it — where a claim was later
falsified, the correction is left in place rather than edited out.

Read in this order.

| # | doc | what it settles |
|---|---|---|
| 1 | [spine-rubric.md](spine-rubric.md) | The 8-dimension scoring rubric, **written before anything was measured** so the result could not be reverse-fitted. D2 (determinism) and D4 (gates) declared gates, not preferences. |
| 2 | [spine-findings.md](spine-findings.md) | asko × flutter-crew × stacked_kit, suites actually executed. Includes the `dep_hash` mutation experiment that proved asko's stale-green defect, and the counter-probe that showed `gen_freshness` holds under the same standard. |
| 3 | [prototype-language.md](prototype-language.md) | Measured LOC/screen — **159 JSX / 118 HTMX / 596 Flutter** — and the asymmetry that outranks it: `new-flutter` produced **zero** reviewable artifacts. |
| 4 | [headtohead-train-shell.md](headtohead-train-shell.md) | flutter-crew vs stacked_kit on a real p2 surface. The translator captured **7 of 112 nodes** because the JSX was branch-matrixed on `role × state × params.branch`. |
| 5 | [htmx-producer-test.md](htmx-producer-test.md) | Controlled experiment: can the FSM build a bespoke app from an htmx prototype? **73/73, identical to the JSX control.** Also the `emit_htmx` asset bug and the three verification layers that all missed it. |
| 6 | [web-research-drift.md](web-research-drift.md) | Industry practice on generated artifacts and drift. The `git diff --exit-code` untracked-file gotcha; spec-driven development's "authority is convention, not enforcement" failure. |
| 7 | [remote-control-and-chat.md](remote-control-and-chat.md) | iOS companion, QR pairing, BYO-key credential storage, and the LLM chat surface. MCP transports, the QR-relay attack, and the macOS Keychain failure modes that go silently green. |
| 8 | [competitors-and-pricing.md](competitors-and-pricing.md) | FlutterFlow / Adalo / Lovable / Cursor pricing, the per-seat backlash, and why BYO-key is a structural cost advantage rather than a discount. Shorebird and Codemagic tiers. |
| 9 | [stub-inventory.md](stub-inventory.md) | What is wired versus what throws. **Stripe and PayPal are both stubs**, so the payment gate has no foundation in the kit yet; auth providers likewise. |

## The three findings that shaped the design

**The prototype must carry structure, not just pixels.** Half of every
surface's layout is invented on every path today — no producer in the corpus
captures tablet or desktop input, yet the deliverable contract demands both.
See 5, and `../plans/architecture.md` §11.

**`design/new-htmx` is already MVVM — the freeze throws it away.** 8,454 lines
of `_view`/`_viewmodel` pairs, `services/{repositories,facades}`, and fixtures
exist in the producer; the frozen contract keeps 37 flat HTML files. See
`../plans/architecture.md` §13.

**A gate that cannot fail is not a gate.** Recurring across all three repos:
`dep_hash` keyed on mtime, a self-test asserting the defective value, an
asset check that verified strings instead of resolving paths, a drift check
guarded on a file the htmx producer does not have. Every one was green.

## Later additions (reading-research, not measured findings)

| doc | what it's for |
|---|---|
| [flutter-genui.md](flutter-genui.md) | Docs digest (2026-07-28) for the GenUI design direction: package status, A2UI architecture, the appboxd-as-A2UI-server fit, custom-catalog consequences. |
| [sim-embed.md](sim-embed.md) | Live iOS/Android display in the canvas (2026-07-29): literal embedding impossible, capture→redisplay pattern, v1 polling-screenshots / v1.5 Android gRPC / v2 iOS ScreenCaptureKit, with local measurements. |
| [icon-library-components-first.md](icon-library-components-first.md) | Icon-library bake-off (2026-07-29) behind the designer's components-first update: Lucide chosen (license/style/currentColor/Flutter parity), inline-SVG-macro over sprite/webfont, `icon()` global + `AppBoxKitGlyphs.lucide` decisions, build evidence, open follow-ups. |
| [provider-fabric-recheck.md](provider-fabric-recheck.md) | Re-verification (2026-07-30) of the LLM-fabric plan's flagged-unverified facts against current official docs: Gemini prices confirmed, z.ai PAYG Anthropic endpoint conditional, Fugu pricing now official, Kimi CLI headless contract corrected (`-p`, no `--afk`), Anthropic OpenAI shim now exists. |
| [agent-memory-and-caching.md](agent-memory-and-caching.md) | Memory + self-learning + caching architecture (2026-07-30): skip mem0/Letta/Zep (97.8%-junk audit, Zep CE shutdown), keep Fugu scorecard affinity, add gate-triggered LESSONS.md, cache-first prompt assembly, exact-match response cache; semantic caching skipped. |
| [monetization-and-licensing.md](monetization-and-licensing.md) | Monetization + licensing research (2026-07-30): charge for the tool never the output, flat annual + JetBrains-style perpetual fallback, Ed25519 offline-signed keys, encrypt the vault not emitted targets, DRM backlash case file (Unity, Adobe CS3, Cursor credits). |

## Measured findings (2026-08-21) — lens capture determinism

Both of these were run, not read. They feed the W1 amendments in
[../plans/rust-port-closure-and-surgical-lens.md](../plans/rust-port-closure-and-surgical-lens.md).

| doc | what it's for |
|---|---|
| [deterministic-screenshot-capture.md](deterministic-screenshot-capture.md) | What actually guarantees a stable screenshot: `document.fonts.ready`'s spec-documented gap, why double-rAF is a heuristic and not a contract, which animation types `getAnimations()` cannot reach (SMIL, GIF/APNG, cross-origin iframes), why CDP virtual time is excluded, and the capture-until-two-match stability loop that backstops all of it. Every claim graded HOT/WARM/COLD against a primary source. |
| [warm-vs-cold-chrome-determinism.md](warm-vs-cold-chrome-determinism.md) | Does a REUSED Chrome render byte-identically to a freshly-launched one? No official source answers it, and it gates the daemon-owns-a-browser plan — a speed win that changes pixels is worthless to a tool that exists to compare them. Three page kinds × four arms, with negative controls, a render-richness floor, and a cold-A/cold-B baseline. **Identical in every arm**, conditional on Chrome build, viewport, settle, and a warm window only ~26s deep. |
