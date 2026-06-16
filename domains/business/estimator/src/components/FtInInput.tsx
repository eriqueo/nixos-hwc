import { C, mono } from '../styles/theme.js';

/** Feet + Inches input — stores value as decimal feet */
export function FtInInput({ label, value, onChange, min = 0, max = 9999, show = true }: any) {
  if (!show) return null;
  const totalInches = Math.round((value || 0) * 12);
  const ft = Math.floor(totalInches / 12);
  const inches = totalInches % 12;

  const handleFt = (e: any) => {
    const newFt = parseInt(e.target.value) || 0;
    onChange(Math.max(min, Math.min(max, newFt + inches / 12)));
  };
  const handleIn = (e: any) => {
    const newIn = Math.min(11, Math.max(0, parseInt(e.target.value) || 0));
    onChange(Math.max(min, Math.min(max, ft + newIn / 12)));
  };

  const inputStyle: any = {
    width: 44, padding: '3px 6px', borderRadius: 3,
    border: `1px solid ${C.brd}`,
    backgroundColor: C.card2, color: C.txB,
    fontSize: 13, textAlign: 'right', fontFamily: mono, outline: 'none',
  };

  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '5px 0' }}>
      <span style={{ color: C.tx, fontSize: 12, fontFamily: mono }}>{label}</span>
      <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
        <input type="number" value={ft} onChange={handleFt} min={min} max={max} step={1} style={inputStyle} />
        <span style={{ color: C.txD, fontSize: 10 }}>ft</span>
        <input type="number" value={inches} onChange={handleIn} min={0} max={11} step={1} style={{ ...inputStyle, width: 36 }} />
        <span style={{ color: C.txD, fontSize: 10 }}>in</span>
      </div>
    </div>
  );
}
