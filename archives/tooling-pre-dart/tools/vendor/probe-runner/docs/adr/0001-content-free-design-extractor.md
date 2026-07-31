---
adr_decision:
  hard_to_reverse: true
  reversal_cost: "the bundle contract, the firewall's placement, and every capture verb depend on these; reversing 'content-free design extractor' re-architects the whole tool."
  surprising_without_context: true
  surprise_reason: "non-obvious that capture reads everything yet the bundle ships zero content, and that a component is reproduced across its states rather than as one frozen snapshot."
  result_of_real_tradeoff: true
  rejected_alternatives: "faithful recorder (captures content — rejected: content-free distribution is the whole point); REST-only single snapshot (can't reproduce a component's states)."
  all_three_true: true
status: accepted
---

# Probe-runner is a content-free design extractor

Probe-runner drives a real browser/device (Chrome, iOS sim, Android emulator, Flutter) at any **target** and emits a content-free reproduction of its *design*. Four principles fix the architecture:

1. **Design extractor, not a recorder.** It captures design — structure, geometry, tokens, layout, states, motion — for any target on any platform; it does not copy content.
2. **Content-free is a bundle invariant.** The content firewall enforces it at packaging; a capture verb is a pure recorder that never runs the firewall.
3. **A component is States + Transitions.** Reproduce a component across its states (minus content), not as a single frozen snapshot.
4. **Honest ceiling.** Where a region can't be reproduced content-free (canvas/video/opaque embed, or native pixels), label the limit — never fake past it.

Platform-specific *implementation* — token sampling, state driving, native fidelity, content-medium detection — is decided when each platform is built, governed by principle 4. It is deliberately NOT frozen here.

**Implementation status (web is real and broad):** skeleton / tokens / layout; broad CSS coverage (properties, pseudo-elements, `@keyframes`); per-state + transition capture (theme, interactive, responsive, form, reduced-motion, fixed-width `@container`, G4 interaction-state as a presence-diff); P2 substrate honesty; cross-route multi-page capture with opt-in token-merge (G3b) and structural chrome dedup. Honest-ceiling boundaries are labeled, never faked: canvas/WebGL, video-bg, cross-origin iframe, closed shadow roots. **Roadmap / deferred:** iOS / Android / Flutter native; recurring-component synthesis (G3c, deferred ×3 — incl. richness-gated rescue, §C9-R-G3c-rg); nav/site graph; virtualized-scroll content recovery (G2, deferred); hover / non-ARIA triggers (G4, deferred). Full status + pre-registered verdicts: `docs/plans/probe-runner-engine-capture-gaps.md`. Glossary: `CONTEXT.md`.
