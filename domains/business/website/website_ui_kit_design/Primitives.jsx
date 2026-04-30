// Heartwood Craft — primitives shared across the website UI kit.
// Exported to window so other Babel scripts can import.

const Eyebrow = ({ children, color, style }) => (
  <div style={{
    fontFamily: "'DM Sans', sans-serif",
    textTransform: 'uppercase',
    letterSpacing: '0.14em',
    fontSize: 11,
    fontWeight: 500,
    color: color || 'var(--fg3)',
    ...style,
  }}>{children}</div>
);

const Rule = ({ width = 64, color = 'var(--accent)', style }) => (
  <div style={{ height: 2, width, background: color, ...style }} />
);

const Button = ({ children, variant = 'primary', onClick, size = 'md', style }) => {
  const pad = size === 'sm' ? '10px 16px' : '14px 22px';
  const fs = size === 'sm' ? 12 : 14;
  const base = {
    fontFamily: "'DM Sans', sans-serif",
    fontWeight: 500,
    fontSize: fs,
    padding: pad,
    borderRadius: 8,
    cursor: 'pointer',
    border: 0,
    transition: 'background 200ms cubic-bezier(0.2,0.7,0.2,1), color 200ms, border-color 200ms',
    letterSpacing: '0.01em',
    ...style,
  };
  const variants = {
    primary: { background: 'var(--accent)', color: 'var(--bg1)' },
    secondary: { background: 'transparent', color: 'var(--fg1)', border: '1px solid var(--accent)', padding: `calc(${pad.split(' ')[0]} - 1px) calc(${pad.split(' ')[1]} - 1px)` },
    tertiary: { background: 'transparent', color: 'var(--fg1)', padding: '12px 0', borderBottom: '1px solid var(--accent)', borderRadius: 0 },
  };
  return (
    <button
      onClick={onClick}
      style={{ ...base, ...variants[variant] }}
      onMouseEnter={(e) => {
        if (variant === 'primary') e.currentTarget.style.background = 'var(--accent-hover)';
      }}
      onMouseLeave={(e) => {
        if (variant === 'primary') e.currentTarget.style.background = 'var(--accent)';
      }}
    >{children}</button>
  );
};

const Field = ({ label, placeholder, type = 'text', value, onChange, rows }) => (
  <label style={{ display: 'block' }}>
    <Eyebrow style={{ marginBottom: 8 }}>{label}</Eyebrow>
    {rows ? (
      <textarea
        rows={rows}
        placeholder={placeholder}
        value={value}
        onChange={onChange}
        style={fieldInputStyle}
      />
    ) : (
      <input
        type={type}
        placeholder={placeholder}
        value={value}
        onChange={onChange}
        style={fieldInputStyle}
      />
    )}
  </label>
);

const fieldInputStyle = {
  width: '100%',
  background: 'var(--bg2)',
  border: '1px solid rgba(235,219,178,0.1)',
  color: 'var(--fg1)',
  padding: '14px',
  borderRadius: 8,
  fontFamily: "'DM Sans', sans-serif",
  fontSize: 14,
  boxSizing: 'border-box',
  outline: 'none',
  transition: 'border-color 200ms',
  resize: 'vertical',
};

// Lucide icon — render by name via CDN data lookup. We inline just the icons we need
// to avoid a build step. Fallbacks gracefully.
const Icon = ({ name, size = 20, color = 'currentColor', stroke = 1.75 }) => {
  const icons = {
    'arrow-right': <><path d="M5 12h14"/><path d="m12 5 7 7-7 7"/></>,
    'map-pin': <><path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/><circle cx="12" cy="10" r="3"/></>,
    'mail': <><rect width="20" height="16" x="2" y="4" rx="2"/><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/></>,
    'phone': <><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.127.96.361 1.903.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.907.339 1.85.573 2.81.7A2 2 0 0 1 22 16.92Z"/></>,
    'hammer': <><path d="m15 12-8.373 8.373a1 1 0 1 1-3-3L12 9"/><path d="m18 15 4-4"/><path d="m21.5 11.5-1.914-1.914A2 2 0 0 1 19 8.172V7l-2.26-2.26a6 6 0 0 0-4.202-1.756L9 2.96l.92.82A6.18 6.18 0 0 1 12 8.4V10l2 2h1.172a2 2 0 0 1 1.414.586L18.5 14.5"/></>,
    'home': <><path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/></>,
    'ruler': <><path d="M21.3 15.3 15.3 21.3a1 1 0 0 1-1.4 0L2.7 10.1a1 1 0 0 1 0-1.4l6-6a1 1 0 0 1 1.4 0l11.2 11.2a1 1 0 0 1 0 1.4Z"/><path d="m14.5 12.5-2 2"/><path d="m11.5 9.5-2 2"/><path d="m8.5 6.5-2 2"/><path d="m17.5 15.5-2 2"/></>,
    'layers': <><path d="m12.83 2.18 8.49 3.76a1 1 0 0 1 0 1.83L12.83 11.5a1 1 0 0 1-.82 0L3.52 7.77a1 1 0 0 1 0-1.83l8.49-3.76a1 1 0 0 1 .82 0Z"/><path d="m22 12-9.68 4.29a1 1 0 0 1-.82 0L2 12"/><path d="m22 17-9.68 4.29a1 1 0 0 1-.82 0L2 17"/></>,
    'drafting': <><path d="M12 3v18"/><path d="M3 9h18"/><circle cx="12" cy="12" r="3"/></>,
    'check': <><polyline points="20 6 9 17 4 12"/></>,
    'menu': <><line x1="4" y1="6" x2="20" y2="6"/><line x1="4" y1="12" x2="20" y2="12"/><line x1="4" y1="18" x2="20" y2="18"/></>,
    'x': <><path d="M18 6 6 18"/><path d="m6 6 12 12"/></>,
  };
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round">
      {icons[name] || null}
    </svg>
  );
};

// Placeholder image panel — deliberate, per brand guide (no stock).
const PhotoPlaceholder = ({ label = 'PROJECT PHOTO', aspect = '4 / 3', style }) => (
  <div style={{
    aspectRatio: aspect,
    background: '#1a1c1d',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 0,
    ...style,
  }}>
    <div style={{
      fontFamily: "'DM Sans', sans-serif",
      letterSpacing: '.22em',
      color: '#5a5d61',
      fontSize: 10,
      fontWeight: 500,
    }}>{label}</div>
  </div>
);

Object.assign(window, { Eyebrow, Rule, Button, Field, Icon, PhotoPlaceholder });
