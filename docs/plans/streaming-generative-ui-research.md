# Streaming generative UI — research findings

Prompted by: "I must see the card component streaming first, then the components
inside it in order, with the card outline highlighted indicating an incoming
component of that size — is that not how the technique works?"

Short answer: that is exactly how the technique works, the format we already
pinned supports it, and the reason we do not have it is one measurable
provider behaviour — not a rendering trick we forgot.

---

## 1. The format is not the blocker. A2UI v0.9 already ships this.

A2UI v0.9 (announced 2026-04-17) lists **Resilient Streaming**: "Incrementally
parse and heal LLM output, allowing the client to render UI components as they
are being generated — no waiting for the full JSON block."

We pinned `A2UI_VERSION = 'v0.9'` in `lib/catalog.js`. So the wire format we
already emit is the one designed for progressive rendering. Nothing about
A2UI stops us.

A2UI also already has the two-phase shape the "skeleton then fill" pattern
needs: `createSurface` (declare the surface) then `updateComponents` (fill it),
keyed by `surfaceId`, with `Map<String, Component>` semantics — a later message
addressing the same id replaces that component. `toA2uiMessages()` builds both
envelopes today; it just emits them **in the same instant, from one tool call**.

## 2. Our provider streams prose but NOT tool arguments. Measured.

From session `e0b1b8ce`, and this is the load-bearing measurement:

| chunk kind | coalesced rows | deltas carried |
|---|---|---|
| reasoning | 642 | many |
| text | 74 | **1045** |
| **tool-call** | **0** | 6 calls × **1 delta each** |

`dsh-session/lib/types/chunk-rows.js` packs any run of **≥ 3** consecutive
same-kind delta events into one row (`MIN_RUN = 3`). Text and reasoning
coalesced heavily, which proves the mechanism was **live in this very log**.
It produced **zero** `tool-call-chunks` rows. That is evidence, not silence:
prose streams token by token, tool arguments arrive whole.

Individual delta sizes, one per call: 1149, 2875, 275, 1466, 1509, 1503 bytes,
each with a 0 ms span.

> Method note. The first pass counted only un-coalesced `assistant/chunk`
> events and would have under-counted a heavily-streamed call, because a long
> run is stored as ONE row holding an array. Re-checked for `tool-call-chunks`
> rows explicitly; there are none. The conclusion survived a real threat to it.

## 3. dsh can receive streamed args. It cannot ask for them.

`argsRaw: base.argsRaw + chunk.argumentsDelta` (ui-conversation `updateChunk`)
is a correct accumulator that never receives a second delta. Searching the
whole runtime for a switch: `toolStream` 0, `streamToolCalls` 0,
`input_json_delta` 0, `partialTool` 0. There is no knob.

**`compat.zaiToolStream: true` in `~/.arxa/dsh/settings.yaml:47` is inert.**
Zero occurrences anywhere in dsh. It is an invented key that has never done
anything. Either delete it or replace it with a real experiment (§7).

## 4. Even with streamed args, there is a second blocker.

`hasVisibleContent` returns `false` for `tool-call` blocks, so a half-built
call draws nothing in the thread, and the toolview mounts from the completed
`tool/call` node. Both would have to change together. This matches the
industry note that an AI-SDK-style `render_gui` tool path "returns the full
spec at tool completion — for args streaming during generation, use the Tool UI
path instead."

## 5. Industry practice: prefer ONE streamed request over N calls.

Vercel's `streamObject` / `useObject` is the reference implementation of
progressive structured rendering — each emission is a deep-partial of the
schema, rendered as it fills. Their explicit guidance is to **stay with a
single streaming request**: multiple sequential calls add round-trip latency
and force you to manage deduplication and state across several async streams.

This corrects the earlier suggestion in this repo's log that the answer is
"have the model make several `gen_ui` calls". That is the fallback when the
transport cannot stream — not the target shape.

## 6. Skeleton UX rules — two of them cut against the request.

Supporting the ask:

- **Match placeholder proportions to real content.** A correctly-sized outline
  is the whole point; it reserves layout and avoids the shift when content
  lands. This is precisely "an outline indicating an incoming component of
  that size".
- Respect `prefers-reduced-motion`, give placeholders ARIA state, and always
  define an error fallback (a skeleton that never resolves is worse than none).

Cutting against it:

- **Do not use a skeleton for anything under ~1 second.** It flashes and reads
  as buggy. This is exactly what happened with the glow we shipped: the design
  server boots fast, so the sweep vanished before it could be seen.
- **Spinners, not skeletons, suit unknown or highly variable durations** — and
  AI generation is named as that case. A skeleton claims "I know what is
  coming and how big"; only the two-phase protocol earns that claim.
- **Excessive motion increases perceived delay and anxiety.** A travelling
  glow on every slot at once would make the wait feel longer, not shorter.

