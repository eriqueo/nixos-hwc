-- Idempotent catalogue repair. Existing rates stay unchanged.
-- Rebuild JSON with ../export_estimator_data.py after applying this migration.
BEGIN;
SET search_path TO public;

UPDATE assembly_rules SET condition_trigger = 'has_shower_work == "yes"'
WHERE id IN (29,35,44,56,61,62,69,81);
UPDATE assembly_rules SET condition_trigger = 'has_shower_work == "yes" AND keep_shower_valve != "yes"'
WHERE id IN (35,44,61,69,81);
UPDATE assembly_rules SET condition_trigger = 'has_shower_work == "yes" AND has_existing_tub != "yes"' WHERE id = 29;
UPDATE assembly_rules SET condition_trigger = 'has_shower_work == "yes" AND has_shower_door != "no"' WHERE id = 56;
UPDATE assembly_rules SET condition_trigger = 'has_shower_tile == "yes" AND shower_niches > 0', waste_factor = 1
WHERE id = 26;
UPDATE assembly_rules SET condition_trigger = 'has_shower_tile == "yes" AND shower_niches > 0'
WHERE id IN (87,132);
UPDATE assembly_rules SET condition_trigger = 'has_shower_tile == "yes" OR has_floor_tile == "yes"'
WHERE id IN (7,46,49,65);
UPDATE assembly_rules SET condition_trigger = '(new_tub == "yes" AND demo_scope == "full_gut") OR has_existing_tub == "yes"'
WHERE id = 68;

-- A supplier flag controls purchases only. Scope still controls installation.
UPDATE assembly_rules SET condition_trigger = 'has_toilet == "yes" AND include_toilet_material != "no"' WHERE id = 6;
UPDATE assembly_rules SET condition_trigger = 'has_vanity == "yes" AND include_vanity_material != "no"' WHERE id IN (8,55);
UPDATE assembly_rules SET condition_trigger = 'new_tub == "yes" AND include_tub_material != "no"' WHERE id = 33;
UPDATE assembly_rules SET condition_trigger = 'has_shower_work == "yes" AND include_shower_trim_material != "no"' WHERE id = 42;
UPDATE assembly_rules SET condition_trigger = 'include_accessory_material != "no"' WHERE id = 15;
UPDATE assembly_rules SET condition_trigger = 'new_electrical == "yes" AND include_electrical_material != "no"' WHERE id IN (28,154);
UPDATE assembly_rules SET condition_trigger = 'has_floor_tile == "yes" AND include_floor_material != "no"' WHERE id = 52;
UPDATE assembly_rules SET condition_trigger = 'has_shower_tile == "yes" AND include_shower_material != "no"' WHERE id = 54;

WITH additions(item_type,trade,subject,display_name,code,cost_type,unit,group_path,condition,formula,sort_order) AS (VALUES
 ('Labor','Finish Carpentry','Install Panel Shower','Labor | Finish Carpentry | Install Panel Shower','2100','Labor','Hours','Finish Carpentry > Panel Shower','shower_finish == "panel"','{panel_install_hours}',525),
 ('Labor','Plumbing','Panel Shower Drain Hookup','Labor | Plumbing | Panel Shower Drain Hookup','1100','Labor','Hours','Plumbing > Panel Shower','shower_finish == "panel"','{panel_drain_hours}',526),
 ('Allowance','Plumbing','Panel Shower Kit','Allowance | Panel Shower Kit','1100','Materials','Lump Sum','Allowances > Panel Shower','shower_finish == "panel" AND include_shower_material != "no"',NULL,905),
 ('Labor','Flooring','Install Vinyl or Marmoleum','Labor | Flooring | Install Vinyl or Marmoleum','1700','Labor','Hours','Flooring > Labor','floor_finish == "vinyl" OR floor_finish == "marmoleum"','{floor_install_hours}',530),
 ('Labor','Flooring','Prepare Subfloor','Labor | Flooring | Prepare Subfloor','1700','Labor','Hours','Flooring > Labor','(floor_finish == "vinyl" OR floor_finish == "marmoleum") AND floor_prep_hours > 0','{floor_prep_hours}',529),
 ('Allowance','Flooring','Floor Covering','Allowance | Floor Covering','1700','Materials','Lump Sum','Allowances > Flooring','(floor_finish == "vinyl" OR floor_finish == "marmoleum") AND include_floor_material != "no"',NULL,906),
 ('Allowance','Finish Carpentry','Shower Door','Allowance | Shower Door','2100','Materials','Lump Sum','Allowances > Shower Door','has_shower_work == "yes" AND has_shower_door == "yes" AND include_shower_door_material != "no"',NULL,907)
), inserted AS (
 INSERT INTO catalog_items(item_type,trade,subject,spec,display_name,jt_cost_code_id,jt_cost_type_id,jt_unit_id,budget_group_path,unit_cost,unit_price,description)
 SELECT a.item_type,a.trade,a.subject,'',a.display_name,c.id,t.id,u.id,a.group_path,0,0,
 'Site-verified hours or total supplier quote required; no assumed production rate.'
 FROM additions a JOIN jt_cost_codes c ON c.code=a.code JOIN jt_cost_types t ON t.name=a.cost_type JOIN jt_units u ON u.name=a.unit
 ON CONFLICT (item_type,trade,subject,spec) DO UPDATE SET display_name=EXCLUDED.display_name
 RETURNING id,item_type,trade,subject
)
INSERT INTO assembly_rules(catalog_item_id,project_type,budget_group_path,condition_trigger,qty_formula,default_qty,waste_factor,sort_order,description)
SELECT i.id,'bathroom',a.group_path,a.condition,a.formula,1,1,a.sort_order,
 'Site-verified input; include installation even when customer supplies material.'
FROM inserted i JOIN additions a USING(item_type,trade,subject)
WHERE NOT EXISTS (SELECT 1 FROM assembly_rules r WHERE r.catalog_item_id=i.id AND r.project_type='bathroom');
COMMIT;
