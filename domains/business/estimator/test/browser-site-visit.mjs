import { chromium } from 'playwright-core';
import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const key = 'local-browser-test';
const dev = spawn('npm', ['run', 'dev', '--', '--host', '127.0.0.1', '--port', '5189', '--strictPort'], { stdio: ['ignore', 'pipe', 'pipe'] });
await new Promise((resolve,reject) => {
 const timer=setTimeout(()=>reject(new Error('Dev server did not start')),15000);
 dev.stdout.on('data',data=>{ if(data.toString().includes('Local:')){clearTimeout(timer);resolve();} });
 dev.on('exit',code=>reject(new Error(`Dev server exited: ${code}`)));
});
const browser = await chromium.launch({ executablePath:process.env.CHROMIUM_PATH || '/run/current-system/sw/bin/chromium', headless:true });
try {
 const prepared=JSON.parse(readFileSync(new URL('../src/data/preparedDraft.json',import.meta.url),'utf8'));
 const fresh=await browser.newContext({viewport:{width:390,height:900}});
 const ready=await fresh.newPage();
 await ready.addInitScript(()=>{
   localStorage.setItem('hwc-webhook-base','https://example.test/webhook');
   localStorage.setItem('hwc-api-key','test');
 });
 await ready.route('**/webhook/jt-customers?*',r=>r.fulfill({json:{customers:[{id:prepared.state.customerId,name:'Carrie'}]}}));
 await ready.route('**/webhook/jt-jobs?*',r=>r.fulfill({json:{jobs:[{id:prepared.state.jobId,name:prepared.state.jobName,number:411,displayName:'#411'}]}}));
 await ready.goto('http://127.0.0.1:5189/');
 assert.equal(await ready.getByLabel('Site notes and open questions').inputValue(),prepared.state.site_notes);
 await ready.getByLabel('Job',{exact:true}).locator(`option[value="${prepared.state.jobId}"]`).waitFor({state:'attached'});
 assert.equal(await ready.getByLabel('Job',{exact:true}).inputValue(),prepared.state.jobId);
 await ready.getByLabel('Room Length feet',{exact:true}).selectOption('9');
 await ready.getByLabel('Site notes and open questions').fill('Answers saved on site.');
 await ready.reload();
 assert.equal(await ready.getByLabel('Site notes and open questions').inputValue(),'Answers saved on site.');
 assert.equal(await ready.getByLabel('Room Length feet',{exact:true}).inputValue(),'9');
 console.log('PASS prepared Carrie worksheet boots automatically and preserves answers on reload');
 await fresh.close();
for (const width of [390,768,1440]) {
 const context = await browser.newContext({ viewport:{width,height:900}, ignoreHTTPSErrors:true, serviceWorkers:'block' });
 const page = await context.newPage();
 const errors=[]; page.on('pageerror',e=>errors.push(e.message));
 await page.route(/\/api\/jobs\/[^/]+\/calculator-intake$/, route => route.fulfill({status:404,contentType:'application/json',body:'{}'}));
 await page.addInitScript(({key}) => {
   if (!localStorage.getItem('hwc-estimate-state')) localStorage.setItem('hwc-estimate-state',JSON.stringify({projectType:'bathroom'}));
   localStorage.setItem('hwc-webhook-base','https://hwc-work.ocelot-wahoo.ts.net/webhook');
   localStorage.setItem('hwc-api-key',key);
   localStorage.setItem('hwc-webhook-url','https://hwc-work.ocelot-wahoo.ts.net/webhook/estimate-push');
 },{key});
 await page.route('**/webhook/jt-customers?*', route => {
   const page2=new URL(route.request().url()).searchParams.get('page');
   return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({version:1,customers:page2 ? [{id:'customer-test',name:'Site visit customer',locations:[]}] : [{id:'first',name:'First',locations:[]}],nextPage:page2 ? null:'page-two'})});
 });
 await page.route('**/webhook/jt-jobs?*', route => route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({jobs:[{id:'job-test',name:'Bathroom project',number:411,displayName:'#411 - Bathroom project'}]})}));
 await page.goto(process.env.ESTIMATOR_TEST_URL || 'http://127.0.0.1:5189/');
 await page.getByLabel('Customer',{exact:true}).locator('option[value="customer-test"]').waitFor({state:'attached'});
 await page.getByLabel('Customer',{exact:true}).selectOption('customer-test');
 await page.getByLabel('Job',{exact:true}).locator('option[value="job-test"]').waitFor({state:'attached'});
 await page.getByLabel('Job',{exact:true}).selectOption('job-test');
 await page.getByLabel('Shower finish',{exact:true}).selectOption('panel');
 await page.getByLabel('Floor finish',{exact:true}).selectOption('vinyl');
 await page.getByLabel('Shower enclosure',{exact:true}).selectOption('no');
 assert.equal(await page.getByLabel('Room Length feet',{exact:true}).evaluate(e=>e.tagName),'SELECT');
 assert.equal(await page.locator('input[type=number]').count(),0);
 await page.getByLabel('Room Length feet',{exact:true}).selectOption('9');
 await page.getByLabel('Room Length inches',{exact:true}).selectOption('6');
 await page.getByLabel('Room Width feet',{exact:true}).selectOption('6');
 await page.getByLabel('Room Width inches',{exact:true}).selectOption('0');
 assert.equal(await page.getByLabel('Flooring area',{exact:true}).inputValue(),'57');
 await page.getByLabel('Room Length inches',{exact:true}).selectOption('6.25');
 assert.equal(await page.getByLabel('Flooring area',{exact:true}).inputValue(),'57.125');
 await page.getByLabel('Room Length inches',{exact:true}).selectOption('6');
 await page.getByLabel('Panel installation',{exact:true}).selectOption('12');
 await page.getByLabel('Drain hookup',{exact:true}).selectOption('2');
 await page.getByLabel('Floor installation',{exact:true}).selectOption('6');
 await page.getByLabel('Subfloor preparation',{exact:true}).selectOption('0');
 await page.getByLabel('Flooring area',{exact:true}).selectOption('54');
 await page.getByLabel('Site notes and open questions').fill('Verify subfloor, fixture models, and customer purchase budget.');
 await page.getByRole('button',{name:'Measurements verified on site',exact:true}).click();
 const layout = await page.evaluate(() => ({ width:innerWidth,scroll:document.documentElement.scrollWidth,
  columns:getComputedStyle(document.querySelector('.form-grid')).gridTemplateColumns,
  small:[...document.querySelectorAll('input:not([type=file]), select,button')].filter(e=>e.getBoundingClientRect().height>0 && e.getBoundingClientRect().height<44).map(e=>e.outerHTML.slice(0,100)),
  fonts:[...document.querySelectorAll('input:not([type=file]),select,textarea')].filter(e=>e.getBoundingClientRect().height>0 && parseFloat(getComputedStyle(e).fontSize)<16).length }));
 assert.equal(layout.scroll, width,JSON.stringify(layout)); assert.equal(layout.small.length,0,JSON.stringify(layout));
 if(width<1024) assert.equal(layout.fonts,0);
 await page.getByRole('button',{name:'Details',exact:true}).click();
 await page.getByLabel('Panel shower kit material cost').fill('1100');
 await page.getByLabel('Floor covering material cost').fill('400');
 await page.getByRole('button',{name:'HWC supplies Vanity',exact:true}).click();
 await page.getByRole('button',{name:'HWC supplies Toilet',exact:true}).click();
 await page.getByRole('button',{name:/^Budget \(/}).click();
 assert.equal(await page.locator('.estimate-issues').count(),0,await page.locator('.estimate-issues').allTextContents());
 const qty = page.getByLabel('Quantity: Labor | Finish Carpentry | Install Panel Shower',{exact:true});
 if (width<1024) {
  await qty.fill('13.25'); await qty.press('End'); await qty.press('0');
  assert.equal(Number(await qty.inputValue()),13.25);
  assert.equal(await qty.evaluate(e=>document.activeElement===e),true);
  await page.getByRole('button',{name:'Scope',exact:true}).first().click();
  await page.getByRole('button',{name:'Assemble Estimate',exact:true}).click();
  assert.equal(await qty.inputValue(),'13.25');
  await page.reload(); await page.getByRole('button',{name:/^Budget \(/}).click();
  assert.equal(await qty.inputValue(),'13.25');
 }
 const downloadWait = page.waitForEvent('download');
 await page.getByRole('button',{name:'Download draft',exact:true}).click();
 const download = await downloadWait;
 const saved=JSON.parse(readFileSync(await download.path(),'utf8'));
 assert.equal(saved.jobId,'job-test'); assert.equal(saved.site_notes,'Verify subfloor, fixture models, and customer purchase budget.');
 assert.equal(saved.bathroom_length_ft,9.5); assert.equal(saved.bathroom_floor_sqft,54);
 let sent;
 await page.route('**/webhook/estimate-push', async route => {
   sent=route.request().postDataJSON();
   await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({success:true,jtPushSuccess:true,jobNumber:411,itemsPushed:sent.jtPayload.length})});
 });
 await page.getByRole('button',{name:'Push to JT',exact:true}).click();
 await page.getByText('Pushed to JobTread',{exact:true}).waitFor();
 assert.equal(sent.jobId,'job-test');
 assert.ok(sent.jtPayload.every(i => Number.isFinite(i.quantity) && i.quantityFormula === undefined));
 if(width<1024) assert.equal(sent.jtPayload.find(i=>i.name==='Labor | Finish Carpentry | Install Panel Shower').quantity,13.25);
 assert.equal(await page.getByRole('button',{name:'Pushed to JT',exact:true}).isDisabled(),true);
 assert.deepEqual(errors,[]);
 console.log('PASS',width,JSON.stringify(layout));
 await context.close();

 const intakeContext = await browser.newContext({ viewport:{width,height:900}, ignoreHTTPSErrors:true, serviceWorkers:'block' });
 const intakePage = await intakeContext.newPage();
 const intakeErrors=[]; intakePage.on('pageerror',e=>intakeErrors.push(e.message));
 await intakePage.addInitScript(() => {
   localStorage.setItem('hwc-webhook-base','https://test.invalid/webhook'); localStorage.setItem('hwc-api-key','fixture');
 });
 await intakePage.route('**/webhook/jt-customers?*', r=>r.fulfill({json:{customers:[{id:'c',name:'Calculator customer'}]}}));
 await intakePage.route('**/webhook/jt-jobs?*', r=>r.fulfill({json:{jobs:[{id:'job-carrie',name:'Bathroom',displayName:'#411 Bathroom',number:411},{id:'other',name:'Other',displayName:'#412 Other',number:412}]}}));
 const intake = { schema_version:1,jt_job_id:'job-carrie',lead_id:'fixture',calculator:'bathroom',report_id:'i682fxmu',rough_estimate:{low:20000,high:29000},
   answers:{project_type:'refresh',bathroom_size:'medium',shower_tub:'shower_only',tile_level:'basic',fixtures:'upgraded',timeline:'asap',features:['niches','new_toilet','lighting','mirror','door','glass_door']} };
 let waitingRoute;
 await intakePage.route(/\/api\/jobs\/[^/]+\/calculator-intake$/, async r=> {
   if (r.request().url().includes('/other/')) return r.fulfill({status:404,json:{}});
   waitingRoute=r;
 });
 await intakePage.goto('http://127.0.0.1:5189/');
 await intakePage.getByLabel('Customer',{exact:true}).selectOption('c');
 await intakePage.getByLabel('Job',{exact:true}).locator('option[value="job-carrie"]').waitFor({state:'attached'});
 await intakePage.getByLabel('Job',{exact:true}).selectOption('job-carrie');
 await intakePage.getByText('Loading customer inputs…',{exact:true}).waitFor();
 await intakePage.getByRole('button',{name:'Measurements verified on site',exact:true}).click();
 await intakePage.getByRole('button',{name:/^Budget \(/}).click();
 assert.match(await intakePage.locator('.estimate-issues').innerText(),/Customer inputs have not loaded/);
 assert.equal(await intakePage.getByRole('button',{name:'Push to JT',exact:true}).isDisabled(),true);
 waitingRoute=undefined;
 await intakePage.getByRole('button',{name:'Scope',exact:true}).first().click();
 await intakePage.getByText('Loading customer inputs…',{exact:true}).waitFor();
 await intakePage.getByLabel('Room Width feet',{exact:true}).selectOption('7');
 for (let count=0;!waitingRoute && count<20;count++) await intakePage.waitForTimeout(100);
 assert.ok(waitingRoute,await intakePage.locator('.customer-inputs').allTextContents());
 await waitingRoute.fulfill({json:intake});
 await intakePage.getByText('Customer calculator inputs',{exact:true}).waitFor({timeout:5000});
 assert.equal(await intakePage.getByLabel('Room Length feet',{exact:true}).inputValue(),'');
 assert.equal(await intakePage.getByLabel('Room Width feet',{exact:true}).inputValue(),'7');
 assert.equal(await intakePage.getByLabel('Niches',{exact:true}).inputValue(),'unknown');
 assert.equal(await intakePage.getByRole('button',{name:'Toilet',exact:true}).getAttribute('aria-pressed'),'true');
 assert.equal(await intakePage.getByLabel('Shower enclosure',{exact:true}).inputValue(),'yes');
 await intakePage.getByLabel('Site notes and open questions').fill('Retain this site note');
 await intakePage.getByRole('button',{name:/^Budget \(/}).click();
 assert.match(await intakePage.locator('.estimate-issues').innerText(),/Measure bathroom length ft/);
 assert.equal(await intakePage.getByRole('button',{name:'Push to JT',exact:true}).isDisabled(),true);
 await intakePage.getByRole('button',{name:'Scope',exact:true}).first().click();
 await intakePage.getByLabel('Job',{exact:true}).selectOption('other');
 assert.equal(await intakePage.getByLabel('Site notes and open questions').inputValue(),'');
 assert.equal(await intakePage.getByText('Customer calculator inputs',{exact:true}).count(),0);
 await intakePage.getByLabel('Job',{exact:true}).selectOption('job-carrie');
 assert.equal(await intakePage.getByLabel('Site notes and open questions').inputValue(),'Retain this site note');
 assert.equal(await intakePage.getByLabel('Room Width feet',{exact:true}).inputValue(),'7');
 await intakePage.reload();
 await intakePage.getByText('Customer calculator inputs',{exact:true}).waitFor();
 assert.equal(await intakePage.getByLabel('Room Width feet',{exact:true}).inputValue(),'7');
 assert.equal(await intakePage.evaluate(()=>document.documentElement.scrollWidth),width);
 assert.deepEqual(intakeErrors,[]);
 await intakePage.getByRole('button',{name:'New Customer',exact:true}).click();
 await intakePage.getByPlaceholder('Customer name',{exact:true}).fill('Keep new customer');
 await intakePage.getByPlaceholder('e.g. Master Bath Remodel',{exact:true}).fill('Keep new job');
 await intakePage.getByRole('button',{name:'Existing Job',exact:true}).click();
 await intakePage.getByRole('button',{name:'New Customer',exact:true}).click();
 assert.equal(await intakePage.getByPlaceholder('Customer name',{exact:true}).inputValue(),'Keep new customer');
 assert.equal(await intakePage.getByPlaceholder('e.g. Master Bath Remodel',{exact:true}).inputValue(),'Keep new job');
 console.log('PASS calculator intake, measured-edit preservation and job switching',width);
 await intakeContext.close();
}
} finally { await browser.close(); dev.kill('SIGTERM'); }
