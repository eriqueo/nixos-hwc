/**
 * Geometry derivation — extracted from assembler.js.
 *
 * Raw project state → derived area/perimeter values.
 * enrichState() maps derived values to the canonical state keys
 * that catalog formulas reference.
 */

// ─── Bathroom geometry ──────────────────────────────────────────────────────

export function deriveGeometry(s) {
  const fl        = s.bathroom_length_ft * s.bathroom_width_ft;
  const perim     = 2 * (s.bathroom_length_ft + s.bathroom_width_ft);
  const showerW   = s.shower_wall_1_width_ft + s.shower_wall_2_width_ft
                  + s.shower_wall_3_width_ft + s.shower_wall_4_width_ft;
  const wallTile  = showerW * s.shower_wall_height_ft;
  const panTile   = s.shower_pan_width_ft * s.shower_pan_length_ft;
  const curbTile  = Math.ceil(
    (s.shower_curb_height_in * 2) / 12 * s.shower_curb_length_ft
    + (s.shower_curb_width_in * 2) / 12 * s.shower_curb_length_ft
  );
  const accentTile = showerW * 1.25;
  const wallArea   = perim * s.wall_height_ft;             // total wall surface
  const ceilArea   = fl;                                    // ceiling = floor area
  const paintableWalls = Math.max(0, wallArea - wallTile);  // walls minus tiled shower area
  const paintSqft  = wallArea;                              // legacy — kept for compat
  return { fl, perim, wallTile, panTile, curbTile, accentTile, paintSqft, wallArea, ceilArea, paintableWalls, showerW };
}

// ─── Deck geometry ──────────────────────────────────────────────────────────

export function deriveDeckGeometry(s) {
  const deckSqft   = s.deck_length_ft * s.deck_width_ft;
  const perimeter  = 2 * (s.deck_length_ft + s.deck_width_ft);
  const joistCount = Math.ceil(s.deck_length_ft / (s.joist_spacing_in / 12)) + 1;
  const railingLf  = s.railing_lf || 0;
  const stairCount = s.stair_tread_count || 0;
  const footingCount = Math.max(4, Math.ceil(deckSqft / 36));
  const deckingLf  = Math.ceil(deckSqft / 0.5);
  return { deckSqft, perimeter, joistCount, railingLf, stairCount, footingCount, deckingLf };
}

// ─── Enrich state with derived geometry keys ────────────────────────────────
// Catalog formulas reference these canonical key names.

export function enrichState(state) {
  const enriched = { ...state };

  if ((state.projectType || state.job_type || '').toLowerCase() === 'deck') {
    const g = deriveDeckGeometry(state);
    enriched.deck_sqft          = g.deckSqft;
    enriched.deck_perimeter_lf  = g.perimeter;
    enriched.deck_joist_count   = g.joistCount;
    enriched.deck_footing_count = g.footingCount;
    enriched.deck_decking_lf    = g.deckingLf;
    enriched.railing_lf         = g.railingLf;
    enriched.stair_tread_count  = g.stairCount;
    enriched.deck_width_ft      = state.deck_width_ft;
    enriched.deck_height_ft     = state.deck_height_ft;
    enriched.stair_width_ft     = state.stair_width_ft || 4;
    enriched.stair_stringer_count = state.stair_stringer_count || 3;
  } else {
    const g = deriveGeometry(state);
    enriched.bathroom_floor_sqft      = state.bathroom_floor_sqft != null ? state.bathroom_floor_sqft : g.fl;
    enriched.bathroom_perimeter_lf    = g.perim;
    enriched.shower_wall_tile_sqft    = g.wallTile;
    enriched.shower_pan_tile_sqft     = g.panTile;
    enriched.shower_curb_tile_sqft    = g.curbTile;
    enriched.shower_accent_tile_sqft  = state.shower_accent_tile_sqft != null ? state.shower_accent_tile_sqft : g.accentTile;

    // Paint area — derived from scope unless manually overridden
    if (state.bathroom_wall_paint_sqft != null) {
      enriched.bathroom_wall_paint_sqft = state.bathroom_wall_paint_sqft;
    } else {
      const ps = state.paint_scope || 'walls_and_ceiling';
      enriched.bathroom_wall_paint_sqft = ps === 'walls_only' ? g.paintableWalls
        : ps === 'ceiling_only' ? g.ceilArea
        : g.paintableWalls + g.ceilArea;
    }

    // Drywall area — derived from scope unless manually overridden
    if (state.drywall_sqft != null) {
      enriched.drywall_sqft = state.drywall_sqft;
    } else {
      const ds = state.drywall_scope || 'walls_and_ceiling';
      enriched.drywall_sqft = ds === 'walls_only' ? g.paintableWalls
        : ds === 'ceiling_only' ? g.ceilArea
        : g.paintableWalls + g.ceilArea;
    }
  }

  return enriched;
}
