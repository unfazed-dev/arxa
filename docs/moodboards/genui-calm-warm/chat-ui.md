# Moodboard — Chat & message-input UI (composers + generative-UI responses)

Slice: the conversation surface for **arxa** — a chat-first build monitor where the composer is the primary control and responses render as contextual cards (pipeline state, gates, charts) inline in the thread.

Captured 2026-07-28 with the arxa lens. Freshness: **🔥** current · **🌡️** canonical.

---

## 1. ChatGPT — https://chatgpt.com (unauthenticated landing) · 🔥

![ChatGPT composer](shots/chat-ui/chatgpt__composer.png)

The reference composer, seen logged-out: one centered pill — leading `+` (attachments/actions), placeholder "Ask anything", trailing mic + Voice pill — under a single calm headline "**Ready when you are.**" The sidebar holds only *three* items. This is the anti-paralysis layout: the entire product is one input.

- **Steal:**
  - **One centered composer + one short headline** as the whole empty state; nothing else competes.
  - **Composer anatomy**: leading `+` for attachment affordance, trailing voice/mic cluster, pill shape, soft dark fill against the page.
  - Sidebar reduced to 3 entries — navigation is collapsed until needed.
- **Why it fits:** arxa's chat surface should open to exactly this: "What are we shipping today?" + composer. Gates, runs, findings stay out of view until the conversation calls them up.

## 2. v0 by Vercel — https://v0.app · 🔥

![v0 composer](shots/chat-ui/v0__composer.png)

v0's logged-out home is a live composer: "What do you want to create?", input with **model-picker chip** (v0 Max ⌄) + mic inside the field, and **suggestion chips directly under the composer** (Contact Form / Image Editor / Mini Game / Finance Calculator) — one tap from empty state to running generation. Template cards with live previews sit below.

- **Steal:**
  - **Suggestion chips as the bridge** from blank page to first message — for arxa: "Cut a release build", "Why did the review gate fail?", "Ship to TestFlight".
  - **In-composer context chip** (model picker) → arxa equivalent: target picker (ios/android/macos) or environment chip *inside* the composer, not a settings page.
  - Template/gallery cards with real thumbnails below the fold — history as visual cards, not a table of runs.
- **Why it fits:** proves a generative-UI product can be welcoming at rest and powerful mid-thread; the chips pattern directly solves "user doesn't know what to ask".

## 3. Claude (product page) — https://claude.com/product/overview · 🔥

![Claude product page](shots/chat-ui/anthropic__claude-product.png)

Anthropic's own marketing is **already the warm palette**: cream paper backgrounds, terracotta/amber accents, serif-warm headlines — living proof that "warm + AI chat" is a shipping brand direction. Product shots show chat + artifacts-style side panels.

- **Steal:**
  - **Warm cream + terracotta as an AI-product brand** — validates the entire genui-calm-warm direction with a tier-1 precedent.
  - **Artifact pattern**: generated content opens as a focused panel *beside* the thread, keeping the conversation clean — arxa's big artifacts (diffs, structure.json, screenshots) belong in a side canvas, not dumped in-line.
  - Long-form product story told as stacked, spacious sections — the anti-dashboard.
- **Why it fits:** the closest existing brand to the target feel; mine its color/type decisions freely. _(Note: claude.ai itself redirects to login — skipped per no-auth rule; the product page carries the same UI in marketing shots.)_

## 4. assistant-ui — https://www.assistant-ui.com · 🔥

![assistant-ui generative demo](shots/chat-ui/assistant-ui__generative-demo.png)

Open-source React chat toolkit whose homepage *is* a working demo: a chat thread where responses render as **generative UI — cards, forms and components inline in the conversation**, with branching/regenerate controls. This is the exact interaction model of arxa's GenUI surface.

- **Steal:**
  - **Generative responses as inline cards**: the assistant answers with a purpose-built component (a card with fields/actions), not a wall of markdown — map to: pipeline-status card, gate-approval card, findings-summary card.
  - **Message-level actions** (retry, branch, copy) tucked under each message on hover — keeps the thread chrome invisible until needed.
  - Streaming typography: text appears progressively inside stable layout — no layout jumps (calm = nothing moves unexpectedly).
- **Why it fits:** this is the literal reference implementation shape for "conversation renders contextual cards" — the GenUI definition the redesign brief uses.

## 5. Things — https://culturedcode.com/things/ · 🌡️

![Things](shots/chat-ui/things__home.png)

The perennial calm-UI benchmark: paper-white surfaces, one list, huge margins, and empty states that feel *finished* rather than blank. Its to-do composer (a single `+` that expands inline) is the quietest input affordance in software.

- **Steal:**
  - **Restraint as luxury**: one accent color (their blue → our terracotta), one list, generous air.
  - **Inline expanding composer**: new item appears as a row in place — for arxa, quick actions materialize inside the thread, not in modals.
  - **Empty states with one gentle line** and no calls-to-action shouting.
- **Why it fits:** Things proves a productivity tool people describe as "beautiful" can do *less* per screen; it's the emotional bar for the redesign.

---

## Patterns this slice must have

1. **Composer-first layout**: centered pill, leading `+` (attach/context), trailing send/voice cluster; everything else is a response. (ChatGPT, v0)
2. **One-line headline empty state** ("Ready when you are.") — no dashboard tiles on first open. (ChatGPT)
3. **Suggestion chips under the composer** mapping to the 3–5 most common build-monitor intents. (v0)
4. **Context pickers live inside the composer as chips** (target/env), not in settings. (v0)
5. **Responses render as inline cards** — pipeline status, gate approval, findings — not prose walls. (assistant-ui)
6. **Big payloads open in a side canvas/artifact panel**, keeping the thread narrow and readable. (Claude)
7. **Message actions on hover only**; zero persistent chrome in the thread. (assistant-ui)
8. **Stable layout while streaming** — no jumping cards; skeleton → content in the same footprint. (assistant-ui)
9. **Warm cream brand surface** behind the chat — AI tool without the cold dark-mode-everything look. (Claude)
10. **One accent color, one list, huge margins** — when in doubt, delete an element. (Things)
