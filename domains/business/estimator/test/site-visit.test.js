import assert from 'node:assert/strict';
import { register } from 'node:module';
import { readFileSync } from 'node:fs';
register(new URL('./json-import-hook.mjs', import.meta.url));
const { calculatorPatch, applyCalculatorIntake, switchJobDraft, DEFAULT_STATE } = await import('../src/hooks/useProjectState.js');
const calculatorIntake = { schema_version: 1, jt_job_id: 'job-carrie', lead_id: 'lead-carrie', calculator: 'bathroom', report_id: 'i682fxmu',
  rough_estimate: { low: 20000, high: 29000 }, answers: { fixtures: 'upgraded', timeline: 'asap', shower_tub: 'shower_only', tile_level: 'basic', project_type: 'refresh', bathroom_size: 'medium', features: ['niches', 'new_toilet', 'lighting', 'mirror', 'door', 'glass_door'] } };
const cp = calculatorPatch(calculatorIntake);
const { parseCalculatorIntake, CALCULATOR_FIELDS } = await import('../src/api/crm.js');
const detailed = { ...calculatorIntake, answers: { ...calculatorIntake.answers, intake_version:2,
  bathroom_length_ft:9.5, bathroom_width_ft:6, shower_finish:'panel', floor_finish:'vinyl', shower_niches:0 } };
assert.equal(parseCalculatorIntake(detailed, detailed.jt_job_id),detailed);
const filled = applyCalculatorIntake(startForDetails(), detailed);
function startForDetails() { return { ...DEFAULT_STATE,jobId:detailed.jt_job_id,touched_fields:['bathroom_width_ft'],bathroom_width_ft:7 }; }
assert.equal(filled.bathroom_length_ft,9.5); assert.equal(filled.bathroom_width_ft,7);
assert.equal(filled.shower_finish,'panel'); assert.equal(filled.has_shower_tile,'no');
assert.equal(filled.floor_finish,'vinyl'); assert.equal(filled.has_floor_tile,'no');
assert.equal(filled.shower_niches,'0'); assert.equal(filled.measurements_checked,'no');
for (const answers of [{intake_version:3},{intake_version:2,bathroom_length_ft:-1},
  {intake_version:2,bathroom_length_ft:0},{intake_version:2,bathroom_length_ft:'9'},
  {intake_version:2,shower_niches:1.5},{intake_version:2,floor_finish:'carpet'}]) {
  assert.throws(()=>parseCalculatorIntake({...calculatorIntake,answers},calculatorIntake.jt_job_id));
}
const deckIntake = { ...calculatorIntake,calculator:'deck',answers:{intake_version:2,deck_length_ft:16,deck_width_ft:12,deck_height_ft:0,railing_lf:0,stair_tread_count:0} };
assert.equal(calculatorPatch(deckIntake).deck_height_ft,0);
for (const calculator of ['bathroom','deck']) for (const f of CALCULATOR_FIELDS[calculator]) assert.ok(Object.hasOwn(DEFAULT_STATE,f.id));
const { buildSteps, makeCalculator } = await import('../../website/calculator/app/src/calcData.js');
assert.equal(buildSteps({calculator:'bathroom',steps:[]})[0].type,'details');
// Production catalog conditions use parentheses and SQL-style equality.
const conditionRange = makeCalculator({engine:'assembly',sizeMap:{medium:{}},showerTubMap:{tub_only:{has_tub:true}},scopeItems:[
  {item_type:'material',unit_price:2000,default_qty:1,condition_trigger:'has_tub AND (project_type = "full_gut" OR project_type = "tub_to_shower")'}]});
