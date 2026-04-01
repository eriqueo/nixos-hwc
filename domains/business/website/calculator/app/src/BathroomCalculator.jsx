import { useState } from "react";

// ─── Brand tokens ────────────────────────────────────────────────────────────
const T = {
  copper: "#cf995f",
  copperLight: "rgba(207,153,95,0.1)",
  copperBorder: "rgba(207,153,95,0.25)",
  copperGlow: "rgba(207,153,95,0.15)",
  bg: "#1a1e25",
  surface: "rgba(255,255,255,0.03)",
  surfaceHover: "rgba(255,255,255,0.06)",
  surfaceSelected: "rgba(207,153,95,0.1)",
  border: "#3a3f46",
  borderHover: "#5a5f66",
  white: "#ffffff",
  text: "#e8e4df",
  textMuted: "#9ca3af",
  textDim: "#6b7280",
  textDark: "#5a5f66",
  charcoal: "#23282d",
};

const STEPS = [
  { id: "project_type", question: "What kind of project is this?", subtitle: "Sets the baseline for everything else.", why: "A gut remodel means all-new plumbing, waterproofing, and subfloor. A refresh keeps most of that in place. This one question changes the estimate by thousands.", type: "cards", options: [
    { value: "full_gut", label: "Full gut remodel", desc: "Down to studs \u2014 new everything", icon: "GR" },
    { value: "refresh", label: "Refresh & update", desc: "New finishes, keep the layout", icon: "RF" },
    { value: "tub_to_shower", label: "Tub \u2192 shower conversion", desc: "Remove tub, build walk-in", icon: "TS" },
    { value: "specific_fix", label: "Specific repair", desc: "Leak, damage, or targeted fix", icon: "FX" },
  ]},
  { id: "bathroom_size", question: "How big is the space?", subtitle: "Rough estimate is fine \u2014 we measure on-site.", why: "Tile, waterproofing, and heated floors are priced per square foot. Even a rough size meaningfully changes the range.", type: "cards", options: [
    { value: "small", label: "Small", desc: "Under 40 sq ft \u00b7 half bath", icon: "S" },
    { value: "medium", label: "Medium", desc: "40\u201370 sq ft \u00b7 standard full", icon: "M" },
    { value: "large", label: "Large", desc: "70\u2013100 sq ft \u00b7 primary bath", icon: "L" },
    { value: "xl", label: "Extra large", desc: "100+ sq ft \u00b7 luxury suite", icon: "XL" },
  ]},
  { id: "shower_tub", question: "Shower, tub, or both?", subtitle: "What you want in the finished bathroom.", why: "Separate tub and shower needs more plumbing, tile, and space. The rough-in alone can add $2,000+.", type: "cards", options: [
    { value: "shower_only", label: "Shower only", desc: "Walk-in, no tub", icon: "SH" },
    { value: "tub_shower", label: "Tub + shower combo", desc: "Bathtub with showerhead", icon: "TB" },
    { value: "both_separate", label: "Both, separate", desc: "Freestanding tub + shower stall", icon: "B" },
    { value: "tub_only", label: "Tub only", desc: "Soaking tub, no shower", icon: "TU" },
  ]},
  { id: "tile_level", question: "Tile level?", subtitle: "Usually the biggest design decision \u2014 and cost driver.", why: "Basic subway runs $3\u20135/sq ft installed. Natural stone or complex mosaics hit $25+/sq ft and take 3x longer. Tile can swing a job by $5,000+.", type: "cards", options: [
    { value: "basic", label: "Clean & simple", desc: "Subway, single pattern, minimal accent", icon: "I" },
    { value: "mid", label: "Designed & detailed", desc: "Mixed patterns, accent niche, quality tile", icon: "II" },
    { value: "high", label: "Custom & premium", desc: "Natural stone, mosaic, floor-to-ceiling", icon: "III" },
  ]},
  { id: "fixtures", question: "Fixture level?", subtitle: "Faucets, showerheads, hardware \u2014 what you touch daily.", why: "A Moen faucet runs $150. A Brizo runs $600. Multiply across showerhead, drain, hardware, accessories \u2014 tier adds $2K\u2013$8K.", type: "cards", options: [
    { value: "standard", label: "Good quality basics", desc: "Moen, Delta \u2014 reliable and clean", icon: "$" },
    { value: "upgraded", label: "Upgraded selections", desc: "Kohler, Brizo \u2014 designer finishes", icon: "$$" },
    { value: "premium", label: "Premium / luxury", desc: "High-end brands, statement pieces", icon: "$$$" },
  ]},
  { id: "features", question: "Any extras?", subtitle: "Select all that apply, or skip.", why: "Each adds labor and materials. Heated floors alone need an electrician, dedicated circuit, and Ditra membrane \u2014 $1,200\u2013$1,800.", type: "multi", options: [
    { value: "heated_floor", label: "Heated floors", add: 1800 },
    { value: "niches", label: "Shower niches", add: 1000 },
    { value: "bench", label: "Shower bench", add: 1400 },
    { value: "double_vanity", label: "Double vanity", add: 2200 },
    { value: "lighting", label: "New lighting / electrical", add: 1500 },
    { value: "ventilation", label: "New ventilation / fan", add: 800 },
  ]},
  { id: "timeline", question: "When would you start?", subtitle: "No pressure \u2014 helps us plan.", why: "Timeline affects scheduling. Planning 3+ months out gives time to order specialty materials at better pricing.", type: "cards", options: [
    { value: "asap", label: "As soon as possible", desc: "Ready to move forward", icon: "\u2192" },
    { value: "1_3_months", label: "1\u20133 months", desc: "Planning ahead", icon: "\u25c7" },
    { value: "3_6_months", label: "3\u20136 months", desc: "Still in the thinking stage", icon: "\u25c7\u25c7" },
    { value: "just_exploring", label: "Just exploring", desc: "Curious about costs", icon: "\u2026" },
  ]},
];

