// ─── Shared calculator runtime ─────────────────────────────────────────────
// Consumed by CalculatorRuntime + EstimateSidebar. Holds the three pricing
// engines (assembly + bathroom + deck) and the step-transformation logic
// that resolves image paths from the JSON's imageBase and per-option image
// filename.

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

// ─── Condition trigger evaluator ──────────────────────────────────────────
// Handles: true, false, AND, OR, =, !=, variable lookup.
// These are constrained expressions we control — no need for a full parser.
function evalCondition(expr, state) {
  if (!expr || expr.trim().toLowerCase() === "true") return true;
  if (expr.trim().toLowerCase() === "false") return false;

  // AND has higher precedence — split OR first
  if (expr.includes(" OR ")) {
    return expr.split(" OR ").some((p) => evalCondition(p.trim(), state));
  }
  if (expr.includes(" AND ")) {
    return expr.split(" AND ").every((p) => evalCondition(p.trim(), state));
  }

  // != comparison
  if (expr.includes("!=")) {
    const [key, val] = expr.split("!=").map((s) => s.trim().replace(/"/g, ""));
    return String(state[key] ?? "").toLowerCase() !== val.toLowerCase();
  }
  // = comparison
  if (expr.includes("=")) {
    const [key, val] = expr.split("=").map((s) => s.trim().replace(/"/g, ""));
    return String(state[key] ?? "").toLowerCase() === val.toLowerCase();
  }

  // Boolean variable
  return Boolean(state[expr.trim()]);
}

// ─── Quantity formula evaluator ──────────────────────────────────────────
function evalFormula(formula, state, item) {
  if (!formula) return item.default_qty || 1;

  // CASE WHEN is_double_vanity THEN 6 ELSE 4 END
  const caseMatch = formula.match(
    /CASE\s+WHEN\s+(\w+)\s+THEN\s+([\d.]+)\s+ELSE\s+([\d.]+)\s+END/i
  );
  if (caseMatch) {
    return state[caseMatch[1]] ? parseFloat(caseMatch[2]) : parseFloat(caseMatch[3]);
  }

  // var * number  or  var * production_rate
  const mulMatch = formula.match(/^(\w+)\s*\*\s*(.+)$/);
  if (mulMatch) {
    const leftVal = Number(state[mulMatch[1]]) || 0;
    const rightStr = mulMatch[2].trim();
    const rightNum = parseFloat(rightStr);
    const rightVal = isNaN(rightNum)
      ? Number(item[rightStr] ?? state[rightStr] ?? 0)
      : rightNum;
    return leftVal * rightVal;
  }

  // Bare variable lookup — formula is just a state key name
  const bareVal = Number(state[formula.trim()]);
  if (!isNaN(bareVal) && bareVal > 0) return bareVal;

  return item.default_qty || 1;
}

// Pricing engines — selected by data.engine or data.pricing.engine.
export function makeCalculator(data) {
  const P = data.pricing || data;
  const engine = data.engine || P.engine || "bathroom";

  if (engine === "assembly") {
    return function calculateRange(state) {
      // 1. Derive variables from calculator state
      const size = P.sizeMap?.[state.bathroom_size] || P.sizeMap?.medium || {};
      const stConfig = P.showerTubMap?.[state.shower_tub] || {
        has_shower: true,
        has_tub: false,
      };

      // Build full state with derived variables
      const fullState = {
        ...state,
        ...size,
        ...stConfig,
        project_type_is_refresh: state.project_type === "refresh",
        has_niches: false,
        niche_count: 0,
        has_bench: false,
        is_double_vanity: false,
        has_new_lighting: false,
        has_new_ventilation: false,
        has_heated_floor: false,
      };

      // Apply feature flags
      const features = state.features || [];
      for (const feat of features) {
        const fMap = P.featureMap?.[feat];
        if (fMap) Object.assign(fullState, fMap);
      }

      const rates = P.tradeRates || {};
      const tileRates = P.tileProductionRates?.[state.tile_level] || {};
      let totalPrice = 0;

      // 2. Iterate scope items, filter by condition, calculate price
      for (const item of P.scopeItems || []) {
        if (!evalCondition(item.condition_trigger, fullState)) continue;

        // Apply tile production rate overrides before quantity calculation.
        // The tileProductionRates config adjusts labor hours based on tile_level
        // (basic/mid/high). This must happen before formula eval since formulas
        // may reference production_rate.
        let effectiveItem = item;
        if (item.item_type === "labor" && item.production_rate) {
          const cn = item.canonical_name || "";
          if (cn.includes("Floor Installation") && tileRates.floor) {
            effectiveItem = { ...item, production_rate: tileRates.floor };
          } else if (
            cn.includes("Shower Wall Installation") &&
            tileRates.wall
          ) {
            effectiveItem = { ...item, production_rate: tileRates.wall };
          }
        }

        // Calculate quantity
        let qty;
        if (effectiveItem.qty_formula) {
          qty = evalFormula(effectiveItem.qty_formula, fullState, effectiveItem);
        } else if (
          effectiveItem.production_rate &&
          effectiveItem.qty_driver &&
          effectiveItem.item_type === "labor"
        ) {
          const driverVal = Number(fullState[effectiveItem.qty_driver]) || 0;
          qty = driverVal * effectiveItem.production_rate;
        } else {
          qty = effectiveItem.default_qty || 1;
        }

        // Refresh projects reduce labor hours for trades that have less scope
        if (
          fullState.project_type === "refresh" &&
          effectiveItem.item_type === "labor" &&
          P.refreshFactors?.[effectiveItem.trade] !== undefined
        ) {
          qty *= P.refreshFactors[effectiveItem.trade];
          if (qty <= 0) continue;
        }

        const waste = effectiveItem.waste_factor || 1.0;

        if (effectiveItem.item_type === "labor") {
          const tradeRate = rates[effectiveItem.trade]?.price || 94.5;
          totalPrice += qty * waste * tradeRate;
        } else if (
          effectiveItem.item_type === "material" ||
          effectiveItem.item_type === "other"
        ) {
          totalPrice += qty * waste * (effectiveItem.unit_price || 0);
        } else if (effectiveItem.item_type === "allowance") {
          let allowQty = qty;
          if (
            effectiveItem.qty_driver &&
            typeof fullState[effectiveItem.qty_driver] === "number" &&
            fullState[effectiveItem.qty_driver] > 0 &&
            !effectiveItem.qty_formula
          ) {
            allowQty = fullState[effectiveItem.qty_driver];
          }

          // Double vanity multiplier for vanity allowances
          const isVanity = (effectiveItem.canonical_name || "").includes(
            "Vanity"
          );
          const vanityMult =
            isVanity && fullState.is_double_vanity ? 1.5 : 1.0;

          totalPrice +=
            allowQty * waste * (effectiveItem.unit_price || 0) * vanityMult;
        }
      }

      // 3. Add flat feature adds (heated_floor, bench — not assembly-based yet)
      for (const feat of features) {
        const add = P.featureAdds?.[feat] || 0;
        totalPrice += add;
      }

      // 4. Apply ±18% spread, round to $500
      const lo = Math.round((totalPrice * 0.82) / 500) * 500;
      const hi = Math.round((totalPrice * 1.18) / 500) * 500;
      return [lo, hi];
    };
  }

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

      // Generic data-driven hooks — calculator JSON can add steps without
      // engine changes. stepMultipliers: { stepId: { value: m | [mLo, mHi] } }
      // scales the running range; stepAdds: { stepId: { value: [aLo, aHi] } }
      // adds flat amounts. Unknown/missing selections are no-ops.
      Object.entries(P.stepMultipliers || {}).forEach(([stepId, byValue]) => {
        const m = byValue?.[state[stepId]];
        if (m == null) return;
        const [mLo, mHi] = Array.isArray(m) ? m : [m, m];
        lo *= mLo;
        hi *= mHi;
      });
      Object.entries(P.stepAdds || {}).forEach(([stepId, byValue]) => {
        const a = byValue?.[state[stepId]];
        if (a == null) return;
        const [aLo, aHi] = Array.isArray(a) ? a : [a, a];
        lo += aLo;
        hi += aHi;
      });

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
    window.dataLayer = window.dataLayer || [];
    window.dataLayer.push(Object.assign({
      event: name,
      calculator_type: calculator
    }, params || {}));
  }

  const fmt = (n) => "$" + n.toLocaleString();

  return { getLabel, getAttribution, fireEvent, fmt };
}
