import { C, mono } from '../styles/theme.js';
import { FtInInput } from './FtInInput.jsx';

// Bounded native pickers keep phone menus usable. Existing values are always
// included, including fractional areas and values above the normal picker range.
const measurementRanges = { sf: [2000, 1], sqft: [2000, 1], in: [96, 0.25], ea: [200, 1], hrs: [240, 0.5] };

export function NumInput({ label, value, onChange, unit, min = 0, max = 9999, step = 1, show = true }) {
  if (!show) return null;
  if (typeof value === 'number' && !Number.isFinite(value)) value = null;
  if (unit === 'ft' || unit === 'lf') return <FtInInput {...{ label, value, onChange, min, max }} pickerMax={unit === 'lf' ? 1000 : 100} />;
  const money = unit === '$';
  const [limit, increment] = measurementRanges[unit] || [200, step];
  const options = Array.from({ length: Math.max(0, Math.floor((Math.min(max, limit) - min) / increment) + 1) }, (_, i) => min + i * increment);
  if (value != null && !options.includes(value)) options.push(value);
  options.sort((a, b) => a - b);
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '5px 0' }}>
      <span style={{ color: C.tx, fontSize: 12, fontFamily: mono }}>{label}</span>
      <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
        {money ? <input
          aria-label={label}
          inputMode="decimal"
          type="number"
          value={value ?? ''}
          onChange={e => onChange(e.target.value === '' ? null : Math.max(min, Math.min(max, parseFloat(e.target.value) || 0)))}
          min={min} max={max} step={step}
          style={{
            width: 60, padding: '3px 6px', borderRadius: 3,
            border: `1px solid ${C.brd}`,
            backgroundColor: C.card2, color: C.txB,
            fontSize: 13, textAlign: 'right', fontFamily: mono, outline: 'none',
          }}
        /> : <select
          className="measurement-select"
          aria-label={label}
          value={value ?? ''}
          onChange={e => onChange(e.target.value === '' ? null : Number(e.target.value))}
        >
          <option value="">Choose…</option>
          {options.map(v => <option key={v} value={v}>{v}</option>)}
        </select>}
        {unit && <span style={{ color: C.txD, fontSize: 10, width: 22 }}>{unit}</span>}
      </div>
    </div>
  );
}
