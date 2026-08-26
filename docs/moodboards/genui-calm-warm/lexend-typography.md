# Moodboard — Lexend typography (superfamily cuts for display / body / UI)

Slice: type direction for **arxa** — one superfamily that covers display, body, and UI-label roles while reinforcing "calm, warm, readable" (Lexend was literally engineered for reading proficiency).

Captured 2026-07-28 with the arxa lens. Freshness: **🔥** current · **🌡️** canonical.

---

## 1. lexend.com — https://www.lexend.com · 🔥

![Lexend official site](shots/lexend-typography/lexend__home.png)

The official superfamily site (Bonnie Shaver-Troup / Thomas Jockin / Superunion): the full expansion ladder **Deca → Exa → Giga → Mega → Peta → Tera → Zetta**, plus the research story — Lexend's expanded forms measurably improve reading fluency, and the variable font's `wght` axis covers 100–900.

- **Steal:**
  - The **rationale as brand copy**: "change the way the world reads" — arxa can honestly claim its typeface is chosen for reduced eye fatigue during long build-watch sessions.
  - The **expansion ladder itself is the display system**: pick the width per role instead of reaching for a second family.
  - Variable-font delivery: one file, `wght` 100–900 — cheap to ship, fine-grained weight control for hierarchy-without-color.
- **Why it fits:** a dev tool whose core activity is *reading* (logs, diffs, chat) benefits from a face designed for exactly that; "calm" is a documented property of the design, not a vibe.

## 2. Lexend (core) — https://fonts.google.com/specimen/Lexend · 🔥

![Lexend specimen](shots/lexend-typography/googlefonts__lexend.png)

The base cut: geometric-humanist sans, gently expanded, open apertures, generous x-height. Google Fonts tags it, fittingly, "Feeling — Calm".

- **Steal:**
  - **Body role**: 400/450 for prose and chat text; 500 for UI emphasis; 300 for large quiet numbers (durations, counts).
  - Open apertures + wide spacing = survives small sizes on dense build-log surfaces without turning to mush.
  - Specimen shows it holds up reversed (light on warm-charcoal) — important for the ember dark mode.
- **Why it fits:** the workhorse. Every chat message, card body, and gate description sets in this cut.

## 3. Lexend Deca — https://fonts.google.com/specimen/Lexend+Deca · 🔥

![Lexend Deca specimen](shots/lexend-typography/googlefonts__lexend-deca.png)

The *least* expanded rung — closest to a conventional UI sans, most compact horizontally.

- **Steal:**
  - **UI-label role**: buttons, tabs, chips, table headers, nav items — anywhere horizontal space is scarce.
  - The mono-adjacent use: Deca's even rhythm makes it a passable stand-in next to real monospace (JetBrains Mono etc.) for metadata rows where a true mono would shout.
  - All-caps Deca 500 at ~11-12px with tracking = the eyebrow/kicker style for card headers ("BUILD GATE · AWAITING APPROVAL").
- **Why it fits:** chat-first surfaces are dense with chips, pills and status labels; Deca keeps them quiet and compact while staying in-family.

## 4. Lexend Giga — https://fonts.google.com/specimen/Lexend+Giga · 🔥

![Lexend Giga specimen](shots/lexend-typography/googlefonts__lexend-giga.png)

The mid-ladder display cut — noticeably expanded, soft and friendly rather than shouty; wide letterforms read as *leisurely*, which is the emotional register the redesign needs.

- **Steal:**
  - **Display role**: empty states ("Ready when you are."), onboarding, section heroes, the one big sentence per screen.
  - Use at 300–400 weight, sentence case, large size — expansion + light weight = calm confidence; avoid 700+ at display sizes (turns oppressive).
  - **Do not go wider for UI**: Mega/Peta/Tera/Zetta are poster cuts — Zetta especially is unusable in product UI. Giga is the ceiling.
- **Why it fits:** the redesign was rejected for information overload; an expanded display face literally slows the page down visually and signals "one thing at a time".

---

## Patterns this slice must have

1. **One superfamily, three cuts**: Giga (display) / Lexend (body) / Deca (UI labels) — no second family. (all above)
2. **Variable font, `wght` axis** for hierarchy — weight and size create levels, not extra colors. (lexend.com)
3. **Display = light weight, large size, sentence case**: Giga 300–400 for the single headline per screen. (Giga)
4. **Body = Lexend 400/450**, 15–16px equivalent, line-height ~1.6 for chat prose. (Lexend)
5. **Labels/eyebrows = Deca 500 caps, tracked**; status pills and chips in Deca. (Deca)
6. **True monospace reserved for data** (hashes, logs, durations) — Deca bridges prose↔mono transitions. (Deca)
7. **Expansion ladder is the brand voice**: wider = more expressive; never mix widths within one role. (lexend.com)
8. Claim the accessibility story: typeface chosen for reading proficiency — a concrete, honest "calm" claim. (lexend.com)
