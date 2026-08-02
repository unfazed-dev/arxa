// probe-inspect.mjs — element inspect: arm, hover overlay, click-to-pin, and that pinning does NOT reload the inspected screen.
// Run against a live studio:
//   dart run appboxd/bin/appbox.dart design serve designs/appbox-studio --port 4319 --json --project portalo
//   node tools/probe-inspect.mjs
// Override with APPBOX_BASE / APPBOX_CHROME.
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { chromium } = await import(
  path.join(REPO, 'skills/appbox-designer/runtime/node_modules/playwright-core/index.mjs'));
const CHROME=process.env.APPBOX_CHROME||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const BASE=process.env.APPBOX_BASE||'http://localhost:4319';
const s=(p)=>p.waitForTimeout(900);
let b;
try{
  b=await chromium.launch({executablePath:CHROME,headless:true});
  const p=await b.newPage({viewport:{width:1600,height:1000}});
  const reqs=[]; p.on('request',r=>{ if(/inspect|context\/element/.test(r.url())) reqs.push(r.method()+' '+r.url().replace(BASE,'')); });
  const errs=[]; p.on('pageerror',e=>errs.push('page: '+e.message));
  p.on('console',m=>{ if(m.type()==='error') errs.push('console: '+m.text().slice(0,120)); });
  // Chrome's console line for a failed request names no URL, so a bare
  // "Failed to load resource: 404" is unactionable on its own. Name it.
  // Known exception: a console 404 with NO matching line here is Chrome's
  // automatic /favicon.ico fetch — the browser issues it, not the renderer, so
  // it reaches the console but never the CDP network events (verified: page-,
  // context- and requestfailed-level listeners all see nothing, and
  // GET /favicon.ico is a real 404 on this server). Cosmetic, not inspect.
  p.on('response',r=>{ if(r.status()>=400) errs.push(`http ${r.status()} ${r.url().replace(BASE,'')}`); });

  await p.goto(BASE+'/design',{waitUntil:'networkidle'}); await s(p);

  console.log('=== 1. click the inspect toggle on portalo.home ===');
  const tool = await p.$('.dv-tile[data-id="portalo.home"] a[hx-get*="inspect="]');
  console.log('  inspect tool button found :', !!tool);
  await p.$eval('.dv-tile[data-id="portalo.home"] a[hx-get*="inspect="]', el=>el.click());
  await s(p);

  const tile = await p.$('.dv-tile[data-id="portalo.home"]');
  console.log('  tile has .is-inspecting   :', await tile.evaluate(e=>e.classList.contains('is-inspecting')));
  const fr = await p.$('.dv-tile[data-id="portalo.home"] iframe');
  console.log('  iframe src                :', await fr.evaluate(e=>e.getAttribute('src')));
  console.log('  computed pointer-events   :', await fr.evaluate(e=>getComputedStyle(e).pointerEvents));

  const doc = await fr.contentFrame();
  const inside = await doc.evaluate(()=>({
    armed: document.body.dataset.inspectArmed,
    inspectLoaded: !!document._inspect,
    dataElCount: document.querySelectorAll('[data-el]').length,
    stylesheets: [...document.styleSheets].map(x=>(x.href||'inline').split('/').pop()),
    hasOutlineRule: [...document.styleSheets].some(sh=>{
      try{ return [...sh.cssRules].some(r=>r.selectorText && r.selectorText.includes('inspect-outline')); }catch{ return false; }
    }),
  }));
  console.log('  --- inside the iframe ---');
  console.log('  data-inspect-armed        :', inside.armed);
  console.log('  inspect.js executed       :', inside.inspectLoaded);
  console.log('  [data-el] elements present:', inside.dataElCount);
  console.log('  stylesheets loaded        :', inside.stylesheets.join(', '));
  console.log('  .inspect-outline CSS rule :', inside.hasOutlineRule);

  console.log('\n=== 2. hover a [data-el] element -> overlay? ===');
  const target = await doc.$('[data-el]');
  if(!target){ console.log('  !! no [data-el] element to hover'); }
  else{
    await target.hover(); await s(p);
    const ov = await doc.evaluate(()=>{
      const o=document.querySelector('.inspect-outline'), l=document.querySelector('.inspect-label');
      const cs=o?getComputedStyle(o):null;
      return { outlineExists:!!o, labelExists:!!l,
               position:cs?cs.position:null, zIndex:cs?cs.zIndex:null,
               visible:cs?(cs.display!=='none'&&cs.visibility!=='hidden'):null,
               labelText:l?l.textContent.slice(0,70):null };
    });
    console.log(' ', JSON.stringify(ov));
  }

  console.log('\n=== 3. click the element -> pin to composer context ===');
  const chipsBefore = await p.evaluate(`document.querySelectorAll('.cs-el-chip').length`);
  // does pinning reload the very screen being inspected?
  await p.evaluate(`[...document.querySelectorAll('iframe')].forEach((f,i)=>f.__pin='p'+i)`);
  const framesBefore = await p.evaluate(`document.querySelectorAll('iframe').length`);
  let navsOnPin = 0;
  const onNav = (f) => { if (f !== p.mainFrame()) navsOnPin++; };
  p.on('framenavigated', onNav);
  if(target){ await target.click({force:true}); await p.waitForTimeout(1600); }
  p.off('framenavigated', onNav);
  const chipsAfter = await p.evaluate(`document.querySelectorAll('.cs-el-chip').length`);
  const kept = await p.evaluate(`[...document.querySelectorAll('iframe')].filter(f=>f.__pin!==undefined).length`);
  console.log('  element chips before/after :', chipsBefore, '->', chipsAfter);
  console.log('  iframes surviving the pin  :', kept, '/', framesBefore, ' (re-navigations:', navsOnPin + ')');
  console.log('  requests seen              :', reqs.length? reqs.join('\n                               '):'(none)');
  console.log('\n=== errors ===');
  console.log(errs.length? errs.slice(0,6).map(e=>'  ! '+e).join('\n') : '  none');
}catch(e){console.log('PROBE ERROR:',e.message)}finally{if(b)await b.close()}
