import { useState, useRef, useEffect } from "react";

// ─── Brand tokens (dark theme — matches BathroomCalculatorV3) ─────────────────
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

// ─── 2-letter icon map ────────────────────────────────────────────────────────
const ICONS = {
  new_build: "NB",
  full_rebuild: "FR",
  partial_rebuild: "PR",
  repair_refresh: "RR",
  small: "SM",
  medium: "MD",
  large: "LG",
  xl: "XL",
  ground_level: "GL",
  low: "LP",
  standard: "SH",
  elevated: "EL",
  pt_lumber: "PT",
  cedar: "CD",
  composite_mid: "CM",
  composite_premium: "CP",
  none: "NO",
  wood: "WD",
  metal_cable: "MC",
  glass: "GL",
  asap: "AS",
  "1_3_months": "13",
  "3_6_months": "36",
  exploring: "EX",
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
      { value: "new_build", label: "New deck build", desc: "No existing deck — building from the ground up" },
      { value: "full_rebuild", label: "Full rebuild", desc: "Tear off the old deck and start fresh" },
      { value: "partial_rebuild", label: "Partial rebuild", desc: "Keep the frame, replace decking and rails" },
      { value: "repair_refresh", label: "Repair or refresh", desc: "Fix specific issues — boards, stairs, rails" },
    ],
  },
  {
    id: "deck_size",
    question: "How big is the deck?",
    subtitle: "A rough estimate works — we'll measure precisely on-site.",
    why: "Materials and labor both scale with square footage. Lumber, fasteners, and joist count are all driven by size. Even a rough number gets us in the right ballpark — Bozeman lumber prices are what make this accurate, not national averages.",
    type: "cards",
    options: [
      { value: "small", label: "Small", desc: "Under 150 sq ft (8x16, entry landing, small patio)", sqft: 120 },
      { value: "medium", label: "Medium", desc: "150-300 sq ft (12x20, standard back deck)", sqft: 225 },
      { value: "large", label: "Large", desc: "300-500 sq ft (16x24, entertaining deck)", sqft: 400 },
      { value: "xl", label: "Extra large", desc: "500+ sq ft (multi-level, wraparound, or custom)", sqft: 600 },
    ],
  },
  {
    id: "deck_height",
    question: "How high off the ground?",
    subtitle: "This affects foundation, railing requirements, and permits.",
    why: "In Gallatin County, decks over 30 inches above grade require railings and typically need a building permit. Ground-level decks skip both — saving $1,500-4,000 in railings alone. Height also determines whether you need concrete footings or can use deck blocks.",
    type: "cards",
    options: [
      { value: "ground_level", label: "Ground level", desc: "Under 12 inches — floating or on blocks" },
      { value: "low", label: "Low profile", desc: "12-30 inches — no railing required" },
      { value: "standard", label: "Standard height", desc: "30-60 inches — railing required" },
      { value: "elevated", label: "Elevated", desc: "5+ feet — second story, walkout, or hillside" },
    ],
  },
  {
    id: "material",
    question: "What material for the decking?",
    subtitle: "This is your biggest material cost decision.",
    why: "Pressure-treated lumber runs $2-3 per linear foot in Bozeman — solid and affordable, but needs maintenance every few years. Cedar is beautiful but pricier. Composite (Trex, TimberTech) costs 2-3x more upfront but lasts decades with zero staining. Material choice alone can swing a deck project by $3,000-8,000.",
    type: "cards",
    options: [
      { value: "pt_lumber", label: "Pressure-treated", desc: "Affordable, proven — needs staining every 2-3 years" },
      { value: "cedar", label: "Cedar", desc: "Beautiful grain, natural weather resistance" },
      { value: "composite_mid", label: "Composite (mid)", desc: "Trex Select, TimberTech Edge — low maintenance" },
      { value: "composite_premium", label: "Composite (premium)", desc: "Trex Transcend, TimberTech Vintage — top tier" },
    ],
  },
  {
    id: "railing",
    question: "What about railings?",
    subtitle: "Required if your deck is over 30\" above grade.",
    why: "Wood railings are the budget option at $30-50 per linear foot installed. Cable rail and metal balusters look sharp but cost 2-3x more. Glass panels are premium at $80-150+ per foot. If your deck is under 30 inches, you might skip them entirely — or add a simple cap rail for looks.",
    type: "cards",
    options: [
      { value: "none", label: "No railing", desc: "Ground-level or low deck — not required" },
      { value: "wood", label: "Wood railing", desc: "PT or cedar posts and balusters — classic look" },
      { value: "metal_cable", label: "Metal or cable", desc: "Aluminum balusters or cable rail — modern and clean" },
      { value: "glass", label: "Glass panels", desc: "Tempered glass — unobstructed views, premium cost" },
    ],
  },
  {
    id: "features",
    question: "Any extras?",
    subtitle: "Select everything that applies. These are the common add-ons we see in Bozeman.",
    why: "Each of these is a standalone scope item with its own materials and labor. Built-in benches and planters add $800-2,000 each. Lighting runs $600-2,000 depending on complexity. A pergola can add $3,000-8,000. We price these from our actual Bozeman project costs.",
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
      { value: "asap", label: "As soon as possible", desc: "Ready to move — let's get on the schedule" },
      { value: "1_3_months", label: "1-3 months", desc: "Planning ahead, want to get numbers" },
      { value: "3_6_months", label: "3-6 months", desc: "Thinking about next season" },
      { value: "exploring", label: "Just exploring", desc: "Curious what a deck costs in Bozeman" },
    ],
  },
];

