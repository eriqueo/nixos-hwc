// ContactForm.jsx — consultation form. Voice rules strictly enforced.
const ContactForm = () => {
  const [state, setState] = React.useState({ name: '', email: '', phone: '', project: '', service: 'Bathroom', area: 'Bozeman' });
  const [submitted, setSubmitted] = React.useState(false);

  const onField = (k) => (e) => setState((s) => ({ ...s, [k]: e.target.value }));
  const submit = (e) => { e.preventDefault(); setSubmitted(true); };

  if (submitted) {
    return (
      <section style={{ padding: '96px 48px', maxWidth: 760, margin: '0 auto' }}>
        <Eyebrow style={{ marginBottom: 20, color: 'var(--accent)' }}>MESSAGE RECEIVED</Eyebrow>
        <h2 style={{
          fontFamily: "'Playfair Display', serif", fontSize: 40, fontWeight: 700,
          lineHeight: 1.1, color: 'var(--fg1)', margin: 0,
        }}>Thanks — we'll be in touch.</h2>
        <Rule style={{ marginTop: 24 }} />
        <p style={{
          fontFamily: "'DM Sans', sans-serif", fontSize: 16, lineHeight: 1.7,
          color: 'var(--fg2)', marginTop: 24, maxWidth: '54ch',
        }}>
          Eric will reach out to learn more about your project and find a time that works for a site visit. No pressure — just a conversation about what's possible.
        </p>
        <div style={{ marginTop: 32 }}>
          <Button variant="secondary" onClick={() => setSubmitted(false)}>Send Another Message</Button>
        </div>
      </section>
    );
  }

  return (
    <section style={{ padding: '96px 48px', maxWidth: 1200, margin: '0 auto' }}>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1.2fr', gap: 80 }}>
        <div>
          <Eyebrow style={{ marginBottom: 20 }}>START THE CONVERSATION</Eyebrow>
          <h2 style={{
            fontFamily: "'Playfair Display', serif", fontSize: 44, fontWeight: 700,
            lineHeight: 1.1, color: 'var(--fg1)', margin: 0,
            letterSpacing: '-0.01em',
          }}>Tell us about your project.</h2>
          <Rule style={{ marginTop: 24 }} />
          <p style={{
            fontFamily: "'DM Sans', sans-serif", fontSize: 15, lineHeight: 1.7,
            color: 'var(--fg2)', marginTop: 24, maxWidth: '38ch',
          }}>
            A few details help us come to the site visit prepared. No pressure. Just a conversation about what's possible.
          </p>
          <div style={{ marginTop: 40, display: 'flex', flexDirection: 'column', gap: 16 }}>
            <ContactLine icon="mail" label="eric@heartwoodcraft.com" />
            <ContactLine icon="phone" label="(406) 555-0123" />
            <ContactLine icon="map-pin" label="Bozeman · Belgrade · Gallatin Gateway" />
          </div>
        </div>
        <form onSubmit={submit} style={{
          background: 'var(--bg2)', borderRadius: 12,
          border: '1px solid rgba(235,219,178,0.08)', padding: 40,
          display: 'flex', flexDirection: 'column', gap: 20,
        }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
            <Field label="YOUR NAME" placeholder="First and last" value={state.name} onChange={onField('name')} />
            <Field label="EMAIL" placeholder="you@domain.com" value={state.email} onChange={onField('email')} />
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
            <Field label="PHONE (OPTIONAL)" placeholder="(406) …" value={state.phone} onChange={onField('phone')} />
            <div>
              <Eyebrow style={{ marginBottom: 8 }}>SERVICE</Eyebrow>
              <select value={state.service} onChange={onField('service')} style={{
                width: '100%', background: 'var(--bg1)', border: '1px solid rgba(235,219,178,0.1)',
                color: 'var(--fg1)', padding: '14px', borderRadius: 8,
                fontFamily: "'DM Sans', sans-serif", fontSize: 14, boxSizing: 'border-box', outline: 'none',
              }}>
                <option>Bathroom</option>
                <option>Decks &amp; exterior</option>
                <option>Custom carpentry</option>
                <option>General remodeling</option>
                <option>Not sure yet</option>
              </select>
            </div>
          </div>
          <Field label="TELL US ABOUT YOUR PROJECT" placeholder="What's going on, what you're hoping for, what's not working now…" rows={5} value={state.project} onChange={onField('project')} />
          <div>
            <Eyebrow style={{ marginBottom: 10 }}>SERVICE AREA</Eyebrow>
            <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
              {['Bozeman', 'Belgrade', 'Gallatin Gateway', 'Other Gallatin Valley'].map((a) => (
                <button key={a} type="button" onClick={() => setState((s) => ({ ...s, area: a }))} style={{
                  padding: '8px 14px', borderRadius: 999,
                  border: state.area === a ? '1px solid var(--accent)' : '1px solid rgba(235,219,178,0.2)',
                  background: state.area === a ? 'var(--accent)' : 'transparent',
                  color: state.area === a ? 'var(--bg1)' : 'var(--fg2)',
                  fontFamily: "'DM Sans', sans-serif", fontSize: 12, fontWeight: 500, cursor: 'pointer',
                  transition: 'all 200ms',
                }}>{a}</button>
              ))}
            </div>
          </div>
          <div style={{ marginTop: 8 }}>
            <Button>Send the Message</Button>
          </div>
        </form>
      </div>
    </section>
  );
};

const ContactLine = ({ icon, label }) => (
  <div style={{ display: 'flex', alignItems: 'center', gap: 12, color: 'var(--fg2)', fontFamily: "'DM Sans', sans-serif", fontSize: 14 }}>
    <div style={{ color: 'var(--accent)' }}><Icon name={icon} size={18} /></div>
    {label}
  </div>
);

Object.assign(window, { ContactForm });