// ─── Pricing (recalibrated March 2026) ───────────────────────────────────────
function calculateRange(state) {
  const bases = { full_gut: [25000, 40000], refresh: [12000, 22000], tub_to_shower: [12000, 20000], specific_fix: [3000, 10000] };
  const sizeMult = { small: 0.7, medium: 1.0, large: 1.35, xl: 1.75 };
  const showerAdd = { shower_only: [0, 0], tub_shower: [1500, 3000], both_separate: [5000, 9000], tub_only: [-500, -1000] };
  const tileMult = { basic: 0.85, mid: 1.0, high: 1.35 };
  const fixtureAdd = { standard: [0, 0], upgraded: [2500, 5000], premium: [6000, 12000] };
  const featureAdd = { heated_floor: 1800, niches: 1000, bench: 1400, double_vanity: 2200, lighting: 1500, ventilation: 800 };

  let [lo, hi] = bases[state.project_type] || [15000, 25000];
  lo *= sizeMult[state.bathroom_size] || 1; hi *= sizeMult[state.bathroom_size] || 1;
  const [sL, sH] = showerAdd[state.shower_tub] || [0, 0]; lo += sL; hi += sH;
  lo *= tileMult[state.tile_level] || 1; hi *= tileMult[state.tile_level] || 1;
  const [fL, fH] = fixtureAdd[state.fixtures] || [0, 0]; lo += fL; hi += fH;
  (state.features || []).forEach(f => { lo += (featureAdd[f] || 0) * 0.8; hi += (featureAdd[f] || 0) * 1.2; });
  return [Math.round(lo / 500) * 500, Math.round(hi / 500) * 500];
}

// ─── Helpers ─────────────────────────────────────────────────────────────────
function getLabel(stepId, value) {
  const s = STEPS.find(s => s.id === stepId);
  const o = s?.options.find(o => o.value === value);
  return o ? o.label : "\u2014";
}
function getAttribution() {
  try {
    const a = JSON.parse(sessionStorage.getItem("hwc_attribution") || "{}");
    return { utm_source: a.utm_source||null, utm_medium: a.utm_medium||null, utm_campaign: a.utm_campaign||null, gclid: a.gclid||null, referrer: a.referrer||null, landing_page: a.landing_page||null, pages_viewed: parseInt(sessionStorage.getItem("hwc_pages_viewed")||"0",10) };
  } catch { return {}; }
}
function fire(name, params) { if (typeof gtag === "function") gtag("event", name, params); }
const fmt = n => "$" + n.toLocaleString();
const WEBHOOK = "https://hwc.ocelot-wahoo.ts.net/webhook/calculator-lead";