// ─── Pricing engine — calibrated from real Bozeman deck projects ─────────────
function calculateRange(state) {
  const bases = {
    new_build: [12000, 22000],
    full_rebuild: [10000, 18000],
    partial_rebuild: [5000, 12000],
    repair_refresh: [2500, 7000],
  };

  const sizeMultipliers = { small: 0.65, medium: 1.0, large: 1.55, xl: 2.2 };

  const heightAdds = {
    ground_level: [0, 0],
    low: [500, 1000],
    standard: [1500, 3000],
    elevated: [4000, 8000],
  };

  const materialMultipliers = {
    pt_lumber: 1.0,
    cedar: 1.25,
    composite_mid: 1.6,
    composite_premium: 2.0,
  };

  const railingPerFoot = {
    none: [0, 0],
    wood: [30, 50],
    metal_cable: [60, 90],
    glass: [90, 150],
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
  lo = lo * 0.6 + deckLo * matMult;
  hi = hi * 0.6 + deckHi * matMult;

  if (state.railing && state.railing !== "none") {
    const [rLo, rHi] = railingPerFoot[state.railing] || [0, 0];
    const perim = perimeterBySize[state.deck_size] || 44;
    lo += rLo * perim;
    hi += rHi * perim;
  }

  if (state.features && state.features.length > 0) {
    const featureMap = {};
    STEPS.find((s) => s.id === "features").options.forEach((o) => {
      featureMap[o.value] = o.add;
    });
    state.features.forEach((f) => {
      lo += featureMap[f] * 0.8;
      hi += featureMap[f] * 1.2;
    });
  }

  return [Math.round(lo / 500) * 500, Math.round(hi / 500) * 500];
}

// ─── Attribution (matches V3) ─────────────────────────────────────────────────
function getAttribution() {
  try {
    const a = JSON.parse(sessionStorage.getItem("hwc_attribution") || "{}");
    return {
      utm_source: a.utm_source || null,
      utm_medium: a.utm_medium || null,
      utm_campaign: a.utm_campaign || null,
      gclid: a.gclid || null,
      referrer: a.referrer || null,
      landing_page: a.landing_page || null,
      pages_viewed: parseInt(sessionStorage.getItem("hwc_pages_viewed") || "0", 10),
    };
  } catch {
    return {};
  }
}

// ─── "Why do we ask this?" component (V3 style) ──────────────────────────────
function WhyBox({ text }) {
  const [open, setOpen] = useState(false);
  return (
    <div style={{ marginBottom: 16 }}>
      <button
        onClick={() => setOpen(!open)}
        style={{
          background: "none",
          border: "none",
          cursor: "pointer",
          padding: 0,
          fontSize: 12,
          fontWeight: 500,
          color: T.textDim,
          fontFamily: "'DM Sans', sans-serif",
          display: "flex",
          alignItems: "center",
          gap: 6,
          transition: "color 0.15s",
        }}
        onMouseEnter={(e) => (e.currentTarget.style.color = T.copper)}
        onMouseLeave={(e) => (e.currentTarget.style.color = T.textDim)}
      >
        <span
          style={{
            display: "inline-flex",
            alignItems: "center",
            justifyContent: "center",
            width: 16,
            height: 16,
            borderRadius: "50%",
            border: `1.5px solid ${T.textDim}`,
            fontSize: 10,
            fontWeight: 700,
            lineHeight: 1,
          }}
        >
          ?
        </span>
        {open ? "hide explanation" : "why do we ask this?"}
      </button>
      {open && (
        <div
          style={{
            marginTop: 10,
            padding: "12px 14px",
            borderRadius: 8,
            background: T.surface,
            fontSize: 12.5,
            color: T.textMuted,
            lineHeight: 1.65,
            borderLeft: `2px solid ${T.copperBorder}`,
          }}
        >
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
    return () => {
      if (ref.current) cancelAnimationFrame(ref.current);
    };
  }, [value, duration]);

  return <>{display.toLocaleString()}</>;
}

// ─── Main component ──────────────────────────────────────────────────────────
export default function DeckCalculator() {
  const [step, setStep] = useState(0);
  const [state, setState] = useState({});
  const [contact, setContact] = useState({ name: "", phone: "", email: "" });
  const [phase, setPhase] = useState("quiz"); // quiz | gate | revealed | submitted
  const [fading, setFading] = useState(false);

  const currentStep = STEPS[step];
  const isComplete = step >= STEPS.length;
  const [lo, hi] = isComplete || phase !== "quiz" ? calculateRange(state) : [0, 0];

  // ─── Fade transition (V3 pattern: 220ms) ─────────────────────────────────
  const fade = (cb) => {
    setFading(true);
    setTimeout(() => {
      cb();
      setFading(false);
    }, 220);
  };

  const goNext = () => fade(() => setStep((s) => s + 1));
  const goBack = () => {
    if (step > 0) fade(() => setStep((s) => s - 1));
  };
  const startOver = () =>
    fade(() => {
      setStep(0);
      setState({});
      setPhase("quiz");
      setContact({ name: "", phone: "", email: "" });
    });

  const selectOption = (stepId, value) => {
    setState((prev) => ({ ...prev, [stepId]: value }));
    setTimeout(goNext, 200);
  };

  const toggleFeature = (value) => {
    setState((prev) => {
      const features = prev.features || [];
      return {
        ...prev,
        features: features.includes(value) ? features.filter((f) => f !== value) : [...features, value],
      };
    });
  };

  // Transition to gate phase when quiz is complete
  useEffect(() => {
    if (isComplete && phase === "quiz") {
      fade(() => setPhase("gate"));
    }
  }, [isComplete, phase]);

  // ─── GA4 events ──────────────────────────────────────────────────────────
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

  // ─── Gate: name + phone reveals the estimate ────────────────────────────
  const canReveal = contact.name.trim() && contact.phone.trim();

  const handleReveal = () => {
    if (!canReveal) return;

    fireEvent("calculator_lead_basic", { estimate_low: lo, estimate_high: hi });

    const payload = {
      action: "calculator_lead_basic",
      project_type: "deck",
      calculator: "deck",
      contact: { name: contact.name, phone: contact.phone },
      projectState: state,
      estimate: { low: lo, high: hi },
      timestamp: new Date().toISOString(),
      source: "website_calculator",
      ...getAttribution(),
    };

    fetch("https://hwc.ocelot-wahoo.ts.net/webhook/calculator-lead", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    }).catch(() => {});

    fade(() => setPhase("revealed"));
  };

  // ─── Revealed: email upsell triggers full lead ──────────────────────────
  const handleEmailSubmit = () => {
    if (!contact.email.trim()) return;

    fireEvent("calculator_lead_full", { estimate_low: lo, estimate_high: hi });

    const payload = {
      action: "calculator_lead_full",
      project_type: "deck",
      calculator: "deck",
      contact,
      projectState: state,
      estimate: { low: lo, high: hi },
      timestamp: new Date().toISOString(),
      source: "website_calculator",
      ...getAttribution(),
    };

    fetch("https://hwc.ocelot-wahoo.ts.net/webhook/calculator-lead", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    }).catch(() => {});

    fade(() => setPhase("submitted"));
  };

  const progress = Math.min((step / STEPS.length) * 100, 100);

  // ─── Summary pills ───────────────────────────────────────────────────────
  const getPills = () => {
    const pills = [];
    Object.entries(state)
      .filter(([k]) => k !== "features")
      .forEach(([key, val]) => {
        const stepDef = STEPS.find((s) => s.id === key);
        const opt = stepDef?.options.find((o) => o.value === val);
        if (opt) pills.push({ label: opt.label, type: "config" });
      });
    (state.features || []).forEach((f) => {
      const opt = STEPS.find((s) => s.id === "features")?.options.find((o) => o.value === f);
      if (opt) pills.push({ label: opt.label, type: "feature" });
    });
    return pills;
  };

  // ─── Summary line items for revealed phase ────────────────────────────────
  const getLineItems = () => {
    const items = [];
    const stepLabels = {
      project_type: "Project type",
      deck_size: "Deck size",
      deck_height: "Height",
      material: "Material",
      railing: "Railing",
      timeline: "Timeline",
    };
    Object.entries(state)
      .filter(([k]) => k !== "features")
      .forEach(([key, val]) => {
        const stepDef = STEPS.find((s) => s.id === key);
        const opt = stepDef?.options.find((o) => o.value === val);
        if (opt) items.push({ label: stepLabels[key] || key, value: opt.label });
      });
    if (state.features && state.features.length > 0) {
      const featureLabels = state.features
        .map((f) => {
          const opt = STEPS.find((s) => s.id === "features")?.options.find((o) => o.value === f);
          return opt?.label;
        })
        .filter(Boolean);
      items.push({ label: "Extras", value: featureLabels.join(", ") });
    }
    return items;
  };

  // ─── Inline styles ────────────────────────────────────────────────────────
  const containerStyle = {
    maxWidth: 620,
    margin: "0 auto",
    padding: "2rem 1.25rem",
    fontFamily: "'DM Sans', 'Helvetica Neue', Arial, sans-serif",
    color: T.text,
    background: T.bg,
    minHeight: "100vh",
  };

  const cardStyle = (selected) => ({
    padding: "14px 16px",
    borderRadius: 12,
    cursor: "pointer",
    textAlign: "left",
    border: `1.5px solid ${selected ? T.copper : T.border}`,
    background: selected ? T.surfaceSelected : T.surface,
    transition: "all 0.15s ease",
    fontFamily: "inherit",
    display: "flex",
    alignItems: "center",
    gap: 14,
    width: "100%",
  });

  const iconBadge = {
    width: 36,
    height: 36,
    borderRadius: 8,
    background: T.copperLight,
    border: `1px solid ${T.copperBorder}`,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    fontSize: 13,
    fontWeight: 700,
    color: T.copper,
    flexShrink: 0,
    letterSpacing: "0.02em",
  };

  const inputStyle = {
    padding: "14px 16px",
    borderRadius: 10,
    border: `1.5px solid ${T.border}`,
    background: T.surface,
    fontSize: 15,
    fontFamily: "inherit",
    outline: "none",
    color: T.text,
    transition: "border-color 0.15s",
    width: "100%",
    boxSizing: "border-box",
  };

  const buttonCopper = {
    padding: "14px 0",
    borderRadius: 10,
    cursor: "pointer",
    border: "none",
    fontSize: 15,
    fontWeight: 600,
    fontFamily: "inherit",
    background: T.copper,
    color: T.charcoal,
    transition: "all 0.15s",
    width: "100%",
  };

  return (
    <div style={containerStyle}>
      <link
        href="https://fonts.googleapis.com/css2?family=DM+Sans:ital,wght@0,400;0,500;0,700&family=Playfair+Display:wght@600;700&display=swap"
        rel="stylesheet"
      />

      {/* ── Header ── */}
      <div style={{ textAlign: "center", marginBottom: 28 }}>
        <div
          style={{
            display: "inline-block",
            fontSize: 11,
            fontWeight: 600,
            letterSpacing: "0.08em",
            textTransform: "uppercase",
            color: T.copper,
            background: T.copperLight,
            border: `1px solid ${T.copperBorder}`,
            borderRadius: 20,
            padding: "5px 14px",
            marginBottom: 16,
          }}
        >
          Free estimate tool
        </div>
        <h1
          style={{
            fontFamily: "'Playfair Display', serif",
            fontSize: 30,
            fontWeight: 700,
            color: T.white,
            margin: "0 0 8px",
            lineHeight: 1.2,
          }}
        >
          What will your deck cost?
        </h1>
        <p
          style={{
            fontSize: 14,
            color: T.textMuted,
            margin: 0,
            maxWidth: 460,
            marginLeft: "auto",
            marginRight: "auto",
            lineHeight: 1.6,
          }}
        >
          7 questions. 2 minutes. Real Bozeman pricing.
        </p>
      </div>

      {/* ── Progress bar (thin 2px, copper gradient) ── */}
      <div
        style={{
          height: 2,
          background: T.border,
          borderRadius: 1,
          marginBottom: 28,
          overflow: "hidden",
        }}
      >
        <div
          style={{
            height: "100%",
            background: `linear-gradient(90deg, ${T.copper}, ${T.copper}dd)`,
            borderRadius: 1,
            width: `${progress}%`,
            transition: "width 0.4s ease",
          }}
        />
      </div>

      {/* ── Animated content wrapper (V3 fade: opacity + translateY) ── */}
      <div
        style={{
          opacity: fading ? 0 : 1,
          transform: fading ? "translateY(8px)" : "translateY(0)",
          transition: "all 0.22s ease",
        }}
      >
        {/* ── QUIZ PHASE ── */}
        {phase === "quiz" && currentStep && (
          <div>
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                marginBottom: 6,
              }}
            >
              <div
                style={{
                  fontSize: 11,
                  fontWeight: 600,
                  color: T.textDim,
                  letterSpacing: "0.06em",
                  textTransform: "uppercase",
                }}
              >
                Step {step + 1} of {STEPS.length}
              </div>
              {step > 0 && (
                <button
                  onClick={startOver}
                  style={{
                    background: "none",
                    border: "none",
                    cursor: "pointer",
                    padding: 0,
                    fontSize: 11,
                    fontWeight: 500,
                    color: T.textDim,
                    fontFamily: "inherit",
                  }}
                  onMouseEnter={(e) => (e.currentTarget.style.color = T.textMuted)}
                  onMouseLeave={(e) => (e.currentTarget.style.color = T.textDim)}
                >
                  Start over
                </button>
              )}
            </div>

            <h2
              style={{
                fontFamily: "'Playfair Display', serif",
                fontSize: 22,
                fontWeight: 700,
                color: T.white,
                margin: "0 0 6px",
                lineHeight: 1.3,
              }}
            >
              {currentStep.question}
            </h2>
            <p style={{ fontSize: 13, color: T.textMuted, margin: "0 0 14px", lineHeight: 1.5 }}>
              {currentStep.subtitle}
            </p>

            <WhyBox text={currentStep.why} />

            {/* Single-select cards */}
            {currentStep.type === "cards" && (
              <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
                {currentStep.options.map((opt) => {
                  const selected = state[currentStep.id] === opt.value;
                  return (
                    <button
                      key={opt.value}
                      onClick={() => selectOption(currentStep.id, opt.value)}
                      style={cardStyle(selected)}
                      onMouseEnter={(e) => {
                        if (!selected) {
                          e.currentTarget.style.borderColor = T.borderHover;
                          e.currentTarget.style.background = T.surfaceHover;
                        }
                      }}
                      onMouseLeave={(e) => {
                        if (!selected) {
                          e.currentTarget.style.borderColor = T.border;
                          e.currentTarget.style.background = T.surface;
                        }
                      }}
                    >
                      <div style={iconBadge}>{ICONS[opt.value] || "??"}</div>
                      <div>
                        <div style={{ fontSize: 15, fontWeight: 600, color: T.text, marginBottom: 2 }}>
                          {opt.label}
                        </div>
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
                  {currentStep.options.map((opt) => {
                    const checked = (state.features || []).includes(opt.value);
                    return (
                      <button
                        key={opt.value}
                        onClick={() => toggleFeature(opt.value)}
                        style={{
                          padding: "14px 14px",
                          borderRadius: 10,
                          cursor: "pointer",
                          textAlign: "left",
                          border: `1.5px solid ${checked ? T.copper : T.border}`,
                          background: checked ? T.surfaceSelected : T.surface,
                          transition: "all 0.15s",
                          fontFamily: "inherit",
                          display: "flex",
                          alignItems: "center",
                          gap: 10,
                        }}
                        onMouseEnter={(e) => {
                          if (!checked) {
                            e.currentTarget.style.borderColor = T.borderHover;
                            e.currentTarget.style.background = T.surfaceHover;
                          }
                        }}
                        onMouseLeave={(e) => {
                          if (!checked) {
                            e.currentTarget.style.borderColor = T.border;
                            e.currentTarget.style.background = T.surface;
                          }
                        }}
                      >
                        <div
                          style={{
                            width: 20,
                            height: 20,
                            borderRadius: 5,
                            flexShrink: 0,
                            border: `2px solid ${checked ? T.copper : T.textDark}`,
                            background: checked ? T.copper : "transparent",
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                            color: T.charcoal,
                            fontSize: 12,
                            fontWeight: 700,
                            transition: "all 0.15s",
                          }}
                        >
                          {checked && "\u2713"}
                        </div>
                        <div style={{ flex: 1 }}>
                          <div style={{ fontSize: 13, fontWeight: 600, color: T.text }}>{opt.label}</div>
                        </div>
                        <div
                          style={{
                            fontSize: 11,
                            fontWeight: 600,
                            color: T.textMuted,
                            whiteSpace: "nowrap",
                          }}
                        >
                          +${opt.add.toLocaleString()}
                        </div>
                      </button>
                    );
                  })}
                </div>
                <button
                  onClick={goNext}
                  style={{ ...buttonCopper, marginTop: 16 }}
                  onMouseEnter={(e) => (e.currentTarget.style.opacity = "0.9")}
                  onMouseLeave={(e) => (e.currentTarget.style.opacity = "1")}
                >
                  {(state.features || []).length === 0
                    ? "None of these \u2014 continue"
                    : `Continue with ${(state.features || []).length} selected`}
                </button>
              </div>
            )}
          </div>
        )}

        {/* ── GATE PHASE — estimate blurred behind name+phone ── */}
        {phase === "gate" && (
          <div>
            {/* Blurred estimate teaser */}
            <div style={{ textAlign: "center", marginBottom: 24 }}>
              <div style={{ fontSize: 13, color: T.textMuted, marginBottom: 8, fontWeight: 500 }}>
                Your Bozeman deck estimate
              </div>
              <div
                style={{
                  fontFamily: "'Playfair Display', serif",
                  fontSize: 44,
                  fontWeight: 700,
                  color: T.white,
                  lineHeight: 1,
                  filter: "blur(12px)",
                  userSelect: "none",
                }}
              >
                ${lo.toLocaleString()} \u2013 ${hi.toLocaleString()}
              </div>
            </div>

            {/* Selection pills */}
            <div
              style={{
                display: "flex",
                flexWrap: "wrap",
                gap: 6,
                justifyContent: "center",
                margin: "0 0 24px",
              }}
            >
              {getPills().map((p, i) => (
                <span
                  key={i}
                  style={{
                    fontSize: 11,
                    padding: "4px 10px",
                    borderRadius: 20,
                    fontWeight: 500,
                    background: p.type === "feature" ? T.copperLight : T.surface,
                    color: p.type === "feature" ? T.copper : T.textMuted,
                    border: `1px solid ${p.type === "feature" ? T.copperBorder : T.border}`,
                  }}
                >
                  {p.type === "feature" ? "+ " : ""}
                  {p.label}
                </span>
              ))}
            </div>

            {/* Contact gate card */}
            <div
              style={{
                padding: 24,
                borderRadius: 12,
                background: T.surface,
                border: `1px solid ${T.border}`,
              }}
            >
              <div
                style={{
                  fontSize: 17,
                  fontWeight: 700,
                  color: T.white,
                  marginBottom: 4,
                  fontFamily: "'Playfair Display', serif",
                }}
              >
                Unlock your estimate
              </div>
              <div style={{ fontSize: 13, color: T.textMuted, marginBottom: 18, lineHeight: 1.6 }}>
                Name and phone reveals the range \u2014 plus a project summary you can keep.
              </div>

              <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
                <input
                  type="text"
                  placeholder="Your name"
                  value={contact.name}
                  onChange={(e) => setContact((c) => ({ ...c, name: e.target.value }))}
                  style={inputStyle}
                  onFocus={(e) => (e.target.style.borderColor = T.copper)}
                  onBlur={(e) => (e.target.style.borderColor = T.border)}
                />
                <input
                  type="tel"
                  placeholder="Phone number"
                  value={contact.phone}
                  onChange={(e) => setContact((c) => ({ ...c, phone: e.target.value }))}
                  style={inputStyle}
                  onFocus={(e) => (e.target.style.borderColor = T.copper)}
                  onBlur={(e) => (e.target.style.borderColor = T.border)}
                />
                <button
                  onClick={handleReveal}
                  disabled={!canReveal}
                  style={{
                    ...buttonCopper,
                    opacity: canReveal ? 1 : 0.4,
                    cursor: canReveal ? "pointer" : "not-allowed",
                  }}
                  onMouseEnter={(e) => {
                    if (canReveal) e.currentTarget.style.opacity = "0.9";
                  }}
                  onMouseLeave={(e) => {
                    if (canReveal) e.currentTarget.style.opacity = "1";
                  }}
                >
                  Reveal my estimate \u2192
                </button>
              </div>
            </div>

            <button
              onClick={startOver}
              style={{
                display: "block",
                margin: "20px auto 0",
                background: "none",
                border: "none",
                cursor: "pointer",
                fontSize: 12,
                color: T.textDim,
                fontFamily: "inherit",
              }}
              onMouseEnter={(e) => (e.currentTarget.style.color = T.textMuted)}
              onMouseLeave={(e) => (e.currentTarget.style.color = T.textDim)}
            >
              \u2190 Start over with different options
            </button>
          </div>
        )}

        {/* ── REVEALED PHASE — clear estimate + summary + email upsell ── */}
        {phase === "revealed" && (
          <div>
            {/* The number — clear */}
            <div style={{ textAlign: "center", marginBottom: 24 }}>
              <div style={{ fontSize: 13, color: T.textMuted, marginBottom: 8, fontWeight: 500 }}>
                Your deck project estimate
              </div>
              <div
                style={{
                  fontFamily: "'Playfair Display', serif",
                  fontSize: 44,
                  fontWeight: 700,
                  color: T.white,
                  lineHeight: 1,
                }}
              >
                $<AnimatedNumber value={lo} /> \u2013 $<AnimatedNumber value={hi} />
              </div>
              <div
                style={{
                  fontSize: 12,
                  color: T.textDim,
                  marginTop: 10,
                  maxWidth: 400,
                  marginLeft: "auto",
                  marginRight: "auto",
                  lineHeight: 1.5,
                }}
              >
                Based on real Heartwood Craft deck projects in the Gallatin Valley \u2014 not national averages.
                Your actual price depends on site conditions, exact dimensions, and material selections.
              </div>
            </div>

            {/* Summary card */}
            <div
              style={{
                padding: 20,
                borderRadius: 12,
                background: T.surface,
                border: `1px solid ${T.border}`,
                marginBottom: 20,
              }}
            >
              <div
                style={{
                  fontSize: 13,
                  fontWeight: 700,
                  color: T.copper,
                  marginBottom: 14,
                  textTransform: "uppercase",
                  letterSpacing: "0.06em",
                }}
              >
                Project summary
              </div>
              {getLineItems().map((item, i) => (
                <div
                  key={i}
                  style={{
                    display: "flex",
                    justifyContent: "space-between",
                    alignItems: "baseline",
                    padding: "8px 0",
                    borderBottom: i < getLineItems().length - 1 ? `1px solid ${T.border}` : "none",
                  }}
                >
                  <span style={{ fontSize: 13, color: T.textMuted }}>{item.label}</span>
                  <span style={{ fontSize: 13, fontWeight: 600, color: T.text }}>{item.value}</span>
                </div>
              ))}
              <div
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  alignItems: "baseline",
                  padding: "12px 0 0",
                  marginTop: 4,
                  borderTop: `1px solid ${T.copperBorder}`,
                }}
              >
                <span style={{ fontSize: 14, fontWeight: 700, color: T.copper }}>Estimated range</span>
                <span
                  style={{
                    fontSize: 14,
                    fontWeight: 700,
                    color: T.white,
                  }}
                >
                  ${lo.toLocaleString()} \u2013 ${hi.toLocaleString()}
                </span>
              </div>
            </div>

            {/* Save/print link */}
            <div style={{ textAlign: "center", marginBottom: 20 }}>
              <button
                onClick={() => window.print()}
                style={{
                  background: "none",
                  border: "none",
                  cursor: "pointer",
                  fontSize: 12,
                  color: T.textDim,
                  fontFamily: "inherit",
                  textDecoration: "underline",
                  textUnderlineOffset: 3,
                }}
                onMouseEnter={(e) => (e.currentTarget.style.color = T.copper)}
                onMouseLeave={(e) => (e.currentTarget.style.color = T.textDim)}
              >
                Save or print this estimate
              </button>
            </div>

            {/* Next step CTA */}
            <div
              style={{
                padding: 20,
                borderRadius: 12,
                background: T.copperGlow,
                border: `1px solid ${T.copperBorder}`,
                textAlign: "center",
                marginBottom: 20,
              }}
            >
              <div style={{ fontSize: 15, fontWeight: 700, color: T.white, marginBottom: 4 }}>
                Next step: Free site visit with Eric
              </div>
              <div style={{ fontSize: 13, color: T.textMuted, lineHeight: 1.5 }}>
                On-site measurements, material discussion, and a detailed quote \u2014 no obligation.
              </div>
            </div>

            {/* Email upsell */}
            <div
              style={{
                padding: 20,
                borderRadius: 12,
                background: T.surface,
                border: `1px solid ${T.border}`,
                marginBottom: 16,
              }}
            >
              <div style={{ fontSize: 14, fontWeight: 600, color: T.text, marginBottom: 4 }}>
                Want a copy emailed to you?
              </div>
              <div style={{ fontSize: 12.5, color: T.textMuted, marginBottom: 12, lineHeight: 1.5 }}>
                We'll send this estimate plus material recommendations for Bozeman's climate.
              </div>
              <div style={{ display: "flex", gap: 8 }}>
                <input
                  type="email"
                  placeholder="Email address"
                  value={contact.email}
                  onChange={(e) => setContact((c) => ({ ...c, email: e.target.value }))}
                  style={{ ...inputStyle, flex: 1 }}
                  onFocus={(e) => (e.target.style.borderColor = T.copper)}
                  onBlur={(e) => (e.target.style.borderColor = T.border)}
                />
                <button
                  onClick={handleEmailSubmit}
                  disabled={!contact.email.trim()}
                  style={{
                    padding: "14px 20px",
                    borderRadius: 10,
                    cursor: contact.email.trim() ? "pointer" : "not-allowed",
                    border: "none",
                    fontSize: 14,
                    fontWeight: 600,
                    fontFamily: "inherit",
                    background: contact.email.trim() ? T.copper : T.border,
                    color: contact.email.trim() ? T.charcoal : T.textDim,
                    transition: "all 0.15s",
                    whiteSpace: "nowrap",
                  }}
                  onMouseEnter={(e) => {
                    if (contact.email.trim()) e.currentTarget.style.opacity = "0.9";
                  }}
                  onMouseLeave={(e) => {
                    if (contact.email.trim()) e.currentTarget.style.opacity = "1";
                  }}
                >
                  Send \u2192
                </button>
              </div>
            </div>

            <button
              onClick={startOver}
              style={{
                display: "block",
                margin: "8px auto 0",
                background: "none",
                border: "none",
                cursor: "pointer",
                fontSize: 12,
                color: T.textDim,
                fontFamily: "inherit",
              }}
              onMouseEnter={(e) => (e.currentTarget.style.color = T.textMuted)}
              onMouseLeave={(e) => (e.currentTarget.style.color = T.textDim)}
            >
              \u2190 Start over with different options
            </button>
          </div>
        )}

        {/* ── SUBMITTED PHASE ── */}
        {phase === "submitted" && (
          <div style={{ textAlign: "center", padding: "32px 0" }}>
            <div
              style={{
                width: 56,
                height: 56,
                borderRadius: "50%",
                background: T.copperLight,
                border: `1.5px solid ${T.copperBorder}`,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                margin: "0 auto 16px",
                fontSize: 24,
                color: T.copper,
              }}
            >
              \u2713
            </div>
            <h3
              style={{
                fontFamily: "'Playfair Display', serif",
                fontSize: 24,
                fontWeight: 700,
                color: T.white,
                margin: "0 0 8px",
              }}
            >
              You're all set, {contact.name.split(" ")[0]}
            </h3>
            <p
              style={{
                fontSize: 14,
                color: T.textMuted,
                maxWidth: 400,
                margin: "0 auto",
                lineHeight: 1.6,
              }}
            >
              Your estimate of{" "}
              <strong style={{ color: T.text }}>
                ${lo.toLocaleString()}\u2013${hi.toLocaleString()}
              </strong>{" "}
              and project summary are on the way to{" "}
              <strong style={{ color: T.text }}>{contact.email}</strong>. Eric will follow up within the
              hour to talk through it.
            </p>

            <div
              style={{
                marginTop: 24,
                padding: "16px 20px",
                borderRadius: 12,
                background: T.surface,
                border: `1px solid ${T.border}`,
                display: "inline-block",
                textAlign: "left",
              }}
            >
              <div
                style={{
                  fontSize: 12,
                  fontWeight: 700,
                  color: T.copper,
                  marginBottom: 10,
                  textTransform: "uppercase",
                  letterSpacing: "0.06em",
                }}
              >
                What happens next
              </div>
              <div style={{ fontSize: 13, color: T.textMuted, lineHeight: 1.9 }}>
                1. Estimate + summary lands in your inbox
                <br />
                2. Eric calls to discuss your deck project
                <br />
                3. Free site visit \u2014 measurements, conditions, access
                <br />
                4. Detailed proposal within 48 hours
              </div>
            </div>

            <button
              onClick={startOver}
              style={{
                display: "block",
                margin: "24px auto 0",
                background: "none",
                border: "none",
                cursor: "pointer",
                fontSize: 12,
                color: T.textDim,
                fontFamily: "inherit",
              }}
              onMouseEnter={(e) => (e.currentTarget.style.color = T.textMuted)}
              onMouseLeave={(e) => (e.currentTarget.style.color = T.textDim)}
            >
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
            marginTop: 20,
            padding: "8px 0",
            background: "none",
            border: "none",
            cursor: "pointer",
            fontSize: 13,
            color: T.textDim,
            fontFamily: "inherit",
            fontWeight: 500,
            display: "flex",
            alignItems: "center",
            gap: 4,
          }}
          onMouseEnter={(e) => (e.currentTarget.style.color = T.textMuted)}
          onMouseLeave={(e) => (e.currentTarget.style.color = T.textDim)}
        >
          \u2190 Back
        </button>
      )}

      {/* ── Footer ── */}
      <div
        style={{
          marginTop: 40,
          paddingTop: 20,
          borderTop: `1px solid ${T.border}`,
          textAlign: "center",
        }}
      >
        <div style={{ fontSize: 11, color: T.textDim, lineHeight: 1.7 }}>
          Heartwood Craft \u00b7 Bozeman, Montana \u00b7 406-551-5061
          <br />
          Ranges based on actual Gallatin Valley deck projects.
          <br />
          Final pricing determined after a site visit.
        </div>
      </div>
    </div>
  );
}