assert.deepEqual(conditionRange({shower_tub:'tub_only',project_type:'full_gut'}),[1500,2500]);
assert.deepEqual(conditionRange({shower_tub:'tub_only',project_type:'refresh'}),[0,0]);
assert.equal(cp.bathroom_length_ft, null);
assert.equal(cp.toilet_allowance, null);
assert.equal(cp.shower_niches, 'unknown');
assert.equal(cp.has_toilet, 'yes'); assert.equal(cp.new_electrical, 'yes');
assert.equal(cp.has_mirror, 'yes'); assert.equal(cp.has_new_door, 'yes'); assert.equal(cp.has_shower_door, 'yes');
const start = { ...DEFAULT_STATE, jobId: 'job-carrie', touched_fields: ['bathroom_width_ft'], bathroom_width_ft: 7 };
const prefilled = applyCalculatorIntake(start, calculatorIntake);
assert.equal(prefilled.bathroom_width_ft, 7); assert.equal(prefilled.bathroom_length_ft, null);
assert.equal(applyCalculatorIntake(prefilled, calculatorIntake), prefilled);
assert.equal(applyCalculatorIntake({ ...start, jobId: 'other' }, calculatorIntake).calculator_intake, undefined);
const stored = new Map(); const storage = { getItem: k => stored.get(k) ?? null, setItem: (k,v) => stored.set(k,v) };
const switched = switchJobDraft({ ...prefilled, site_notes: 'Keep my measurements', budget_overrides: { 'rule:1': 8 } }, { jobId: 'other' }, storage);
assert.equal(switched.site_notes, ''); assert.deepEqual(switched.budget_overrides, {});
const back = switchJobDraft(switched, { jobId: 'job-carrie' }, storage);
assert.equal(back.site_notes, 'Keep my measurements'); assert.equal(back.budget_overrides['rule:1'], 8);
assert.throws(() => switchJobDraft(prefilled, { jobId: 'other' }, { ...storage, setItem: () => { throw Error('quota'); } }));
const unassigned = { ...DEFAULT_STATE, site_notes: 'Before choosing a job', touched_fields: ['site_notes'] };
const assigned = switchJobDraft(unassigned, { mode:'existing',jobId:'first-job',customerId:'c' }, storage);
assert.equal(switchJobDraft(assigned, { mode:'existing',jobId:'',customerId:'' }, storage).site_notes, 'Before choosing a job');
const newCustomer = { ...DEFAULT_STATE, mode:'new_customer', newCustomerName:'Keep customer', site_notes:'Keep scope' };
const changedMode = switchJobDraft(newCustomer, { mode:'existing',jobId:'',customerId:'' }, storage);
assert.equal(switchJobDraft(changedMode, { mode:'new_customer',jobId:'',customerId:'' }, storage).newCustomerName,'Keep customer');
console.log('PASS calculator preferences, unknown measurements, manual edits and per-job isolation');
const engine = await import('../src/engine/assembler.js');
const { enrichState } = await import('../src/engine/geometry.js');
assert.ok(engine.estimateIssues({ ...DEFAULT_STATE, measurements_checked:'yes', calculator_input_status:'pending' }, []).some(i=>i.includes('have not loaded')));
assert.ok(engine.estimateIssues({ ...DEFAULT_STATE, measurements_checked:'yes', calculator_input_status:'failed' }, []).some(i=>i.includes('have not loaded')));
const fullyMeasured = { ...DEFAULT_STATE,calculator_intake:calculatorIntake,calculator_input_status:'ready',calculator_scope_checked:'yes',measurements_checked:'yes',shower_finish:'tile',floor_finish:'none',has_shower_door:'no',has_floor_tile:'no',shower_trim_allowance:null,accessory_allowance:null,has_toilet:'no',has_vanity:'no' };
const unpriced = engine.assemble(enrichState(fullyMeasured));
assert.ok(engine.estimateIssues(fullyMeasured,unpriced).some(i=>i.includes('shower trim allowance')));
assert.ok(engine.estimateIssues(fullyMeasured,unpriced).some(i=>i.includes('accessory allowance')));
const customerSupply = { ...fullyMeasured,include_shower_trim_material:'no',include_accessory_material:'no',new_electrical:'yes',include_electrical_material:'no',electrical_allowance:null };
assert.deepEqual(engine.estimateIssues(customerSupply,engine.assemble(enrichState(customerSupply))),[]);
const templates = (await import('../src/data/templates.json', { with: { type: 'json' } })).default;
const state = templates.find(t => t.project_type === 'bathroom').state;
const original = engine.assemble(enrichState(state));
const target = original.find(i => i.name.includes('Vanity') && i.type === 'Labor');
assert.ok(target);
const edits = { [`rule:${target._ruleId}`]: 9.25 };
assert.equal(engine.applyEdits(original, edits, {}) .find(i => i._ruleId === target._ruleId).qty, 9.25,
  'reviewed quantities must use stable rule identities');
