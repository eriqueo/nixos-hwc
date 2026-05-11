# Estimator Rate Audit Report

**Date:** 2026-05-05
**Auditor:** Claude (automated)
**Sources:** estimator tradeRates.json, calculator-bathroom.json (source of truth), Postgres trade_rates, catalog.json

---

## Section 1: Trade Rate Comparison

### Estimator model: `price = wage × burden × markup`
### Calculator model: `cost / price` (flat values, no formula)
### Postgres model: `unit_price = base_wage × burden_factor × markup_factor` (generated column)

#### Trades used in bathroom estimates

| Trade (Estimator) | Rate Key Used | Est Wage | Est Burden | Est Markup | Est Cost/hr | Est Price/hr | Calc Cost/hr | Calc Price/hr | PG Cost/hr | PG Price/hr | Status |
|---|---|---|---|---|---|---|---|---|---|---|---|
| admin | planning | $35.00 | 1.35 | 2.00 | $47.25 | $94.50 | $47.25 | $94.50 | $47.25 | $94.50 | **MATCH** |
| demo | demo | $35.00 | 1.35 | 2.00 | $47.25 | $94.50 | $35.00 | $70.00 | $47.25 | $94.50 | **MISMATCH** |
| drywall | drywall | $35.00 | 1.35 | 2.00 | $47.25 | $94.50 | $47.25 | $94.50 | $47.25 | $94.50 | **MATCH** |
| electrical | electrical | $45.00 | 1.35 | 1.75 | $60.75 | $106.31 | $60.75 | $106.31 | $60.75 | $106.31 | **MATCH** |
| finish_carpentry | cabinetry | $35.00 | 1.35 | 1.85 | $47.25 | $87.41 | $51.30 | $94.91 | $47.25 | $87.41 | **MISMATCH** |
| framing | framing | $38.00 | 1.35 | 1.85 | $51.30 | $94.91 | $51.30 | $94.91 | $51.30 | $94.91 | **MATCH** |
| painting | painting | $35.00 | 1.35 | 2.00 | $47.25 | $94.50 | $47.25 | $94.50 | $47.25 | $94.50 | **MATCH** |
| plumbing | plumbing | $42.00 | 1.35 | 1.75 | $56.70 | $99.23 | $56.70 | $120.00 | $56.70 | $99.23 | **MISMATCH** |
| tile | tiling | $45.00 | 1.35 | 2.00 | $60.75 | $121.50 | $60.75 | $100.00 | $60.75 | $121.50 | **MISMATCH** |
| waterproofing | waterproofing | $42.00 | 1.35 | 1.75 | $56.70 | $99.23 | — | — | $56.70 | $99.23 | **NOT IN CALCULATOR** |

#### Mismatch details

**demo** — Estimator overcharges by $24.50/hr ($94.50 vs $70.00 = +35%)
- Calculator uses cost=$35 (raw wage, no burden) and price=$70 (2× wage)
- Estimator applies burden to demo workers: $35 × 1.35 = $47.25 cost, × 2.0 = $94.50 price
- Calculator approach makes more sense: demo labor is less skilled, shouldn't carry full burden

**finish_carpentry** — Estimator undercharges by $7.50/hr ($87.41 vs $94.91 = -8%)
- TRADE_RATE_KEY maps "finish_carpentry" → "cabinetry" (wage=$35)
- Calculator uses cost=$51.30 (framing-level wage=$38), price=$94.91
- Postgres "trimwork" matches calculator: $94.91
- **Root cause:** Wrong mapping. Should map to "trimwork" not "cabinetry"

**plumbing** — Estimator undercharges by $20.77/hr ($99.23 vs $120.00 = -17%)
- Same cost ($56.70) but calculator markup implies ~2.12× vs estimator's 1.75×
- Plumbing carries licensing/insurance premium the estimator doesn't capture

**tile** — Estimator overcharges by $21.50/hr ($121.50 vs $100.00 = +22%)
- Same cost ($60.75) but calculator markup implies ~1.65× vs estimator's 2.0×
- Tile is the highest-volume trade in bathroom remodels — this compounds significantly

**waterproofing** — No calculator equivalent
- Calculator assigns waterproofing labor to the "tile" trade
- Estimator has dedicated trade at $99.23/hr (plumbing-level pricing)

