// ─── Deck Calculator Data ──────────────────────────────────────────────────
// Step definitions, pricing model, and helpers.
// Mirrors bathroomData.js structure for consistency.

// ─── Steps ─────────────────────────────────────────────────────────────────
export const STEPS = [
  {
    id: "project_type",
    question: "What kind of deck project is this?",
    subtitle: "This sets the baseline for everything else.",
    why: "A brand-new deck build means foundation, framing, and decking from scratch. A rebuild reuses some existing structure. A repair might just be boards and rails. This one question changes the estimate by thousands.",
    type: "cards",
    options: [
      { value: "new_build", label: "New deck build", desc: "No existing deck — building from the ground up", icon: "NB" },
      { value: "full_rebuild", label: "Full rebuild", desc: "Tear off the old deck and start fresh", icon: "FR" },
      { value: "partial_rebuild", label: "Partial rebuild", desc: "Keep the frame, replace decking and rails", icon: "PR" },
      { value: "repair_refresh", label: "Repair or refresh", desc: "Fix specific issues — boards, stairs, rails", icon: "RR" },
    ],
  },
  {
    id: "deck_size",
    question: "How big is the deck?",
    subtitle: "A rough estimate works — we'll measure precisely on-site.",
    why: "Materials and labor both scale with square footage. Lumber, fasteners, and joist count are all driven by size. Even a rough number gets us in the right ballpark — Bozeman lumber prices are what make this accurate, not national averages.",
    type: "cards",
    options: [
      { value: "small", label: "Small", desc: "Under 150 sq ft · 8×16, entry landing", icon: "S" },
      { value: "medium", label: "Medium", desc: "150–300 sq ft · 12×20, standard back deck", icon: "M" },
      { value: "large", label: "Large", desc: "300–500 sq ft · 16×24, entertaining deck", icon: "L" },
      { value: "xl", label: "Extra large", desc: "500+ sq ft · multi-level, wraparound", icon: "XL" },
    ],
  },
  {
    id: "deck_height",
    question: "How high off the ground?",
    subtitle: "This affects foundation, railing requirements, and permits.",
    why: "In Gallatin County, decks over 30 inches above grade require railings and typically need a building permit. Ground-level decks skip both — saving $1,500–4,000 in railings alone. Height also determines whether you need concrete footings or can use deck blocks.",
    type: "cards",
    options: [
      { value: "ground_level", label: "Ground level", desc: "Under 12 inches — floating or on blocks", icon: "GL" },
      { value: "low", label: "Low profile", desc: "12–30 inches — no railing required", icon: "LP" },
      { value: "standard", label: "Standard height", desc: "30–60 inches — railing required", icon: "SH" },
      { value: "elevated", label: "Elevated", desc: "5+ feet — second story, walkout, or hillside", icon: "EL" },
    ],
  },
  {
    id: "material",
    question: "What material for the decking?",
    subtitle: "This is your biggest material cost decision.",
    why: "Pressure-treated lumber runs $2–3 per linear foot in Bozeman — solid and affordable, but needs maintenance every few years. Cedar is beautiful but pricier. Composite (Trex, TimberTech) costs 2–3× more upfront but lasts decades with zero staining. Material choice alone can swing a deck project by $3,000–8,000.",
    type: "cards",
    options: [
      { value: "pt_lumber", label: "Pressure-treated", desc: "Affordable, proven — needs staining every 2–3 years", icon: "PT" },
      { value: "cedar", label: "Cedar", desc: "Beautiful grain, natural weather resistance", icon: "CD" },
      { value: "composite_mid", label: "Composite (mid)", desc: "Trex Select, TimberTech Edge — low maintenance", icon: "CM" },
      { value: "composite_premium", label: "Composite (premium)", desc: "Trex Transcend, TimberTech Vintage — top tier", icon: "CP" },
    ],
  },
  {
    id: "railing",
    question: "What about railings?",
    subtitle: "Required if your deck is over 30\" above grade.",
    why: "Wood railings are the budget option at $30–50 per linear foot installed. Cable rail and metal balusters look sharp but cost 2–3× more. Glass panels are premium at $80–150+ per foot. If your deck is under 30 inches, you might skip them entirely — or add a simple cap rail for looks.",
    type: "cards",
    options: [
      { value: "none", label: "No railing", desc: "Ground-level or low deck — not required", icon: "—" },
      { value: "wood", label: "Wood railing", desc: "PT or cedar posts and balusters — classic look", icon: "WR" },
      { value: "metal_cable", label: "Metal or cable", desc: "Aluminum balusters or cable rail — modern and clean", icon: "MC" },
      { value: "glass", label: "Glass panels", desc: "Tempered glass — unobstructed views, premium cost", icon: "GP" },
    ],
  },
  {
    id: "features",
    question: "Any extras?",
    subtitle: "Select everything that applies.",
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
      { value: "asap", label: "As soon as possible", desc: "Ready to move — let's get on the schedule", icon: "→" },
      { value: "1_3_months", label: "1–3 months", desc: "Planning ahead, want to get numbers", icon: "◇" },
      { value: "3_6_months", label: "3–6 months", desc: "Thinking about next season", icon: "◇◇" },
      { value: "exploring", label: "Just exploring", desc: "Curious what a deck costs in Bozeman", icon: "…" },
    ],
  },
];