const changed = engine.assemble(enrichState({ ...state, has_shower_tile: 'no' }));
assert.equal(engine.applyEdits(changed, edits, {}).find(i => i._ruleId === target._ruleId).qty, 9.25);
const reviewed = engine.applyEdits(original, edits, {});
const payload = engine.buildJtItems(reviewed);
assert.equal(payload[reviewed.indexOf(reviewed.find(i => i._ruleId === target._ruleId))].quantity, 9.25);
assert.ok(payload.every(i => i.quantityFormula === undefined && Number.isFinite(i.quantity)), 'push exact reviewed quantities, including waste');
console.log('PASS stable edits across scope changes and exact JobTread quantities');
for (const projectType of ['bathroom','deck']) {
  const customState = { ...state, projectType, measurements_checked:'yes', custom_items:[
    { draftId:'quote', name:'Window quote', qty:1, cost:0, type:'Subcontractor', unit:'Lump Sum', code:'1300' },
  ] };
  const assembled = engine.assemble(enrichState(customState));
  assert.ok(engine.estimateIssues(customState,assembled).includes('Enter the cost for Window quote in Details.'));
  const excluded = engine.applyEdits(assembled,{}, { 'custom:quote':true });
  assert.ok(!engine.estimateIssues(customState,excluded).some(issue=>issue.includes('Window quote')));
  customState.custom_items[0].cost=800;
  const priced = engine.assemble(enrichState(customState));
  assert.ok(!engine.estimateIssues(customState,priced).some(issue=>issue.includes('Window quote')));
}
console.log('PASS unpriced custom scope blocks sending only while included, for bathroom and deck');

const panelState = { ...state, projectType: 'bathroom', measurements_checked: 'yes', shower_finish: 'panel', floor_finish: 'vinyl', has_shower_tile: 'no', has_floor_tile: 'no',
  has_shower_door: 'no', has_toilet: 'yes', shower_niches: '0', panel_install_hours: 12, panel_drain_hours: 2, panel_material_allowance: 1100,
  floor_install_hours: 6, floor_prep_hours: 1.5, floor_material_allowance: 400,
  include_toilet_material: 'no', include_vanity_material: 'no', include_shower_trim_material: 'no' };
