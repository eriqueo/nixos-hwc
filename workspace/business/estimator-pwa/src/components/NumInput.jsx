import { C, mono } from '../styles/theme.js';

export function NumInput({ label, value, onChange, unit, min = 0, max = 9999, step = 1, show = true }) {
  if (!show) return null;
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '5px 0' }}>
      <span style={{ color: C.tx, fontSize: 12, fontFamily: mono }}>{label}</span>
      <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
        <input
          type="number"
          value={value ?? ''}
          onChange={e => onChange(parseFloat(e.target.value) || 0)}
          min={min} max={max} step={step}
          style={{
            width: 60, padding: '3px 6px', borderRadius: 3,
            border: `1px solid ${C.brd}`,
            backgroundColor: C.card2, color: C.txB,
            fontSize: 13, textAlign: 'right', fontFamily: mono, outline: 'none',
          }}
        />
        {unit && <span style={{ color: C.txD, fontSize: 10, width: 22 }}>{unit}</span>}
      </div>
    </div>
  );
}
