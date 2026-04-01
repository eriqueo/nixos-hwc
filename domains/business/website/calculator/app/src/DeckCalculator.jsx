import { useState, useRef, useEffect } from "react";

// ─── Brand tokens (matches bathroom calculator V3) ───────────────────────────
const T = {
  copper: "#cf995f",
  copperLight: "#F5EDE4",
  copperMid: "#E8D5C4",
  copperDark: "#a67a45",
  charcoal: "#23282d",
  charcoalLight: "#2d3239",
  charcoalMid: "#3a3f46",
  cream: "#faf8f5",
  warmGray: "#e8e4df",
  text: "#2d2d2d",
  textMuted: "#6b7280",
  textLight: "#9ca3af",
  border: "#e5e7eb",
  white: "#ffffff",
  success: "#059669",
  successBg: "#ecfdf5",
};

// ─── Steps ───────────────────────────────────────────────────────────────────
const STEPS = [
  {
    id: "project_type",
    question: "What kind of deck project is this?",
    subtitle: "This sets the baseline for everything else.",
    why: "A brand-new deck build means foundation, framing, and decking from scratch. A rebuild reuses some existing structure. A repair might just be boards and rails. This one question changes the estimate by thousands.",
    type: "cards",
    options: [
      { value: "new_build", label: "New deck build", desc: "No existing deck — building from the ground up", emoji: "🔨" },
      { value: "full_rebuild", label: "Full rebuild", desc: "Tear off the old deck and start fresh", emoji: "♻️" },
      { value: "partial_rebuild", label: "Partial rebuild", desc: "Keep the frame, replace decking and rails", emoji: "🔧" },
      { value: "repair_refresh", label: "Repair or refresh", desc: "Fix specific issues — boards, stairs, rails", emoji: "✨" },
    ],
  },
  {
    id: "deck_size",
    question: "How big is the deck?",
    subtitle: "A rough estimate works — we'll measure precisely on-site.",
    why: "Materials and labor both scale with square footage. Lumber, fasteners, and joist count are all driven by size. Even a rough number gets us in the right ballpark — Bozeman lumber prices are what make this accurate, not national averages.",
    type: "cards",
    options: [
      { value: "small", label: "Small", desc: "Under 150 sq ft (8×16, entry landing, small patio)", emoji: "▪️", sqft: 120 },
      { value: "medium", label: "Medium", desc: "150–300 sq ft (12×20, standard back deck)", emoji: "▫️", sqft: 225 },
      { value: "large", label: "Large", desc: "300–500 sq ft (16×24, entertaining deck)", emoji: "⬜", sqft: 400 },
      { value: "xl", label: "Extra large", desc: "500+ sq ft (multi-level, wraparound, or custom)", emoji: "🔳", sqft: 600 },
    ],
  },
  {
    id: "deck_height",
    question: "How high off the ground?",
    subtitle: "This affects foundation, railing requirements, and permits.",
    why: "In Gallatin County, decks over 30 inches above grade require railings and typically need a building permit. Ground-level decks skip both — saving $1,500–4,000 in railings alone. Height also determines whether you need concrete footings or can use deck blocks.",
    type: "cards",
    options: [
      { value: "ground_level", label: "Ground level", desc: "Under 12 inches — floating or on blocks", emoji: "⏚" },
      { value: "low", label: "Low profile", desc: "12–30 inches — no railing required", emoji: "▬" },
      { value: "standard", label: "Standard height", desc: "30–60 inches — railing required", emoji: "📐" },
      { value: "elevated", label: "Elevated", desc: "5+ feet — second story, walkout, or hillside", emoji: "🏔️" },
    ],
  },
  {
    id: "material",
    question: "What material for the decking?",
    subtitle: "This is your biggest material cost decision.",
    why: "Pressure-treated lumber runs $2–3 per linear foot in Bozeman — solid and affordable, but needs maintenance every few years. Cedar is beautiful but pricier. Composite (Trex, TimberTech) costs 2–3× more upfront but lasts decades with zero staining. Material choice alone can swing a deck project by $3,000–8,000.",
    type: "cards",
    options: [
      { value: "pt_lumber", label: "Pressure-treated", desc: "Affordable, proven — needs staining every 2–3 years", emoji: "🪵" },
      { value: "cedar", label: "Cedar", desc: "Beautiful grain, natural weather resistance", emoji: "🌲" },
      { value: "composite_mid", label: "Composite (mid)", desc: "Trex Select, TimberTech Edge — low maintenance", emoji: "📋" },
      { value: "composite_premium", label: "Composite (premium)", desc: "Trex Transcend, TimberTech Vintage — top tier", emoji: "💎" },
    ],
  },
  {
    id: "railing",
    question: "What about railings?",
    subtitle: "Required if your deck is over 30\" above grade.",
    why: "Wood railings are the budget option at $30–50 per linear foot installed. Cable rail and metal balusters look sharp but cost 2–3× more. Glass panels are premium at $80–150+ per foot. If your deck is under 30 inches, you might skip them entirely — or add a simple cap rail for looks.",
    type: "cards",
    options: [
      { value: "none", label: "No railing", desc: "Ground-level or low deck — not required", emoji: "—" },
      { value: "wood", label: "Wood railing", desc: "PT or cedar posts and balusters — classic look", emoji: "🪵" },
      { value: "metal_cable", label: "Metal or cable", desc: "Aluminum balusters or cable rail — modern and clean", emoji: "⚡" },
      { value: "glass", label: "Glass panels", desc: "Tempered glass — unobstructed views, premium cost", emoji: "🪟" },
    ],
  },
  {
    id: "features",
    question: "Any extras?",
    subtitle: "Select everything that applies. These are the common add-ons we see in Bozeman.",
    why: "Each of these is a standalone scope item with its own materials and labor. Built-in benches and planters add $800–2,000 each. Lighting runs $600–2,000 depending on complexity. A pergola can add $3,000–8,000. We price these from our actual Bozeman project costs.",
    type: "multi",
    options: [
      { value: "stairs", label: "Stairs (3+ steps)", add: 1500 },
      { value: "lighting", label: "Deck lighting", add: 1200 },
      { value: "builtin_bench", label: "Built-in bench seating", add: 1400 },
      { value: "pergola", label: "Pergola or shade structure", add: 5000 },
      { value: "hottub_pad", label: "Hot tub pad / reinforcement", add: 2000 },
      { value: "skirting", label: "Deck skirting / lattice", add: 1000 },
    ],
  },
  {
    id: "timeline",
    question: "When are you thinking?",
    subtitle: "Helps us plan the schedule — Bozeman deck season books up fast.",
    why: "Montana's build season for outdoor work is roughly May through October. Bozeman contractors book up quickly in spring — if you're targeting summer, starting the conversation now gives you the best shot at getting on the schedule.",
    type: "cards",
    options: [
      { value: "asap", label: "As soon as possible", desc: "Ready to move — let's get on the schedule", emoji: "🚀" },
      { value: "1_3_months", label: "1–3 months", desc: "Planning ahead, want to get numbers", emoji: "📅" },
      { value: "3_6_months", label: "3–6 months", desc: "Thinking about next season", emoji: "🗓️" },
      { value: "exploring", label: "Just exploring", desc: "Curious what a deck costs in Bozeman", emoji: "🔍" },
    ],
  },
];

