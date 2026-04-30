// Footer.jsx — service areas strip, contact lines, micro-legal.
const Footer = ({ onNavigate }) => (
  <footer style={{
    background: 'var(--bg2)',
    padding: '72px 48px 40px',
    borderTop: '1px solid rgba(235,219,178,0.06)',
    marginTop: 96,
  }}>
    <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr 1fr 1fr', gap: 48, maxWidth: 1200, margin: '0 auto' }}>
      <div>
        <img src="../../assets/logo-wordmark-cream.svg" alt="Heartwood Craft" style={{ height: 32, marginBottom: 20 }} />
        <div style={{ fontFamily: "'DM Sans', sans-serif", fontSize: 14, lineHeight: 1.7, color: 'var(--fg2)', maxWidth: 320 }}>
          Remodeling, decks, and custom carpentry in Bozeman and the Gallatin Valley. Work done properly, the first time.
        </div>
        <Rule style={{ marginTop: 20 }} />
      </div>
      <div>
        <Eyebrow style={{ marginBottom: 14 }}>Services</Eyebrow>
        <FooterLink>Bathroom remodeling</FooterLink>
        <FooterLink>Decks &amp; exterior</FooterLink>
        <FooterLink>Custom carpentry</FooterLink>
        <FooterLink>General remodeling</FooterLink>
      </div>
      <div>
        <Eyebrow style={{ marginBottom: 14 }}>Service Area</Eyebrow>
        <FooterLink>Bozeman</FooterLink>
        <FooterLink>Belgrade</FooterLink>
        <FooterLink>Gallatin Gateway</FooterLink>
      </div>
      <div>
        <Eyebrow style={{ marginBottom: 14 }}>Contact</Eyebrow>
        <FooterLink>eric@heartwoodcraft.com</FooterLink>
        <FooterLink>(406) 555-0123</FooterLink>
        <div style={{ marginTop: 20 }}>
          <Button variant="secondary" size="sm" onClick={() => onNavigate('contact')}>Start the Conversation</Button>
        </div>
      </div>
    </div>
    <div style={{
      maxWidth: 1200, margin: '56px auto 0', paddingTop: 24,
      borderTop: '1px solid rgba(235,219,178,0.06)',
      display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 16,
    }}>
      <div style={{ fontFamily: "'DM Sans', sans-serif", fontSize: 11, letterSpacing: '0.14em', textTransform: 'uppercase', color: 'var(--fg3)', fontWeight: 500 }}>
        Licensed · Insured · Bozeman, Montana
      </div>
      <div style={{ fontFamily: "'DM Sans', sans-serif", fontSize: 11, color: 'var(--fg3)' }}>
        © Heartwood Craft
      </div>
    </div>
  </footer>
);

const FooterLink = ({ children }) => (
  <a href="#" onClick={(e) => e.preventDefault()} style={{
    display: 'block',
    fontFamily: "'DM Sans', sans-serif",
    fontSize: 13,
    color: 'var(--fg2)',
    textDecoration: 'none',
    padding: '5px 0',
    transition: 'color 200ms',
  }}
  onMouseEnter={(e) => e.currentTarget.style.color = 'var(--fg1)'}
  onMouseLeave={(e) => e.currentTarget.style.color = 'var(--fg2)'}
  >{children}</a>
);

Object.assign(window, { Footer });
