// Testimonial.jsx — editorial pull-quote section.
const Testimonial = () => (
  <section style={{ padding: '96px 48px', maxWidth: 960, margin: '0 auto', textAlign: 'left' }}>
    <Rule style={{ marginBottom: 40, width: 48 }} />
    <blockquote style={{
      fontFamily: "'Playfair Display', serif",
      fontSize: 36, fontWeight: 500, lineHeight: 1.3,
      letterSpacing: '-0.005em',
      color: 'var(--fg1)', margin: 0,
    }}>
      Eric showed up when he said he would, told us what things actually cost, and finished on the schedule we agreed on. After two contractors who ghosted us, that felt like a novelty.
    </blockquote>
    <div style={{ marginTop: 32, display: 'flex', alignItems: 'center', gap: 12 }}>
      <div style={{
        fontFamily: "'DM Sans', sans-serif", fontSize: 13, fontWeight: 500,
        color: 'var(--fg2)', letterSpacing: '0.02em',
      }}>
        Sarah &amp; Mike — Bozeman
      </div>
      <div style={{ color: 'var(--fg3)' }}>·</div>
      <div style={{
        fontFamily: "'DM Sans', sans-serif", textTransform: 'uppercase',
        letterSpacing: '0.14em', fontSize: 10, color: 'var(--fg3)', fontWeight: 500,
      }}>BATHROOM REMODEL · 2025</div>
    </div>
  </section>
);

Object.assign(window, { Testimonial });
