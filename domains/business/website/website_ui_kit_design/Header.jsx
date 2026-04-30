// Header.jsx — fixed top header. Charcoal, orange rule underneath on scroll.
const Header = ({ current, onNavigate }) => {
  const [scrolled, setScrolled] = React.useState(false);
  const [servicesOpen, setServicesOpen] = React.useState(false);
  React.useEffect(() => {
    const el = document.querySelector('.hwc-scroll');
    if (!el) return;
    const onScroll = () => setScrolled(el.scrollTop > 8);
    el.addEventListener('scroll', onScroll);
    return () => el.removeEventListener('scroll', onScroll);
  }, []);

  const navItem = (label, route) => (
    <a
      onClick={(e) => { e.preventDefault(); onNavigate(route); setServicesOpen(false); }}
      href="#"
      style={{
        fontFamily: "'DM Sans', sans-serif",
        fontSize: 13,
        color: current === route ? 'var(--fg1)' : 'var(--fg2)',
        textDecoration: 'none',
        fontWeight: 500,
        letterSpacing: '0.01em',
        padding: '6px 0',
        borderBottom: current === route ? '1px solid var(--accent)' : '1px solid transparent',
        transition: 'color 200ms, border-color 200ms',
      }}
    >{label}</a>
  );

  const SUB = [
    { route: 'service:bathrooms', label: 'Bathrooms' },
    { route: 'service:decks', label: 'Decks' },
    { route: 'service:carpentry', label: 'Custom Carpentry' },
    { route: 'service:universal-design', label: 'Universal Design' },
  ];

  return (
    <header style={{
      position: 'sticky', top: 0, zIndex: 10,
      background: 'rgba(35,40,45,0.92)',
      backdropFilter: 'blur(8px)',
      height: 72, padding: '0 48px',
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      borderBottom: scrolled ? '1px solid rgba(207,153,95,0.45)' : '1px solid transparent',
      transition: 'border-color 200ms',
    }}>
      <a href="#" onClick={(e) => { e.preventDefault(); onNavigate('home'); }}>
        <img src="../../assets/logo-header-cream.webp" alt="Heartwood Craft" style={{ height: 44, display: 'block' }} />
      </a>
      <nav style={{ display: 'flex', gap: 32, alignItems: 'center' }}>
        <div style={{ position: 'relative' }} onMouseEnter={() => setServicesOpen(true)} onMouseLeave={() => setServicesOpen(false)}>
          {navItem('Services', 'services')}
          {servicesOpen && (
            <div style={{ position: 'absolute', top: 'calc(100% + 16px)', left: -20, background: 'var(--bg2)', border: '1px solid rgba(235,219,178,0.1)', borderRadius: 10, padding: 8, minWidth: 220, boxShadow: '0 12px 40px rgba(0,0,0,0.5)' }}>
              {SUB.map((s) => (
                <a key={s.route} href="#" onClick={(e) => { e.preventDefault(); onNavigate(s.route); setServicesOpen(false); }} style={{ display: 'block', padding: '10px 14px', fontFamily: "'DM Sans', sans-serif", fontSize: 13, color: 'var(--fg2)', textDecoration: 'none', borderRadius: 6, transition: 'background 150ms' }}
                  onMouseEnter={(e) => e.currentTarget.style.background = 'var(--bg1)'}
                  onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}
                >{s.label}</a>
              ))}
            </div>
          )}
        </div>
        {navItem('Process', 'process')}
        {navItem('About', 'about')}
        <Button size="sm" onClick={() => onNavigate('contact')}>Request a Consultation</Button>
      </nav>
    </header>
  );
};

Object.assign(window, { Header });
