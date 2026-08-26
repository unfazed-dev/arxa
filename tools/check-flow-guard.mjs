#!/usr/bin/env node
// Self-check for the flow-edit invariants (D2 dual-write + D3 remove guard).
// Node only: no browser, no server, no test framework. It imports the two PURE
// exports — `canRemoveFrom` (design_facade) and `patchAnswersFlows`
// (project_repository) — precisely so it never reaches writeProjectFixture's
// fetch and never touches the live studio on :4319.
//
// What it CANNOT check from node: that Dart's `emitFlows` actually reproduces
// the written flows. Dart is not runnable here, so check 4 asserts the SHAPE
// that intake.dart:604-615 makes a fixed point (spread + `action` default +
// declared-feedback-wins) rather than the emit itself. The Dart-side proof is
// arxa's own passthrough test.
//
//   node tools/check-flow-guard.mjs
//
// The imports below are v1 BY DESIGN: this is the Dart↔JS parity suite for
// the flow-edit services that exist only in the v1 design (v2's studio
// services are render-context doors, not flow editors). v1 stays in-tree as
// the retained reference (VISUAL PARITY LAW) — flip these only if the flow
// services are ported into a v2 design.
import assert from 'node:assert/strict';
import { canRemoveFrom } from '../designs/arxa-studio/services/facades/design_facade.js';
import { patchAnswersFlows } from '../designs/arxa-studio/services/repositories/project_repository.js';

const clone = (x) => structuredClone(x);
let n = 0;
const check = (name, fn) => { fn(); n += 1; console.log(`  ok  ${name}`); };

// A 3-screen chain (2 edges) with a feedback on the incoming edge of the middle
// screen — that feedback is what a naive stitch drops and emit then re-derives.
const three = () => ({
  id: 'flow-browse-buy',
  name: 'Browse and buy',
  provenance: 'founder',
  edges: [
    { from: 'p.home', to: 'p.cart', trigger: 'Add to bag', action: 'push', element: 'button:Add', feedback: { kind: 'success', text: 'Add to bag', inferred: true } },
    { from: 'p.cart', to: 'p.checkout', trigger: 'Checkout', action: 'push' },
  ],
});
// A 2-screen chain (1 edge): removing EITHER end leaves 0 edges.
const two = () => ({
  id: 'flow-account',
  name: 'Account',
  provenance: 'founder',
  edges: [{ from: 'p.account', to: 'p.orders', trigger: 'Order history', action: 'push' }],
});

// `excise`'s post-condition, mirrored here only to prove the guard AGREES with
// it. design_facade does not export excise; canRemoveFrom is the contract this
// file is actually pinning, and check 1 asserts the resulting chain directly.
const exciseCount = (flow, screenId) => {
  const edges = flow.edges ?? [];
  const inc = edges.find((e) => e.to === screenId) ?? null;
  const out = edges.find((e) => e.from === screenId) ?? null;
  if (!inc && !out) return edges.length;
  return edges.filter((e) => e !== inc && e !== out).length + (inc && out ? 1 : 0);
};

console.log('flow-guard self-check');

// 1 — the middle screen of a 3-screen flow comes out, leaving a valid chain.
check('3-screen flow: removing the middle screen is allowed', () => {
  const f = three();
  assert.equal(canRemoveFrom(f, 'p.cart'), true);
  assert.equal(exciseCount(f, 'p.cart'), 1, 'stitched chain keeps exactly one edge');
});
check('3-screen flow: removing either END is allowed too', () => {
  const f = three();
  assert.equal(canRemoveFrom(f, 'p.home'), true);
  assert.equal(canRemoveFrom(f, 'p.checkout'), true);
  assert.equal(exciseCount(f, 'p.home'), 1);
});

