import { useState } from 'react';
import { Box, Label } from './Section.jsx';
import { FLOORING_CHOICES, FLOORING_FIELDS, FLOORING_JOB_FIELDS, MAX_FLOORING_AREAS,
  createFlooringArea, flooringQuantities } from '../engine/flooring.js';

function NumericFields({ fields, value, change }) {
  return <div className="flooring-fields">{fields.filter(f => f.active(value)).map(f => (
    <label key={f.key}>{f.label}<input type="number" min="0" max={f.max} step={f.key === 'transitions' ? '1' : 'any'}
      value={value[f.key] ?? ''} onChange={e => {
        const input = e.target.value === '' ? null : Number(e.target.value);
        if (input !== null && (!Number.isFinite(input) || input < 0 || input > f.max || (f.key === 'transitions' && !Number.isInteger(input)))) return;
        change(f.key, input);
      }} /></label>
  ))}</div>;
}

export function FlooringScope({ s, set }) {
  const floor = s.flooring;
  const [selectedId, select] = useState('');
  const [deleted, setDeleted] = useState(null);
  const area = floor.areas.find(a => a.id === selectedId) || floor.areas[0];
  const change = (key, value) => {
    set('flooring', current => ({ ...current, [key]: value }));
    set('measurements_checked', 'no');
  };
  const changeArea = (key, value) => change('areas', floor.areas.map(a => a.id === area.id ? {
    ...a, [key]: value,
    ...(key === 'finish' || key === 'substrate' ? { substrate_checked: 'no' } : {}),
  } : a));
  const add = () => {
    if (floor.areas.length >= MAX_FLOORING_AREAS) return;
    const added = createFlooringArea(crypto.randomUUID(), `Area ${floor.areas.length + 1}`);
    change('areas', [...floor.areas, added]); select(added.id);
  };
  const quantity = area ? flooringQuantities(area) : null;
  return <section className="flooring-scope" aria-label="Flooring scope">
    <Box>
      <Label>Flooring areas</Label>
      <p>Use a separate area for each flooring product or installation scope. Click-lock LVT / LVP and tile can share this job.</p>
      <div className="flooring-actions">
        {area && <label>Area to edit<select aria-label="Area to edit" value={area.id} onChange={e => select(e.target.value)}>
          {floor.areas.map((a, i) => <option key={a.id} value={a.id}>{i + 1}. {a.name || 'Unnamed area'}</option>)}
        </select></label>}
        <button type="button" onClick={add} disabled={floor.areas.length >= MAX_FLOORING_AREAS}>Add flooring area</button>
      </div>
      {floor.areas.length >= MAX_FLOORING_AREAS && <p>This job has the maximum of {MAX_FLOORING_AREAS} areas.</p>}
      {!area && <p>Add an area to start the flooring budget.</p>}
      {area && <>
        <label>Area name<input maxLength={120} value={area.name} onChange={e => changeArea('name', e.target.value)} /></label>
        <div className="flooring-fields">{Object.entries(FLOORING_CHOICES).map(([key, field]) => (
          <label key={key}>{field.label}<select aria-label={field.label} value={area[key]} onChange={e => changeArea(key, e.target.value)}>
            {Object.entries(field.options).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select></label>
        ))}</div>
        <p>Check the chosen product's substrate, moisture and flatness requirements on site. Include leveling, repairs and required underlayment below. Enter 0 only when work is checked and unnecessary.</p>
        <p>Enter supplier costs before markup and labor hours for this area. Tile installation hours include setting and grouting. Customer supply excludes only the flooring product.</p>
        <NumericFields fields={FLOORING_FIELDS} value={area} change={changeArea} />
        <p role="status">{quantity.purchaseSqft > 0 ? `Floor product quantity: ${quantity.purchaseSqft} sq ft${quantity.boxes === null ? '' : ` (${quantity.boxes} boxes)`}. Waste and box rounding do not increase labor hours.` : 'Enter net area, waste and box coverage to calculate the product quantity.'}</p>
        <button type="button" onClick={() => { setDeleted({ area, index: floor.areas.indexOf(area) }); change('areas', floor.areas.filter(a => a.id !== area.id)); }}>Remove this area</button>
      </>}
      {deleted && <div className="flooring-actions"><span>Removed {deleted.area.name}.</span><button type="button" disabled={floor.areas.length >= MAX_FLOORING_AREAS} onClick={() => {
        const areas = [...floor.areas]; areas.splice(deleted.index, 0, deleted.area);
        change('areas', areas); select(deleted.area.id); setDeleted(null);
      }}>Undo area removal</button></div>}
    </Box>
    <Box>
      <Label>Whole-job work</Label>
      <p>These costs apply once to the job. Include floor protection materials, unusual work or supplier fees in Details → Additional scope.</p>
      <NumericFields fields={FLOORING_JOB_FIELDS} value={floor} change={change} />
    </Box>
  </section>;
}