// ─── Pricing engine — calibrated from real Bozeman deck projects ─────────────
function calculateRange(state) {
  const bases = {
    new_build:       [12000, 22000],
    full_rebuild:    [10000, 18000],
    partial_rebuild: [5000,  12000],
    repair_refresh:  [2500,  7000],
  };

  const sizeMultipliers = { small: 0.65, medium: 1.0, large: 1.55, xl: 2.2 };

  const heightAdds = {
    ground_level: [0, 0],
    low:          [500, 1000],
    standard:     [1500, 3000],
    elevated:     [4000, 8000],
  };

  const materialMultipliers = {
    pt_lumber:         1.0,
    cedar:             1.25,
    composite_mid:     1.6,
    composite_premium: 2.0,
  };

  const railingPerFoot = {
    none:        [0, 0],
    wood:        [30, 50],
    metal_cable: [60, 90],
    glass:       [90, 150],
  };

  const perimeterBySize = { small: 30, medium: 44, large: 58, xl: 75 };

  let [lo, hi] = bases[state.project_type] || [10000, 18000];

  const sizeMult = sizeMultipliers[state.deck_size] || 1.0;
  lo *= sizeMult;
  hi *= sizeMult;

  const [hLo, hHi] = heightAdds[state.deck_height] || [0, 0];
  lo += hLo;
  hi += hHi;

  // Material multiplier only on decking portion (~40% of base)
  const matMult = materialMultipliers[state.material] || 1.0;
  const deckLo = lo * 0.4;
  const deckHi = hi * 0.4;
  lo = (lo * 0.6) + (deckLo * matMult);
  hi = (hi * 0.6) + (deckHi * matMult);

  if (state.railing && state.railing !== "none") {
    const [rLo, rHi] = railingPerFoot[state.railing] || [0, 0];
    const perim = perimeterBySize[state.deck_size] || 44;
    lo += rLo * perim;
    hi += rHi * perim;
  }

  if (state.features && state.features.length > 0) {
    const featureMap = {};
    STEPS.find(s => s.id === "features").options.forEach(o => { featureMap[o.value] = o.add; });
    state.features.forEach(f => { lo += featureMap[f] * 0.8; hi += featureMap[f] * 1.2; });
  }

  return [Math.round(lo / 500) * 500, Math.round(hi / 500) * 500];
}

