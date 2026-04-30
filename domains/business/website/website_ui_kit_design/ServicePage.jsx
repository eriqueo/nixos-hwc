// ServicePage.jsx — reusable template for Bathrooms, Decks, Carpentry, Universal Design.
// Each service is a data object; the component renders the same editorial layout.

const SERVICE_CONTENT = {
  bathrooms: {
    eyebrow: 'SERVICE · 01',
    title: 'Bathrooms.',
    italic: 'where every morning starts.',
    lede: "Full gut remodels, refreshes, tub-to-shower conversions, targeted repairs. Waterproofing behind every tile — that's where the job lives or dies.",
    stats: [
      { n: '6–10', label: 'week typical job' },
      { n: '12', label: 'yr waterproofing warranty' },
      { n: '40+', label: 'bathrooms built' },
    ],
    sections: [
      { heading: 'What we build.', body: "Primary baths, guest baths, powder rooms, basement baths. Tub-to-shower conversions for aging in place. Vanity replacements with the plumbing redone properly. Full layout changes when the floor plan isn't working." },
      { heading: 'Where the quality lives.', body: "Waterproofing membranes behind every tiled wall and floor. Blocking in the walls for grab bars, even if you're not installing them yet. Exhaust fans sized for the room and ducted outside, not into the attic. The stuff you don't see is the stuff that matters." },
      { heading: 'What a scope looks like.', body: "Demo, framing adjustments, rough plumbing, rough electric, waterproofing, tile, finish plumbing, finish electric, paint, accessories, punch list. You'll see each line and what it includes. No ballparks." },
    ],
    projects: [
      { tag: 'BOZEMAN · 2025', title: 'Gut remodel on an early-90s primary bath.' },
      { tag: 'BELGRADE · 2024', title: 'Tub-to-shower conversion with curbless entry.' },
      { tag: 'GALLATIN GATEWAY · 2024', title: 'Basement guest bath added under the stairs.' },
    ],
    quote: {
      body: "The tile work is the kind of thing we'll be happy about for twenty years. Eric took time on the layout and it shows every morning.",
      attribution: 'Sarah & Mike — Bozeman',
      meta: 'BATHROOM REMODEL · 2025',
    },
  },
  decks: {
    eyebrow: 'SERVICE · 02',
    title: 'Decks.',
    italic: 'built for Montana freeze-thaw.',
    lede: "Cedar and composite decks, railings, stairs, pergolas, skirting. Flashing where water wants to get in, fasteners that won't bleed in twenty winters.",
    stats: [
      { n: '3–5', label: 'week typical job' },
      { n: 'Lifetime', label: 'fastener warranty' },
      { n: '25+', label: 'decks built' },
    ],
    sections: [
      { heading: 'What we build.', body: "New decks from ledger to railing cap. Rebuilds when the frame is sound but the surface is done. Pergolas and covered decks. Stairs to grade. Skirting and storage underneath. Railings that meet IRC code and actually look like something." },
      { heading: 'Where the quality lives.', body: "Flashing at the ledger board. Stainless or hot-dipped fasteners, not bright steel. Joist tape on every horizontal frame member. Proper drainage away from the house. Footings sized and dug for Gallatin County frost depth — 48 inches, not 36." },
      { heading: 'What a scope looks like.', body: "Design, permit if required, demo, footings, framing, decking, railings, stairs, skirting, stain or seal, punch list. Material options quoted side by side — cedar vs. composite vs. PVC. You pick, we build." },
    ],
    projects: [
      { tag: 'BOZEMAN · 2025', title: 'Cedar deck with pergola, south-facing.' },
      { tag: 'BELGRADE · 2024', title: 'Composite rebuild on a 20-year frame.' },
      { tag: 'GALLATIN GATEWAY · 2023', title: 'Two-level deck with hot-tub pad.' },
    ],
    quote: {
      body: "Third Montana winter and it looks like the day it was finished. No cupping, no bleeding fasteners, no loose railings.",
      attribution: 'Dan R. — Belgrade',
      meta: 'CEDAR DECK · 2023',
    },
  },
  carpentry: {
    eyebrow: 'SERVICE · 03',
    title: 'Custom carpentry.',
    italic: 'the part you live with every day.',
    lede: "Built-ins, trim, shelving, mantels, mudrooms. The kind of work that only shows itself when you've lived with it a while.",
    stats: [
      { n: '1–4', label: 'week typical job' },
      { n: '∞', label: 'revisions in shop drawing' },
      { n: 'Local', label: 'hardwoods when we can' },
    ],
    sections: [
      { heading: 'What we build.', body: "Built-in bookcases and media walls. Window seats with storage. Mudrooms with benches, hooks, and cubbies that fit the boots and bags you actually own. Fireplace mantels and surrounds. Shelving in awkward corners. Trim packages when the house needs a refresh." },
      { heading: 'Where the quality lives.', body: "Shop-drawn before a cut is made. Scribes to the wall so there's no gap, no matter how out of square the room is. Face frames, not just cabinet boxes. Drawer boxes with dovetails or sturdy box joints — not staples. Finish that will stand up to a decade of daily use." },
      { heading: 'What a scope looks like.', body: "Site measure, shop drawings for your approval, material selection, build in-shop, finish, install, punch list. You see the drawings before anything is built. Changes are cheapest on paper." },
    ],
    projects: [
      { tag: 'BOZEMAN · 2025', title: 'Built-in shelving on either side of a fireplace.' },
      { tag: 'BOZEMAN · 2024', title: 'Mudroom bench and locker wall in a mountain home.' },
      { tag: 'BELGRADE · 2024', title: 'Office built-in with fold-down desk.' },
    ],
    quote: {
      body: "The bookshelves look like they were part of the house from day one. That's what I wanted and that's what Eric delivered.",
      attribution: 'Kate L. — Bozeman',
      meta: 'BUILT-INS · 2024',
    },
  },
  'universal-design': {
    eyebrow: 'SERVICE · 04',
    title: 'Universal design.',
    italic: 'a home that works for every stage.',
    lede: "Aging-in-place remodels, accessible bathrooms, curbless showers, zero-step entries. Done so they look like design choices, not medical equipment.",
    stats: [
      { n: 'CAPS', label: 'certified approach' },
      { n: '36"', label: 'min clear doorway' },
      { n: '0', label: 'curbs at entries' },
    ],
    sections: [
      { heading: 'What we build.', body: "Curbless showers with proper slope and drainage. Grab bars that look like towel bars. Lever handles, rocker switches, and pull-out drawers in place of shelves. Zero-step entries. Wider halls and doorways. Ramps built into the landscape instead of bolted onto it." },
      { heading: 'Where the quality lives.', body: "Blocking for grab bars goes in every bathroom we touch, whether you need them today or not. Slopes planned so water goes to the drain, not the floor. Reach ranges, clear floor spaces, and turning radii follow ANSI A117.1 — not just what fits. Finishes that read as design, not clinical." },
      { heading: 'What a scope looks like.', body: "Consultation, accessibility audit of the space, scoped plan, permit if required, build. We'll flag what's easy now and what's worth holding for later. The goal is a home that works at 40 and still works at 80." },
    ],
    projects: [
      { tag: 'BOZEMAN · 2025', title: 'Primary suite remodel for aging in place.' },
      { tag: 'BELGRADE · 2024', title: 'Curbless shower and widened doorways after surgery.' },
      { tag: 'GALLATIN GATEWAY · 2023', title: 'Zero-step entry integrated into a front porch.' },
    ],
    quote: {
      body: "My mom moved in with us and none of the changes look like what you'd expect. It just feels like a nicer house now.",
      attribution: 'Pat W. — Bozeman',
      meta: 'AGING-IN-PLACE REMODEL · 2024',
    },
  },
};

