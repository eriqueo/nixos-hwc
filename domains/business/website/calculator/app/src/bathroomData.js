// ─── Bathroom Calculator Data ──────────────────────────────────────────────
// Step definitions, pricing model, and helpers.
// Extracted from BathroomCalculator.jsx for maintainability.

// ─── Images ────────────────────────────────────────────────────────────────
// Images are served from /img/calculator/bathroom/ on the live site.
// Only steps with good photos use image-cards; others use compact cards.
const IMG = "/img/calculator/bathroom";

// ─── Steps ─────────────────────────────────────────────────────────────────
export const STEPS = [
  {
    id: "project_type",
    question: "What kind of project is this?",
    subtitle: "This sets the baseline for everything else.",
    why: "A gut remodel means all-new plumbing, waterproofing, and subfloor. A refresh keeps most of that in place. This one question changes the estimate by thousands.",
    type: "cards",
    options: [
      { value: "full_gut", label: "Full gut remodel", desc: "Down to studs — new everything", icon: "GR" },
      { value: "refresh", label: "Refresh & update", desc: "New finishes, keep the layout", icon: "RF" },
      { value: "tub_to_shower", label: "Tub → shower conversion", desc: "Remove tub, build walk-in", icon: "TS" },
      { value: "specific_fix", label: "Specific repair", desc: "Leak, damage, or targeted fix", icon: "FX" },
    ],
  },
  {
    id: "bathroom_size",
    question: "How big is the bathroom?",
    subtitle: "A rough estimate is fine — we measure on-site.",
    why: "Tile, waterproofing, and heated floors are priced per square foot. Even a rough size meaningfully changes the range.",
    type: "cards",
    options: [
      { value: "small", label: "Small", desc: "Under 40 sq ft · half bath / powder room", icon: "S" },
      { value: "medium", label: "Medium", desc: "40–70 sq ft · standard full bathroom", icon: "M" },
      { value: "large", label: "Large", desc: "70–100 sq ft · primary bathroom", icon: "L" },
      { value: "xl", label: "Extra large", desc: "100+ sq ft · luxury primary suite", icon: "XL" },
    ],
  },
  {
    id: "shower_tub",
    question: "What's your shower and tub setup?",
    subtitle: "What you want in the finished bathroom.",
    why: "Separate tub and shower means two drain locations, more tile, and more waterproofing — that's where the cost jumps. The rough-in alone can add $2,000+.",
    type: "image-cards",
    options: [
      { value: "shower_only", label: "Walk-in shower", desc: "Shower only, no tub", image: `${IMG}/curbless_shower.webp` },
      { value: "tub_shower", label: "Tub + shower combo", desc: "Bathtub with showerhead above" },
      { value: "both_separate", label: "Separate tub & shower", desc: "Freestanding tub plus a shower stall" },
      { value: "tub_only", label: "Soaking tub only", desc: "Soaking tub, no shower in this room" },
    ],
  },
  {
    id: "tile_level",
    question: "What level of tile work?",
    subtitle: "Tile is usually the biggest design decision — and the biggest cost driver.",
    why: "Basic subway tile runs $3–5/sq ft installed. Natural stone and complex mosaics hit $25+/sq ft and take 3× longer. Tile choice alone can swing a bathroom by $5,000+.",
    type: "image-cards",
    options: [
      { value: "basic", label: "Clean & simple", desc: "Subway, single pattern, minimal accent", image: `${IMG}/subway_tile_niche.webp` },
      { value: "mid", label: "Designed & detailed", desc: "Mixed patterns, accent niche, quality tile", image: `${IMG}/curbless_shower_niche.webp` },
      { value: "high", label: "Custom & premium", desc: "Natural stone, mosaic, floor-to-ceiling", image: `${IMG}/tiled_large_niche.webp` },
    ],
  },
  {
    id: "fixtures",
    question: "What about fixtures and finishes?",
    subtitle: "Faucets, showerheads, hardware — the things you touch every day.",
    why: "A standard Moen faucet is $150. A Brizo or Kohler Purist is $400–600. Multiply that across every fixture in the room and the tier choice adds $2,000–$8,000.",
    type: "cards",
    options: [
      { value: "standard", label: "Good quality basics", desc: "Moen, Delta — reliable and clean", icon: "$" },
      { value: "upgraded", label: "Upgraded selections", desc: "Kohler, Brizo — designer finishes", icon: "$$" },
      { value: "premium", label: "Premium / luxury", desc: "High-end brands, statement pieces", icon: "$$$" },
    ],
  },
  {
    id: "features",
    question: "Any special features?",
    subtitle: "Select all that apply — or skip if none.",
    why: "Each of these is a standalone scope item with its own materials and labor. Heated floors alone need an electrician, dedicated circuit, and Ditra membrane — $1,200–$1,800.",
    type: "multi",
    options: [
      { value: "heated_floor", label: "Heated floors", add: 1800 },
      { value: "niches", label: "Built-in shower niches", add: 1000 },
      { value: "bench", label: "Shower bench", add: 1400 },
      { value: "double_vanity", label: "Double vanity", add: 2200 },
      { value: "lighting", label: "New lighting / electrical", add: 1500 },
      { value: "ventilation", label: "New ventilation / fan", add: 800 },
    ],
  },
  {
    id: "timeline",
    question: "When are you hoping to start?",
    subtitle: "No pressure — this helps us plan our schedule.",
    why: "Bozeman contractors book up fast. Planning 3+ months out gives time to order specialty tile and materials at better pricing.",
    type: "cards",
    options: [
      { value: "asap", label: "As soon as possible", desc: "Ready to move forward", icon: "→" },
      { value: "1_3_months", label: "1–3 months", desc: "Planning ahead, getting quotes", icon: "◇" },
      { value: "3_6_months", label: "3–6 months", desc: "Still in the thinking stage", icon: "◇◇" },
      { value: "just_exploring", label: "Just exploring", desc: "Curious about costs, no rush", icon: "…" },
    ],
  },
];

