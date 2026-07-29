# Moodboard — Progressive disclosure & calm UI (one thing at a time)

Slice: layout behavior for **appbox**'s redesign — the previous design failed on information overload/paralysis; this slice is the antidote pattern library: focus modes, card stacks, spacious empty states, depth-on-demand.

Captured 2026-07-28 via probe-runner. Freshness: **🔥** current · **🌡️** canonical.

---

## 1. iA Writer — https://ia.net/writer · 🔥

![iA Writer](shots/calm-ui/ia-writer__focus-mode.png)

The canonical "dim the rest" interface: **Focus Mode** fades everything except the current sentence/paragraph; the chrome disappears entirely in full-screen writing. The marketing page itself demonstrates the aesthetic — one column, one idea, vast margins.

- **Steal:**
  - **Focus Mode as a first-class verb**: when a user opens a run or a gate card, *dim every other element* — the thread, the nav, other cards. Attention is a resource the UI manages explicitly.
  - **Syntax/level-based dimming** (current paragraph bright, rest at ~40%): for appbox, the active pipeline stage is bright; completed/queued stages recede.
  - Chrome-free mode: everything hides except content and one escape affordance.
- **Why it fits:** this is the single most direct cure for "where do I look?" paralysis — the answer becomes mechanical: the bright thing.

## 2. Craft — https://www.craft.do/ · 🔥

![Craft](shots/calm-ui/craft__home.png)

Docs/cards app with a warm-neutral, paper-adjacent aesthetic: content lives on **cards with soft shadows and generous internal spacing**, grouped into gentle stacks; depth (sub-pages, attachments) opens progressively instead of all at once.

- **Steal:**
  - **Card as the unit of everything**: each response, document, or result is a card on a calm background — directly applicable to GenUI response cards.
  - **Progressive nesting**: cards open into pages, pages into sub-pages; the top level stays sparse.
  - Warm off-whites + soft shadows: depth via elevation, not borders — quieter than hairline-heavy UIs.
- **Why it fits:** appbox's generative answers (run summaries, gate results) are documents; Craft shows how documents-in-cards stay calm at scale.

## 3. Raycast — https://www.raycast.com · 🔥

![Raycast](shots/calm-ui/raycast__home.png)

A whole pro tool inside **one centered floating window**: a single input, a short ranked list, and every action hidden behind the command bar + `⌘K` action panel. Immense capability, near-zero visible chrome. Its homepage hero *is* the window.

- **Steal:**
  - **One window, one list**: complexity lives behind the input, not in panels — the UI is empty until asked.
  - **Action panel pattern**: contextual actions revealed by shortcut/hotkey on the *selected* item — no per-row button clutter.
  - Ranking + grouping in a single flat list ("suggestions" over "recents") beats multi-pane navigation.
- **Why it fits:** appbox's chat composer is philosophically the same object — one input that summons arbitrary depth; Raycast proves pros accept this as the *primary* interface.

## 4. Amie — https://amie.so · 🌡️

![Amie](shots/calm-ui/amie__home.png)

Calendar/todos app with a soft warm-neutral palette, pill-shaped UI, and a **progressive day view**: your schedule unfolds as a calm stack of cards rather than a dense grid; todos tuck into the same flow.

- **Steal:**
  - **Warm neutrals in a data-adjacent app**: proof that schedules/lists (structured, dry data) feel friendly on cream/sand backgrounds with pill radii.
  - **Stack-of-cards day flow**: chronological items as spaced cards, current/next emphasized, future faded — maps to appbox's run timeline.
  - Playful-but-quiet iconography: small warm accents guide the eye without badges screaming.
- **Why it fits:** the emotional register (soft, warm, unhurried) over structured dev data is precisely the genui-calm-warm target.

---

## Patterns this slice must have

1. **Focus mode dims the rest**: opening a run/gate/artifact reduces everything else to ~40% — one bright thing per screen. (iA Writer)
2. **Active stage bright, others recede** in any timeline/pipeline visualization. (iA Writer)
3. **Cards are the unit of content**, soft-elevated on a warm background; depth via shadow, not borders. (Craft)
4. **Progressive nesting**: top level sparse; detail opens in place or in a side panel, never a new crowded page. (Craft)
5. **Complexity behind one input**: composer/command bar summons depth; default chrome is near-zero. (Raycast)
6. **Contextual actions on the focused item** via shortcut/hover panel — no persistent button rows. (Raycast)
7. **Chronological stacks as spaced cards** with now/next emphasized and the rest faded. (Amie)
8. **Empty states that feel finished**: one line, one gentle affordance, no CTA confetti. (Things — see chat-ui board)
9. **One thing at a time is a rule, not a theme**: if two elements compete for attention, one leaves the screen. (all)
10. Warm neutrals + pill radii as the container language for structured data. (Amie, Craft)
