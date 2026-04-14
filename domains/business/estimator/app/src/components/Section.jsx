import { C, mono } from '../styles/theme.js';

/** Raised card container */
export function Box({ children, style }) {
  return (
    <div style={{
      backgroundColor: C.card,
      borderRadius: 8,
      border: `1px solid ${C.brd}`,
      padding: 14,
      ...style,
    }}>
      {children}
    </div>
  );
}

/** Section header with accent bar */
export function Label({ children, color }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginBottom: 8 }}>
      <div style={{ width: 3, height: 14, borderRadius: 2, backgroundColor: color ?? C.acc }} />
      <span style={{
        color: C.txB, fontSize: 11, fontWeight: 700,
        letterSpacing: '0.08em', textTransform: 'uppercase', fontFamily: mono,
      }}>
        {children}
      </span>
    </div>
  );
}

/** Horizontal rule / divider between sections */
export function Divider() {
  return <div style={{ height: 1, backgroundColor: C.brd, margin: '10px 0' }} />;
}

/** Single stat display (label + value) */
export function Stat({ label, value, color, compact = false }) {
  return (
    <div style={{ textAlign: 'center' }}>
      <div style={{ color: C.txD, fontSize: compact ? 8 : 9, textTransform: 'uppercase', letterSpacing: '0.1em' }}>
        {label}
      </div>
      <div style={{ color: color ?? C.txB, fontSize: compact ? 13 : 16, fontWeight: 700, fontFamily: mono }}>
        {value}
      </div>
    </div>
  );
}
