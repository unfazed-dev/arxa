# Research index

Findings that led to app_box's architecture. Every claim here was measured by
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
