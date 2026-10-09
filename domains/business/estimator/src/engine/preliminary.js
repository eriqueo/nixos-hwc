/** Server composition for preliminary budgets; browser intake stays unverified.
 * assembler.js owns line pricing, intake.js owns translations; neither owns
 * template assumptions, provenance or the bounded stdin/stdout port.
 */
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { parseCalculatorIntake, deckAnswerEstimates, CALCULATOR_INPUT_VERSION } from '../api/crm.js';
import { calculatorPatch, DEFAULT_STATE } from './intake.js';
import { enrichState } from './geometry.js';
import { assemble, buildJtItems, estimateIssues, computeTotals } from './assembler.js';
import templates from '../data/templates.json' with { type: 'json' };
import parameters from '../data/parameters.json' with { type: 'json' };

export function preparePreliminary(raw) {
  const intake = parseCalculatorIntake(raw, raw.jt_job_id);
  const answers = intake.answers;
  const templateId = intake.calculator === 'bathroom'
    ? ({ full_gut:1, refresh:3, tub_to_shower:4 })[answers.project_type]
    : ({ new_build:5, full_rebuild:5, partial_rebuild:8, repair_refresh:8 })[answers.project_type];
  const template = templates.find(t => t.id === templateId && t.project_type === intake.calculator);
  if (!template) throw Error('unsupported_preliminary_scope');
  const base = { ...DEFAULT_STATE, ...template.state, projectType:intake.calculator };
  const patch = calculatorPatch(intake);
  const state = { ...base };
  for (const [key,value] of Object.entries(patch)) if (value !== null && value !== 'unknown') state[key] = value;
  if (intake.calculator === 'bathroom') {
    if (patch.shower_finish === 'unknown') {
      state.shower_finish = answers.shower_tub === 'tub_only' ? 'none' : 'tile';
      state.has_shower_tile = state.shower_finish === 'tile' ? 'yes' : 'no';
    }
    if (patch.floor_finish === 'unknown') { state.floor_finish = 'tile'; state.has_floor_tile = 'yes'; }
    if (patch.shower_niches === 'unknown') state.shower_niches = '1';
    if (patch.has_shower_door === 'unknown') state.has_shower_door = 'no';
    if (answers.shower_tub === 'tub_only' || answers.shower_tub === 'tub_shower' || answers.shower_tub === 'both_separate') state.new_tub = 'yes';
  }
  state.measurements_checked = 'no';
  // Shared browser defaults include both scopes. Use the existing parameter
  // registry to scope preset provenance without changing assembly or pricing.
  const deckFields = new Set(parameters.deck_numeric.map(p => p.name));
  const presetInScope = key => intake.calculator === 'deck' ? deckFields.has(key) : !deckFields.has(key);
  const assumptions = Object.entries(state).filter(([key]) =>
    !['state_version','projectType','job_type','measurements_checked','calculator_scope_checked'].includes(key) &&
    (Object.hasOwn(template.state,key) || (presetInScope(key) && /(_ft|_in|_sqft|_lf|_allowance)$/.test(key))) &&
    (patch[key] === undefined || patch[key] === null || patch[key] === 'unknown'))
    .filter(([,value])=>value !== null)
    .map(([field,value]) => ({ field, value, source:Object.hasOwn(template.state,field) ? `Template: ${template.name}` : 'Estimator preset — review' }));
  if (intake.calculator === 'deck') for (const [field,{value,basis}] of Object.entries(deckAnswerEstimates(answers))) {
    if (state[field] === value && !(answers.intake_version === CALCULATOR_INPUT_VERSION && typeof answers[field] === 'number'))
      assumptions.push({ field, value, source:`From calculator answer (${basis}) — verify on site` });
  }
  for (const key of ['shower_finish','floor_finish','shower_niches','has_shower_door']) {
    if (patch[key] === 'unknown' && !assumptions.some(a=>a.field===key)) assumptions.push({field:key,value:state[key],source:'Preliminary scope assumption'});
  }
  const items = assemble(enrichState(state), intake.calculator);
  const mapped = items.filter(item=> { const i=buildJtItems([item])[0]; return i.costCodeId && i.costTypeId && i.unitId; });
  const jtItems = buildJtItems(mapped);
  if (!jtItems.length || jtItems.length > 400 || jtItems.some(i =>
    !i.costCodeId || !i.costTypeId || !i.unitId ||
    ![i.quantity,i.unitCost,i.unitPrice].every(v=>typeof v === 'number' && Number.isFinite(v) && v >= 0))) throw Error('invalid_preliminary_items');
  const missing = estimateIssues({ ...state, calculator_intake:intake },items);
  for (const item of items.filter(i=>!mapped.includes(i))) missing.push(`Excluded ${item.name}: catalog JobTread mapping is missing. Add and price this line before quoting.`);
  for (const item of items) if (item.qty === 0 || item.uc === 0) missing.push(`Confirm quantity and purchase cost for ${item.name}; this line is not fully priced.`);
  const supported = new Set(['niches','new_toilet','lighting','mirror','ventilation','double_vanity','paint','baseboard','gfci','glass_door',
    ...(intake.calculator === 'deck' && state.stair_tread_count > 0 ? ['stairs'] : [])]);
  const unpriced = (answers.features || []).filter(f=>!supported.has(f)).map(f=>`Confirm and price requested feature: ${f.replaceAll('_',' ')}.`);
  for (const item of items.filter(i=>i._usedDefault)) assumptions.push({field:item.name,value:item.qty,source:'Catalog fallback quantity — review'});
  return { schema_version:1, jt_job_id:intake.jt_job_id, lead_id:intake.lead_id, preliminary:true, quote_hold:true,
    template:{id:template.id,name:template.name}, assumptions, missing_inputs:[...new Set([...missing,...unpriced])],
    original_answers:answers, totals:computeTotals(mapped), items:jtItems,
  };
}

// Bounded, credential-free process port. No JobTread call or persisted write.
async function main(input, output, args) {
  if (args.includes('--check')) { output.write(JSON.stringify({schema_version:1,ready:true})); return; }
  let body='';
  for await (const chunk of input) {
    body += chunk;
    if (Buffer.byteLength(body) > 65536) throw Error('preliminary_input_too_large');
  }
  const plan=JSON.stringify(preparePreliminary(JSON.parse(body)));
  if (Buffer.byteLength(plan) > 1048576) throw Error('preliminary_output_too_large');
  output.write(plan);
}
if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.stdin,process.stdout,process.argv.slice(2)).catch(e=>{
    process.stderr.write(e.message+'\n');process.exitCode=1;
  });
}
