// Pages.jsx — simple page containers that compose the other components.
const HomePage = ({ onNavigate }) => (
  <div>
    <Hero onNavigate={onNavigate} />
    <Services onNavigate={onNavigate} />
    <Process />
    <Testimonial />
    <section style={{ padding: '72px 48px', maxWidth: 1200, margin: '0 auto', textAlign: 'center' }}>
      <Eyebrow style={{ marginBottom: 18, color: 'var(--accent)' }}>NEXT STEP</Eyebrow>
      <h2 style={{ fontFamily: "'Playfair Display', serif", fontSize: 40, fontWeight: 700, color: 'var(--fg1)', margin: 0, lineHeight: 1.15 }}>
        Have a project in mind?
      </h2>
      <p style={{ fontFamily: "'DM Sans', sans-serif", fontSize: 16, lineHeight: 1.7, color: 'var(--fg2)', margin: '20px auto 32px', maxWidth: '44ch' }}>
        A short message is enough to start. We'll read it, reach out, and find a time for a site visit.
      </p>
      <Button onClick={() => onNavigate('contact')}>Request a Consultation</Button>
    </section>
  </div>
);

const ServicesPage = ({ onNavigate }) => {
  const cards = [
    { svc: 'bathrooms', title: 'Bathrooms', sub: 'where every morning starts.' },
    { svc: 'decks', title: 'Decks', sub: 'built for Montana freeze-thaw.' },
    { svc: 'carpentry', title: 'Custom carpentry', sub: 'the part you live with every day.' },
    { svc: 'universal-design', title: 'Universal design', sub: 'a home for every stage.' },
  ];
  return (
    <div>
      <section style={{ padding: '120px 48px 0', maxWidth: 1200, margin: '0 auto' }}>
        <Eyebrow style={{ marginBottom: 20 }}>SERVICES</Eyebrow>
        <h1 style={{ fontFamily: "'Playfair Display', serif", fontSize: 64, fontWeight: 700, color: 'var(--fg1)', margin: 0, lineHeight: 1.05, letterSpacing: '-0.015em', maxWidth: '14ch' }}>
          What we build.
        </h1>
        <Rule style={{ marginTop: 32, width: 96 }} />
        <p style={{ fontFamily: "'DM Sans', sans-serif", fontSize: 18, lineHeight: 1.6, color: 'var(--fg2)', margin: '28px 0 0', maxWidth: '52ch' }}>
          Four categories. Each one scoped before we start, priced without surprises, and done properly the first time.
        </p>
      </section>
      <section style={{ padding: '72px 48px 96px', maxWidth: 1200, margin: '0 auto' }}>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 16 }}>
          {cards.map((c) => (
            <div key={c.svc} onClick={() => onNavigate(`service:${c.svc}`)} style={{ cursor: 'pointer', background: 'var(--bg2)', borderRadius: 12, overflow: 'hidden', border: '1px solid rgba(235,219,178,0.08)', transition: 'border-color 200ms' }}
              onMouseEnter={(e) => e.currentTarget.style.borderColor = 'rgba(207,153,95,0.4)'}
              onMouseLeave={(e) => e.currentTarget.style.borderColor = 'rgba(235,219,178,0.08)'}
            >
              <PhotoPlaceholder aspect="16 / 10" label={c.svc.toUpperCase()} />
              <div style={{ padding: 28 }}>
                <div style={{ fontFamily: "'Playfair Display', serif", fontSize: 32, fontWeight: 700, color: 'var(--fg1)', lineHeight: 1.1 }}>
                  {c.title}<span style={{ color: 'var(--accent)' }}>.</span>
                </div>
                <div style={{ fontFamily: "'Playfair Display', serif", fontStyle: 'italic', fontSize: 18, color: 'var(--fg2)', marginTop: 8 }}>{c.sub}</div>
                <div style={{ marginTop: 16, display: 'flex', alignItems: 'center', gap: 8, fontFamily: "'DM Sans', sans-serif", fontSize: 13, fontWeight: 500, color: 'var(--fg1)', borderBottom: '1px solid var(--accent)', alignSelf: 'flex-start', width: 'fit-content', paddingBottom: 4 }}>
                  See the page <Icon name="arrow-right" size={14} />
                </div>
              </div>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
};

const ProcessPage = () => (
  <div>
    <section style={{ padding: '120px 48px 48px', maxWidth: 1200, margin: '0 auto' }}>
      <Eyebrow style={{ marginBottom: 20 }}>PROCESS</Eyebrow>
      <h1 style={{ fontFamily: "'Playfair Display', serif", fontSize: 64, fontWeight: 700, color: 'var(--fg1)', margin: 0, lineHeight: 1.05, letterSpacing: '-0.015em', maxWidth: '14ch' }}>
        How a job runs, start to finish.
      </h1>
      <Rule style={{ marginTop: 32, width: 96 }} />
    </section>
    <Process />
    <Testimonial />
  </div>
);

const AboutPage = () => (
  <div>
    <section style={{ padding: '120px 48px 48px', maxWidth: 1200, margin: '0 auto', display: 'grid', gridTemplateColumns: '1.2fr 1fr', gap: 80, alignItems: 'start' }}>
      <div>
        <Eyebrow style={{ marginBottom: 20 }}>ABOUT</Eyebrow>
        <h1 style={{ fontFamily: "'Playfair Display', serif", fontSize: 56, fontWeight: 700, color: 'var(--fg1)', margin: 0, lineHeight: 1.08, letterSpacing: '-0.015em' }}>
          Eric, and the work.
        </h1>
        <Rule style={{ marginTop: 32, width: 96 }} />
        <p style={{ fontFamily: "'DM Sans', sans-serif", fontSize: 17, lineHeight: 1.7, color: 'var(--fg2)', margin: '32px 0 20px', maxWidth: '52ch' }}>
          Heartwood Craft is a Bozeman remodeling company run by Eric. Bathrooms, decks, custom carpentry, general remodeling.
        </p>
        <p style={{ fontFamily: "'DM Sans', sans-serif", fontSize: 17, lineHeight: 1.7, color: 'var(--fg2)', margin: '0 0 20px', maxWidth: '52ch' }}>
          The name comes from heartwood — the dense, structural core of a tree. The part that holds everything up. That's the work: substance over flash, structure over shortcuts.
        </p>
        <p style={{ fontFamily: "'DM Sans', sans-serif", fontSize: 17, lineHeight: 1.7, color: 'var(--fg2)', margin: 0, maxWidth: '52ch' }}>
          Licensed, insured, local. Montana freeze-thaw, Gallatin County permitting, and local suppliers are built into how every job is planned.
        </p>
      </div>
      <div>
        <PhotoPlaceholder aspect="4 / 5" label="PORTRAIT · ERIC" style={{ borderRadius: 12 }} />
      </div>
    </section>
  </div>
);

const ContactPage = () => <ContactForm />;

Object.assign(window, { HomePage, ServicesPage, ProcessPage, AboutPage, ContactPage });
