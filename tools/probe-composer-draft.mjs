// probe-composer-draft.mjs — the hx-preserve pairing, in both shells that share
// the composer: a half-typed draft must SURVIVE an unrelated swap, and must be
// CLEARED by a send. Preserving on send would leave the sent text ready to be
// sent twice, so these two assertions only mean anything together.
//   node tools/probe-composer-draft.mjs      (APPBOX_BASE / APPBOX_CHROME to override)
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { chromium } = await import(
  path.join(REPO, 'skills/appbox-designer/runtime/node_modules/playwright-core/index.mjs'));
const CHROME=process.env.APPBOX_CHROME||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const BASE=process.env.APPBOX_BASE||'http://localhost:4319';
const ta='textarea[name="text"]';
let b,fails=0;
const ck=(n,ok,x='')=>{if(!ok)fails++;console.log(`  [${ok?'PASS':'FAIL'}] ${n}${x?' — '+x:''}`)};
try{
  b=await chromium.launch({executablePath:CHROME,headless:true});
  for (const shell of ['/design','/design/freeze']) {
    const p=await b.newPage({viewport:{width:1600,height:1000}});
    await p.goto(BASE+shell,{waitUntil:'networkidle'}); await p.waitForTimeout(900);
    console.log(`\n=== ${shell} ===`);
    // 1. an unrelated interaction must NOT eat the draft
    await p.fill(ta,'HALF TYPED DRAFT');
    const pin = await p.$('.dv-tile .dv-tile-tools a[hx-get*="context"], .cs-thumb');
    if (pin) { await pin.evaluate(e=>e.click()); await p.waitForTimeout(1500);
      ck('draft survives an unrelated swap', await p.$eval(ta,e=>e.value)==='HALF TYPED DRAFT'); }
    else console.log('  [skip] no pin control on this shell');
    // 2. sending must clear it
    await p.fill(ta,'MESSAGE TO SEND');
    await p.$eval('#composer', f=>f.requestSubmit?f.requestSubmit():f.submit());
    await p.waitForTimeout(1800);
    const v=await p.$eval(ta,e=>e.value).catch(()=>'(gone)');
    ck('textarea clears after send', v==='', JSON.stringify(v));
    await p.close();
  }
}catch(e){console.log('ERR',e.message);fails++}
finally{if(b)await b.close();console.log(`\n==== ${fails?fails+' FAILED':'ALL PASSED'} ====`)}