// 2 — both screens of a 2-screen flow are refused: 1 edge - 1 = 0, and a 0-edge
// flow is rejected by intake.dart:269 AND unrefillable (appendTo bails on an
// empty chain), so it is a permanent dead end.
check('2-screen flow: removing the HEAD is refused', () => {
  const f = two();
  assert.equal(exciseCount(f, 'p.account'), 0, 'premise: excise would empty the flow');
  assert.equal(canRemoveFrom(f, 'p.account'), false);
});
check('2-screen flow: removing the TAIL is refused', () => {
  const f = two();
  assert.equal(exciseCount(f, 'p.orders'), 0);
  assert.equal(canRemoveFrom(f, 'p.orders'), false);
});
check('2-screen flow: a refusal writes NOTHING', () => {
  const f = two();
  const before = JSON.stringify(f);
  canRemoveFrom(f, 'p.account');
  assert.equal(JSON.stringify(f), before, 'canRemoveFrom must be pure — no mutation, no write');
});

// 3 — the case a `chain.length <= 2` precondition gets WRONG. A non-member
// removal changes nothing, so it cannot empty anything; the guard must not be
// what stops it (excise's own null return already makes it a no-op).
check('non-member screen is NOT refused by the guard (2-screen flow)', () => {
  const f = two();
  assert.equal(f.edges.length, 1, 'premise: a chain.length<=2 precondition would refuse here');
  assert.equal(canRemoveFrom(f, 'p.nowhere'), true, 'the guard is about emptiness, not flow size');
});
check('non-member screen is NOT refused by the guard (3-screen flow)', () => {
  assert.equal(canRemoveFrom(three(), 'p.nowhere'), true);
});
check('an ALREADY-empty flow refuses everything', () => {
  assert.equal(canRemoveFrom({ id: 'x', edges: [] }, 'p.home'), false);
  assert.equal(canRemoveFrom(undefined, 'p.home'), false);
});

// 4 — after a mutation, re-emitting from the patched answers reproduces the
// written flows. Shape asserted, per the header note.
const emitFixedPoint = (edge) => {
  // intake.dart:604  ...(e as Map).cast<String, dynamic>()   -> every key survives
  // intake.dart:607  'action': e['action'] ?? 'push'         -> default only when absent
  // intake.dart:615  ...?_edgeFeedback(e), and :440-441 declared feedback wins verbatim
  const out = { ...edge, action: edge.action ?? 'push' };
  if (edge.feedback != null) out.feedback = edge.feedback;
  return out;
};

check('patch: the edited flow round-trips through answers', () => {
  const answers = { product: { value: 'x' }, flows: [three(), two()] };
  const flows = [three(), two()];
  // Simulate a move: reverse the browse-buy chain's tail.
  flows[0].edges = [
    { from: 'p.home', to: 'p.checkout', trigger: 'Add to bag', action: 'push', element: 'button:Add', feedback: { kind: 'success', text: 'Add to bag', inferred: true } },
  ];
  const patched = patchAnswersFlows(answers, flows, ['flow-browse-buy']);
  assert.equal(patched, 1, 'exactly one flow patched');
  assert.deepEqual(answers.flows[0].edges, flows[0].edges, 'answers now declares what flows.json holds');
  // Re-emit is the identity on what we wrote — the dual write is a fixed point.
  assert.deepEqual(answers.flows[0].edges.map(emitFixedPoint), flows[0].edges);
});

check('patch: every edge carries `action`, so emit never re-defaults it', () => {
  const answers = { flows: [three()] };
  const flows = [three()];
  patchAnswersFlows(answers, flows, ['flow-browse-buy']);
  for (const e of answers.flows[0].edges) assert.ok(e.action, `edge ${e.from}->${e.to} declares action`);
});

check('patch: a declared feedback survives verbatim (emit will not re-derive it)', () => {
  const answers = { flows: [three()] };
  const flows = [three()];
  patchAnswersFlows(answers, flows, ['flow-browse-buy']);
  const fb = answers.flows[0].edges[0].feedback;
  assert.deepEqual(fb, { kind: 'success', text: 'Add to bag', inferred: true });
  // The trigger 'Add to bag' contains a mutation word (intake.dart:390), so emit
  // WOULD derive a feedback here — declared winning is what makes it a no-op.
  assert.deepEqual(emitFixedPoint(answers.flows[0].edges[0]), flows[0].edges[0]);
});

