// ─── Shared calculator runtime ─────────────────────────────────────────────
// Consumed by bathroomData.js and deckData.js. Holds the two pricing engines
// (bathroom + deck) and the step-transformation logic that resolves image
// paths from the JSON's imageBase and per-option image filename.

// Resolve an option's image to a full URL: imageBase + "/" + filename
function resolveImage(imageBase, filename) {
  if (!filename) return null;
  if (filename.startsWith("/") || filename.startsWith("http")) return filename;
  return `${imageBase}/${filename}`;
}

// Take the raw JSON steps and replace bare image filenames with full paths.
// Leaves all other fields untouched. The React components see exactly what
// they used to: { value, label, desc, image?, icon? } per option.
export function buildSteps(data) {
  const base = data.imageBase || "";
  return (data.steps || []).map((step) => ({
    ...step,
    options: (step.options || []).map((opt) => ({
      ...opt,
      ...(opt.image ? { image: resolveImage(base, opt.image) } : {}),
    })),
  }));
}

// Pricing engines — selected by data.pricing.engine ("bathroom" or "deck").
export function makeCalculator(data) {
  const P = data.pricing || {};
  const engine = P.engine || "bathroom";

  if (engine === "bathroom") {
    return function calculateRange(state) {
      let [lo, hi] = P.bases?.[state.project_type] || [15000, 25000];

      const sm = P.sizeMultipliers?.[state.bathroom_size] || 1;
      lo *= sm;
      hi *= sm;

      const [sL, sH] = P.showerAdds?.[state.shower_tub] || [0, 0];
      lo += sL;
      hi += sH;

      const tm = P.tileMultipliers?.[state.tile_level] || 1;
      lo *= tm;
      hi *= tm;

      const [fL, fH] = P.fixtureAdds?.[state.fixtures] || [0, 0];
      lo += fL;
      hi += fH;

      (state.features || []).forEach((f) => {
        const add = P.featureAdds?.[f] || 0;
        lo += add * 0.8;
        hi += add * 1.2;
      });

      return [Math.round(lo / 500) * 500, Math.round(hi / 500) * 500];
    };
  }

  if (engine === "deck") {
    return function calculateRange(state) {
      let [lo, hi] = P.bases?.[state.project_type] || [10000, 18000];

      const sm = P.sizeMultipliers?.[state.deck_size] || 1;
      lo *= sm;
      hi *= sm;

      const [hL, hH] = P.heightAdds?.[state.deck_height] || [0, 0];
      lo += hL;
      hi += hH;

      // Material multiplier applies only to the decking-board portion of cost.
      const mm = P.materialMultipliers?.[state.material] || 1;
      const ratio = P.materialPortionRatio ?? 0.4;
      const deckLo = lo * ratio;
      const deckHi = hi * ratio;
      lo = lo * (1 - ratio) + deckLo * mm;
      hi = hi * (1 - ratio) + deckHi * mm;

      // Railing is per linear foot × perimeter (driven by deck size).
      if (state.railing && state.railing !== "none") {
        const [rL, rH] = P.railingPerFoot?.[state.railing] || [0, 0];
        const perim = P.perimeterBySize?.[state.deck_size] || 44;
        lo += rL * perim;
        hi += rH * perim;
      }

      (state.features || []).forEach((f) => {
        const add = P.featureAdds?.[f] || 0;
        lo += add * 0.8;
        hi += add * 1.2;
      });

      return [Math.round(lo / 500) * 500, Math.round(hi / 500) * 500];
    };
  }

  // Fallback if a future calculator type is added but no engine is defined.
  return () => [0, 0];
}

// Helpers — same signatures the React components already use.
export function makeHelpers(data) {
  const calculator = data.calculator || "bathroom";

  function getLabel(stepId, value) {
    const step = (data.steps || []).find((s) => s.id === stepId);
    const opt = step?.options.find((o) => o.value === value);
    return opt ? opt.label : "—";
  }

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

  function fireEvent(name, params) {
    if (typeof gtag === "function") {
      gtag("event", name, { ...params, calculator_type: calculator });
    }
  }

  const fmt = (n) => "$" + n.toLocaleString();

  return { getLabel, getAttribution, fireEvent, fmt };
}