## 7. The cheapest next experiment (do this before building anything)

The active model is `kimi-coding / k3` (`agent-default-model`). The same
settings file also configures `zai` (`glm-5.3`, 1M context) and
`zai-coding-cn`. Whether tool arguments stream is a **per-provider** property.

**Switch the model to `zai/glm-5.3`, run one gen_ui prompt, then count
`tool-call-chunks` rows in the new session log.**

- Rows appear → tool args stream on that provider. Real token-level streaming
  becomes reachable, and the work is the §4 mount-point change plus an
  incremental parser. A2UI's resilient-streaming healer is the reference.
- Still zero → the provider is the ceiling, and §8 is the only route.

This costs one prompt. Building the two-phase feature costs about a day. Do
the measurement first.

**OUTCOME (2026-08-23):** measured in session `e0b1b8ce` — zai/`glm-5.3` at
effort max emitted **0 `tool-call-chunks` rows** across the pricing-card runs
(117 text-chunks, 1452 reasoning-chunks, 34 gen_ui dispatches). The provider
is the ceiling; §8 is the route. Control: the dsh build CAN record
tool-call-chunks (312 rows in an operator-harness session the same day), so
the zero is the provider, not the plumbing.

## 8. If the provider is the ceiling: two-phase declare-then-fill

The shape that delivers the user's description without any streaming at all,
because the **agent** supplies the size signal instead of the transport:

1. **Catalogue**: add a `Card` container and a `Pending` placeholder taking
   `{ id, label, height }`. `height` is the size signal that does not exist
   today — nothing else can know how tall an unarrived component is.
2. **Client folding**: `gen_ui` calls sharing a `surfaceId` merge into one
   growing card instead of N sibling rows. This is `updateComponents`
   semantics, which A2UI already defines (§1) — the client just has to honour
   them across calls rather than within one.
3. **Fill by id**: a later call replaces `{id: 'hero'}` with the real
   component. The placeholder glows only until it is replaced.

Then call 1 emits the card outline with four sized, glowing slots, and calls
2..N fill them in order. That is the requested behaviour exactly.

**This reverses plan decision 23** ("kept to five … resist growing it
speculatively"). It is not speculative — it is the minimum to make a declared
skeleton expressible — but it is a reversal and should be recorded as one.

Apply §6 when building it: no glow under ~1s, one slot animated at a time
rather than all four, and a resolved fallback if a fill never arrives.

**§8.2 SHIPPED (2026-08-23), the rest deferred.** The client fold landed in
arxa-studio (`plugins/gen-ui` — foldCall + ledger): stepwise calls sharing a
surfaceId — or matching the title+prefix-chain heuristic when the model omits
it, which glm-5.3 always does — merge into ONE card that grows in place, with
new children arriving via the entrance animation; folded-away calls render a
one-line stub. The tool schema gained an optional `surfaceId` and the receipt
teaches it in-band. Follow-up (same day): the pending glow never showed on
component surfaces — glm-5.3 settles each call in milliseconds, so tool
pending lasts a frame. The glow now hangs off a warmth clock instead: the
ledger stamps `lastChangeAt` on real growth and the host card glows while
`!settled || surfaceWarm(...)` (1500ms, ~2x the measured 700ms inter-call
cadence); replay is cold by construction. Same follow-up again for the
ENTRANCE: per-node wrappers already reached every depth but fired in
unison, so the mechanism is now a batch cascade — the fold ledger stamps
each component id with the ordinal of the call that joined it
(`firstSeen`), and a render assigns per-node `animation-delay` steps
(90ms, 720ms cap) in depth-first reading order within each batch. The JS
reveal clock, per-card child gating and estimated stand-in slots are
DELETED: real elements reserve their own height from frame one, growth
re-renders cannot restart finished animations (old ids keep their delay
values), and the CSS media query is the whole reduced-motion stand-down.
§8.1/§8.3 (the `Pending`
placeholder + fill-by-id) are NOT built: no catalogue growth means plan
decision 23 stands unreversed, and the fold alone covered the observed
failure (N disjoint prefix cards).

---

## Sources

- [A2UI v0.9: The New Standard for Portable, Framework-Agnostic Generative UI](https://developers.googleblog.com/a2ui-v0-9-generative-ui/) — resilient streaming, catalogs, renderers
- [a2ui.org — component catalogs](https://a2ui.org/concepts/catalogs)
- Vercel AI SDK — `streamObject` / `useObject` partial-object streaming, and the
  single-request-over-sequential-calls guidance
- Skeleton-screen practice: proportion matching, the sub-1s flash rule,
  spinner-vs-skeleton for variable durations, reduced-motion and ARIA
- Local, measured: `dsh-session/lib/types/chunk-rows.js` (`MIN_RUN = 3`),
  `dsh-client-ui-conversation` (`updateChunk`, `hasVisibleContent`),
  session `e0b1b8ce`