const panel = engine.assemble(enrichState(panelState));
assert.equal(panel.find(i => i.name === 'Labor | Finish Carpentry | Install Panel Shower')?.qty, 12);
assert.equal(panel.find(i => i.name === 'Labor | Flooring | Install Vinyl or Marmoleum')?.qty, 6);
assert.equal(panel.find(i => i.name === 'Allowance | Panel Shower Kit')?.uc, 1100);
assert.ok(panel.some(i => i.name === 'Labor | Finish Carpentry | Install Vanity'));
assert.ok(panel.some(i => i.name === 'Labor | Plumbing | Install Toilet'));
assert.ok(!panel.some(i => ['Allowance | Vanity', 'Allowance | Toilet', 'Allowance | Shower Trim'].includes(i.name)));
assert.ok(!panel.some(i => i.name.includes('Material | Tile |') || i.name.includes('Labor | Tile |')));
console.log('PASS panel and vinyl work with customer purchases and retained installation');
assert.ok(engine.estimateIssues({ ...panelState, projectType: 'bathroom' }, panel).length === 0);
assert.ok(engine.estimateIssues({ ...panelState, panel_install_hours: null }, panel).some(i => i.includes('panel installation')));
assert.ok(engine.estimateIssues({ ...panelState, floor_prep_hours: null }, panel).some(i => i.includes('subfloor')));
const niche = engine.assemble(enrichState({ ...state, has_shower_tile: 'yes', shower_niches: '2' })).find(i => i._ruleId === 26);
assert.equal(niche.qty, 8);
console.log('PASS missing input checks and four hours per tile niche');
const { parseDraft } = await import('../src/hooks/useProjectState.js');
const { applyPreparedDraft } = await import('../src/hooks/useProjectState.js');
const actualPrepared = (await import('../src/data/preparedDraft.json', { with: { type:'json' } })).default;
const combined = applyCalculatorIntake(applyPreparedDraft(null), { ...calculatorIntake, jt_job_id:actualPrepared.state.jobId });
assert.equal(combined.target_budget,10000); assert.equal(combined.bathroom_floor_sqft,54);
assert.equal(combined.shower_finish,'panel'); assert.equal(combined.floor_finish,'vinyl');
assert.equal(combined.bathroom_length_ft,null); assert.equal(combined.vanity_allowance,null);
assert.equal(combined.calculator_intake.report_id,'i682fxmu');
const prepared = { version: 1, revision: 'test-carrie-1', state: { projectType: 'bathroom', jobId: 'carrie-job', target_budget: 10000, bathroom_floor_sqft: 54, site_notes: 'Which products fit?' } };
assert.equal(applyPreparedDraft(null, prepared).jobId,'carrie-job');
const fieldDraft = parseDraft({projectType:'bathroom',jobId:'carrie-job',site_notes:'Measured already.',bathroom_length_ft:9.5,bathroom_floor_sqft:57,vanity_allowance:350,budget_overrides:edits});
const loaded = applyPreparedDraft(fieldDraft, prepared);
assert.equal(loaded.bathroom_length_ft,9.5); assert.equal(loaded.bathroom_floor_sqft,57);
assert.equal(loaded.vanity_allowance,350); assert.deepEqual(loaded.budget_overrides,edits);
assert.equal(loaded.site_notes,'Measured already.\n\nWhich products fit?');
assert.equal(loaded.target_budget,10000);
assert.equal(applyPreparedDraft(loaded,prepared),loaded);
const answered={...loaded,site_notes:'Answered: products fit.'};
assert.equal(applyPreparedDraft(answered,prepared),answered);
const other={...fieldDraft,jobId:'other'};
assert.equal(applyPreparedDraft(other,prepared),other);
console.log('PASS prepared job draft loads once and preserves saved field work and other jobs');
const migrated = parseDraft({ projectType: 'bathroom', custom_items: [{ name: 'Work', qty: 1, cost: 50 }], catalog_picks: [] });
assert.equal(migrated.state_version,3); assert.equal(migrated.custom_items[0].draftId,'legacy-custom-0');
assert.deepEqual(parseDraft({ ...migrated, budget_overrides: edits }).budget_overrides,edits);
assert.throws(() => parseDraft({ ...migrated, budget_overrides: { 'rule:1': -1 } }));
assert.throws(() => parseDraft({ ...migrated, custom_items: {} }));
console.log('PASS legacy draft migration and import validation');
const { fetchCrmList } = await import('../src/api/crm.js');
const requests=[];
const request = async url => {
 requests.push(url);
 const second = new URL(url).searchParams.get('page') === 'cursor & two';
 return { ok:true, json:async () => ({ customers: second ? [{ id:'carrie', name:'Carrie' }] : [{ id:'first', name:'First' }], nextPage:second ? null:'cursor & two' }) };
};
const customers=await fetchCrmList({base:'https://example.test/webhook',key:'test',resource:'customers',signal:new AbortController().signal,request});
assert.ok(customers.some(c=>c.id==='carrie')); assert.equal(requests.length,2);
await assert.rejects(fetchCrmList({base:'https://example.test',key:'test',resource:'customers',signal:new AbortController().signal,
 request:async()=>({ok:false,status:401})}), /401/);