// ─── Pricing Engine ────────────────────────────────────────────────────────
const PRICING = {
  bases: {
    new_build: [12000, 22000],
    full_rebuild: [10000, 18000],
    partial_rebuild: [5000, 12000],
    repair_refresh: [2500, 7000],
  },
  sizeMultipliers: { small: 0.65, medium: 1.0, large: 1.55, xl: 2.2 },
  heightAdds: {
    ground_level: [0, 0],
    low: [500, 1000],
    standard: [1500, 3000],
    elevated: [4000, 8000],
  },
  materialMultipliers: { pt_lumber: 1.0, cedar: 1.25, composite_mid: 1.6, composite_premium: 2.0 },
  railingPerFoot: {
    none: [0, 0],
    wood: [30, 50],
    metal_cable: [60, 90],
    glass: [90, 150],
  },
  perimeterBySize: { small: 30, medium: 44, large: 58, xl: 75 },
  featureAdds: {
    stairs: 1500,
    lighting: 1200,
    builtin_bench: 1400,
    pergola: 5000,
    hottub_pad: 2000,
    skirting: 1000,
  },
};

export function calculateRange(state) {
  let [lo, hi] = PRICING.bases[state.project_type] || [10000, 18000];

  const sm = PRICING.sizeMultipliers[state.deck_size] || 1;
  lo *= sm;
  hi *= sm;

  const [hL, hH] = PRICING.heightAdds[state.deck_height] || [0, 0];
  lo += hL;
  hi += hH;

  const mm = PRICING.materialMultipliers[state.material] || 1;
  const deckLo = lo * 0.4;
  const deckHi = hi * 0.4;
  lo = lo * 0.6 + deckLo * mm;
  hi = hi * 0.6 + deckHi * mm;

  if (state.railing && state.railing !== "none") {
    const [rL, rH] = PRICING.railingPerFoot[state.railing] || [0, 0];
    const perim = PRICING.perimeterBySize[state.deck_size] || 44;
    lo += rL * perim;
    hi += rH * perim;
  }

  (state.features || []).forEach((f) => {
    lo += (PRICING.featureAdds[f] || 0) * 0.8;
    hi += (PRICING.featureAdds[f] || 0) * 1.2;
  });

  return [Math.round(lo / 500) * 500, Math.round(hi / 500) * 500];
}

// ─── Helpers ───────────────────────────────────────────────────────────────
export function getLabel(stepId, value) {
  const step = STEPS.find((s) => s.id === stepId);
  const opt = step?.options.find((o) => o.value === value);
  return opt ? opt.label : "—";
}

export function getAttribution() {
  try {
    const utm = {};
    ["utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term"].forEach((k) => {
      const v = sessionStorage.getItem(k);
      if (v) utm[k] = v;
    });
    return {
      ...utm,
      landing_page: sessionStorage.getItem("landing_page") || window.location.pathname,
      referrer: sessionStorage.getItem("referrer") || document.referrer || "",
    };
  } catch {
    return {};
  }
}

export function fireEvent(name, params) {
  if (typeof gtag === "function") gtag("event", name, { ...params, calculator_type: "deck" });
}

export const fmt = (n) => "$" + n.toLocaleString();

export const WEBHOOK = "https://hwc.ocelot-wahoo.ts.net/webhook/calculator-lead";
