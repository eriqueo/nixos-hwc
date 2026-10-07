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
for (const width of [390,768,1440]) {
 const context = await browser.newContext({ viewport:{width,height:900}, ignoreHTTPSErrors:true });
 const page = await context.newPage();
 const errors=[]; page.on('pageerror',e=>errors.push(e.message));
 await page.addInitScript(({key}) => {
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
}
} finally { await browser.close(); dev.kill('SIGTERM'); }