#### Estimator trades NOT in calculator (17 trades)

appliances, cabinetry, cleanup, concrete, countertop, decking, doors_windows, flooring, furnishings, hvac, insulation, miscellaneous, siding, sitework, specialty, tiling (dupe of tile), trimwork

These are used for non-bathroom project types (deck, kitchen, general) or are the underlying keys that bathroom trades map to.

---

## Section 2: Production Rate Comparison

| Scope Item | Trade | Est Rate (mh/unit) | Unit | Calc Rate | Craftsman Ref | Status |
|---|---|---|---|---|---|---|
| Demo - Floor Tile | demo | 0.08 mh/SF | SF | 0.08 mh/SF | 0.08 (Sm crew) | **MATCH** |
| Demo - Shower Surround | demo | — (fixed 4 hrs) | — | 0.06 mh/SF | 0.06 (Sm crew) | **STRUCTURAL DIFF** |
| Framing - General | framing | 0.05 mh/SF | SF | 0.05 mh/SF | 0.05 remodel | **MATCH** (but estimator uses fixed 4hr default, not formula-driven) |
| Waterproofing Membrane | tile/waterproofing | 0.15 mh/SF | SF | 0.15 mh/SF | — (custom) | **MATCH** |
| Tile - Floor | tile | 0.28 mh/SF | SF | varies by level: 0.20/0.28/0.38 | Craftsman-derived | **PARTIAL MATCH** |
| Tile - Shower Wall | tile | 0.33 mh/SF | SF | varies by level: 0.24/0.33/0.45 | Craftsman-derived | **PARTIAL MATCH** |
| Tile - Shower Pan | tile | 0.25 mh/SF | SF | — | custom | **ESTIMATOR ONLY** |
| Tile - Shower Curb | tile | 0.30 mh/SF | SF | — | custom | **ESTIMATOR ONLY** |
| Tile - Accent Band | tile | 0.25 mh/SF | SF | — | custom | **ESTIMATOR ONLY** |
| Tile - Niche | tile | — (4 hrs/niche) | EA | 4 hrs/niche | custom | **MATCH** (but see wasteFactor bug) |
| Drywall Remove/Replace | drywall | 0.05 mh/SF | SF | 0.05 mh/SF | 0.03 new, 0.05 remodel | **MATCH** |
| Painting Prime/Finish | painting | 0.02 mh/SF | SF | 0.02 mh/SF | 0.006+2×0.007 | **MATCH** |
| Trim & Baseboard | finish_carp | 0.15 mh/LF | LF | 0.15 mh/LF | Craftsman-derived | **NOT IN ESTIMATOR CATALOG** |

#### Key differences

1. **Tile production rates are fixed in estimator, variable in calculator.** The calculator uses `tileProductionRates` keyed by tile_level (basic/mid/high). The estimator catalog hardcodes mid-tier rates (0.28 floor, 0.33 wall). No mechanism to adjust by complexity.

2. **Demo shower surround** — Calculator uses 0.06 mh/SF (area-driven), estimator uses fixed 4 hours regardless of shower size.

3. **Estimator has granular tile sub-items** (pan, curb, accent) that the calculator doesn't break out — calculator bundles these into the shower wall tile scope.

4. **Trim & baseboard** exists in calculator scope items but not in the estimator catalog as a distinct production-rate item.

---

## Section 3: Structural Differences

### Trade count comparison

| System | Trade Count | Notes |
|---|---|---|
| Estimator (tradeRates.json) | 26 | Full trade list for all project types |
| Calculator (bathroom JSON) | 9 | Bathroom-specific trades only |
| Postgres (trade_rates) | 26 | Mirrors estimator exactly |

### Pricing model differences

The estimator and calculator use **fundamentally different pricing models:**

| Aspect | Estimator | Calculator |
|---|---|---|
| Rate storage | wage × burden × markup (3 values) | cost / price (2 values) |
| Rate computation | Dynamic: `price = wage * burden * markup` | Static: pre-computed flat rates |
| Material markup | `MAT_MARKUP = 1.4286` (~30% margin) | `materialMarkup = 1.429` | 
| Burden concept | Explicit (payroll tax, insurance, etc.) | Baked into cost or absent |

