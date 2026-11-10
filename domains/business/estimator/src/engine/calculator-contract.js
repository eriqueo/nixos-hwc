// Shared calculator -> estimator contract. Feet and counts are customer reports,
// never site verification. The public calculator imports this same vocabulary.
export const CALCULATOR_INPUT_VERSION = 2;
export const CALCULATOR_FIELDS = {
  bathroom: [
    { id: 'bathroom_length_ft', label: 'Room length', unit: 'ft', min: 0.25, max: 100 },
    { id: 'bathroom_width_ft', label: 'Room width', unit: 'ft', min: 0.25, max: 100 },
    { id: 'wall_height_ft', label: 'Ceiling height', unit: 'ft', min: 1, max: 30 },
    { id: 'shower_pan_length_ft', label: 'Shower base length', unit: 'ft', min: 0.25, max: 30 },
    { id: 'shower_pan_width_ft', label: 'Shower base width', unit: 'ft', min: 0.25, max: 30 },
    { id: 'shower_niches', label: 'Number of shower niches', unit: 'count', min: 0, max: 3, integer: true },
    { id: 'shower_finish', label: 'Shower finish', options: [{ v: 'unknown', l: 'Choose on site' }, { v: 'none', l: 'No shower work' }, { v: 'tile', l: 'Tile' }, { v: 'panel', l: 'Panel / prefab kit' }] },
    { id: 'floor_finish', label: 'Floor finish', options: [{ v: 'unknown', l: 'Choose on site' }, { v: 'none', l: 'Keep existing' }, { v: 'tile', l: 'Tile' }, { v: 'vinyl', l: 'Vinyl / LVP' }, { v: 'marmoleum', l: 'Marmoleum' }] },
  ],
  deck: [
    { id: 'deck_length_ft', label: 'Deck length', unit: 'ft', min: 0.25, max: 200 },
    { id: 'deck_width_ft', label: 'Deck width', unit: 'ft', min: 0.25, max: 200 },
    { id: 'deck_height_ft', label: 'Height above ground', unit: 'ft', min: 0, max: 30 },
    { id: 'railing_lf', label: 'Total railing length', unit: 'ft', min: 0, max: 800 },
    { id: 'stair_tread_count', label: 'Number of stair treads', unit: 'count', min: 0, max: 100, integer: true },
  ],
};

// Deck category answers -> rough dimensions, used only where the customer gave
// no number. Square feet are the calculator's own (website-site
// src/_data/calculator-deck.json, deck_size options); keep the two in step.
const DECK_SIZE_SQFT = { small: 120, medium: 225, large: 400, xl: 600 };
const DECK_HEIGHT_FT = { ground_level: 0.75, low: 1.75, standard: 3.75, elevated: 6 };
const STAIR_RISE_IN = 7.5;

// Returns { field: { value, basis } }. Footprint is 2:3. Railing runs the
// exposed edge of a deck attached along its length (an L's outer edge equals
// its bounding box's); a multi-level deck adds one tier edge; a stair opening
// is left out. Every value is an assumption to verify, never a measurement.
export function deckAnswerEstimates(answers, stairWidthFt = 4) {
  const out = {};
  const sqft = DECK_SIZE_SQFT[answers.deck_size];
  if (sqft) {
    const width = Math.round(Math.sqrt(sqft * 2 / 3));
    const basis = `deck size "${answers.deck_size}" ≈ ${sqft} sq ft`;
    out.deck_width_ft = { value: width, basis };
    out.deck_length_ft = { value: Math.round(sqft / width), basis };
  }
  const height = DECK_HEIGHT_FT[answers.deck_height];
  if (height !== undefined) out.deck_height_ft = { value: height, basis: `deck height "${answers.deck_height}"` };
  const stairs = (answers.features || []).includes('stairs');
  if (stairs && height !== undefined) {
    out.stair_tread_count = { value: Math.max(1, Math.ceil(height * 12 / STAIR_RISE_IN) - 1),
      basis: `stairs requested, ${STAIR_RISE_IN}" rise from ${height} ft` };
  }
  // A customer's own numbers (v2 fields) shape the railing edge over the bucket.
  const given = key => answers.intake_version === CALCULATOR_INPUT_VERSION && typeof answers[key] === 'number' ? answers[key] : out[key]?.value;
  const l = given('deck_length_ft'), w = given('deck_width_ft');
  if (l && w && answers.railing && answers.railing !== 'none') {
    const edge = l + 2 * w + (answers.deck_shape === 'multi_level' ? w : 0) - (stairs ? stairWidthFt : 0);
    out.railing_lf = { value: Math.max(0, edge), basis: `${answers.railing.replaceAll('_',' ')} railing on the exposed edge of ${l}×${w} ft` };
  }
  return out;
}

export function validateCalculatorFields(calculator, answers) {
  if (answers.intake_version === undefined) return; // Permanent legacy reader.
  if (answers.intake_version !== CALCULATOR_INPUT_VERSION) throw Error('Unsupported customer input version.');
  for (const field of CALCULATOR_FIELDS[calculator]) {
    const value = answers[field.id];
    if (value === undefined || value === null) continue;
    if (field.options ? !field.options.some(o => o.v === value) :
      typeof value !== 'number' || !Number.isFinite(value) || value < field.min || value > field.max || (field.integer && !Number.isInteger(value))) {
      throw Error(`Invalid customer input: ${field.label}.`);
    }
  }
}

export function parseCalculatorIntake(data, jobId) {
  if (data.schema_version !== 1 || data.jt_job_id !== jobId || !['bathroom','deck'].includes(data.calculator) ||
      typeof data.lead_id !== 'string' || (data.report_id !== null && typeof data.report_id !== 'string') || !data.answers || Array.isArray(data.answers) || typeof data.answers !== 'object' ||
      Object.keys(data.answers).length > 40 ||
      Object.entries(data.answers).some(([key,v]) => key === 'features' ? !Array.isArray(v) || v.some(f => typeof f !== 'string') :
        v !== null && typeof v !== 'boolean' && typeof v !== 'string' && !(typeof v === 'number' && Number.isFinite(v)))) throw Error('Customer inputs have an unsupported format. Enter scope manually.');
  if (data.rough_estimate !== null && (!data.rough_estimate || ![data.rough_estimate.low,data.rough_estimate.high].every(v => typeof v === 'number' && Number.isFinite(v) && v >= 0) || data.rough_estimate.low > data.rough_estimate.high)) throw Error('Customer estimate has an unsupported format.');
  if (data.preliminary_budget !== undefined) parsePreliminaryStatus(data.preliminary_budget);
  validateCalculatorFields(data.calculator, data.answers);
  return data;
}

export function automaticBudgetBlocks(budget) {
  return !!budget && (!['failed','skipped'].includes(budget.state) || budget.error_code === 'existing_budget');
}

export function parsePreliminaryStatus(budget) {
  if (budget !== null && (!budget || budget.schema_version !== 1 || !['pending','reserved','completed','failed','uncertain','skipped'].includes(budget.state) || budget.quote_hold !== true)) throw Error('Automatic budget status has an unsupported format. Reload before sending.');
}
