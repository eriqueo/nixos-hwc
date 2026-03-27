-- ============================================================================
-- BATHROOM COST RULES - SEED DATA
-- ============================================================================
-- NOTE: These are sample prices for a mid-tier market.
-- Adjust base_cost_min/max values to match your local market rates.
-- ============================================================================

-- Clear existing rules (for re-seeding)
TRUNCATE TABLE cost_rules CASCADE;

-- ============================================================================
-- MODULE: tub_to_shower (Tub to Shower Conversion)
-- ============================================================================

-- Base demo + prep work
INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'tub_to_shower',
    'demo_and_prep',
    '{"goals_contains": "convert_tub_to_shower"}'::jsonb,
    800, 1500, 0.80, 1,
    'Demo existing tub, dispose, prep substrate',
    true
);

-- Custom tiled shower base
INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'tub_to_shower',
    'tiled_shower_pan',
    '{"goals_contains": "convert_tub_to_shower", "shower_type": "custom_tiled_shower"}'::jsonb,
    2000, 3500, 0.65, 2,
    'Custom tile shower pan with liner',
    true
);

-- Prefab shower base (cheaper alternative)
INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'tub_to_shower',
    'prefab_shower_base',
    '{"goals_contains": "convert_tub_to_shower", "shower_type": "prefab_shower_kit"}'::jsonb,
    600, 1200, 0.50, 0,
    'Prefab acrylic or fiberglass base',
    true
);

-- Shower wall tile (per sqft, assuming ~90 sqft for standard shower)
INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, cost_per_sqft_min, cost_per_sqft_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'tub_to_shower',
    'shower_wall_tile_ceramic',
    '{"goals_contains": "convert_tub_to_shower", "tile_level": "basic_ceramic"}'::jsonb,
    12, 18, 0.60, 0,
    'Basic ceramic tile + backer + labor per sqft',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, cost_per_sqft_min, cost_per_sqft_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'tub_to_shower',
    'shower_wall_tile_porcelain',
    '{"goals_contains": "convert_tub_to_shower", "tile_level": "porcelain"}'::jsonb,
    18, 28, 0.60, 1,
    'Porcelain tile + backer + labor per sqft',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, cost_per_sqft_min, cost_per_sqft_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'tub_to_shower',
    'shower_wall_tile_stone',
    '{"goals_contains": "convert_tub_to_shower", "tile_level": "natural_stone"}'::jsonb,
    30, 50, 0.55, 2,
    'Natural stone tile + backer + specialized labor per sqft',
    true
);

-- Shower door/enclosure
INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'tub_to_shower',
    'standard_shower_door',
    '{"goals_contains": "convert_tub_to_shower"}'::jsonb,
    600, 1200, 0.40, 0,
    'Standard framed or semi-frameless shower door',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'tub_to_shower',
    'frameless_glass',
    '{"goals_contains": "convert_tub_to_shower", "extras_contains": "frameless_glass"}'::jsonb,
    1500, 3000, 0.35, 1,
    'Custom frameless glass shower enclosure',
    true
);

-- Shower fixtures
INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'tub_to_shower',
    'shower_valve_standard',
    '{"goals_contains": "convert_tub_to_shower"}'::jsonb,
    400, 800, 0.60, 0,
    'Standard shower valve + trim',
    true
);

-- ============================================================================
-- MODULE: wall_tile_replacement
-- ============================================================================

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'wall_tile_replacement',
    'demo_existing',
    '{"goals_contains": "replace_wall_tile"}'::jsonb,
    600, 1000, 0.80, 0,
    'Demo existing wall tile, prep surface',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, cost_per_sqft_min, cost_per_sqft_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'wall_tile_replacement',
    'install_ceramic',
    '{"goals_contains": "replace_wall_tile", "tile_level": "basic_ceramic"}'::jsonb,
    10, 16, 0.60, 0,
    'Ceramic wall tile installation per sqft',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, cost_per_sqft_min, cost_per_sqft_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'wall_tile_replacement',
    'install_porcelain',
    '{"goals_contains": "replace_wall_tile", "tile_level": "porcelain"}'::jsonb,
    15, 25, 0.60, 1,
    'Porcelain wall tile installation per sqft',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, cost_per_sqft_min, cost_per_sqft_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'wall_tile_replacement',
    'install_stone',
    '{"goals_contains": "replace_wall_tile", "tile_level": "natural_stone"}'::jsonb,
    25, 45, 0.55, 2,
    'Natural stone wall tile installation per sqft',
    true
);

