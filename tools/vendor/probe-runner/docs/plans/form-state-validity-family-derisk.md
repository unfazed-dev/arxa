# Form-state validity family — DE-RISK (pre-registration + gates)

**Rung:** extend the shipped `:checked`/`:disabled` form-state capture to the validity/attribute
family `:invalid` / `:valid` / `:required` / `:read-only` / `:placeholder-shown`.
**Status:** de-risk COMPLETE. Mechanism gate PASS. **Signal gate FAILS pre-registered bar → DEFER.**

---

## Gate 1 — Mechanism — CAPABILITY yes, but NOT a real capture path (2026-06-03)

Question: validity/attribute-derived pseudo-classes are not freely toggled like `:hover`/`:focus`;
does CDP `CSS.forcePseudoState` actually APPLY them so a FORM_PROPS computed-style delta appears?

Harness: `scripts/derisk_form_state_validity.py` (manual, headless, ~10s — NOT pytest; live-CDP is a
manual-harness regime).

**Capability pass (PROXY fixture — base crafted to NOT match the pseudo):** all 5 force ON cleanly
(`:invalid`/`:valid`/`:required`/`:read-only`/`:placeholder-shown` each flip their sentinel prop).
So `forcePseudoState` *accepts* the full set.

**BUT that was a proxy, not a real artifact (validate-real-artifact applied to self).** A real form
input carries its attribute/validity state at BASE, so the pseudo already matches before any force —
and `forcePseudoState` forces a pseudo **ON only; it never forces OFF and never suppresses the natural
match**. Re-ran in the REALISTIC regime (inputs that ship the real state):

| pseudo | realistic input | force-on-natural-match |
|---|---|---|
| required | `<input required>` | **NO-OP** (already `:required` at base → value already in base skeleton) |
| read-only | `<input readonly>` | **NO-OP** (already `:read-only` at base) |
| placeholder-shown | `<input placeholder>` empty | **NO-OP** (already `:placeholder-shown`; the interesting floated state needs it OFF — unreachable) |
| valid | `<input value=ok>` | **NO-OP** (already `:valid` at base) |
| invalid (on naturally-`:valid` input) | force opposite | bg lime→red, but input now matches `:valid` AND `:invalid` — **physically-impossible chimera** |

**Structural verdict:** unlike `:checked`/`:disabled` (reliably OFF at base → forceable ON → clean
dynamic delta), the validity family is either (a) **static/attribute-derived** (`:required`/
`:read-only`) → already in the base skeleton's computed style, no dynamic delta exists; (b)
**naturally-ON at base** (`:valid`/`:placeholder-shown` on a fresh form) → forcing ON is a no-op and
the interesting transition needs OFF, which force cannot do; or (c) **mutually-exclusive pairs**
(`:valid`↔`:invalid`) → forcing superimposes both rulesets = chimera (the FS3 smear concern, now
intrinsic). Capability ≠ a capturable path. This is the deeper reason the rung DEFERs — independent of
prevalence.

## Gate 2 — Signal (real sites style these with mechanism, not content) — PRE-REGISTERED, not run

Mechanism working ≠ worth building. The rung ships only if real sites carry a **capturable,
non-redundant, mechanism-shaped** delta. Bar locked HERE, before any real-site data is read.

**SHIP iff** ≥2 distinct real form-heavy sites EACH carry ≥1 rule matching a validity pseudo
(`:invalid`|`:valid`|`:required`|`:read-only`|`:placeholder-shown`) whose declaration block sets ≥1
FORM_PROPS-class **mechanism** property — color / background-color / border-*-color / outline-* /
box-shadow / opacity / accent-color / cursor / text-decoration — AND that signal is not already
recoverable by the shipped `:checked`/`:disabled` rung.

**DEFER iff** any of:
- signal is **content-only** — the pseudo only drives `content:` / a pseudo-element (e.g. a required
  asterisk `::after{content:"*"}`). Content is redacted, not a capturable mechanism delta.
