// The composer must always say what the canvas has pinned.
//
// WHY THIS EXISTS: the screens filmstrip used to live in the composer tray,
// and composer.html gated the WHOLE tray — including the `cm-tray-title`
// summary of the pinned screens — on `{% if hasStrip or hasEls %}`. The strip
// was non-empty on every design surface, so that gate was always true and
// nobody noticed it was the wrong condition. When the strip moved out of the
// tray and into the viewer, `hasStrip` went false on the canvas surfaces and the
// composer stopped showing the pinned context entirely: you could pin two
// screens, watch the canvas tiles and the viewer strip both mark them, and the
// composer would say nothing. The state was fine the whole time (the
// placeholder tracked it) — only the render gate was wrong.
//
// So this probe asserts the INVARIANT, not the markup that happened to
// satisfy it: whatever is pinned in the session shows up in the composer and
// in the viewer strip at the same time. No browser needed — this is a
// server-render contract, and each check is one GET.

import { resolveBase, requireDisposableProject } from './_probe_base.mjs';

const BASE = resolveBase();
await requireDisposableProject(BASE);

const jar = [];
const get = async (p, init) => {
  const r = await fetch(BASE + p, { ...init, headers: { ...(init?.headers ?? {}), cookie: jar.join('; ') } });
  for (const c of (r.headers.getSetCookie?.() ?? [])) {
    const kv = c.split(';')[0], k = kv.split('=')[0];
    const i = jar.findIndex((x) => x.startsWith(k + '='));
    if (i > -1) jar[i] = kv; else jar.push(kv);
  }
  return r.text();
};