// ─── Pricing Engine (recalibrated March 2026) ──────────────────────────────
const PRICING = {
  bases: {
    full_gut: [25000, 40000],
    refresh: [12000, 22000],
    tub_to_shower: [12000, 20000],
    specific_fix: [3000, 10000],
  },
  sizeMultipliers: { small: 0.7, medium: 1.0, large: 1.35, xl: 1.75 },
  showerAdds: {
    shower_only: [0, 0],
    tub_shower: [1500, 3000],
    both_separate: [5000, 9000],
    tub_only: [-500, -1000],
  },
  tileMultipliers: { basic: 0.85, mid: 1.0, high: 1.35 },
  fixtureAdds: {
    standard: [0, 0],
    upgraded: [2500, 5000],
    premium: [6000, 12000],
  },
  featureAdds: {
    heated_floor: 1800,
    niches: 1000,
    bench: 1400,
    double_vanity: 2200,
    lighting: 1500,
    ventilation: 800,
  },
};

export function calculateRange(state) {
  let [lo, hi] = PRICING.bases[state.project_type] || [15000, 25000];

  const sm = PRICING.sizeMultipliers[state.bathroom_size] || 1;
  lo *= sm;
  hi *= sm;

  const [sL, sH] = PRICING.showerAdds[state.shower_tub] || [0, 0];
  lo += sL;
  hi += sH;

  const tm = PRICING.tileMultipliers[state.tile_level] || 1;
  lo *= tm;
  hi *= tm;

  const [fL, fH] = PRICING.fixtureAdds[state.fixtures] || [0, 0];
  lo += fL;
  hi += fH;

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

export function fireEvent(name, params) {
  if (typeof gtag === "function") gtag("event", name, params);
}

export const fmt = (n) => "$" + n.toLocaleString();

export const WEBHOOK = "https://hwc.ocelot-wahoo.ts.net/webhook/calculator-lead";