**The models do NOT produce the same results** for 4 of 9 bathroom trades. The calculator was updated tonight and represents Eric's actual pricing intent. The estimator's wage×burden model produces different numbers because:
- Demo: burden shouldn't apply to unskilled demo labor
- Finish carpentry: wrong wage level (general vs framing)
- Plumbing: markup too low (1.75× vs implied 2.12×)
- Tile: markup too high (2.0× vs implied 1.65×)

### Missing scope items

**In calculator, not in estimator catalog:**
- Trim & Baseboard (has production rate 0.15 mh/LF, exists in calculator scopeItems)
- Heated Floor feature add ($1,800)
- Shower Bench feature add ($1,400)
- Double Vanity multiplier (calculator uses 1.5× on vanity allowances)
- Refresh/tub_to_shower project type modifiers (calculator has `refreshFactors` and per-item CASE expressions)

**In estimator catalog, not in calculator:**
- Tile sub-items: Shower Pan, Shower Curb, Accent Band (separate labor items)
- Granular material line items (individual products vs lump-sum packages)
- Waterproofing as distinct trade (calculator uses tile trade for waterproofing)

### Catalog hardcoded prices vs trade rate lookups

The assembler **always** uses `tradeRate()` for Labor-type items, ignoring any `unitCost`/`unitPrice` in the catalog. However, 6 catalog entries have hardcoded prices that contradict the trade rate:

| Catalog Item | Catalog unitCost | Catalog unitPrice | Actual Rate Used | Discrepancy |
|---|---|---|---|---|
| Plumbing - Mixer Valve (id:938) | $100.00 | $142.86 | $56.70 / $99.23 | Catalog has sub pricing, ignored |
| Plumbing - Shower Trim (id:939) | $62.00 | $124.00 | $56.70 / $99.23 | Catalog has sub pricing, ignored |
| Plumbing - Toilet (id:940) | $80.00 | $120.00 | $56.70 / $99.23 | Catalog has sub pricing, ignored |
| Painting - Caulking (id:924) | $50.00 | $83.33 | $47.25 / $94.50 | Stale values, ignored |
| Painting - Prime Coat (id:950) | $50.00 | $83.33 | $47.25 / $94.50 | Stale values, ignored |
| Tile - Niche (id:27) | $80.00 | $114.29 | $60.75 / $121.50 | Stale values, ignored |

These stale values create confusion but don't affect computed prices (the assembler overrides them).

---

## Section 4: Template Audit

### Template 1: "Standard Medium Gut" (id:1)

**State:** 10×8 bathroom, full gut, shower only (5+3+5+0 walls × 8ft), 1 niche, new electrical + fan, all finishes, 32 sqft wall repair. Allowances: toilet=$400, vanity=$1,500, shower_trim=$500, accessories=$300.

**Derived geometry:** floor=80sf, perimeter=36lf, shower_wall=104sf, pan=15sf, curb=5sf, paint=288sf

**Estimated total price: ~$28,800–$29,500**

| Category | Hours | Price |
|---|---|---|
| Admin (planning) | 9 hrs | ~$850 |
| Demo | 14 hrs | ~$1,323 |
| Framing | 6 hrs | ~$570 |
| Plumbing | 15 hrs | ~$1,489 |
| Electrical | 7 hrs | ~$744 |
| Waterproofing | 20 hrs | ~$1,985 |
| Tile labor | ~64 hrs | ~$7,825 |
| Drywall | 2 hrs | ~$189 |
| Painting | 14 hrs | ~$1,323 |
| Finish Carpentry | 21 hrs | ~$1,836 |
| **Labor subtotal** | **~172 hrs** | **~$18,134** |
| Materials/supplies | — | ~$2,935 |
| Allowances (fixtures, tile) | — | ~$6,784 |
| Permit + other | — | ~$786 |
| **Grand total** | — | **~$28,639** |

**Issues found:**
- **BUG: Niche tile wasteFactor=0.1** — Catalog id:27 has `wasteFactor: 0.1`. This multiplies the 4-hour niche qty by 0.1, producing 0.4 hours instead of 4. Should be 1.0 (or removed). **Impact: ~$437 undercharge per niche.**
- Waterproofing at 20 hours ($1,985) seems high for a medium bathroom — the formula `(104 + 80*0.3) * 0.15 = 19.2 → 20` includes 30% of floor area, which may overcount.
- Tile labor (64 hrs at $121.50/hr) is the dominant cost. If using calculator's $100/hr tile rate, this would be $6,440 — a **$1,385 difference**.

