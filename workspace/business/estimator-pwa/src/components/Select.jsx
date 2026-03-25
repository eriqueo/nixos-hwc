import { C, mono } from '../styles/theme.js';

/** options: [{ v: 'value', l: 'Label' }] */
export function Select({ label, value, onChange, options, show = true }) {
  if (!show) return null;
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '5px 0' }}>
      <span style={{ color: C.tx, fontSize: 12, fontFamily: mono }}>{label}</span>
      <select
        value={value}
        onChange={e => onChange(e.target.value)}
        style={{
          padding: '3px 6px', borderRadius: 3,
          border: `1px solid ${C.brd}`,
          backgroundColor: C.card2, color: C.txB,
          fontSize: 12, fontFamily: mono, outline: 'none', cursor: 'pointer',
        }}
      >
        {options.map(o => <option key={o.v} value={o.v}>{o.l}</option>)}
      </select>
    </div>
  );
}
