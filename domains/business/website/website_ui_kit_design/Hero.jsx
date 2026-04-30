// Hero.jsx — full-bleed dark hero with editorial display type.
const Hero = ({ onNavigate }) => (
  <section style={{
    position: 'relative',
    background: 'var(--bg1)',
    padding: '120px 48px 96px',
    overflow: 'hidden',
  }}>
    {/* Full-bleed placeholder photo on the right */}
    <div style={{
      position: 'absolute', top: 0, right: 0, width: '48%', height: '100%',
      background: '#1a1c1d',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
    }}>
      <div style={{ fontFamily: "'DM Sans', sans-serif", letterSpacing: '.3em', color: '#3a3d41', fontSize: 10, fontWeight: 500 }}>
        HERO PROJECT PHOTO
      </div>
      {/* protection scrim for text edge */}
      <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(to right, rgba(35,40,45,1) 0%, rgba(35,40,45,0) 30%)' }} />
    </div>

    <div style={{ position: 'relative', margin: '0 auto', maxWidth: '60%' }}>
      <Eyebrow style={{ marginBottom: 24, color: 'var(--accent)' }}>
        BATHROOMS · DECKS · CARPENTRY · REMODELING
      </Eyebrow>
      <h1 style={{
        fontFamily: "'Playfair Display', serif",
        fontWeight: 700,
        fontSize: 72,
        lineHeight: 1.05,
        letterSpacing: '-0.015em',
        color: 'var(--fg1)',
        margin: 0,
        maxWidth: '12ch',
      }}>
        Built for Montana.<br/>Done properly.
      </h1>
      <Rule style={{ marginTop: 32, width: 96 }} />
      <p style={{
        fontFamily: "'DM Sans', sans-serif",
        fontSize: 18,
        lineHeight: 1.6,
        color: 'var(--fg2)',
        margin: '28px 0 40px',
        maxWidth: '42ch',
      }}>
        Remodeling, decks, and custom carpentry for Bozeman homeowners who want work done right the first time. No ghosting, no surprises, no shortcuts.
      </p>
      <div style={{ display: 'flex', gap: 14, flexWrap: 'wrap' }}>
        <Button onClick={() => onNavigate('contact')}>Request a Consultation</Button>
        <Button variant="secondary" onClick={() => onNavigate('process')}>See the Process</Button>
      </div>
    </div>
  </section>
);

Object.assign(window, { Hero });