// ─── Info box component ──────────────────────────────────────────────────────
function InfoBox({ text }) {
  const [open, setOpen] = useState(false);
  return (
    <div style={{ marginBottom: 16 }}>
      <button
        onClick={() => setOpen(!open)}
        style={{
          background: "none", border: "none", cursor: "pointer", padding: 0,
          fontSize: 12, fontWeight: 600, color: T.copper, fontFamily: "inherit",
          display: "flex", alignItems: "center", gap: 5,
        }}
      >
        <span style={{
          display: "inline-flex", alignItems: "center", justifyContent: "center",
          width: 18, height: 18, borderRadius: "50%", border: `1.5px solid ${T.copper}`,
          fontSize: 11, fontWeight: 700, color: T.copper, lineHeight: 1,
        }}>?</span>
        {open ? "Hide explanation" : "Why do we ask this?"}
      </button>
      {open && (
        <div style={{
          marginTop: 8, padding: "12px 14px", borderRadius: 8,
          background: T.copperLight, fontSize: 12.5, color: T.charcoalLight,
          lineHeight: 1.6, borderLeft: `3px solid ${T.copper}`,
        }}>
          {text}
        </div>
      )}
    </div>
  );
}

// ─── Animated number (counts up on reveal) ───────────────────────────────────
function AnimatedNumber({ value, duration = 800 }) {
  const [display, setDisplay] = useState(0);
  const ref = useRef(null);

  useEffect(() => {
    const start = 0;
    const end = value;
    const startTime = performance.now();

    const tick = (now) => {
      const elapsed = now - startTime;
      const progress = Math.min(elapsed / duration, 1);
      const eased = 1 - Math.pow(1 - progress, 3);
      setDisplay(Math.round(start + (end - start) * eased));
      if (progress < 1) ref.current = requestAnimationFrame(tick);
    };

    ref.current = requestAnimationFrame(tick);
    return () => { if (ref.current) cancelAnimationFrame(ref.current); };
  }, [value, duration]);

  return <>{display.toLocaleString()}</>;
}