console.log('PASS paged CRM list and HTTP error handling');
const jobs = await fetchCrmList({base:'https://example.test',key:'test',resource:'jobs',signal:new AbortController().signal,
 request:async()=>({ok:true,json:async()=>({jobs:[{id:'new',name:'Zulu'},{id:'old',name:'Alpha'}]})})});
assert.deepEqual(jobs.map(j=>j.id),['new','old'],'keep server job order');
const workflow=JSON.parse(readFileSync(new URL('../../../automation/n8n/parts/workflows/08a-jt-data-provider.json',import.meta.url),'utf8'));
const runNode=(name,input,env={})=>new Function('$input','$env',workflow.nodes.find(n=>n.name===name).parameters.jsCode)(input,env);
const auth=runNode('Validate Auth (Customers)',{item:{json:{headers:{'x-api-key':'test'},query:{page:'cursor & two'}}}},{ESTIMATOR_API_KEY:'test'});
assert.equal(auth.json.page,'cursor & two');
const query=runNode('Build JT Query',{first:()=>auth},{JOBTREAD_GRANT_KEY:'test'})[0].json.query;
assert.equal(query.organization.accounts.$.page,'cursor & two');
assert.deepEqual(query.organization.accounts.nextPage,{});
const transformed=runNode('Transform Customers',{first:()=>({json:{organization:{accounts:{nextPage:'next',nodes:[{
 id:'one',name:'Customer',primaryLocation:{id:'primary'},locations:{nodes:[{id:'other',address:'Other'},{id:'primary',address:'Primary'}]}
}]}}}})})[0].json;
assert.equal(transformed.version,1); assert.equal(transformed.nextPage,'next'); assert.equal(transformed.customers[0].address,'Primary');
console.log('PASS n8n auth-to-query paging and primary location contract');

const { preparePreliminary } = await import('../src/engine/preliminary.js');
const rough = preparePreliminary(calculatorIntake);
assert.equal(rough.quote_hold,true);
assert.ok(rough.items.length > 0 && rough.items.every(i=>Number.isFinite(i.quantity) && !i.quantityFormula));
assert.ok(rough.assumptions.some(a=>a.field==='bathroom_length_ft'));
assert.ok(!rough.assumptions.some(a=>/^(deck_|joist_|railing_|stair_)/.test(a.field)), 'Bathroom assumptions exclude deck presets');
assert.ok(rough.assumptions.some(a=>a.field==='baseboard_lf'), 'Keep bathroom preset provenance');
assert.ok(rough.missing_inputs.some(v=>v.includes('shower door purchase cost')));
const knownPlan=preparePreliminary(detailed);
assert.ok(!knownPlan.assumptions.some(a=>a.field==='bathroom_length_ft'));
assert.ok(knownPlan.missing_inputs.some(v=>v.includes('panel kit')));
assert.ok(knownPlan.missing_inputs.some(v=>v.includes('flooring, adhesive')));
for (const state of ['pending','reserved','completed','uncertain']) {
 const withBudget={...calculatorIntake,preliminary_budget:{schema_version:1,state,quote_hold:true}};
 assert.ok(engine.estimateIssues({...customerSupply,calculator_intake:withBudget},engine.assemble(enrichState(customerSupply))).some(v=>v.includes('append another budget')));
}
const deckPlan=preparePreliminary({...deckIntake,answers:{...deckIntake.answers,project_type:'new_build',material:'pt_lumber',railing:'none'}});
assert.ok(deckPlan.items.length && !deckPlan.assumptions.some(a=>a.field==='deck_height_ft'));
assert.ok(!deckPlan.assumptions.some(a=>/^(bathroom_|shower_|wall_height|baseboard_)|_allowance$/.test(a.field)), 'Deck assumptions exclude bathroom presets');
assert.ok(deckPlan.assumptions.some(a=>a.field==='joist_spacing_in'), 'Keep deck preset provenance');
assert.throws(()=>preparePreliminary({...calculatorIntake,answers:{project_type:'unsupported'}}),/unsupported_preliminary_scope/);
console.log('PASS preliminary plans, assumption provenance, missing costs and duplicate append guard');