### Template 2: "Medium Gut + Tub" (id:2)

**State:** Same as Template 1 but with `new_tub="yes"`, shower walls 5+3+5+0=13×8=104sf, curb length 5ft.

**Additional items vs Template 1:**
- Bathtub surround demo: +6 hrs demo ($567)
- Tub install: +5 hrs framing ($475)
- Tub drain hookup: +4 hrs plumbing ($397)
- Tub allowance: $1,000 state value → matPrice = $1,429

**Estimated total: ~$31,500–$32,000**

**Issues:** Same niche bug. Tub allowance uses state key but Template 2 state has `tub_allowance: 1000`.

### Template 3: "Small Refresh" (id:3)

**State:** 5×8 bathroom, demo_scope="shower_and_floors", no tub, no electrical, no fan, 0 wall repair.

**Derived geometry:** floor=40sf, perimeter=26lf, shower_wall=(4+3+4+0)×7=77sf, pan=9sf, paint=208sf

**Key items that DON'T fire:** bathtub demo, tub install, tub drain, electrical general, exhaust fan, drywall, building permit.

**Estimated total: ~$17,000–$18,000**

**Issues:** This template's allowances are modest (toilet=$300, vanity=$1,000, accessories=$200). Reasonable for a refresh.

### Template 4: "Tub-to-Shower Conversion" (id:4)

**State:** 10×8, full gut, 2 niches, shower walls 5+5+5+0=15×8=120sf, no tub (removing it).

**Note:** `new_tub="no"` so tub-related items don't fire. Bathtub surround demo condition is `new_tub == "yes" AND demo_scope == "full_gut"` — this means the tub removal labor **doesn't fire** for a tub-to-shower conversion unless new_tub is "yes". This seems like a **condition logic error** — removing a tub should trigger demo even when not installing a new one.

**Estimated total: ~$30,000–$31,000** (2 niches add ~$1,200 in framing + tile)

**Issues:**
- **Missing tub removal scope** — no demo line item fires for removing the existing tub
- Niche wasteFactor bug doubles in impact (2 niches × $437 = ~$874 undercharge)

### Template 5–8: Deck Templates

Deck templates (id:5–8) use a separate project type and different catalog entries. Trade rate audit for deck trades shows same rates since they share tradeRates.json. The TRADE_RATE_KEY mappings for deck trades:
- `decking` → `framing` ($94.91/hr)
- `concrete` → `framing` ($94.91/hr)
- `stairs` → `framing` ($94.91/hr)
- `railing` → `framing` ($94.91/hr)
- `sitework` → `demo` ($94.50/hr)

No calculator comparison available for deck (calculator only covers bathrooms).

### Referenced trades/items that don't exist

All templates reference valid trades. No template references a nonexistent state key — all state keys map to parameters.json entries or derived geometry keys.

---

## Section 5: Recommended Changes (Do Not Implement)

### P0 — Wrong rates producing incorrect estimates today

1. **Fix TRADE_RATE_KEY mapping for finish_carpentry**
   - Change: `'finish_carpentry': 'cabinetry'` → `'finish_carpentry': 'trimwork'`
   - Also: `'finish carpentry': 'cabinetry'` → `'finish carpentry': 'trimwork'`
   - Impact: Finish carpentry goes from $87.41/hr → $94.91/hr (+$7.50/hr)
   - Affects: ~21 hrs in standard gut = ~$158 increase per estimate

2. **Fix niche tile wasteFactor bug**
   - Change: catalog.json id:27 `wasteFactor: 0.1` → `wasteFactor: 1.0`
   - Impact: Niche tile labor goes from 0.4 hrs → 4 hrs per niche
   - Affects: ~$437/niche undercharge currently

3. **Fix tub-to-shower demo condition**
   - Catalog id:1215 condition: `new_tub == "yes" AND demo_scope == "full_gut"`
   - Should also fire when demo_scope is full_gut and a tub exists (regardless of new_tub)
   - Or add separate "Demo | Tub Removal" item with condition for conversions
   - Impact: 6 hrs demo labor (~$567) currently missing from tub-to-shower estimates