// What the three surfaces claim about the context, read out of one render.
const readContext = (html) => ({
  // The composer's context label. ABSENT is the regression this probe exists for.
  composer: (html.match(/<span class="cm-tray-title">([\s\S]*?)<\/span>/) || [, null])[1]?.replace(/\s+/g, ' ').trim() ?? null,
  // One chip per pinned screen: {tone, id, label, remove}.
  chips: [...html.matchAll(/<span class="cs-ctx-chip ctx-([a-z]+)" title="([^"]*)">[\s\S]*?<span class="cs-ctx-name">([^<]*)<\/span>[\s\S]*?href="([^"]*)"/g)]
    .map((m) => ({ tone: m[1], id: m[2], label: m[3], remove: m[4] })),
  // The tone the canvas tile paints for a given screen — the value a chip
  // must match. Both come from toneFor(id), so a mismatch means someone
  // started copying tones around instead of deriving them.
  tileTone: (id) => (html.match(new RegExp(`dv-tile in-ctx ctx-([a-z]+)[\\s\\S]{0,80}?data-id="${id.replace(/\./g, '\\.')}"`)) || [, null])[1],
  // The composer's textarea placeholder ("Refine Home + Orders…") — the other
  // place the composer names the context, and the one that never broke.
  placeholder: (html.match(/id="composer-text"[^>]*placeholder="([^"]*)"/) || [, ''])[1],
  // Pinned thumbs in the viewer's floating filmstrip (.dv-vstrip, views only).
  stripPinned: (html.match(/cs-thumb [^"]*in-ctx/g) || []).length,
  tilesPinned: (html.match(/dv-tile [^"]*in-ctx/g) || []).length,
});

let fails = 0;
const check = (label, ok, detail) => {
  console.log(`  [${ok ? 'PASS' : 'FAIL'}] ${label}${detail ? ' — ' + detail : ''}`);
  if (!ok) fails++;
};

console.log('\n=== the composer names every pinned screen the canvas marks ===');

// Start clean: ?screen=none clears the context.
await get('/design/chat?screen=none');

// The composer names every pin as its own chip — one per pinned screen, in
// the screen's own tone, with an unpin control. Not a "first +N" summary.
for (const [n, id, label] of [[1, 'portalo.home', 'Home'], [2, 'portalo.orders', 'Orders']]) {
  await get(`/design/chat/context/${id}?state=on`);
  const c = readContext(await get('/design'));
  check(`${n} pinned: the composer shows a context label`, c.composer !== null,
    c.composer === null ? 'cm-tray-title ABSENT — the composer says nothing about the pin' : JSON.stringify(c.composer));
  check(`${n} pinned: one chip per pin`, c.chips.length === n,
    JSON.stringify(c.chips.map((x) => x.id)));
  check(`${n} pinned: the new chip names the screen`, c.chips.some((x) => x.id === id && x.label === label),
    JSON.stringify(c.chips.map((x) => `${x.id}=${x.label}`)));
  check(`${n} pinned: every chip wears its screen's canvas tone`,
    c.chips.every((x) => x.tone && x.tone === c.tileTone(x.id)),
    c.chips.map((x) => `${x.id} chip=${x.tone} tile=${c.tileTone(x.id)}`).join(', '));
  check(`${n} pinned: every chip carries an unpin href`,
    c.chips.every((x) => x.remove.includes(`/context/${x.id}?state=off`)),
    JSON.stringify(c.chips.map((x) => x.remove)));
  check(`${n} pinned: the placeholder agrees`, c.placeholder.includes(label), JSON.stringify(c.placeholder));
  check(`${n} pinned: the viewer strip marks ${n}`, c.stripPinned === n, `${c.stripPinned}`);
  check(`${n} pinned: the canvas tiles mark ${n}`, c.tilesPinned === n, `${c.tilesPinned}`);
}

// The × is the whole point of the chips: one GET, and the composer, the strip
// and the tiles all drop that screen together.
{
  const before = readContext(await get('/design'));
  const target = before.chips[0];
  const after = readContext(await get(target.remove));
  check('unpin via a chip × removes that chip', !after.chips.some((x) => x.id === target.id),
    JSON.stringify(after.chips.map((x) => x.id)));
  check('unpin via a chip × leaves the others', after.chips.length === before.chips.length - 1,
    `${before.chips.length} → ${after.chips.length}`);
  check('unpin via a chip × unmarks the viewer strip in the same swap',
    after.stripPinned === before.stripPinned - 1, `${before.stripPinned} → ${after.stripPinned}`);
  check('unpin via a chip × unmarks the canvas tile in the same swap',
    after.tilesPinned === before.tilesPinned - 1, `${before.tilesPinned} → ${after.tilesPinned}`);
}

// The strip is VIEWS-ONLY. It floats over the views canvas; in flows it would
// cover the flow rows, and in proto it would sit beside a device frame that
// has nothing to do with it. The gate lives in the facade (filmstrip: null),
// so this is what proves the template isn't quietly rendering it anyway.
{
  await get('/design/chat/context/portalo.home?state=on');
  for (const [mode, want] of [['views', true], ['flows', false], ['proto', false]]) {
    await get(`/design/viewer?mode=${mode}`);
    const html = await get('/design');
    const thumbs = (html.match(/class="dv-thumb cs-thumb/g) || []).length;
    check(`${mode}: the filmstrip ${want ? 'renders' : 'is absent'}`,
      want ? thumbs > 0 : thumbs === 0, `${thumbs} thumb(s)`);
    // The pin itself must survive the lens switch either way — hiding the
    // strip is a render decision, not a state change.
    check(`${mode}: the pin survives the lens switch`,
      readContext(html).chips.some((x) => x.id === 'portalo.home'), '');
  }
  await get('/design/viewer?mode=views');
}

// Unpinning must take the summary away again — a stale "context ·" line is the
// same desync in the other direction.
await get('/design/chat?screen=none');
const cleared = readContext(await get('/design'));
check('cleared: no pinned thumbs', cleared.stripPinned === 0, `${cleared.stripPinned}`);
check('cleared: no pinned tiles', cleared.tilesPinned === 0, `${cleared.tilesPinned}`);
check('cleared: the composer drops every chip', cleared.chips.length === 0, JSON.stringify(cleared.chips.map((x) => x.id)));
check('cleared: the composer drops the context label', cleared.composer === null, JSON.stringify(cleared.composer));

console.log(fails ? `\n==== ${fails} CHECK(S) FAILED ====` : '\n==== ALL CHECKS PASSED ====');
process.exit(fails ? 1 : 0);