const ServicePage = ({ service, onNavigate }) => {
  const c = SERVICE_CONTENT[service];
  if (!c) return null;

  return (
    <div>
      {/* HERO — editorial two-column with large title + italic tag */}
      <section style={{ padding: '120px 48px 72px', maxWidth: 1200, margin: '0 auto' }}>
        <Eyebrow style={{ marginBottom: 28 }}>{c.eyebrow}</Eyebrow>
        <h1 style={{
          fontFamily: "'Playfair Display', serif", fontSize: 96, fontWeight: 700,
          color: 'var(--fg1)', margin: 0, lineHeight: 0.95, letterSpacing: '-0.02em',
        }}>
          {c.title.replace('.', '')}<span style={{ color: 'var(--accent)' }}>.</span>
        </h1>
        <div style={{
          fontFamily: "'Playfair Display', serif", fontStyle: 'italic', fontWeight: 500,
          fontSize: 32, lineHeight: 1.2, color: 'var(--fg2)', marginTop: 20, maxWidth: '24ch',
        }}>{c.italic}</div>
        <Rule style={{ marginTop: 36, width: 120 }} />
        <p style={{
          fontFamily: "'DM Sans', sans-serif", fontSize: 18, lineHeight: 1.65,
          color: 'var(--fg2)', margin: '32px 0 0', maxWidth: '56ch',
        }}>{c.lede}</p>
      </section>

      {/* FEATURE PHOTO BAND */}
      <section style={{ padding: '0 48px', maxWidth: 1400, margin: '0 auto' }}>
        <PhotoPlaceholder aspect="21 / 9" label={`HERO · ${service.toUpperCase()}`} />
      </section>

      {/* STAT STRIP */}
      <section style={{ padding: '56px 48px', maxWidth: 1200, margin: '0 auto' }}>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 0, borderTop: '1px solid rgba(235,219,178,0.1)', borderBottom: '1px solid rgba(235,219,178,0.1)' }}>
          {c.stats.map((s, i) => (
            <div key={i} style={{
              padding: '32px 24px',
              borderLeft: i === 0 ? 'none' : '1px solid rgba(235,219,178,0.1)',
              display: 'flex', flexDirection: 'column', gap: 8,
            }}>
              <div style={{ fontFamily: "'Playfair Display', serif", fontSize: 56, fontWeight: 600, color: 'var(--accent)', lineHeight: 1, letterSpacing: '-0.02em' }}>{s.n}</div>
              <div style={{ fontFamily: "'DM Sans', sans-serif", fontSize: 13, color: 'var(--fg2)', textTransform: 'uppercase', letterSpacing: '0.14em', fontWeight: 500 }}>{s.label}</div>
            </div>
          ))}
        </div>
      </section>

      {/* THREE-BEAT SECTION STACK */}
      <section style={{ padding: '48px 48px 96px', maxWidth: 1200, margin: '0 auto' }}>
        {c.sections.map((s, i) => (
          <div key={i} style={{
            display: 'grid', gridTemplateColumns: '1fr 2fr', gap: 80,
            padding: '40px 0',
            borderTop: i === 0 ? 'none' : '1px solid rgba(235,219,178,0.08)',
          }}>
            <div>
              <div style={{ fontFamily: "'Playfair Display', serif", fontSize: 32, fontWeight: 600, color: 'var(--fg1)', lineHeight: 1.15, letterSpacing: '-0.01em' }}>{s.heading}</div>
              <Rule style={{ marginTop: 18, width: 48 }} />
            </div>
            <div style={{ fontFamily: "'DM Sans', sans-serif", fontSize: 16, lineHeight: 1.75, color: 'var(--fg2)', maxWidth: '60ch' }}>{s.body}</div>
          </div>
        ))}
      </section>

      {/* RECENT PROJECTS */}
      <section style={{ background: 'var(--bg2)', padding: '96px 48px' }}>
        <div style={{ maxWidth: 1200, margin: '0 auto' }}>
          <Eyebrow style={{ marginBottom: 20 }}>RECENT WORK</Eyebrow>
          <h2 style={{ fontFamily: "'Playfair Display', serif", fontSize: 44, fontWeight: 700, color: 'var(--fg1)', margin: 0, lineHeight: 1.1, letterSpacing: '-0.01em' }}>A few jobs from this category.</h2>
          <Rule style={{ marginTop: 24 }} />
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 16, marginTop: 48 }}>
            {c.projects.map((p, i) => (
              <div key={i} style={{ background: 'var(--bg1)', borderRadius: 12, overflow: 'hidden', border: '1px solid rgba(235,219,178,0.08)' }}>
                <PhotoPlaceholder aspect="4 / 3" label={`PROJECT · ${String(i+1).padStart(2,'0')}`} />
                <div style={{ padding: 22 }}>
                  <Eyebrow style={{ marginBottom: 8 }}>{p.tag}</Eyebrow>
                  <div style={{ fontFamily: "'Playfair Display', serif", fontSize: 20, color: 'var(--fg1)', lineHeight: 1.25, fontWeight: 500 }}>{p.title}</div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* PULL QUOTE */}
      <section style={{ padding: '96px 48px', maxWidth: 960, margin: '0 auto' }}>
        <Rule style={{ marginBottom: 40, width: 48 }} />
        <blockquote style={{
          fontFamily: "'Playfair Display', serif", fontSize: 32, fontWeight: 500,
          lineHeight: 1.35, color: 'var(--fg1)', margin: 0,
        }}>{c.quote.body}</blockquote>
        <div style={{ marginTop: 28, display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap' }}>
          <div style={{ fontFamily: "'DM Sans', sans-serif", fontSize: 13, fontWeight: 500, color: 'var(--fg2)' }}>{c.quote.attribution}</div>
          <div style={{ color: 'var(--fg3)' }}>·</div>
          <div style={{ fontFamily: "'DM Sans', sans-serif", textTransform: 'uppercase', letterSpacing: '0.14em', fontSize: 10, color: 'var(--fg3)', fontWeight: 500 }}>{c.quote.meta}</div>
        </div>
      </section>

      {/* CTA */}
      <section style={{ padding: '48px 48px 96px', maxWidth: 1200, margin: '0 auto' }}>
        <div style={{ background: 'var(--bg2)', border: '1px solid rgba(207,153,95,0.3)', borderRadius: 12, padding: 56, display: 'grid', gridTemplateColumns: '1.4fr 1fr', gap: 48, alignItems: 'center' }}>
          <div>
            <Eyebrow style={{ marginBottom: 16, color: 'var(--accent)' }}>NEXT STEP</Eyebrow>
            <h2 style={{ fontFamily: "'Playfair Display', serif", fontSize: 40, fontWeight: 700, color: 'var(--fg1)', margin: 0, lineHeight: 1.1 }}>Have a project like this in mind?</h2>
            <p style={{ fontFamily: "'DM Sans', sans-serif", fontSize: 15, lineHeight: 1.7, color: 'var(--fg2)', margin: '18px 0 0', maxWidth: '48ch' }}>A short message is enough to start. We'll read it, reach out, and find a time for a site visit.</p>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            <Button onClick={() => onNavigate('contact')}>Request a Consultation</Button>
            <Button variant="secondary" onClick={() => onNavigate('services')}>See Other Services</Button>
          </div>
        </div>
      </section>
    </div>
  );
};

Object.assign(window, { ServicePage, SERVICE_CONTENT });
