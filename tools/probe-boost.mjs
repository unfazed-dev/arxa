// probe-boost.mjs — boosted MPA inside generated screens: still tiles stay script-free, live tiles navigate same-document.
// Run against a live studio:
//   dart run appboxd/bin/appbox.dart design serve designs/appbox-studio --port 4319 --json --project portalo
//   node tools/probe-boost.mjs
// Override with APPBOX_BASE / APPBOX_CHROME.
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { chromium } = await import(
  path.join(REPO, 'skills/appbox-designer/runtime/node_modules/playwright-core/index.mjs'));
const CHROME=process.env.APPBOX_CHROME||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const BASE=process.env.APPBOX_BASE||'http://localhost:4319';
let b, fails=0;
const check=(n,ok,x='')=>{ if(!ok)fails++; console.log(`  [${ok?'PASS':'FAIL'}] ${n}${x?' — '+x:''}`); };
try{
  b=await chromium.launch({executablePath:CHROME,headless:true});
  const p=await b.newPage({viewport:{width:1600,height:1000}});
  await p.goto(BASE+'/design',{waitUntil:'networkidle'}); await p.waitForTimeout(900);

  console.log('=== still tiles stay script-free ===');
  const stillDoc=await (await p.$('.dv-tile[data-id="portalo.cart"] iframe')).contentFrame();
  check('static canvas tile does NOT load htmx', await stillDoc.evaluate(`typeof window.htmx === 'undefined'`));

  console.log('\n=== live tile is boosted ===');
  await p.$eval('.dv-tile[data-id="portalo.home"] a[hx-get*="live="]',e=>e.click());
  await p.waitForTimeout(1400);
  const sel='.dv-tile[data-id="portalo.home"] iframe';
  let doc=await (await p.$(sel)).contentFrame();
  console.log('  src:', (await (await p.$(sel)).evaluate(e=>e.getAttribute('src'))));
  check('live tile loads htmx', await doc.evaluate(`typeof window.htmx !== 'undefined'`));
  check('body carries hx-boost', await doc.evaluate(`document.body.hasAttribute('hx-boost')`));

  console.log('\n=== navigate inside: boosted swap, not a document load ===');
  await doc.evaluate(`window.__tok='SURVIVE'; document.documentElement.dataset.tok='SURVIVE';`);
  const before=doc.url().replace(BASE,'');
  const link=await doc.$('a[href*="portalo.category"]');
  check('found in-frame link', !!link);
  if(link){
    await link.click();
    await p.waitForTimeout(1600);
    doc=await (await p.$(sel)).contentFrame();
    const after=doc.url().replace(BASE,'');
    const tok=await doc.evaluate(`window.__tok || null`);
    console.log('  ', before, '->', after);
    check('screen actually changed', after.includes('portalo.category'), after);
    check('same document (boosted, no full load)', tok==='SURVIVE', 'window token='+tok);
    check('inspect param rides along in links', after.includes('vp=')&&!after.includes('undefined'), after);
  }
}catch(e){console.log('PROBE ERROR:',e.message);fails++}
finally{ if(b)await b.close(); console.log(`\n==== ${fails?fails+' FAILED':'ALL PASSED'} ====`); }