// ─── Shared input style ──────────────────────────────────────────────────────
const inputStyle = { width: "100%", padding: "12px 14px", borderRadius: 8, border: `1px solid ${T.border}`, background: T.surface, fontSize: 14, fontFamily: "inherit", outline: "none", color: T.white, boxSizing: "border-box" };

// ─── Component ───────────────────────────────────────────────────────────────
export default function BathroomCalculator() {
  const [step, setStep] = useState(0);
  const [state, setState] = useState({});
  const [contact, setContact] = useState({ name: "", email: "", phone: "", preferred_date: "", preferred_time: "" });
  const [phase, setPhase] = useState("quiz");
  const [showWhy, setShowWhy] = useState(false);
  const [fading, setFading] = useState(false);
  const [reportUrl, setReportUrl] = useState(null);
  const [submitting, setSubmitting] = useState(false);

  const cur = STEPS[step];
  const [lo, hi] = step >= STEPS.length ? calculateRange(state) : [0, 0];

  const fade = cb => { setFading(true); setTimeout(() => { cb(); setShowWhy(false); setTimeout(() => setFading(false), 30); }, 220); };
  const goNext = () => fade(() => { const n = step + 1; setStep(n); if (n >= STEPS.length) setPhase("gate"); fire("calculator_step", { step_number: step + 1, step_id: cur?.id }); });
  const goBack = () => { if (step > 0) fade(() => setStep(s => s - 1)); };
  const pick = (id, v) => { setState(p => ({ ...p, [id]: v })); setTimeout(goNext, 180); };
  const toggle = v => setState(p => { const f = p.features || []; return { ...p, features: f.includes(v) ? f.filter(x => x !== v) : [...f, v] }; });
  const reset = () => fade(() => { setStep(0); setState({}); setContact({ name: "", email: "", phone: "", preferred_date: "", preferred_time: "" }); setPhase("quiz"); setReportUrl(null); });

  const submitBasic = async () => {
    if (!contact.name || !contact.phone) return;
    try { await fetch(WEBHOOK, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action: "calculator_lead_basic", contact: { name: contact.name, phone: contact.phone }, projectState: state, estimate: { low: lo, high: hi }, timestamp: new Date().toISOString(), source: "website_calculator", ...getAttribution() }) }); } catch {}
    fire("calculator_lead_basic", { estimate_low: lo, estimate_high: hi });
    fade(() => setPhase("revealed"));
  };

  const submitFull = async () => {
    if (!contact.email) return;
    setSubmitting(true);
    try {
      const res = await fetch(WEBHOOK, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action: "calculator_lead_full", contact, projectState: state, estimate: { low: lo, high: hi }, timestamp: new Date().toISOString(), source: "website_calculator", calculator: "bathroom", source_page: window.location.pathname, ...getAttribution() }) });
      const data = await res.json();
      setReportUrl(data.reportUrl || null);
    } catch { setReportUrl(null); }
    fire("calculator_lead_full", { estimate_low: lo, estimate_high: hi });
    setSubmitting(false);
    fade(() => setPhase("submitted"));
  };

  const progress = Math.min((step / STEPS.length) * 100, 100);
  const pills = () => (
    <div style={{ display: "flex", flexWrap: "wrap", gap: 4, justifyContent: "center", margin: "8px 0 20px" }}>
      {Object.entries(state).filter(([k]) => k !== "features").map(([k, v]) => <span key={k} style={{ display: "inline-block", fontSize: 10, padding: "3px 10px", borderRadius: 20, fontWeight: 500, border: `1px solid ${T.border}`, color: T.textMuted }}>{getLabel(k, v)}</span>)}
      {(state.features || []).map(f => <span key={f} style={{ display: "inline-block", fontSize: 10, padding: "3px 10px", borderRadius: 20, fontWeight: 500, border: `1px solid ${T.copperBorder}`, color: T.copper }}>{getLabel("features", f)}</span>)}
    </div>
  );

  return (
    <div style={{ maxWidth: 540, margin: "0 auto", padding: "0 1.25rem 2rem", fontFamily: "'DM Sans', sans-serif", color: T.text, background: T.bg, borderRadius: 16 }}>
      <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&family=Playfair+Display:wght@600;700&display=swap" rel="stylesheet" />

      {/* Header */}
      <div style={{ textAlign: "center", padding: "2.5rem 0 1.5rem" }}>
        <div style={{ display: "inline-block", fontSize: 10, fontWeight: 600, letterSpacing: "0.12em", textTransform: "uppercase", color: T.copper, border: `1px solid ${T.copperBorder}`, padding: "4px 14px", borderRadius: 20, marginBottom: 14 }}>Free estimate tool</div>
        <h1 style={{ fontFamily: "'Playfair Display', serif", fontSize: 28, fontWeight: 700, color: T.white, margin: "0 0 8px", lineHeight: 1.15 }}>What will your remodel cost?</h1>
        <p style={{ fontSize: 14, color: T.textMuted, margin: 0, lineHeight: 1.5 }}>7 questions. 2 minutes. Real Bozeman pricing.</p>
      </div>

      {/* Progress */}
      {phase === "quiz" && <div style={{ height: 2, background: T.border, borderRadius: 1, margin: "0 0 2rem", overflow: "hidden" }}><div style={{ height: "100%", background: `linear-gradient(90deg, ${T.copper}, #e8b878)`, borderRadius: 1, width: `${progress}%`, transition: "width 0.5s cubic-bezier(0.4,0,0.2,1)" }} /></div>}

      <div style={{ opacity: fading ? 0 : 1, transform: fading ? "translateY(10px)" : "translateY(0)", transition: "all 0.22s ease" }}>

        {/* ═══ QUIZ ═══ */}
        {phase === "quiz" && cur && <div>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}>
            <span style={{ fontSize: 12, color: T.textDim, fontWeight: 500 }}>{step + 1} of {STEPS.length}</span>
            {step > 0 && <button onClick={reset} style={{ fontSize: 11, color: T.textDim, background: "none", border: "none", cursor: "pointer", fontFamily: "inherit", textDecoration: "underline", textUnderlineOffset: 2 }}>start over</button>}
          </div>
          <h2 style={{ fontSize: 21, fontWeight: 700, color: T.white, margin: "0 0 4px", lineHeight: 1.25 }}>{cur.question}</h2>
          <p style={{ fontSize: 13, color: T.textDim, margin: "0 0 8px", lineHeight: 1.4 }}>{cur.subtitle}</p>
          {cur.why && <>
            <button onClick={() => setShowWhy(!showWhy)} style={{ fontSize: 12, color: T.copper, background: "none", border: "none", cursor: "pointer", fontFamily: "inherit", padding: "0 0 12px", fontWeight: 500, opacity: 0.8 }}>{showWhy ? "got it \u25b4" : "why do we ask this?"}</button>
            {showWhy && <div style={{ fontSize: 12, color: T.textMuted, background: T.copperLight, borderLeft: `2px solid ${T.copper}`, padding: "10px 14px", margin: "0 0 14px", borderRadius: "0 6px 6px 0", lineHeight: 1.5 }}>{cur.why}</div>}
          </>}

          {cur.type === "cards" && <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            {cur.options.map(o => { const sel = state[cur.id] === o.value; return (
              <button key={o.value} onClick={() => pick(cur.id, o.value)} style={{ padding: "14px 16px", borderRadius: 10, cursor: "pointer", textAlign: "left", border: `1px solid ${sel ? T.copper : T.border}`, background: sel ? T.surfaceSelected : T.surface, transition: "all 0.15s", fontFamily: "inherit", display: "flex", alignItems: "center", gap: 14, width: "100%", color: T.text }}
                onMouseEnter={e => { if (!sel) { e.currentTarget.style.borderColor = T.borderHover; e.currentTarget.style.background = T.surfaceHover; }}}
                onMouseLeave={e => { if (!sel) { e.currentTarget.style.borderColor = T.border; e.currentTarget.style.background = T.surface; }}}>
                <div style={{ width: 36, height: 36, borderRadius: 8, display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0, fontSize: 13, fontWeight: 700, color: T.copper, background: T.copperLight, border: `1px solid ${T.copperBorder}`, letterSpacing: "-0.02em" }}>{o.icon}</div>
                <div><div style={{ fontSize: 14, fontWeight: 600, color: T.white }}>{o.label}</div><div style={{ fontSize: 12, color: T.textDim, lineHeight: 1.3 }}>{o.desc}</div></div>
              </button>
            ); })}
          </div>}

          {cur.type === "multi" && <div>
            <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
              {cur.options.map(o => { const chk = (state.features || []).includes(o.value); return (
                <button key={o.value} onClick={() => toggle(o.value)} style={{ padding: "11px 14px", borderRadius: 8, cursor: "pointer", textAlign: "left", border: `1px solid ${chk ? T.copper : T.border}`, background: chk ? T.surfaceSelected : T.surface, transition: "all 0.15s", fontFamily: "inherit", display: "flex", alignItems: "center", gap: 10, width: "100%", color: T.text }}>
                  <div style={{ width: 18, height: 18, borderRadius: 3, flexShrink: 0, border: `1.5px solid ${chk ? T.copper : T.borderHover}`, background: chk ? T.copper : "transparent", display: "flex", alignItems: "center", justifyContent: "center", color: T.charcoal, fontSize: 11, fontWeight: 700, transition: "all 0.15s" }}>{chk && "\u2713"}</div>
                  <span style={{ fontSize: 13, fontWeight: 600, color: T.text }}>{o.label}</span>
                  <span style={{ fontSize: 11, color: T.textDim, marginLeft: "auto", flexShrink: 0 }}>+${o.add.toLocaleString()}</span>
                </button>
              ); })}
            </div>
            <button onClick={goNext} style={{ marginTop: 12, width: "100%", padding: "13px 0", borderRadius: 8, cursor: "pointer", border: "none", background: T.copper, color: T.charcoal, fontSize: 14, fontWeight: 700, fontFamily: "inherit" }}>
              {(state.features || []).length === 0 ? "None of these \u2014 continue" : `Continue with ${(state.features || []).length} selected`}
            </button>
          </div>}

          {step > 0 && cur.type === "cards" && <button onClick={goBack} style={{ marginTop: 14, padding: "6px 0", background: "none", border: "none", cursor: "pointer", fontSize: 12, color: T.textDark, fontFamily: "inherit" }}>\u2190 back</button>}
        </div>}

        {/* ═══ GATE ═══ */}
        {phase === "gate" && <div>
          <div style={{ textAlign: "center", padding: "1.5rem 0" }}>
            <div style={{ fontSize: 13, color: T.textDim, marginBottom: 6, fontWeight: 500 }}>Your estimated range</div>
            <div style={{ fontFamily: "'Playfair Display', serif", fontSize: 42, fontWeight: 700, color: T.white, lineHeight: 1, filter: "blur(14px)", userSelect: "none", WebkitUserSelect: "none" }}>{fmt(lo)} \u2013 {fmt(hi)}</div>
          </div>
          {pills()}
          <div style={{ height: 1, background: T.border, margin: "0 0 20px" }} />
          <div style={{ textAlign: "center", marginBottom: 16 }}>
            <h3 style={{ fontFamily: "'Playfair Display', serif", fontSize: 22, fontWeight: 700, color: T.white, margin: "0 0 6px" }}>Unlock your estimate</h3>
            <p style={{ fontSize: 13, color: T.textDim, margin: 0, lineHeight: 1.5 }}>Name and phone reveals the range \u2014 plus a project summary you can keep.</p>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            <input type="text" placeholder="Your name" value={contact.name} onChange={e => setContact(c => ({ ...c, name: e.target.value }))} style={inputStyle} onFocus={e => e.target.style.borderColor = T.copper} onBlur={e => e.target.style.borderColor = T.border} />
            <input type="tel" placeholder="Phone number" value={contact.phone} onChange={e => setContact(c => ({ ...c, phone: e.target.value }))} style={inputStyle} onFocus={e => e.target.style.borderColor = T.copper} onBlur={e => e.target.style.borderColor = T.border} />
            <button onClick={submitBasic} disabled={!contact.name || !contact.phone} style={{ width: "100%", padding: "13px 0", borderRadius: 8, cursor: contact.name && contact.phone ? "pointer" : "not-allowed", border: "none", background: contact.name && contact.phone ? T.copper : T.border, color: contact.name && contact.phone ? T.charcoal : T.textDark, fontSize: 14, fontWeight: 700, fontFamily: "inherit" }}>Reveal my estimate \u2192</button>
          </div>
          <button onClick={reset} style={{ marginTop: 14, width: "100%", padding: "6px 0", background: "none", border: "none", cursor: "pointer", fontSize: 12, color: T.textDark, fontFamily: "inherit", textAlign: "center" }}>start over</button>
        </div>}

        {/* ═══ REVEALED ═══ */}
        {phase === "revealed" && <div>
          <div style={{ textAlign: "center", padding: "1rem 0 0.5rem" }}>
            <div style={{ fontSize: 13, color: T.textDim, marginBottom: 6, fontWeight: 500 }}>Your bathroom remodel estimate</div>
            <div style={{ fontFamily: "'Playfair Display', serif", fontSize: 42, fontWeight: 700, color: T.white, lineHeight: 1 }}>{fmt(lo)} \u2013 {fmt(hi)}</div>
          </div>

          {/* Summary card */}
          <div style={{ background: T.surface, border: `1px solid ${T.border}`, borderRadius: 10, padding: "20px 24px", marginTop: 20 }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16, paddingBottom: 12, borderBottom: `1px solid ${T.border}` }}>
              <div style={{ fontFamily: "'Playfair Display', serif", fontSize: 14, fontWeight: 600, color: T.copper }}>Heartwood Craft</div>
              <div style={{ fontSize: 11, color: T.textDark }}>{new Date().toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" })}</div>
            </div>
            {[["Project", "project_type"], ["Size", "bathroom_size"], ["Layout", "shower_tub"], ["Tile", "tile_level"], ["Fixtures", "fixtures"], ["Timeline", "timeline"]].map(([label, id]) => (
              <div key={id} style={{ display: "flex", justifyContent: "space-between", padding: "6px 0", fontSize: 13, borderBottom: `1px solid rgba(58,63,70,0.5)` }}>
                <span style={{ color: T.textDim }}>{label}</span>
                <span style={{ color: T.text, fontWeight: 500 }}>{getLabel(id, state[id])}</span>
              </div>
            ))}
            {state.features && state.features.length > 0 && (
              <div style={{ display: "flex", justifyContent: "space-between", padding: "6px 0", fontSize: 13 }}>
                <span style={{ color: T.textDim }}>Extras</span>
                <span style={{ color: T.text, fontWeight: 500 }}>{state.features.map(f => getLabel("features", f)).join(", ")}</span>
              </div>
            )}
            <div style={{ textAlign: "center", padding: "14px 0 0" }}>
              <div style={{ fontSize: 12, color: T.textDim, marginBottom: 4 }}>Estimated range</div>
              <div style={{ fontFamily: "'Playfair Display', serif", fontSize: 28, fontWeight: 700, color: T.copper }}>{fmt(lo)} \u2013 {fmt(hi)}</div>
            </div>
            <div style={{ marginTop: 14, paddingTop: 14, borderTop: `1px solid ${T.border}`, textAlign: "center", fontSize: 12, color: T.textDim, lineHeight: 1.5 }}>
              <strong style={{ color: T.copper }}>Next step:</strong> Free site visit with Eric<br />
              <a href="tel:4065515061" style={{ color: T.copper, textDecoration: "none", fontWeight: 600 }}>406-551-5061</a>
            </div>
          </div>

          <div style={{ textAlign: "center", marginTop: 10 }}>
            <button onClick={() => window.print && window.print()} style={{ background: "none", border: "none", color: T.textDark, fontSize: 12, cursor: "pointer", fontFamily: "inherit", textDecoration: "underline", textUnderlineOffset: 2 }}>Save or print this summary</button>
          </div>

          {/* Email upsell + preferred call time */}
          <div style={{ background: T.copperGlow, border: `1px solid ${T.copperBorder}`, borderRadius: 12, padding: 20, marginTop: 20, textAlign: "center" }}>
            <h3 style={{ fontSize: 16, fontWeight: 700, color: T.white, margin: "0 0 4px" }}>Want a project summary?</h3>
            <p style={{ fontSize: 13, color: T.textDim, margin: "0 0 14px", lineHeight: 1.5 }}>Add your email and I'll send a detailed breakdown with your project summary link.</p>
            <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
              <input type="email" placeholder="Email address" value={contact.email} onChange={e => setContact(c => ({ ...c, email: e.target.value }))} style={inputStyle} onFocus={e => e.target.style.borderColor = T.copper} onBlur={e => e.target.style.borderColor = T.border} />
              <div style={{ textAlign: "left" }}>
                <div style={{ fontSize: 12, fontWeight: 600, color: T.textDim, marginBottom: 6 }}>Prefer a specific time for a call? (optional)</div>
                <div style={{ display: "flex", gap: 8 }}>
                  <input type="date" value={contact.preferred_date || ""} onChange={e => setContact(c => ({ ...c, preferred_date: e.target.value }))} min={new Date().toISOString().split('T')[0]} style={{ ...inputStyle, flex: 1 }} />
                  <select value={contact.preferred_time || ""} onChange={e => setContact(c => ({ ...c, preferred_time: e.target.value }))} style={{ ...inputStyle, flex: 1 }}>
                    <option value="">Time...</option>
                    <option value="morning">Morning (9\u201312)</option>
                    <option value="afternoon">Afternoon (12\u20135)</option>
                    <option value="evening">Evening (5\u20137)</option>
                  </select>
                </div>
              </div>
              <button onClick={submitFull} disabled={!contact.email || submitting} style={{ width: "100%", padding: "13px 0", borderRadius: 8, border: "none", background: contact.email && !submitting ? T.copper : T.border, color: contact.email && !submitting ? T.charcoal : T.textDark, fontSize: 14, fontWeight: 700, fontFamily: "inherit", cursor: contact.email && !submitting ? "pointer" : "not-allowed" }}>{submitting ? "Sending..." : "Send me the project summary"}</button>
            </div>
          </div>
          <div style={{ textAlign: "center", marginTop: 14 }}><p style={{ fontSize: 13, color: T.textDark }}>Or call \u2014 <a href="tel:4065515061" style={{ color: T.copper, fontWeight: 600, textDecoration: "none" }}>406-551-5061</a></p></div>
        </div>}

        {/* ═══ SUBMITTED ═══ */}
        {phase === "submitted" && <div style={{ textAlign: "center", padding: "2rem 0" }}>
          <div style={{ width: 48, height: 48, borderRadius: "50%", background: T.copperLight, border: `1px solid ${T.copperBorder}`, display: "flex", alignItems: "center", justifyContent: "center", margin: "0 auto 16px", color: T.copper, fontSize: 20, fontWeight: 700 }}>\u2713</div>
          <h3 style={{ fontFamily: "'Playfair Display', serif", fontSize: 22, fontWeight: 700, color: T.white, margin: "0 0 8px" }}>You're all set, {contact.name.split(" ")[0]}</h3>
          <p style={{ fontSize: 14, color: T.textMuted, maxWidth: 360, margin: "0 auto", lineHeight: 1.6 }}>I'll call within the hour to schedule your free site visit. Your ballpark of <strong style={{ color: T.copper }}>{fmt(lo)}\u2013{fmt(hi)}</strong> is a starting point \u2014 exact number after seeing the space.</p>
          <div style={{ margin: "24px auto 0", padding: "16px 20px", borderRadius: 10, background: T.copperLight, border: `1px solid ${T.copperBorder}`, textAlign: "left", maxWidth: 320 }}>
            <div style={{ fontSize: 11, fontWeight: 600, color: T.copper, marginBottom: 8, textTransform: "uppercase", letterSpacing: "0.06em" }}>What happens next</div>
            <div style={{ fontSize: 13, color: T.textMuted, lineHeight: 1.8 }}>1. Eric calls to schedule the visit<br />2. Free 45-minute site assessment<br />3. Detailed estimate within 48 hours<br />4. Got Pinterest boards? Share before the visit</div>
          </div>
          {reportUrl && (
            <a href={reportUrl} target="_blank" rel="noopener noreferrer" style={{ display: "inline-flex", alignItems: "center", gap: 8, padding: "12px 24px", borderRadius: 10, marginTop: 20, background: T.copper, color: T.charcoal, fontSize: 14, fontWeight: 700, textDecoration: "none", transition: "opacity 0.15s" }}
              onMouseEnter={e => e.currentTarget.style.opacity = "0.9"} onMouseLeave={e => e.currentTarget.style.opacity = "1"}>
              View your project summary \u2192
            </a>
          )}
        </div>}

      </div>

      {/* Footer */}
      <div style={{ marginTop: 40, paddingTop: 16, borderTop: `1px solid ${T.border}`, textAlign: "center", fontSize: 11, color: T.textDark, lineHeight: 1.6 }}>
        Heartwood Craft \u00b7 Bozeman, Montana \u00b7 <a href="tel:4065515061" style={{ color: T.textDark, textDecoration: "none" }}>406-551-5061</a><br />
        Based on real local project data. Final pricing after site visit.
      </div>
    </div>
  );
}
