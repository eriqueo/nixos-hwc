import assert from 'node:assert/strict';
import { register } from 'node:module';
import { readFileSync } from 'node:fs';
register(new URL('./json-import-hook.mjs', import.meta.url));
const engine = await import('../src/engine/assembler.js');
const { enrichState } = await import('../src/engine/geometry.js');
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
const panelState = { ...state, measurements_checked: 'yes', shower_finish: 'panel', floor_finish: 'vinyl', has_shower_tile: 'no', has_floor_tile: 'no',
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
assert.equal(migrated.state_version,2); assert.equal(migrated.custom_items[0].draftId,'legacy-custom-0');
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
