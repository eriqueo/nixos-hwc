// Process.jsx — numbered 4-step stack.
const STEPS = [
  { n: '01', title: 'You reach out', body: "Tell us about your project — scope, timeline, what's bothering you. We'll reach out to learn more and find a time that works." },
  { n: '02', title: 'Site visit', body: 'Eric walks the space, measures what matters, and asks the questions that shape the estimate. Charged against larger jobs — it funds real planning.' },
  { n: '03', title: 'Scoped estimate', body: "A real number, broken out by trade. No ballparks, no surprises. You see exactly what's in and what isn't." },
  { n: '04', title: 'Work done properly', body: 'Clear schedule. Transparent communication. Details nobody sees — waterproofing, flashing, fasteners — are where the quality lives.' },
];

const Process = () => (
  <section style={{
    background: 'var(--bg2)',
    padding: '96px 48px',
  }}>
    <div style={{ maxWidth: 1200, margin: '0 auto', display: 'grid', gridTemplateColumns: '1fr 1.4fr', gap: 80, alignItems: 'start' }}>
      <div style={{ position: 'sticky', top: 120 }}>
        <Eyebrow style={{ marginBottom: 20 }}>HOW IT WORKS</Eyebrow>
        <h2 style={{
          fontFamily: "'Playfair Display', serif",
          fontSize: 44, fontWeight: 700, lineHeight: 1.1,
          letterSpacing: '-0.01em', color: 'var(--fg1)', margin: 0,
        }}>
          Process first.<br/>Everything follows from that.
        </h2>
        <Rule style={{ marginTop: 24 }} />
        <p style={{
          fontFamily: "'DM Sans', sans-serif", fontSize: 15, lineHeight: 1.7,
          color: 'var(--fg2)', marginTop: 24, maxWidth: '40ch',
        }}>
          Most contractor horror stories come from unclear scope and no communication. We fix that by running the same four steps on every job.
        </p>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
        {STEPS.map((s, i) => (
          <div key={s.n} style={{
            display: 'grid', gridTemplateColumns: '80px 1fr', gap: 32,
            padding: '28px 0',
            borderTop: i === 0 ? 'none' : '1px solid rgba(235,219,178,0.08)',
          }}>
            <div style={{
              fontFamily: "'Playfair Display', serif",
              fontSize: 36, color: 'var(--accent)', fontWeight: 500,
              lineHeight: 1,
            }}>{s.n}</div>
            <div>
              <div style={{
                fontFamily: "'Playfair Display', serif",
                fontSize: 26, fontWeight: 600, color: 'var(--fg1)',
                lineHeight: 1.2, marginBottom: 10,
              }}>{s.title}</div>
              <div style={{
                fontFamily: "'DM Sans', sans-serif", fontSize: 15,
                lineHeight: 1.7, color: 'var(--fg2)', maxWidth: '52ch',
              }}>{s.body}</div>
            </div>
          </div>
        ))}
      </div>
    </div>
  </section>
);

Object.assign(window, { Process });