const flooring = await import('../src/engine/flooring.js');
const makeArea = (id, finish, values = {}) => ({ ...flooring.createFlooringArea(id, id),
  finish, substrate:'wood', substrate_checked:'yes', supply:'hwc', net_sqft:101,
  waste_percent:10, box_sqft:20, product_cost:3, install_hours:8,
  prep_hours:2, prep_cost:50, underlay_hours:1, underlay_cost:60,
  removal:'vinyl', removal_hours:2, trim:'new', trim_lf:30, trim_hours:2, trim_cost:2,
  transitions:2, transition_hours:1, transition_cost:25, ...values });
const floorState = { ...DEFAULT_STATE, projectType:'flooring', measurements_checked:'yes', flooring:{
  ...flooring.createFlooring(), setup_hours:2, cleanup_hours:1, haul_cost:40,
  areas:[makeArea('living','lvp'),makeArea('entry','tile',{net_sqft:40,waste_percent:15,box_sqft:10,
    product_cost:6,install_hours:6,prep_hours:1,prep_cost:20,underlay_cost:80,
    removal:'none',trim:'none',transitions:0,setting_cost:50,grout_cost:30})],
} };
const floorItems = engine.assemble(enrichState(floorState), 'flooring');
assert.deepEqual(engine.estimateIssues(floorState,floorItems),[]);
assert.equal(floorItems.find(i=>i._editKey==='rule:flooring:living:lvp:product').qty,120);
assert.equal(floorItems.find(i=>i._editKey==='rule:flooring:living:lvp:install').qty,8);
assert.equal(floorItems.find(i=>i._editKey==='rule:flooring:entry:tile:product').qty,50);
assert.equal(floorItems.filter(i=>i._editKey==='rule:flooring:job:setup').length,1);
assert.ok(floorItems.every(i=>i._editKey.startsWith('rule:flooring:')));
assert.ok(engine.buildJtItems(floorItems).every(i=>i.costCodeId && i.costTypeId && i.unitId));
assert.deepEqual(engine.buildProjectParameters(floorState),[{name:'flooring_area_sqft',value:141},{name:'flooring_area_count',value:2}]);
const ownerFloor = structuredClone(floorState); ownerFloor.flooring.areas[1].supply='customer';ownerFloor.flooring.areas[1].product_cost=null;
const ownerItems = engine.assemble(enrichState(ownerFloor),'flooring');
assert.deepEqual(engine.estimateIssues(ownerFloor,ownerItems),[]);
assert.ok(!ownerItems.some(i=>i._editKey==='rule:flooring:entry:tile:product'));
assert.ok(ownerItems.some(i=>i._editKey==='rule:flooring:entry:tile:install'));
assert.ok(ownerItems.some(i=>i._editKey==='rule:flooring:entry:tile:setting'));
const noPrices = structuredClone(floorState); noPrices.flooring.areas[1].grout_cost=null;
assert.ok(engine.estimateIssues(noPrices,engine.assemble(noPrices,'flooring')).some(i=>i.includes('Grout cost')));
const switchedFinish = structuredClone(floorState);switchedFinish.flooring.areas[0].finish='tile';
assert.ok(!engine.applyEdits(engine.assemble(switchedFinish,'flooring'),{'rule:flooring:living:lvp:install':999},{}).some(i=>i.qty===999));
assert.equal(flooring.flooringQuantities({...floorState.flooring.areas[0],net_sqft:100,box_sqft:0}).purchaseSqft,110);
assert.equal(flooring.flooringQuantities({...floorState.flooring.areas[0],net_sqft:100,box_sqft:22}).boxes,5);
assert.equal(flooring.flooringQuantities({...floorState.flooring.areas[0],net_sqft:0.25,waste_percent:0,box_sqft:0}).purchaseSqft,0.25);
assert.deepEqual(flooring.parseFlooring(JSON.parse(JSON.stringify(floorState.flooring))),floorState.flooring);
for (const bad of [
 {...floorState.flooring,schema_version:2}, {...floorState.flooring,areas:[floorState.flooring.areas[0],floorState.flooring.areas[0]]},
 {...floorState.flooring,areas:Array.from({length:51},(_,i)=>makeArea(`a${i}`,'lvp'))},
 {...floorState.flooring,areas:[makeArea('bad','glue_down')]},
 {...floorState.flooring,areas:[makeArea('bad','lvp',{net_sqft:-1})]},
 {...floorState.flooring,areas:[makeArea('bad','lvp',{net_sqft:'100'})]},
]) assert.throws(()=>flooring.parseFlooring(bad));
assert.equal(parseDraft(floorState).state_version,3);
const floorStorage = new Map();const floorStore={getItem:k=>floorStorage.get(k)??null,setItem:(k,v)=>floorStorage.set(k,v)};
const away = switchJobDraft({...floorState,jobId:'floor-job'}, {jobId:'bath-job'},floorStore);
assert.deepEqual(switchJobDraft(away,{jobId:'floor-job'},floorStore).flooring,floorState.flooring);
console.log('PASS mixed flooring areas, purchase quantities, owner supply, scoped edits, missing costs, mappings and bounded drafts');