- signal appears on **<2** distinct real sites (no demo+1; no single-framework-only).
- the styled prop is **redundant** with what `:checked`/`:disabled` already capture.
- signal is **regime-fragile** (headed-only / load-order dependent).

**Negative control (anti-vacuous):** a form-light prose page (e.g. a Wikipedia article) must yield
~0 validity-pseudo mechanism rules. If "signal" fires everywhere, it is noise, not signal.

**Survey method (cheap, multi-site, falsifiable):** static CSS read — fetch each site's served
stylesheet(s), extract rules whose selector contains a validity pseudo, classify each declaration
block as `mechanism` (FORM_PROPS-class prop) vs `content` (`content:`/pseudo-element) vs
`combinator-only` (pseudo only gates a sibling/descendant, not the element itself). This property —
"does the shipped CSS style the pseudo, and with what" — IS statically observable in the stylesheet
(unlike G2's dynamic below-fold), so a static read is the correct falsifier. A live capture confirms
ONLY if static clears the bar.

Honest outcome: DEFER is a valid answer to "proceed to next." If the signal is thin, the report is
"web-CDP axis confirmed exhausted; validity family does not clear the pre-registered bar."

### Gate 2 RESULT — DEFER (2026-06-03; survey BEFORE-bar-locked, not bent)

Static CSS survey, distinct ecosystems + one big real-site sample + negative control:

| source | validity-pseudo mechanism rules |
|---|---|
| bootstrap@5.3.3 (CDN, served by millions) | `:invalid`/`:valid` mech-self=7 each, BUT under `.was-validated` (JS-gated) + dominant path is the **`.is-invalid`/`.is-valid` CLASS** (static → already in base skeleton); `:placeholder-shown ~ label` floating-label combinator (real, mechanism: transform/color) + a sibling `::after{content}` (content, not capturable). `:required`/`:read-only`: **0**. |
| bulma@1.0.2 | **0** |
| @primer/css (github.com) | **0** |
| foundation@6.8.1 | **0** |
| stackoverflow.com real CSS (1.2 MB, 4 sheets) | **0** |
| normalize.css (neg-control) | **0** (clean — signal is not vacuous) |

(HN / github.com/login / djangoproject CSS-discovery returned 0 linked sheets via static `<link>`
parse; gitlab 403 — those are INCONCLUSIVE, not positive. Not counted either way.)

**Verdict vs the locked bar:** bar = ≥2 distinct real sites with ≥1 **non-redundant mechanism**
validity-pseudo rule. Result = at most **1** (Bootstrap), and even that is **class-redundant**: the
real-world dominant pattern is a **state CLASS** (`.is-invalid` / `.is-danger` / `.error`) toggled by
JS — which the BASE skeleton already captures as a static class + its computed style. The forceable
CSS validity pseudo path this rung would add is rarely the path real sites actually use. **DEFER.**

**Honest refinement (makes the bar HARDER, surfaced not bent):** the operative redundancy is not with
the `:checked`/`:disabled` rung (orthogonal states) but with the **base skeleton's class capture** —
the path 3 of 4 frameworks + the 1.2 MB real sample actually use. The `:placeholder-shown` floating-
label combinator is the single genuinely-pseudo-driven mechanism pattern found, on 1 framework — below
the ≥2 floor on its own.

**Reopen criteria (pre-committed):** ≥2 distinct real, non-Bootstrap sites whose SHIPPED CSS styles a
validity pseudo ON THE ELEMENT ITSELF (or a captured combinator sibling) with a mechanism prop, where
that delta is NOT already present in the base skeleton's class-based computed style. Until then: the
validity family is forceable-but-not-worth-capturing; web-CDP axis remains at its honest ceiling.

**Artifact retained:** `scripts/derisk_form_state_validity.py` (mechanism-gate harness, non-collected;
the falsification record — proves the gate was capability, not the blocker).
