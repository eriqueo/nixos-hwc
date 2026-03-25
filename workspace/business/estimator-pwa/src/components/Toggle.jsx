import { C, mono } from '../styles/theme.js';

export function Toggle({ label, value, onChange, show = true }) {
  if (!show) return null;
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '5px 0' }}>
      <span style={{ color: C.tx, fontSize: 12, fontFamily: mono }}>{label}</span>
      <button
        onClick={() => onChange(!value)}
        aria-pressed={value}
        style={{
          width: 40, height: 22, borderRadius: 11,
          border: 'none', cursor: 'pointer', position: 'relative',
          backgroundColor: value ? C.acc : C.brd,
          transition: 'background-color 0.15s',
        }}
      >
        <div style={{
          width: 16, height: 16, borderRadius: 8,
          backgroundColor: '#fff',
          position: 'absolute', top: 3,
          left: value ? 21 : 3,
          transition: 'left 0.15s',
          boxShadow: '0 1px 3px rgba(0,0,0,0.3)',
        }} />
      </button>
    </div>
  );
}
