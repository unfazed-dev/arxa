#!/usr/bin/env node
// Self-check for the flow-edge `element` invariant (tasks #66 / #68).
//
// THE INVARIANT, stated correctly: `element` is a data-el selector for a control
// on the edge's `from` screen (design_facade:222-224, and the island split where
// `walkel` carries the selector while `walk` separately carries the destination).
// So after ANY reorder, an element must still sit on an edge whose `from` is the
// screen that authored it — and it must not vanish.
//
// Node only, no server: it imports the PURE exports `rewire` and `moveMemory`,
// on the tools/check-flow-guard.mjs precedent, so it never reaches
// writeProjectFixture and never touches the live studio on :4319.
//
//   node check-flow-element.mjs
import assert from 'node:assert/strict';
// v1 import BY DESIGN — see the note in check-flow-guard.mjs: the flow-edit
// services exist only in the v1 design (retained reference).
import { rewire, moveMemory } from '../designs/arxa-studio/services/facades/design_facade.js';

let n = 0;
const check = (name, fn) => { fn(); n += 1; console.log(`  ok  ${name}`); };

// portalo's real flow-onboarding: element authored on the auth -> home edge,
// i.e. "the control on portalo.auth that advances this flow is button:Continue".
const onboarding = () => ({
  id: 'flow-onboarding',
  name: 'Onboarding',
  provenance: 'founder',
  edges: [
    { from: 'portalo.splash', to: 'portalo.startup', trigger: 'App launch', action: 'push' },
    { from: 'portalo.startup', to: 'portalo.auth', trigger: 'Kits loaded', action: 'push' },
    { from: 'portalo.auth', to: 'portalo.home', trigger: 'continue', action: 'push', element: 'button:Continue' },
  ],
});

const AUTHOR = 'portalo.auth';
const EL = 'button:Continue';

// The assertion the whole file exists for. Deliberately TWO clauses: "present"
// alone passes while the element rides the wrong screen, and "on the author"
// alone passes vacuously once it has been dropped. Task #66 broke the first,
// task #68 alleged the second; only both together pin the invariant.
const assertOnAuthor = (flow, where) => {
  const carrying = (flow.edges ?? []).filter((e) => e.element === EL);
  assert.equal(carrying.length, 1, `${where}: element must survive exactly once (found ${carrying.length})`);
  assert.equal(carrying[0].from, AUTHOR, `${where}: element must sit on the screen that authored it, not ${carrying[0].from}`);
};

console.log('flow-element self-check');

// 1 — premise.
check('premise: element starts on the authoring screen', () => {
  assertOnAuthor(onboarding(), 'before');
});

// 2 — #68 as filed: a mid-chain nudge. This is the case the brief measured and
// called a defect. It is NOT one: `from` stays portalo.auth. Only the
// destination changes, and excise (:222-224) already ruled that a changed
// destination does not invalidate an element.
check('#68 mid-chain move: element stays on its authoring screen', () => {
  const f = onboarding();
  rewire(f, ['portalo.splash', 'portalo.auth', 'portalo.startup', 'portalo.home'], moveMemory(f));
  assertOnAuthor(f, 'after mid-chain move');
  // ...and the destination is allowed to have moved. Pinned so a future
  // "fix" that pair-gates the element trips this instead of silently
  // deleting authored data on every reorder.
  assert.equal(f.edges.find((e) => e.from === AUTHOR).to, 'portalo.startup');
});

// 3 — THE RED ONE (#66). Move the authoring screen to the chain TAIL, then undo.
// At the tail portalo.auth has no outgoing edge, so the element is off the file;
// undo re-derives that edge and must fall back to `memory` to rebuild it. If the
// snapshot did not capture `element`, the order comes back perfectly and the
// element is gone for good — the exact four-times corruption signature.
check('#66 move-to-tail then undo: element is restored, not dropped', () => {
  const f = onboarding();
  const before = ['portalo.splash', 'portalo.startup', 'portalo.auth', 'portalo.home'];
  const after = ['portalo.splash', 'portalo.startup', 'portalo.home', 'portalo.auth'];
  const memory = moveMemory(f); // snapshot taken BEFORE the move, as moveInFlow does
  rewire(f, after, memory);
  // undo replays from the CURRENT file, which no longer carries the element
  rewire(f, before, memory);
  assert.deepEqual(f.edges.map((e) => e.from), before.slice(0, -1), 'premise: undo restored the order');
  assertOnAuthor(f, 'after move-to-tail + undo');
});

// 4 — same path, `feedback`: dropped, emit re-derives it from the trigger
// (intake.dart:481) and the answers dual-write stops round-tripping.
check('#66 move-to-tail then undo: a declared feedback is restored too', () => {
  const f = onboarding();
  f.edges[2].feedback = { kind: 'success', text: 'Signed in', inferred: false };
  const before = ['portalo.splash', 'portalo.startup', 'portalo.auth', 'portalo.home'];
  const after = ['portalo.splash', 'portalo.startup', 'portalo.home', 'portalo.auth'];
  const memory = moveMemory(f);
  rewire(f, after, memory);
  rewire(f, before, memory);
  const edge = f.edges.find((e) => e.from === AUTHOR);
  assert.deepEqual(edge.feedback, { kind: 'success', text: 'Signed in', inferred: false });
});

console.log(`\n${n} checks passed`);
