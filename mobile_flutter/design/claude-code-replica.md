# claude-code-replica — the authored anatomy for `code_shell`

> Design source: Claude iOS app (v1.260828) App Store screenshots — the
> "Review, approve, ship from anywhere" frame (session list + inline approval)
> and composer frames — plus code.claude.com/docs remote-control behavior.
> Captured 2026-08-30. This file is the surface contract the builder stage
> fills; structure.json froze only the shape.

## Design language (Claude replica tokens)

- **Canvas:** warm cream `~#F0EEE6`; ink `~#1A1A18`; charcoal cards `~#262624`.
- **Accent:** Claude terracotta `~#D97757` — the ONLY accent (send button,
  new-session FAB, starburst logo). Green = connected/online status.
- **Type:** clean geometric sans for all UI text; high-contrast serif reserved
  for greeting/empty-state display text. Aggressive title truncation.
- **Shape:** pill chips (filter row, model selector), 16–24px card/bubble
  radii, generous padding, airy assistant line-height.

## code.sessions — the "Code" tab (session list)

- **Chrome:** hamburger left; orange circular new-session button with white
  starburst top-right.
- **Filter chips** (segmented, with counts): `All 300` (selected = dark
  charcoal pill, white text), `Blocked 12`, `In progress 3`, `Done`
  (unselected = light gray pills).
- **Session rows:** status glyph (spinner = in progress, `</>` = done/PR,
  hand/emoji = needs input), truncated title, relative time ("Just now",
  "2m", "5m"), repo line (`☁ owner/repo`), status line `🔗 Connected`
  in green when online.
- **Inline approval card** on the active session row: agent message bubble
  ("I found 3 more components using the hard-coded 8px value. Change
  them?") followed by a full-width rounded **Approve** button. Reuse the
  `_ApprovalCard` pattern (chips + free-text) from approvals.list for
  multi-question prompts.
- **Push provenance:** permission requests arrive as notifications too
  ("Claude requested…" on lock screen) — tapping deep-links here.

## code.conversation — the session (transcript + composer)

- **Header:** back, truncated session title, status dot (green connected /
  spinner running), repo + model line.
- **Transcript:**
  - user messages: light gray bubbles, large radius;
  - assistant messages: plain text on canvas (no bubble);
  - tool use: compact white cards (glyph + title, tappable to expand);
  - subagents/workflows: activity rows with per-task status; stop control;
  - compaction: notice row where the conversation was compacted;
  - attachments out: image thumbnails + `DOC`/`PDF` chips;
  - **inline approval cards** at their raised position (the wired-cards
    seam: approvals already carry session id — thread them into this
    timeline; decide over the proven approvals action path).
- **Connection banner:** reconnecting state; queued outbound messages show
  queued until the link returns.
- **Composer:** `+` attach left; multi-line text field; model pill
  (`Opus`-style); mic; orange circular send with white up-arrow, right.

## Flows (frozen in structure.json)

studio.session → code.sessions (code) → code.conversation (session tapped)
↔ back; code.conversation ↔ approvals.list (all approvals / handled).