const { loadSaved, STORAGE_KEY, JOB_DRAFTS_KEY } = await import('../src/hooks/useProjectState.js');
const legacyDraft = JSON.stringify({...DEFAULT_STATE,state_version:2,site_notes:'Legacy measurements'});
const legacyJobs = JSON.stringify({schema_version:1,jobs:{'job:old':{...DEFAULT_STATE,state_version:2,jobId:'old',site_notes:'Older job'}}});
const migrationData = new Map([['hwc-estimate-state',legacyDraft],['hwc-estimate-job-drafts',legacyJobs]]);
const migrationStore = {getItem:k=>migrationData.get(k)??null,setItem:(k,v)=>migrationData.set(k,v)};
assert.equal(loadSaved(migrationStore).state.state_version,3);
const oldJob = switchJobDraft({...floorState,jobId:'floor'}, {jobId:'old'},migrationStore);
assert.equal(oldJob.site_notes,'Older job');
assert.equal(migrationData.get('hwc-estimate-job-drafts'),legacyJobs);
assert.equal(migrationData.get('hwc-estimate-state'),legacyDraft);
assert.equal(JSON.parse(migrationData.get(JOB_DRAFTS_KEY)).schema_version,2);
for (const corrupt of ['{',JSON.stringify({...floorState,state_version:99}),JSON.stringify({...floorState,flooring:{schema_version:9}})]) {
 migrationData.set(STORAGE_KEY,corrupt);
 const recovery=loadSaved(migrationStore);
 assert.equal(recovery.state,null);assert.equal(recovery.recovery.raw,corrupt);
 assert.equal(migrationData.get(STORAGE_KEY),corrupt);
}
const full=JSON.stringify({schema_version:2,jobs:Object.fromEntries(Array.from({length:50},(_,i)=>[`job:${i}`,DEFAULT_STATE]))});
migrationData.set(JOB_DRAFTS_KEY,full);
assert.throws(()=>switchJobDraft({...floorState,jobId:'overflow'},{jobId:'other'},migrationStore),/50 drafts/);
assert.equal(migrationData.get(JOB_DRAFTS_KEY),full);
const pendingFloor = {...floorState,flooring:flooring.createFlooring()};
assert.ok(engine.estimateIssues(pendingFloor,engine.assemble(pendingFloor)).some(i=>i.includes('Add at least one')));
for (const value of [0,null]) {
 const missing=structuredClone(floorState);missing.flooring.areas[0].product_cost=value;
 assert.ok(engine.estimateIssues(missing,engine.assemble(missing)).some(i=>i.includes('product cost')));
}
// The contract guard must reject malformed imported counts, even if HTML did not.
assert.throws(()=>parseDraft({...floorState,flooring:{...floorState.flooring,areas:[makeArea('bad','lvp',{transitions:1.5})]}}));
console.log('PASS legacy recovery snapshots, future/corrupt draft containment and capacity blocking');

