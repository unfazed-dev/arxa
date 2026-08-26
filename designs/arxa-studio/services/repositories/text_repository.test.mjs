// arxa:provenance
// generator: arxa  licence: free  project: 662368770980
// Built with arxa (free tier) — https://arxa.dev
// Identity regression test for the widget TEXT router.
//
//   node services/repositories/text_repository.test.mjs      (exit 0 = pass)
//
// What it guards. Layout edits (widget_repository.setWidgetAttr) and copy edits
// (text_repository.setWidgetText) must address THE SAME element for a given
// (screen, kind, index). They once did not: textProvenance re-derived the
// element with its own scan instead of using resolveWidget's, and the two rules
// disagreed in two ways that a single-element fixture cannot show —
//
//   1. PREFIX. The re-find matched `data-el="<kind>` with no delimiter, so kind
//      "tab" also selected a `data-el="tabbar:…"` element.
//   2. TAG. The re-find scanned only `<${tag}`, while elsIn() counts a kind
//      across EVERY tag name. One kind spread over <span> and <button> makes
//      index N mean different elements in the two paths.
//
// Both are silent in production: the studio shows the edit (its own /project-src/
// key updates immediately) while the wrong file — or the wrong element — is what
// actually changed on disk. Hence R5: this test FAILS on the pre-fix code.
//
// Fixture note: readSource() resolves /project-src/ relative to the repository
// module, so the test stages a real directory there and removes it afterwards.
// It refuses to run if one already exists rather than clobbering a live window.
// Only node:fs and URL are used — node:url/node:path are banned in this tree
// (the worker's import map shims node:fs alone).
import { existsSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { resolveWidget } from './widget_repository.js';
import { textProvenance } from './text_repository.js';

const SRC = new URL('../../project-src/', import.meta.url);
const at = (rel) => new URL(rel, SRC);

// tabbar deliberately shares the <span> tag with tab:x — that is what makes the
// prefix bug observable rather than accidentally masked by a tag mismatch.
const FIXTURE = `<span data-el="tabbar:chrome">CHROME</span>
<span data-el="tab:x">Alpha</span>
<button data-el="tab:y">{{ t('adv.beta') }}</button>
<span data-el="tab:z">Gamma</span>
`;

const EXPECT = [
  { index: 0, tag: 'span', text: 'Alpha', source: 'literal' },
  { index: 1, tag: 'button', text: "{{ t('adv.beta') }}", source: 'arb', key: 'adv.beta' },
  { index: 2, tag: 'span', text: 'Gamma', source: 'literal' },
];

const fails = [];
const check = (ok, msg) => { if (!ok) fails.push(msg); };

if (existsSync(SRC)) {
  console.error('REFUSING: designs/arxa-studio/project-src/ already exists — not clobbering it.');
  process.exit(2);
}

try {
  mkdirSync(at('design/surfaces/'), { recursive: true });
  writeFileSync(at('design/surfaces/adv.html'), FIXTURE);
  writeFileSync(at('index.json'), JSON.stringify(['design/surfaces/adv.html']));
  writeFileSync(at('l10n-index.json'), '[]');
  writeFileSync(at('seed-index.json'), '[]');

  const SCREEN = 'proj.adv';

  for (const e of EXPECT) {
    const w = resolveWidget(SCREEN, 'tab', e.index);
    const p = textProvenance(SCREEN, 'tab', e.index);
    check(w, `tab[${e.index}]: resolveWidget returned null`);
    check(p, `tab[${e.index}]: textProvenance returned null (pre-fix: the tag-scan cannot reach this index)`);
    if (!w || !p) continue;
    check(w.tag === e.tag, `tab[${e.index}]: resolveWidget tag ${w.tag} != expected ${e.tag}`);
    check(p.tag === e.tag, `tab[${e.index}]: textProvenance tag ${p.tag} != expected ${e.tag}`);
    check(w.file === p.file, `tab[${e.index}]: file disagreement ${w.file} vs ${p.file}`);
    check(p.text === e.text, `tab[${e.index}]: text ${JSON.stringify(p.text)} != ${JSON.stringify(e.text)}`);
    check(p.source === e.source, `tab[${e.index}]: source ${p.source} != ${e.source}`);
    if (e.key) check(p.key === e.key, `tab[${e.index}]: key ${p.key} != ${e.key}`);
  }

  // The prefix guard, stated as its own assertion so a failure names the cause.
  const texts = EXPECT.map((e) => textProvenance(SCREEN, 'tab', e.index)?.text ?? '');
  check(!texts.some((t) => t.includes('CHROME')),
    `kind "tab" selected the tabbar: element — prefix match regression (got ${JSON.stringify(texts)})`);

  // …and the sibling kind still resolves on its own terms.
  const bar = textProvenance(SCREEN, 'tabbar', 0);
  check(bar?.text === 'CHROME', `kind "tabbar" should read "CHROME", got ${JSON.stringify(bar?.text)}`);
} finally {
  rmSync(SRC, { recursive: true, force: true });
}

if (fails.length) {
  console.error(`text_repository identity: FAIL (${fails.length})`);
  for (const f of fails) console.error('  ✗ ' + f);
  process.exit(1);
}
console.log('text_repository identity: PASS — layout and copy edits address the same element');
