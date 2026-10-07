import { C, mono } from '../styles/theme.js';

/** Feet + Inches input — stores value as decimal feet */
export function FtInInput({ label, value, onChange, min = 0, max = 9999, pickerMax = 100, show = true }) {
  if (!show) return null;
  const totalInches = Math.round((value || 0) * 12 * 1e8) / 1e8;
  const ft = Math.floor(totalInches / 12);
  const inches = totalInches % 12;
  const feetOptions = Array.from({ length: Math.min(pickerMax, Math.floor(max)) + 1 }, (_, i) => i);
  if (!feetOptions.includes(ft)) feetOptions.push(ft);
  feetOptions.sort((a, b) => a - b);
  const inchOptions = Array.from({ length: 48 }, (_, i) => i / 4);
  if (!inchOptions.includes(inches)) inchOptions.push(inches);
  inchOptions.sort((a, b) => a - b);

  const handleFt = e => {
    const newFt = parseInt(e.target.value) || 0;
    onChange(Math.max(min, Math.min(max, newFt + inches / 12)));
  };
  const handleIn = e => {
    const newIn = Number(e.target.value);
    onChange(Math.max(min, Math.min(max, ft + newIn / 12)));
  };

  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '5px 0' }}>
      <span style={{ color: C.tx, fontSize: 12, fontFamily: mono }}>{label}</span>
      <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
        <select className="measurement-select dimension-select" aria-label={`${label} feet`} value={value == null ? '' : ft} onChange={handleFt}>
          <option value="">Measure…</option>
          {feetOptions.map(v => <option key={v} value={v}>{v}</option>)}
        </select>
        <span style={{ color: C.txD, fontSize: 10 }}>ft</span>
        <select className="measurement-select dimension-select" aria-label={`${label} inches`} value={value == null ? '' : inches} onChange={handleIn}>
          <option value="">Measure…</option>
          {inchOptions.map(v => <option key={v} value={v}>{v}</option>)}
        </select>
        <span style={{ color: C.txD, fontSize: 10 }}>in</span>
      </div>
    </div>
  );
}
