// Services.jsx — 4-up grid of service categories.
const SERVICES = [
  {
    key: 'bathroom',
    icon: 'home',
    title: 'Bathroom remodeling',
    body: 'Full gut remodels, refreshes, tub-to-shower conversions, targeted repairs. Waterproofing behind every tile.',
  },
  {
    key: 'decks',
    icon: 'layers',
    title: 'Decks & exterior',
    body: 'Cedar and composite decks, railings, stairs, pergolas, skirting. Built for Montana freeze-thaw.',
  },
  {
    key: 'carpentry',
    icon: 'ruler',
    title: 'Custom carpentry',
    body: 'Built-ins, trim, shelving. The kind of work that only shows itself when you live with it every day.',
  },
  {
    key: 'remodel',
    icon: 'hammer',
    title: 'General remodeling',
    body: 'Interior remodels, basement finishing, additions, fences. Scoped properly, priced honestly.',
  },
];

const Services = ({ onNavigate }) => (
  <section style={{ padding: '96px 48px', maxWidth: 1200, margin: '0 auto' }}>
    <div style={{ maxWidth: 720, marginBottom: 56 }}>
      <Eyebrow style={{ marginBottom: 20 }}>WHAT WE DO</Eyebrow>
      <h2 style={{
        fontFamily: "'Playfair Display', serif",
        fontSize: 44, fontWeight: 700, lineHeight: 1.1,
        letterSpacing: '-0.01em', color: 'var(--fg1)', margin: 0,
      }}>
        Four categories. Every job scoped and priced up front.
      </h2>
      <Rule style={{ marginTop: 24 }} />
    </div>
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 16 }}>
      {SERVICES.map((s) => (
        <div key={s.key} style={{
          background: 'var(--bg2)',
          border: '1px solid rgba(235,219,178,0.08)',
          borderRadius: 12, padding: 28,
          display: 'flex', flexDirection: 'column', gap: 16,
          cursor: 'pointer',
          transition: 'background 200ms, border-color 200ms',
        }}
        onMouseEnter={(e) => { e.currentTarget.style.background = '#2c3238'; e.currentTarget.style.borderColor = 'rgba(207,153,95,0.35)'; }}
        onMouseLeave={(e) => { e.currentTarget.style.background = 'var(--bg2)'; e.currentTarget.style.borderColor = 'rgba(235,219,178,0.08)'; }}
        onClick={() => onNavigate('services')}
        >
          <div style={{ color: 'var(--accent)' }}>
            <Icon name={s.icon} size={28} />
          </div>
          <div style={{
            fontFamily: "'Playfair Display', serif",
            fontSize: 22, fontWeight: 600, lineHeight: 1.2,
            color: 'var(--fg1)',
          }}>{s.title}</div>
          <div style={{
            fontFamily: "'DM Sans', sans-serif",
            fontSize: 14, lineHeight: 1.65, color: 'var(--fg2)',
            flex: 1,
          }}>{s.body}</div>
          <div style={{
            fontFamily: "'DM Sans', sans-serif",
            fontSize: 13, fontWeight: 500,
            color: 'var(--fg1)', display: 'flex', alignItems: 'center', gap: 8,
            borderBottom: '1px solid var(--accent)', alignSelf: 'flex-start', paddingBottom: 4,
          }}>
            Learn more <Icon name="arrow-right" size={14} />
          </div>
        </div>
      ))}
    </div>
  </section>
);

Object.assign(window, { Services });