// Run the existing export workflow through its actual mapping boundary, with
// the provider port captured. No JobTread request is made.
const exportWorkflow=JSON.parse(readFileSync(new URL('../../../automation/n8n/parts/workflows/08b-estimate-router.json',import.meta.url),'utf8'));
const validateExport=exportWorkflow.nodes.find(n=>n.name==='Validate Request').parameters.jsCode;
const floorExport=new Function('$input','$env',validateExport)({item:{json:{headers:{'x-api-key':'fixture'},body:{
 action:'push_estimate',mode:'existing',jobId:'floor-fixture',projectType:'flooring',projectState:floorState,jtPayload:engine.buildJtItems(floorItems),totals:engine.computeTotals(floorItems),
}}}},{ESTIMATOR_API_KEY:'fixture'}).json;
assert.equal(floorExport.projectType,'flooring');assert.deepEqual(floorExport.projectState.flooring,floorState.flooring);
const providerCalls=[];
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
const pushed=await new AsyncFunction('$json','$env',exportWorkflow.nodes.find(n=>n.name==='Additive Budget Push').parameters.jsCode).call({helpers:{httpRequest:async request=>{
 providerCalls.push(request.body.query.createCostGroup.$);
 return {createCostGroup:{createdCostGroup:{id:'fixture-group'}}};
}}},floorExport,{JOBTREAD_GRANT_KEY:'fixture'});
assert.equal(providerCalls.length,1);assert.equal(providerCalls[0].name,'Flooring');
assert.deepEqual(providerCalls[0].lineItems.map(g=>g.name),['1. living','2. entry','Whole job']);
assert.equal(providerCalls[0].lineItems[0].lineItems.find(i=>i.name==='living | Click-lock LVT / LVP').quantity,120);
assert.equal(pushed.json.itemsPushed,floorItems.length);
console.log('PASS flooring through existing n8n validation and captured nested JobTread export');

const { removeJobDraft } = await import('../src/hooks/useProjectState.js');
const resetData = new Map([['hwc-estimate-job-drafts',legacyJobs]]);
const resetStore={getItem:k=>resetData.get(k)??null,setItem:(k,v)=>resetData.set(k,v)};
removeJobDraft({jobId:'old'},resetStore);
assert.ok(!Object.hasOwn(JSON.parse(resetData.get(JOB_DRAFTS_KEY)).jobs,'job:old'));
assert.equal(resetData.get('hwc-estimate-job-drafts'),legacyJobs);
assert.equal(switchJobDraft({...DEFAULT_STATE,jobId:'different'},{jobId:'old'},resetStore).site_notes,'');
resetData.set(JOB_DRAFTS_KEY,'');
assert.throws(()=>removeJobDraft({jobId:'old'},resetStore));
assert.equal(resetData.get(JOB_DRAFTS_KEY),'');
console.log('PASS reset migrates legacy job store without resurrecting removed drafts');