-- ============================================================================
-- MODULE: floor_tile_replacement
-- ============================================================================

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'floor_tile_replacement',
    'demo_existing',
    '{"goals_contains": "replace_flooring", "flooring_type": "tile"}'::jsonb,
    400, 800, 0.80, 0,
    'Demo existing floor, prep substrate',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, cost_per_sqft_min, cost_per_sqft_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'floor_tile_replacement',
    'install_ceramic',
    '{"goals_contains": "replace_flooring", "flooring_type": "tile", "tile_level": "basic_ceramic"}'::jsonb,
    8, 14, 0.60, 0,
    'Ceramic floor tile per sqft',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, cost_per_sqft_min, cost_per_sqft_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'floor_tile_replacement',
    'install_porcelain',
    '{"goals_contains": "replace_flooring", "flooring_type": "tile", "tile_level": "porcelain"}'::jsonb,
    12, 20, 0.60, 0,
    'Porcelain floor tile per sqft',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, cost_per_sqft_min, cost_per_sqft_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'floor_tile_replacement',
    'install_stone',
    '{"goals_contains": "replace_flooring", "flooring_type": "tile", "tile_level": "natural_stone"}'::jsonb,
    20, 35, 0.55, 1,
    'Natural stone floor tile per sqft',
    true
);

-- Heated floor
INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, cost_per_sqft_min, cost_per_sqft_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'floor_tile_replacement',
    'heated_floor_system',
    '{"extras_contains": "heated_floor"}'::jsonb,
    15, 25, 0.50, 2,
    'Electric radiant heat mat + installation per sqft',
    true
);

-- ============================================================================
-- MODULE: vanity_replacement
-- ============================================================================

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'vanity_replacement',
    'stock_vanity',
    '{"vanity_type": "stock"}'::jsonb,
    600, 1200, 0.30, 0,
    'Stock vanity cabinet from big box store',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'vanity_replacement',
    'semi_custom_vanity',
    '{"vanity_type": "semi_custom"}'::jsonb,
    1500, 3000, 0.35, 1,
    'Semi-custom vanity with some size/finish options',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'vanity_replacement',
    'custom_vanity',
    '{"vanity_type": "custom"}'::jsonb,
    3000, 6000, 0.40, 2,
    'Fully custom vanity built to spec',
    true
);

-- Countertops
INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'vanity_replacement',
    'countertop_laminate',
    '{"countertop_type": "laminate"}'::jsonb,
    200, 400, 0.40, 0,
    'Laminate countertop',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'vanity_replacement',
    'countertop_prefab_quartz',
    '{"countertop_type": "prefab_quartz"}'::jsonb,
    600, 1200, 0.35, 0,
    'Prefab quartz vanity top',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'vanity_replacement',
    'countertop_custom_quartz',
    '{"countertop_type": "custom_quartz"}'::jsonb,
    1200, 2500, 0.35, 1,
    'Custom quartz countertop',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'vanity_replacement',
    'countertop_stone',
    '{"countertop_type": "stone_other"}'::jsonb,
    1500, 3500, 0.35, 1,
    'Natural stone countertop (granite, marble, etc.)',
    true
);

-- Sink + faucet
INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'vanity_replacement',
    'sink_and_faucet',
    '{"goals_contains": "update_fixtures"}'::jsonb,
    300, 800, 0.50, 0,
    'Sink and faucet (mid-range)',
    true
);