4. **Update demo trade rate to match calculator**
   - In tradeRates.json, demo wage/burden/markup produces $94.50/hr
   - Calculator says $70.00/hr
   - Options: (a) change demo markup from 2.0 → ~1.48 to hit $70, or (b) set demo wage=$35, burden=1.0, markup=2.0 = $70
   - Impact: 14 hrs demo in standard gut = $343 overcharge currently

5. **Update plumbing markup to match calculator**
   - Calculator price=$120.00, estimator produces $99.23 (markup 1.75)
   - Need markup ≈ 2.116 to hit $120: change from 1.75 → 2.12
   - Impact: 15 hrs plumbing in standard gut = $312 undercharge currently

6. **Update tile markup to match calculator**
   - Calculator price=$100.00, estimator produces $121.50 (markup 2.0)
   - Need markup ≈ 1.646 to hit $100: change from 2.0 → 1.65
   - Impact: 64 hrs tile in standard gut = $1,376 overcharge currently
   - **This is the single largest rate discrepancy by dollar volume**

### P1 — Structural changes

7. **Add tile_level production rate support to estimator**
   - Calculator varies tile rates by complexity: basic (0.20/0.24), mid (0.28/0.33), high (0.38/0.45)
   - Estimator hardcodes mid-tier rates
   - Add `tile_level` state key and conditional production rates in catalog formulas

8. **Add refresh/conversion project type modifiers**
   - Calculator has `refreshFactors` (demo 0.5×, framing 0.3×) and per-item CASE formulas
   - Estimator catalog conditions only distinguish by demo_scope, not project_type_is_refresh
   - Need to add state keys and conditional qty adjustments for refresh vs gut

9. **Clean up stale catalog unitCost/unitPrice on Labor items**
   - 6 labor catalog entries have prices the assembler ignores
   - Either remove them or document they're reference-only
   - Confusing for anyone reading the catalog data

10. **Add missing scope items: heated floor, bench, trim/baseboard**
    - Calculator has these as feature adds or scope items
    - Estimator catalog lacks them

11. **Reconcile waterproofing trade vs calculator's tile trade approach**
    - Calculator prices waterproofing at tile rate ($100/hr)
    - Estimator uses dedicated waterproofing trade at $99.23/hr
    - These are close but should be intentionally aligned

### P2 — Nice-to-have improvements

12. **Consider switching estimator to cost/price model**
    - The wage×burden×markup model is more complex and produces rates that diverge from what Eric actually charges
    - A direct cost/price model (like the calculator) is simpler and keeps rates aligned
    - Postgres could store both models (it already has generated columns)

13. **Remove duplicate tile/tiling entries**
    - tradeRates.json has both "tile" and "tiling" with identical values
    - The TRADE_RATE_KEY maps 'tile' → 'tiling', so "tile" entry is dead code
    - Clean up to avoid confusion

14. **Add double vanity multiplier**
    - Calculator applies 1.5× to vanity allowances for double vanity
    - Estimator has `is_double_vanity` in some formulas but not on vanity allowance

15. **Review waterproofing formula**
    - `(shower_wall_tile_sqft + bathroom_floor_sqft * 0.3) * 0.15` seems aggressive
    - 20 hrs waterproofing for a medium bathroom is high
    - Compare against actual project data

---

## Summary

| Finding | Severity | Annual Impact (est. 20 bathroom estimates) |
|---|---|---|
| Tile rate $121.50 vs $100 (overcharge) | P0 | ~$27,500 overbilled |
| Demo rate $94.50 vs $70 (overcharge) | P0 | ~$6,860 overbilled |
| Plumbing rate $99.23 vs $120 (undercharge) | P0 | ~$6,240 underbilled |
| Finish carpentry mapping (undercharge) | P0 | ~$3,160 underbilled |
| Niche wasteFactor bug (undercharge) | P0 | ~$8,740 underbilled (assuming avg 1 niche) |
| Tub removal missing from conversions | P0 | ~$2,835 underbilled (5 conversions/yr) |

**Net effect on a Standard Medium Gut estimate:** Estimator currently produces ~$28,600. After P0 fixes, it would produce ~$27,200 — about $1,400 lower, primarily because the tile rate overage ($1,376) nearly cancels the plumbing/finish carp/niche underage.

The tile rate fix alone would reduce every bathroom estimate by $1,000–$2,000 depending on size. This is the highest-priority single change.