// `feedback.action` is the snackbar BUTTON ({label, trigger}, intake.dart:94) and
// is NOT an edge's `action` (the nav op). Nothing here names either: the edge is
// copied whole, so a nested action survives by construction. Asserted because the
// failure mode — a patch that enumerated edge keys — would be silent.
check('patch: a declared feedback.action survives the round-trip', () => {
  const edge = {
    from: 'p.checkout', to: 'p.orders', trigger: 'Place order', action: 'replace',
    feedback: { kind: 'error', text: 'Payment failed', action: { label: 'Retry', trigger: 'Re-run the payment' } },
  };
  const answers = { flows: [{ id: 'f', name: 'F', provenance: 'founder', edges: [] }] };
  const flows = [{ id: 'f', name: 'F', provenance: 'founder', edges: [edge] }];
  patchAnswersFlows(answers, flows, ['f']);
  const got = answers.flows[0].edges[0];
  assert.deepEqual(got.feedback.action, { label: 'Retry', trigger: 'Re-run the payment' });
  assert.equal(got.action, 'replace', "the edge's OWN action is the nav op, untouched and not conflated");
  assert.deepEqual(emitFixedPoint(got), edge, 'declared feedback wins, so emit re-derives nothing');
});

check('stitch/rewire carry `feedback` WHOLE, so feedback.action rides along', () => {
  // Mirrors the `...(incoming.feedback ? { feedback: incoming.feedback } : {})`
  // carry in excise/rewire: the value is one object, never rebuilt key by key.
  const incoming = { from: 'p.home', to: 'p.cart', trigger: 'Add to bag', action: 'push', feedback: { kind: 'success', text: 'Added', action: { label: 'Undo', trigger: 'Remove it again' } } };
  const outgoing = { from: 'p.cart', to: 'p.checkout', trigger: 'Checkout', action: 'push' };
  const stitch = {
    from: incoming.from, to: outgoing.to, trigger: incoming.trigger, action: incoming.action ?? 'push',
    ...(incoming.element ? { element: incoming.element } : {}),
    ...(incoming.feedback ? { feedback: incoming.feedback } : {}),
  };
  assert.deepEqual(stitch.feedback.action, { label: 'Undo', trigger: 'Remove it again' });
  assert.deepEqual(emitFixedPoint(stitch), stitch, 'the stitch is a fixed point of emit');
});

check('patch: `fields` scoping leaves untouched flows and untouched keys alone', () => {
  const answers = { flows: [three(), { ...two(), provenance: 'inferred' }] };
  const drifted = clone(answers.flows[0].edges);
  const flows = [three(), { ...two(), provenance: 'founder' }];
  flows[0].edges = [];                       // a change we did NOT declare in `ids`
  const patched = patchAnswersFlows(answers, flows, ['flow-account'], ['provenance']);
  assert.equal(patched, 1);
  assert.equal(answers.flows[1].provenance, 'founder', 'provenance confirmed');
  assert.deepEqual(answers.flows[1].edges, two().edges, 'a provenance confirm does NOT adopt edge drift');
  assert.deepEqual(answers.flows[0].edges, drifted, 'a flow outside `ids` is untouched');
});

check('patch: an id absent from answers.flows is skipped, not appended', () => {
  const answers = { flows: [two()] };
  assert.equal(patchAnswersFlows(answers, [three()], ['flow-browse-buy']), 0);
  assert.equal(answers.flows.length, 1, 'no flow invented');
});

check('patch: answers with NO flows group stays on emit\'s derive branch', () => {
  const answers = { product: { value: 'x' } };
  assert.equal(patchAnswersFlows(answers, [three()], ['flow-browse-buy']), 0);
  assert.equal(answers.flows, undefined, 'never fabricate a declared flows group');
});

console.log(`\n${n} checks passed`);
