import { chromium } from 'playwright-core';
import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
const key = 'local-browser-test';
const mappings = JSON.parse(readFileSync(new URL('../src/data/jtMappings.json', import.meta.url), 'utf8'));
const rates = JSON.parse(readFileSync(new URL('../src/data/tradeRates.json', import.meta.url), 'utf8'));
const dev = spawn('npm', ['run', 'dev', '--', '--host', '127.0.0.1', '--port', '5189', '--strictPort'], { stdio: ['ignore', 'pipe', 'pipe'] });
await new Promise((resolve,reject) => {
 const timer=setTimeout(()=>reject(new Error('Dev server did not start')),15000);
 dev.stdout.on('data',data=>{ if(data.toString().includes('Local:')){clearTimeout(timer);resolve();} });
 dev.on('exit',code=>reject(new Error(`Dev server exited: ${code}`)));
});
let calculatorDev;
const browser = await chromium.launch({ executablePath:process.env.CHROMIUM_PATH || '/run/current-system/sw/bin/chromium', headless:true });
try {
 if (!process.env.CALCULATOR_TEST_ONLY && !process.env.FLOORING_TEST_ONLY) {
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
 await page.route('**/webhook/jt-jobs?*', route => route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({jobs:[{id:'job-test',name:'Bathroom project',number:411,displayName:'#411 - Bathroom project'},{id:'other-test',name:'Other fixture',number:412,displayName:'#412'}]})}));
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
 // Additional scope uses the real form, saved draft, engine and send payload.
 const customForm = page.getByRole('form', {name:'Custom item'});
 await customForm.getByLabel('Item name',{exact:true}).fill('Window trim');
 await customForm.getByLabel('Quantity',{exact:true}).fill('12.5');
 await customForm.getByLabel('Unit',{exact:true}).selectOption('Linear Feet');
 await customForm.getByLabel('Cost code',{exact:true}).selectOption('1700');
 await customForm.getByRole('button',{name:'Add item',exact:true}).click();
 await page.getByRole('button',{name:/^Budget \(/}).click();
 assert.match(await page.locator('.estimate-issues').innerText(),/Enter the cost for Window trim in Details/);
 assert.equal(await page.getByRole('button',{name:'Push to JT',exact:true}).isDisabled(),true);
 await page.getByRole('button',{name:'Details',exact:true}).click();
 await page.getByRole('button',{name:'Edit Window trim',exact:true}).click();
 await customForm.getByLabel('Unit cost',{exact:true}).fill('4');
 await customForm.getByRole('button',{name:'Save item',exact:true}).click();
 await customForm.getByLabel('Item name',{exact:true}).fill('Window installation quote');
 await customForm.getByLabel('Cost type',{exact:true}).selectOption('Subcontractor');
 await customForm.getByLabel('Cost code',{exact:true}).selectOption('1300');
 await customForm.getByLabel('Unit',{exact:true}).selectOption('Lump Sum');
 await customForm.getByLabel('Unit cost',{exact:true}).fill('800');
 await customForm.getByRole('button',{name:'Add item',exact:true}).click();
 await customForm.getByLabel('Item name',{exact:true}).fill('Move supply lines');
 await customForm.getByLabel('Cost type',{exact:true}).selectOption('Labor');
 await customForm.getByLabel('Trade rate',{exact:true}).selectOption('plumbing');
 await customForm.getByLabel('Quantity',{exact:true}).fill('3.5');
 assert.equal(await customForm.getByLabel('Unit',{exact:true}).inputValue(),'Hours');
 assert.equal(await customForm.getByLabel('Unit cost',{exact:true}).isDisabled(),true);
 await customForm.getByRole('button',{name:'Add item',exact:true}).click();
 const customBefore = await page.evaluate(()=>JSON.parse(localStorage.getItem('hwc-estimate-state-v3')).custom_items);
 await page.getByRole('button',{name:/^Budget \(/}).click();
 await page.getByLabel('Quantity: Window trim',{exact:true}).fill('14');
 await page.getByRole('button',{name:'Details',exact:true}).click();
 await page.getByRole('button',{name:'Edit Window trim',exact:true}).click();
 assert.equal(await customForm.getByLabel('Quantity',{exact:true}).inputValue(),'14');
 await customForm.getByLabel('Quantity',{exact:true}).fill('15');
 await customForm.getByLabel('Unit cost',{exact:true}).fill('5');
 await customForm.getByRole('button',{name:'Cancel edit',exact:true}).click();
 await page.getByRole('button',{name:'Edit Window trim',exact:true}).click();
 assert.equal(await customForm.getByLabel('Unit cost',{exact:true}).inputValue(),'4');
 await customForm.getByLabel('Quantity',{exact:true}).fill('15');
 await customForm.getByRole('button',{name:'Save item',exact:true}).click();
 await page.reload();
 await page.getByRole('button',{name:'Details',exact:true}).click();
 const customLayout = await page.evaluate(()=>({scroll:document.documentElement.scrollWidth,
   small:[...document.querySelectorAll('.custom-items input,.custom-items select,.custom-items button')].filter(e=>e.getBoundingClientRect().height<44).length}));
 assert.equal(customLayout.scroll,width);assert.equal(customLayout.small,0);
 const customAfter = await page.evaluate(()=>JSON.parse(localStorage.getItem('hwc-estimate-state-v3')).custom_items);
 assert.equal(customAfter.length,3);
 assert.deepEqual(customAfter.map(i=>i.draftId),customBefore.map(i=>i.draftId));
 assert.equal(customAfter[0].qty,15);assert.equal(customAfter[0].cost,4);
 await customForm.getByLabel('Item name',{exact:true}).fill('Optional work');
 await customForm.getByLabel('Quantity',{exact:true}).fill('-1');
 await customForm.getByRole('button',{name:'Add item',exact:true}).click();
 assert.equal(await page.getByRole('button',{name:'Edit Optional work',exact:true}).count(),0);
 await customForm.getByLabel('Quantity',{exact:true}).fill('1');
 await customForm.getByRole('button',{name:'Add item',exact:true}).click();
 await page.getByRole('button',{name:/^Budget \(/}).click();
 await page.getByRole('button',{name:'Remove Optional work',exact:true}).click();
 await page.getByRole('button',{name:'Details',exact:true}).click();
 await page.getByRole('button',{name:'Edit Optional work',exact:true}).click();
 await customForm.getByLabel('Quantity',{exact:true}).fill('2');
 await customForm.getByRole('button',{name:'Save item',exact:true}).click();
 await page.getByText('Excluded from budget. Restore removed items in Budget to include it.',{exact:true}).waitFor();
 await page.getByRole('button',{name:/^Budget \(/}).click();
 assert.equal(await page.getByLabel('Quantity: Optional work',{exact:true}).count(),0);
 assert.equal(await page.locator('.estimate-issues').count(),0);
 await page.getByRole('button',{name:'Details',exact:true}).click();
 await page.getByRole('button',{name:'Delete Optional work',exact:true}).click();
 assert.deepEqual(await page.evaluate(()=>JSON.parse(localStorage.getItem('hwc-estimate-state-v3')).custom_items),customAfter);
 await page.getByRole('button',{name:'Scope',exact:true}).first().click();
 await page.getByLabel('Job',{exact:true}).selectOption('other-test');
 assert.deepEqual(await page.evaluate(()=>JSON.parse(localStorage.getItem('hwc-estimate-state-v3')).custom_items),[]);
 await page.getByLabel('Job',{exact:true}).selectOption('job-test');
 assert.deepEqual(await page.evaluate(()=>JSON.parse(localStorage.getItem('hwc-estimate-state-v3')).custom_items),customAfter);

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
 assert.deepEqual(saved.custom_items,customAfter);
 let sent;
 // Manual-entry draft still reads current server budget ownership at Send.
 await page.route('**/api/jobs/*/preliminary-budget',r=>r.fulfill({json:{schema_version:1,preliminary_budget:{schema_version:1,state:'completed',quote_hold:true}}}));
 await page.getByRole('button',{name:'Push to JT',exact:true}).click();
 await page.getByText(/Sending here would append another budget/).waitFor();
 assert.equal(sent,undefined);
 await page.route('**/api/jobs/*/preliminary-budget',r=>r.fulfill({json:{schema_version:1,preliminary_budget:null}}));
 await page.route('**/webhook/estimate-push', async route => {
   sent=route.request().postDataJSON();
   await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({success:true,jtPushSuccess:true,jobNumber:411,itemsPushed:sent.jtPayload.length})});
 });
 await page.getByRole('button',{name:'Push to JT',exact:true}).click();
 await page.getByText('Pushed to JobTread',{exact:true}).waitFor();
 assert.equal(sent.jobId,'job-test');
 const trim=sent.jtPayload.find(i=>i.name==='Window trim');
 assert.equal(trim.quantity,15);assert.equal(trim.unitCost,4);assert.equal(trim.unitPrice,5.71);
 assert.equal(trim.costCodeId,mappings.codes['1700']);assert.equal(trim.unitId,mappings.units['Linear Feet']);
 const quote=sent.jtPayload.find(i=>i.name==='Window installation quote');
 assert.equal(quote.quantity,1);assert.equal(quote.unitCost,800);assert.equal(quote.unitPrice,1142.88);
 assert.equal(quote.costTypeId,mappings.types.Subcontractor);assert.equal(quote.unitId,mappings.units['Lump Sum']);
 const labor=sent.jtPayload.find(i=>i.name==='Move supply lines');
 assert.equal(labor.quantity,3.5);assert.equal(labor.unitId,mappings.units.Hours);
 assert.equal(labor.unitCost,Math.round(rates.plumbing.wage*rates.plumbing.burden*100)/100);
 assert.equal(labor.unitPrice,Math.round(labor.unitCost*rates.plumbing.markup*100)/100);

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
 }

 if (!process.env.CALCULATOR_TEST_ONLY) for (const width of [390, 768, 1440]) {
   const context = await browser.newContext({viewport:{width,height:900},serviceWorkers:'block'});
   const page = await context.newPage(); const errors=[]; page.on('pageerror',e=>errors.push(e.message));
   const legacy = JSON.stringify({state_version:2,projectType:'bathroom',mode:'existing',jobId:'floor-test',customerId:'floor-customer',jobName:'Flooring fixture',calculator_input_status:'none'});
   await page.addInitScript(legacy=>{
     if (!localStorage.getItem('hwc-estimate-state')) localStorage.setItem('hwc-estimate-state',legacy);
     localStorage.setItem('hwc-webhook-base','https://example.test/webhook');
     localStorage.setItem('hwc-webhook-url','https://example.test/webhook/estimate-push');
     localStorage.setItem('hwc-api-key','fixture');
   },legacy);
   await page.route('**/webhook/jt-customers?*',r=>r.fulfill({json:{customers:[{id:'floor-customer',name:'Flooring fixture'}]}}));
   await page.route('**/webhook/jt-jobs?*',r=>r.fulfill({json:{jobs:[{id:'floor-test',name:'Flooring fixture',number:1,displayName:'#1'},{id:'other-floor',name:'Other fixture',number:2,displayName:'#2'}]}}));
   await page.route('**/api/jobs/*/calculator-intake',r=>r.fulfill({status:404,json:{}}));
   await page.route('**/api/jobs/*/preliminary-budget',r=>r.fulfill({json:{schema_version:1,preliminary_budget:null}}));
   let sent;
   await page.route('**/webhook/estimate-push',r=>{
     sent=r.request().postDataJSON();
     return r.fulfill({json:{success:true,jtPushSuccess:true,jobNumber:1,itemsPushed:sent.jtPayload.length}});
   });
   await page.goto(process.env.ESTIMATOR_TEST_URL || 'http://127.0.0.1:5189/');
   await page.getByLabel('Project Type',{exact:true}).selectOption('flooring');
   assert.equal(await page.getByLabel('Room Length feet',{exact:true}).count(),0);
   await page.getByRole('button',{name:/^Budget \(/}).click();
   assert.match(await page.locator('.estimate-issues').innerText(),/Add at least one flooring area/);
   assert.equal(await page.getByRole('button',{name:'Push to JT',exact:true}).isDisabled(),true);
   await page.getByRole('button',{name:'Scope',exact:true}).first().click();
   for (const [name,finish,net,cost,hours] of [['Living','lvp',101,3,8],['Entry','tile',40,6,6]]) {
     await page.getByRole('button',{name:'Add flooring area',exact:true}).click();
     await page.getByLabel('Area name',{exact:true}).fill(name);
     await page.getByLabel('Flooring',{exact:true}).selectOption(finish);
     await page.getByLabel('Substrate',{exact:true}).selectOption('wood');
     await page.getByLabel('Substrate reviewed for chosen product',{exact:true}).selectOption('yes');
     await page.getByLabel('Floor product supplied by',{exact:true}).selectOption('hwc');
     await page.getByLabel('Existing flooring removal',{exact:true}).selectOption('none');
     await page.getByLabel('Baseboard / shoe molding',{exact:true}).selectOption('none');
     for (const [label,value] of Object.entries({
       'Net area (sq ft)':net,'Floor product waste (%)':10,'Coverage per box (sq ft; 0 for loose product)':20,
       'Floor product cost per sq ft ($)':cost,'Installation hours':hours,
       'Subfloor preparation hours':0,'Subfloor preparation materials cost ($ total)':0,
       'Underlayment / membrane hours':0,'Underlayment / membrane cost ($ total)':0,'Transition count':0,
       ...(finish==='tile'?{'Tile setting materials cost ($ total)':50,'Grout cost ($ total)':30}:{}),
     })) await page.getByLabel(label,{exact:true}).fill(String(value));
   }
   for (const label of ['Moving and protection hours (whole job)','Cleanup hours (whole job)','Hauling / disposal cost ($ whole job)']) await page.getByLabel(label,{exact:true}).fill('1');
   const layout=await page.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth,
     small:[...document.querySelectorAll('button,input:not([type=file]),select')].filter(e=>e.getBoundingClientRect().height>0&&e.getBoundingClientRect().height<44).length,
     fonts:[...document.querySelectorAll('input:not([type=file]),select,textarea')].filter(e=>e.getBoundingClientRect().height>0&&parseFloat(getComputedStyle(e).fontSize)<16).length}));
   assert.equal(layout.scroll,width);assert.equal(layout.small,0);if(width<1024)assert.equal(layout.fonts,0);
   await page.getByRole('button',{name:'Measurements verified on site',exact:true}).click();
   await page.getByRole('button',{name:/^Budget \(/}).click();
   assert.equal(await page.locator('.estimate-issues').count(),0);
   await page.getByLabel('Quantity: Living | Install flooring',{exact:true}).fill('9.5');
   await page.getByRole('button',{name:'Scope',exact:true}).first().click();
   await page.getByLabel('Area to edit',{exact:true}).selectOption({label:'2. Entry'});
   await page.getByLabel('Floor product supplied by',{exact:true}).selectOption('customer');
   // Area deletion and undo preserve the exact identity and quote fields.
   const snapshot=await page.evaluate(()=>JSON.parse(localStorage.getItem('hwc-estimate-state-v3')));
   await page.getByRole('button',{name:'Remove this area',exact:true}).click();
   assert.equal(await page.getByLabel('Area to edit',{exact:true}).locator('option').count(),1);
   await page.getByRole('button',{name:'Undo area removal',exact:true}).click();
   assert.equal(await page.getByLabel('Area name',{exact:true}).inputValue(),'Entry');
   assert.deepEqual(await page.evaluate(()=>JSON.parse(localStorage.getItem('hwc-estimate-state-v3')).flooring),snapshot.flooring);
   await page.getByLabel('Job',{exact:true}).selectOption('other-floor');
   await page.getByLabel('Job',{exact:true}).selectOption('floor-test');
   await page.getByLabel('Project Type',{exact:true}).waitFor();
   assert.equal(await page.getByLabel('Project Type',{exact:true}).inputValue(),'flooring');
   await page.getByLabel('Area to edit',{exact:true}).selectOption(snapshot.flooring.areas[1].id);
   await page.getByLabel('Grout cost ($ total)',{exact:true}).fill('');
   await page.getByRole('button',{name:/^Budget \(/}).click();
   assert.equal(await page.getByRole('button',{name:'Push to JT',exact:true}).isDisabled(),true);
   assert.match(await page.locator('.estimate-issues').innerText(),/Grout cost/);
   await page.getByRole('button',{name:'Scope',exact:true}).first().click();
   await page.getByLabel('Area to edit',{exact:true}).selectOption(snapshot.flooring.areas[1].id);
   await page.getByLabel('Grout cost ($ total)',{exact:true}).fill('30');
   await page.getByRole('button',{name:'Measurements verified on site',exact:true}).click();
   const downloadWait=page.waitForEvent('download');await page.getByRole('button',{name:'Download draft',exact:true}).click();
   const saved=JSON.parse(readFileSync(await (await downloadWait).path(),'utf8'));
   assert.equal(saved.state_version,3);assert.equal(saved.flooring.areas.length,2);
   await page.getByLabel('Import draft',{exact:true}).setInputFiles({name:'flooring.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(saved))});
   await page.reload();
   assert.equal(await page.evaluate(()=>localStorage.getItem('hwc-estimate-state')),legacy,'migration never overwrites legacy recovery data');
   await page.getByRole('button',{name:'Details',exact:true}).click();
   assert.equal(await page.getByLabel('Accessories material cost',{exact:true}).count(),0);
   await page.getByRole('button',{name:/^Budget \(/}).click();
   assert.equal(await page.locator('.estimate-issues').count(),0);
   await page.getByRole('button',{name:'Push to JT',exact:true}).click();
   await page.getByText('Pushed to JobTread',{exact:true}).waitFor();
   assert.equal(sent.projectType,'flooring');
   assert.deepEqual(sent.parameters,[{name:'flooring_area_sqft',value:141},{name:'flooring_area_count',value:2}]);
   assert.equal(sent.jtPayload.find(i=>i.name==='Living | Click-lock LVT / LVP').quantity,120);
   assert.equal(sent.jtPayload.find(i=>i.name==='Living | Install flooring').quantity,9.5);
   assert.equal(sent.jtPayload.find(i=>i.name==='Entry | Install flooring').quantity,6);
   assert.ok(!sent.jtPayload.some(i=>i.name==='Entry | Floor tile'));
   assert.equal(sent.jtPayload.find(i=>i.name==='Entry | Tile setting materials').unitCost,50);
   assert.equal(sent.jtPayload.filter(i=>i.name==='Moving and floor protection').length,1);
   assert.ok(sent.jtPayload.every(i=>i.costCodeId&&i.costTypeId&&i.unitId&&i.quantityFormula===undefined));
   assert.deepEqual(errors,[]);
   // Unsupported active data is downloadable and never silently replaced.
   const corrupt=JSON.stringify({...saved,state_version:99});
   await page.evaluate(raw=>localStorage.setItem('hwc-estimate-state-v3',raw),corrupt);
   await page.reload();await page.getByText(/Saved draft could not be loaded/).waitFor();
   assert.equal(await page.getByLabel('Project Type',{exact:true}).count(),0);
   assert.equal(await page.evaluate(()=>localStorage.getItem('hwc-estimate-state-v3')),corrupt);
   const recoverWait=page.waitForEvent('download');await page.getByRole('button',{name:'Download saved data',exact:true}).click();
   assert.equal(readFileSync(await (await recoverWait).path(),'utf8'),corrupt);
   await page.getByLabel('Import draft',{exact:true}).setInputFiles({name:'flooring.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(saved))});
   assert.equal(await page.getByLabel('Project Type',{exact:true}).inputValue(),'flooring');
   console.log('PASS multi-area flooring form, exact intercepted budget, migration and recovery',width);
   await context.close();
 }
 if (!process.env.FLOORING_TEST_ONLY) {
 // Exercise the public form and pass its actual serialized answers into the
 // linked-job estimator, instead of testing only a translation helper.
 if (!process.env.HWC_WEBSITE_SITE_DIR) throw Error('HWC_WEBSITE_SITE_DIR is required for calculator contract tests');
 calculatorDev = spawn('npm',['run','dev','--','--host','127.0.0.1','--port','5190','--strictPort'],{
   cwd:fileURLToPath(new URL('../../website/calculator/app/',import.meta.url)),stdio:['ignore','pipe','pipe'],env:process.env,
 });
 await new Promise((resolve,reject)=>{
   const timer=setTimeout(()=>reject(Error('Calculator dev server did not start')),15000);
   calculatorDev.stderr.on('data',data=>process.stderr.write(data));
   calculatorDev.stdout.on('data',data=>{if(data.toString().includes('Local:')){clearTimeout(timer);resolve();}});
   calculatorDev.on('exit',code=>reject(Error(`Calculator dev server exited: ${code}`)));
 });
 for (const width of [390,1440]) for (const kind of ['bathroom','deck']) {
   const context=await browser.newContext({viewport:{width,height:900},serviceWorkers:'block'});
   const page=await context.newPage();const errors=[];page.on('pageerror',e=>{errors.push(e.message);process.stderr.write(e.stack+'\n');});
   const data=JSON.parse(readFileSync(`${process.env.HWC_WEBSITE_SITE_DIR}/src/_data/calculator-${kind}.json`,'utf8'));
   await page.route('http://127.0.0.1:5190/',async r=>{
     const response=await r.fetch();
     const html=(await response.text()).replace('id="calculator-root"',`id="${kind==='bathroom'?'calculator-root':'deck-calculator-root'}"`);
     await r.fulfill({response,body:html});
   });
   let payload;
   await page.route('**/hooks/calculator',r=>{
     payload=r.request().postDataJSON();
     return r.fulfill({json:{saved:true,measurement_version:payload.measurement_version,submission_id:payload.submission_id,reportId:'contract-report',reportUrl:'https://example.test/report'}});
   });
   await page.goto('http://127.0.0.1:5190/');
   for (const step of data.steps) {
     await page.getByRole('heading',{name:step.question,exact:true}).waitFor();
     if(step.type==='multi') await page.getByRole('button',{name:'None of these — continue',exact:true}).click();
     else await page.locator('button[aria-pressed]').first().click();
   }
   await page.getByRole('heading',{name:'What do you already know about the space?',exact:true}).waitFor();
   if(kind==='bathroom') {
     await page.getByLabel('Room length',{exact:true}).fill('-1');
     await page.getByRole('button',{name:'Continue — unanswered details are fine',exact:true}).click();
     assert.equal(await page.getByLabel('Your name').count(),0,'invalid dimensions must block navigation');
     await page.getByLabel('Room length',{exact:true}).fill('9.5');
     await page.getByLabel('Room width',{exact:true}).fill('6');
     await page.getByLabel('Shower finish',{exact:true}).selectOption('panel');
     await page.getByLabel('Floor finish',{exact:true}).selectOption('vinyl');
     await page.getByLabel('Number of shower niches',{exact:true}).fill('0');
   } else {
     await page.getByLabel('Deck length',{exact:true}).fill('16');
     await page.getByLabel('Deck width',{exact:true}).fill('12');
     await page.getByLabel('Height above ground',{exact:true}).fill('0');
   }
   assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth),width);
   await page.getByRole('button',{name:'Continue — unanswered details are fine',exact:true}).click();
   await page.getByLabel('Your name').fill('Contract fixture');await page.getByLabel('Email address').fill('fixture@example.test');
   await page.getByRole('button',{name:'Show my estimate',exact:true}).click();
   await page.getByText('Project summary saved for',{exact:false}).first().waitFor();
   assert.equal(payload.projectState.intake_version,2);
   assert.equal(kind==='bathroom'?payload.projectState.bathroom_length_ft:payload.projectState.deck_length_ft,kind==='bathroom'?9.5:16);
   const received={preliminary_budget:{schema_version:1,state:'completed',quote_hold:true,budget_group_id:'fixture-budget'},schema_version:1,calculator:kind,answers:payload.projectState,rough_estimate:payload.estimate,report_id:'contract-report',lead_id:'fixture',jt_job_id:'contract-job'};
   await page.addInitScript(kind=>{
     localStorage.setItem('hwc-webhook-base','https://example.test/webhook');localStorage.setItem('hwc-api-key','test');
     localStorage.setItem('hwc-estimate-state',JSON.stringify({projectType:kind,mode:'existing',jobId:'contract-job',customerId:'fixture',touched_fields:[]}));
   },kind);
   await page.route('**/webhook/jt-customers?*',r=>r.fulfill({json:{customers:[{id:'fixture',name:'Contract fixture'}]}}));
   await page.route('**/webhook/jt-jobs?*',r=>r.fulfill({json:{jobs:[{id:'contract-job',name:'Fixture',number:1,displayName:'#1'}]}}));
   await page.route('**/api/jobs/contract-job/calculator-intake',r=>r.fulfill({json:received}));
   await page.goto('http://127.0.0.1:5189/');await page.getByText('Customer calculator inputs',{exact:true}).waitFor();
   if(kind==='bathroom') {
     assert.equal(await page.getByLabel('Room Length feet',{exact:true}).inputValue(),'9');
     assert.equal(await page.getByLabel('Room Length inches',{exact:true}).inputValue(),'6');
     assert.equal(await page.getByLabel('Shower finish',{exact:true}).inputValue(),'panel');
   } else {
     assert.equal(await page.getByLabel('Length feet',{exact:true}).inputValue(),'16');
   }
   await page.getByRole('button',{name:/^Budget \(/}).click();
   assert.equal(await page.getByRole('button',{name:'Push to JT',exact:true}).isDisabled(),true);
   assert.match(await page.locator('.estimate-issues').innerText(),/Verify measurements on site/);
   assert.match(await page.locator('.estimate-issues').innerText(),/append another budget/);
   assert.deepEqual(errors,[]);console.log('PASS calculator serialized answers -> linked estimator',kind,width);
   await context.close();
 }
}
} finally { await browser.close(); dev.kill('SIGTERM'); calculatorDev?.kill('SIGTERM'); }