// ─── Main component ──────────────────────────────────────────────────────────
export default function DeckCalculator() {
  const [step, setStep] = useState(0);
  const [state, setState] = useState({});
  const [contact, setContact] = useState({ name: "", email: "", phone: "", notes: "", preferred_date: "", preferred_time: "" });
  const [phase, setPhase] = useState("quiz"); // quiz | results | submitted
  const [animating, setAnimating] = useState(false);
  const [reportUrl, setReportUrl] = useState(null);
  const [submitting, setSubmitting] = useState(false);

  const currentStep = STEPS[step];
  const isComplete = step >= STEPS.length;
  const [lo, hi] = isComplete ? calculateRange(state) : [0, 0];

  const animate = (cb) => {
    setAnimating(true);
    setTimeout(() => { cb(); setAnimating(false); }, 180);
  };

  const goNext = () => animate(() => setStep(s => s + 1));
  const goBack = () => { if (step > 0) animate(() => setStep(s => s - 1)); };
  const startOver = () => animate(() => { setStep(0); setState({}); setPhase("quiz"); setContact({ name: "", email: "", phone: "", notes: "", preferred_date: "", preferred_time: "" }); setReportUrl(null); });

  const selectOption = (stepId, value) => {
    setState(prev => ({ ...prev, [stepId]: value }));
    setTimeout(goNext, 200);
  };

  const toggleFeature = (value) => {
    setState(prev => {
      const features = prev.features || [];
      return { ...prev, features: features.includes(value) ? features.filter(f => f !== value) : [...features, value] };
    });
  };

  useEffect(() => {
    if (isComplete && phase === "quiz") setPhase("results");
  }, [isComplete, phase]);

  // GA4 events
  const fireEvent = (name, params = {}) => {
    if (typeof gtag === "function") {
      gtag("event", name, { ...params, calculator_type: "deck" });
    }
  };

  useEffect(() => {
    if (step > 0 && step <= STEPS.length) {
      fireEvent("calculator_step", { step: step, step_name: STEPS[step - 1]?.id });
    }
  }, [step]);

  const canSubmit = contact.name.trim() && contact.phone.trim() && contact.email.trim();

  // Submit contact info to get the report
  const handleReportRequest = async () => {
    if (!canSubmit) return;
    setSubmitting(true);

    fireEvent("calculator_lead_full", { estimate_low: lo, estimate_high: hi });

    const payload = {
      action: "calculator_lead_full",
      project_type: "deck",
      contact,
      projectState: state,
      estimate: { low: lo, high: hi },
      timestamp: new Date().toISOString(),
      source: "website_calculator",
      calculator: "deck",
      source_page: window.location.pathname,
    };

    try {
      const utm = {};
      ["utm_source","utm_medium","utm_campaign","utm_content","utm_term"].forEach(k => {
        const v = sessionStorage.getItem(k); if (v) utm[k] = v;
      });
      if (Object.keys(utm).length) payload.attribution = utm;
      payload.landing_page = sessionStorage.getItem("landing_page") || window.location.pathname;
      payload.referrer = sessionStorage.getItem("referrer") || document.referrer || "";
    } catch (e) {}

    try {
      const res = await fetch("https://hwc.ocelot-wahoo.ts.net/webhook/calculator-lead", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const data = await res.json();
      setReportUrl(data.reportUrl || null);
    } catch (e) {
      setReportUrl(null);
    }

    setSubmitting(false);
    setPhase("submitted");
  };

  const progress = Math.min((step / STEPS.length) * 100, 100);

  const getPills = () => {
    const pills = [];
    Object.entries(state).filter(([k]) => k !== "features").forEach(([key, val]) => {
      const stepDef = STEPS.find(s => s.id === key);
      const opt = stepDef?.options.find(o => o.value === val);
      if (opt) pills.push({ label: opt.label, type: "config" });
    });
    (state.features || []).forEach(f => {
      const opt = STEPS.find(s => s.id === "features")?.options.find(o => o.value === f);
      if (opt) pills.push({ label: opt.label, type: "feature" });
    });
    return pills;
  };

  // ─── Styles ──────────────────────────────────────────────────────────────
  const containerStyle = {
    maxWidth: 620, margin: "0 auto", padding: "2rem 1.25rem",
    fontFamily: "'DM Sans', 'Helvetica Neue', Arial, sans-serif",
    color: T.text,
  };

  const cardStyle = (selected) => ({
    padding: "16px 18px", borderRadius: 12, cursor: "pointer", textAlign: "left",
    border: selected ? `2px solid ${T.copper}` : `1.5px solid ${T.border}`,
    background: selected ? T.copperLight : T.white,
    transition: "all 0.15s ease", fontFamily: "inherit",
    display: "flex", alignItems: "flex-start", gap: 14, width: "100%",
  });

  const inputStyle = {
    padding: "14px 16px", borderRadius: 10, border: `1.5px solid ${T.border}`,
    fontSize: 15, fontFamily: "inherit", outline: "none",
    transition: "border-color 0.15s", width: "100%", boxSizing: "border-box",
  };

  const buttonCopper = {
    padding: "14px 0", borderRadius: 10, cursor: "pointer",
    border: "none", fontSize: 15, fontWeight: 600, fontFamily: "inherit",
    background: T.copper, color: T.white, transition: "all 0.15s", width: "100%",
  };

  return (
    <div style={containerStyle}>
      <link href="https://fonts.googleapis.com/css2?family=DM+Sans:ital,wght@0,400;0,500;0,700&family=Playfair+Display:wght@600;700&display=swap" rel="stylesheet" />

      {/* ── Header ── */}
      <div style={{ textAlign: "center", marginBottom: 28 }}>
        <div style={{
          fontSize: 11, fontWeight: 600, letterSpacing: "0.14em", textTransform: "uppercase",
          color: T.copper, marginBottom: 8,
        }}>
          Heartwood Craft · Bozeman
        </div>
        <h1 style={{
          fontFamily: "'Playfair Display', serif", fontSize: 30, fontWeight: 700,
          color: T.charcoal, margin: "0 0 8px", lineHeight: 1.2,
        }}>
          Deck cost calculator
        </h1>
        <p style={{
          fontSize: 14, color: T.textMuted, margin: 0, maxWidth: 460,
          marginLeft: "auto", marginRight: "auto", lineHeight: 1.6,
        }}>
          7 questions, real numbers from Bozeman deck projects. Not national averages — actual Gallatin Valley material and labor costs.
        </p>
      </div>

      {/* ── Progress bar ── */}
      <div style={{ height: 3, background: T.border, borderRadius: 2, marginBottom: 28, overflow: "hidden" }}>
        <div style={{
          height: "100%", background: T.copper, borderRadius: 2,
          width: `${progress}%`, transition: "width 0.4s ease",
        }} />
      </div>

      {/* ── Animated content wrapper ── */}
      <div style={{
        opacity: animating ? 0 : 1,
        transform: animating ? "translateY(6px)" : "translateY(0)",
        transition: "all 0.18s ease",
      }}>

        {/* ── QUIZ PHASE ── */}
        {phase === "quiz" && currentStep && (
          <div>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 6 }}>
              <div style={{ fontSize: 11, fontWeight: 600, color: T.textLight, letterSpacing: "0.06em" }}>
                STEP {step + 1} OF {STEPS.length}
              </div>
              {step > 0 && (
                <button onClick={startOver} style={{
                  background: "none", border: "none", cursor: "pointer", padding: 0,
                  fontSize: 11, fontWeight: 600, color: T.textLight, fontFamily: "inherit",
                }}>
                  Start over
                </button>
              )}
            </div>

            <h2 style={{
              fontFamily: "'Playfair Display', serif", fontSize: 22, fontWeight: 700,
              color: T.charcoal, margin: "0 0 6px", lineHeight: 1.3,
            }}>
              {currentStep.question}
            </h2>
            <p style={{ fontSize: 13, color: T.textMuted, margin: "0 0 14px", lineHeight: 1.5 }}>
              {currentStep.subtitle}
            </p>

            <InfoBox text={currentStep.why} />

            {/* Single-select cards */}
            {currentStep.type === "cards" && (
              <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
                {currentStep.options.map(opt => {
                  const selected = state[currentStep.id] === opt.value;
                  return (
                    <button
                      key={opt.value}
                      onClick={() => selectOption(currentStep.id, opt.value)}
                      style={cardStyle(selected)}
                      onMouseEnter={e => { if (!selected) e.currentTarget.style.borderColor = T.copperMid; }}
                      onMouseLeave={e => { if (!selected) e.currentTarget.style.borderColor = T.border; }}
                    >
                      <div style={{
                        fontSize: 22, lineHeight: 1, flexShrink: 0, marginTop: 2,
                        width: 36, textAlign: "center",
                      }}>
                        {opt.emoji}
                      </div>
                      <div>
                        <div style={{ fontSize: 15, fontWeight: 600, color: T.charcoal, marginBottom: 2 }}>{opt.label}</div>
                        <div style={{ fontSize: 12.5, color: T.textMuted, lineHeight: 1.4 }}>{opt.desc}</div>
                      </div>
                    </button>
                  );
                })}
              </div>
            )}

            {/* Multi-select */}
            {currentStep.type === "multi" && (
              <div>
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8 }}>
                  {currentStep.options.map(opt => {
                    const checked = (state.features || []).includes(opt.value);
                    return (
                      <button
                        key={opt.value}
                        onClick={() => toggleFeature(opt.value)}
                        style={{
                          padding: "14px 14px", borderRadius: 10, cursor: "pointer", textAlign: "left",
                          border: checked ? `2px solid ${T.copper}` : `1.5px solid ${T.border}`,
                          background: checked ? T.copperLight : T.white,
                          transition: "all 0.15s", fontFamily: "inherit",
                          display: "flex", alignItems: "center", gap: 10,
                        }}
                      >
                        <div style={{
                          width: 22, height: 22, borderRadius: 5, flexShrink: 0,
                          border: checked ? `2px solid ${T.copper}` : `2px solid #d1d5db`,
                          background: checked ? T.copper : "transparent",
                          display: "flex", alignItems: "center", justifyContent: "center",
                          color: T.white, fontSize: 13, fontWeight: 700, transition: "all 0.15s",
                        }}>
                          {checked && "✓"}
                        </div>
                        <div style={{ fontSize: 13, fontWeight: 600, color: T.charcoal }}>{opt.label}</div>
                      </button>
                    );
                  })}
                </div>
                <button
                  onClick={goNext}
                  style={{ ...buttonCopper, marginTop: 16 }}
                  onMouseEnter={e => e.currentTarget.style.opacity = "0.9"}
                  onMouseLeave={e => e.currentTarget.style.opacity = "1"}
                >
                  {(state.features || []).length === 0 ? "None of these — continue" : `Continue with ${(state.features || []).length} selected`}
                </button>
              </div>
            )}
          </div>
        )}

        {/* ── RESULTS PHASE — estimate shown immediately, report gated ── */}
        {phase === "results" && (
          <div>
            {/* The number — no gate, no blur */}
            <div style={{ textAlign: "center", marginBottom: 20 }}>
              <div style={{ fontSize: 13, color: T.textMuted, marginBottom: 8, fontWeight: 500 }}>
                Your Bozeman deck estimate
              </div>
              <div style={{
                fontFamily: "'Playfair Display', serif", fontSize: 44, fontWeight: 700,
                color: T.charcoal, lineHeight: 1,
              }}>
                $<AnimatedNumber value={lo} /> – $<AnimatedNumber value={hi} />
              </div>
              <div style={{
                fontSize: 12, color: T.textLight, marginTop: 10,
                maxWidth: 400, marginLeft: "auto", marginRight: "auto", lineHeight: 1.5,
              }}>
                Based on real Heartwood Craft deck projects in the Gallatin Valley — not national averages. Your actual price depends on site conditions, exact dimensions, and material selections.
              </div>
            </div>

            {/* Summary pills */}
            <div style={{ display: "flex", flexWrap: "wrap", gap: 6, justifyContent: "center", margin: "0 0 24px" }}>
              {getPills().map((p, i) => (
                <span key={i} style={{
                  fontSize: 11, padding: "4px 10px", borderRadius: 20, fontWeight: 500,
                  background: p.type === "feature" ? T.copperLight : "#f3f2ef",
                  color: p.type === "feature" ? T.copper : T.textMuted,
                }}>
                  {p.type === "feature" ? "+ " : ""}{p.label}
                </span>
              ))}
            </div>

            <div style={{ height: 1, background: T.border, margin: "0 0 24px" }} />

            {/* Report CTA — gated behind name + phone + email */}
            <div style={{
              padding: "24px", borderRadius: 12, background: T.copperLight,
              border: `1px solid ${T.copperMid}`,
            }}>
              <div style={{ fontSize: 17, fontWeight: 700, color: T.charcoal, marginBottom: 4 }}>
                Get your project summary
              </div>
              <div style={{ fontSize: 13, color: T.textMuted, marginBottom: 18, lineHeight: 1.6 }}>
                A breakdown of your selections, what drives the cost at each level, material considerations for Bozeman's climate, and what to expect next. I'll also follow up to answer any questions.
              </div>

              <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
                <input
                  type="text" placeholder="Your name" value={contact.name}
                  onChange={e => setContact(c => ({ ...c, name: e.target.value }))}
                  style={{ ...inputStyle, background: T.white }}
                  onFocus={e => e.target.style.borderColor = T.copper}
                  onBlur={e => e.target.style.borderColor = T.border}
                />
                <input
                  type="tel" placeholder="Phone number" value={contact.phone}
                  onChange={e => setContact(c => ({ ...c, phone: e.target.value }))}
                  style={{ ...inputStyle, background: T.white }}
                  onFocus={e => e.target.style.borderColor = T.copper}
                  onBlur={e => e.target.style.borderColor = T.border}
                />
                <input
                  type="email" placeholder="Email address" value={contact.email}
                  onChange={e => setContact(c => ({ ...c, email: e.target.value }))}
                  style={{ ...inputStyle, background: T.white }}
                  onFocus={e => e.target.style.borderColor = T.copper}
                  onBlur={e => e.target.style.borderColor = T.border}
                />
                <textarea
                  placeholder="Anything else about the project? (optional)" value={contact.notes}
                  onChange={e => setContact(c => ({ ...c, notes: e.target.value }))}
                  rows={2}
                  style={{ ...inputStyle, background: T.white, resize: "vertical" }}
                  onFocus={e => e.target.style.borderColor = T.copper}
                  onBlur={e => e.target.style.borderColor = T.border}
                />
                {/* Preferred call time — optional */}
                <div style={{ marginBottom: 4 }}>
                  <div style={{ fontSize: 13, fontWeight: 600, color: T.charcoal, marginBottom: 8 }}>
                    Prefer a specific time for a call? (optional)
                  </div>
                  <div style={{ display: "flex", gap: 8 }}>
                    <input
                      type="date"
                      value={contact.preferred_date || ""}
                      onChange={e => setContact(c => ({ ...c, preferred_date: e.target.value }))}
                      min={new Date().toISOString().split('T')[0]}
                      style={{ ...inputStyle, background: T.white, flex: 1 }}
                    />
                    <select
                      value={contact.preferred_time || ""}
                      onChange={e => setContact(c => ({ ...c, preferred_time: e.target.value }))}
                      style={{ ...inputStyle, background: T.white, flex: 1 }}
                    >
                      <option value="">Time...</option>
                      <option value="morning">Morning (9–12)</option>
                      <option value="afternoon">Afternoon (12–5)</option>
                      <option value="evening">Evening (5–7)</option>
                    </select>
                  </div>
                </div>
                <button
                  onClick={handleReportRequest}
                  disabled={!canSubmit || submitting}
                  style={{
                    padding: "14px 0", borderRadius: 10,
                    cursor: canSubmit ? "pointer" : "not-allowed",
                    border: "none", fontSize: 15, fontWeight: 600, fontFamily: "inherit",
                    background: canSubmit ? T.charcoal : "#d1d5db",
                    color: T.white, transition: "all 0.15s", width: "100%",
                  }}
                  onMouseEnter={e => { if (canSubmit && !submitting) e.currentTarget.style.background = T.charcoalMid; }}
                  onMouseLeave={e => { if (canSubmit && !submitting) e.currentTarget.style.background = T.charcoal; }}
                >
                  {submitting ? "Sending..." : "Send me the project summary"}
                </button>
              </div>
            </div>

            <button onClick={startOver} style={{
              display: "block", margin: "20px auto 0", background: "none", border: "none",
              cursor: "pointer", fontSize: 12, color: T.textLight, fontFamily: "inherit",
            }}>
              ← Start over with different options
            </button>
          </div>
        )}

        {/* ── SUBMITTED PHASE ── */}
        {phase === "submitted" && (
          <div style={{ textAlign: "center", padding: "32px 0" }}>
            <div style={{
              width: 56, height: 56, borderRadius: "50%", background: T.successBg,
              display: "flex", alignItems: "center", justifyContent: "center",
              margin: "0 auto 16px", fontSize: 24, color: T.success,
            }}>
              ✓
            </div>
            <h3 style={{
              fontFamily: "'Playfair Display', serif", fontSize: 24, fontWeight: 700,
              color: T.charcoal, margin: "0 0 8px",
            }}>
              You're all set, {contact.name.split(" ")[0]}
            </h3>
            <p style={{
              fontSize: 14, color: T.textMuted, maxWidth: 400,
              margin: "0 auto", lineHeight: 1.6,
            }}>
              Your project summary is on its way to <strong>{contact.email}</strong>. Your ballpark of <strong>${lo.toLocaleString()}–${hi.toLocaleString()}</strong> is based on real Bozeman deck costs — I'll follow up within the hour to talk through it.
            </p>
            <div style={{
              marginTop: 24, padding: "16px 20px", borderRadius: 12,
              background: T.copperLight, display: "inline-block", textAlign: "left",
            }}>
              <div style={{ fontSize: 12, fontWeight: 700, color: T.copper, marginBottom: 8 }}>What happens next</div>
              <div style={{ fontSize: 13, color: T.charcoalLight, lineHeight: 1.8 }}>
                1. Project summary lands in your inbox<br />
                2. Eric calls to discuss your project<br />
                3. Site visit — measurements, conditions, access<br />
                4. Detailed estimate within 48 hours
              </div>
            </div>

            {reportUrl && (
              <a
                href={reportUrl}
                target="_blank"
                rel="noopener noreferrer"
                style={{
                  display: "inline-flex", alignItems: "center", gap: 8,
                  padding: "12px 24px", borderRadius: 10, marginTop: 20,
                  background: T.copper, color: T.white,
                  fontSize: 14, fontWeight: 600, textDecoration: "none",
                  transition: "opacity 0.15s",
                }}
                onMouseEnter={e => e.currentTarget.style.opacity = "0.9"}
                onMouseLeave={e => e.currentTarget.style.opacity = "1"}
              >
                View your project summary →
              </a>
            )}

            <button onClick={startOver} style={{
              display: "block", margin: "24px auto 0", background: "none", border: "none",
              cursor: "pointer", fontSize: 12, color: T.textLight, fontFamily: "inherit",
            }}>
              Run the calculator again
            </button>
          </div>
        )}
      </div>

      {/* ── Back button ── */}
      {phase === "quiz" && step > 0 && (
        <button
          onClick={goBack}
          style={{
            marginTop: 20, padding: "8px 0", background: "none", border: "none",
            cursor: "pointer", fontSize: 13, color: T.textLight, fontFamily: "inherit",
            fontWeight: 500, display: "flex", alignItems: "center", gap: 4,
          }}
          onMouseEnter={e => e.currentTarget.style.color = T.textMuted}
          onMouseLeave={e => e.currentTarget.style.color = T.textLight}
        >
          ← Back
        </button>
      )}

      {/* ── Footer ── */}
      <div style={{
        marginTop: 40, paddingTop: 20, borderTop: `1px solid ${T.border}`,
        textAlign: "center",
      }}>
        <div style={{ fontSize: 11, color: T.textLight, lineHeight: 1.7 }}>
          Heartwood Craft · Bozeman, Montana · 406-551-5061<br />
          Ranges based on actual Gallatin Valley deck projects.<br />
          Final pricing determined after a site visit.
        </div>
      </div>
    </div>
  );
}