-- ============================================================================
-- MODULE: plumbing_moves
-- ============================================================================

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'plumbing_moves',
    'minor_move',
    '{"plumbing_changes": "moving_shower_or_tub"}'::jsonb,
    800, 1500, 0.80, 1,
    'Minor plumbing relocation within same wall',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'plumbing_moves',
    'toilet_move',
    '{"plumbing_changes": "moving_toilet"}'::jsonb,
    1200, 2500, 0.80, 2,
    'Relocating toilet drain (major work)',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'plumbing_moves',
    'multiple_fixtures',
    '{"plumbing_changes": "multiple_fixtures_moved"}'::jsonb,
    2500, 5000, 0.80, 3,
    'Moving multiple fixtures (comprehensive replumb)',
    true
);

-- ============================================================================
-- MODULE: layout_changes
-- ============================================================================

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'layout_changes',
    'non_structural',
    '{"layout_change_level": "non_structural_changes"}'::jsonb,
    1500, 3000, 0.70, 1,
    'Non-structural layout changes (partition walls, openings)',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'layout_changes',
    'structural',
    '{"layout_change_level": "structural_changes"}'::jsonb,
    4000, 8000, 0.70, 3,
    'Structural changes (load-bearing walls, expansion)',
    true
);

-- ============================================================================
-- MODULE: electrical_work
-- ============================================================================

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'electrical_work',
    'basic_fixtures',
    '{"electrical_scope": "fixtures_only"}'::jsonb,
    300, 600, 0.70, 0,
    'Replace existing light fixtures (same locations)',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'electrical_work',
    'add_lighting',
    '{"electrical_scope": "add_lighting"}'::jsonb,
    800, 1500, 0.70, 1,
    'Add new lighting circuits and fixtures',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'electrical_work',
    'add_circuits',
    '{"electrical_scope": "add_circuits"}'::jsonb,
    1000, 2000, 0.80, 1,
    'Add new electrical circuits to panel',
    true
);

-- ============================================================================
-- MODULE: ventilation
-- ============================================================================

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'ventilation',
    'upgrade_fan',
    '{"ventilation_scope": "upgrade_fan"}'::jsonb,
    300, 600, 0.60, 0,
    'Upgrade existing exhaust fan',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'ventilation',
    'add_new_fan',
    '{"ventilation_scope": "add_new_fan"}'::jsonb,
    600, 1200, 0.65, 1,
    'Install new exhaust fan with ductwork',
    true
);

-- ============================================================================
-- MODULE: extras (Shower niche, bench, etc.)
-- ============================================================================

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'extras',
    'shower_niche',
    '{"extras_contains": "shower_niche"}'::jsonb,
    300, 600, 0.70, 0,
    'Built-in shower niche (tiled)',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'extras',
    'shower_bench',
    '{"extras_contains": "shower_bench"}'::jsonb,
    600, 1200, 0.70, 1,
    'Built-in tiled shower bench',
    true
);

INSERT INTO cost_rules (engine, module_key, rule_key, applies_when, base_cost_min, base_cost_max, labor_fraction, complexity_points, notes, active)
VALUES (
    'bathroom',
    'extras',
    'custom_storage',
    '{"extras_contains": "custom_storage_cabinetry"}'::jsonb,
    1200, 3000, 0.50, 1,
    'Custom storage cabinetry beyond vanity',
    true
);

-- ============================================================================
-- NOTES
-- ============================================================================
-- To adjust pricing:
-- 1. Update base_cost_min/max values in this file
-- 2. Re-run: psql -U username -d dbname -f cost_rules_seed.sql
--
-- To add new modules:
-- 1. Add new INSERT statements with a new module_key
-- 2. Update the cost engine to recognize the module activation trigger
--
-- applies_when syntax:
-- - Simple match: {"tile_level": "porcelain"}
-- - Array contains: {"goals_contains": "convert_tub_to_shower"}
-- - Array contains (extras): {"extras_contains": "heated_floor"}
-- ============================================================================
