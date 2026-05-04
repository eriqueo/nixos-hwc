#!/usr/bin/env bash
#
# export_catalog.sh - Export Heartwood cost catalog to JSON for React app
# Run this after updating the SQLite catalog, then rebuild the app.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
CATALOG_DB="${APP_DIR}/../catalog.db"
OUTPUT_FILE="${APP_DIR}/src/data/catalog_export.json"
TEMP_DIR=$(mktemp -d)

mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "Exporting catalog from: $CATALOG_DB"

# Export each table to temp files (matching actual SQLite schema)
sqlite3 "$CATALOG_DB" -json 'SELECT id, canonical_name, description, budget_group_path, cost_code_id, cost_type_id, unit_id, category_id, default_qty, unit_cost, unit_price, labor_wage, labor_burden, waste_factor, production_rate, qty_driver_key, qty_formula, condition_trigger, source FROM cost_items WHERE is_active = 1 ORDER BY budget_group_path, canonical_name' > "$TEMP_DIR/items.json"

sqlite3 "$CATALOG_DB" -json 'SELECT id, code, name, jt_id FROM cost_codes ORDER BY code' > "$TEMP_DIR/cost_codes.json"

sqlite3 "$CATALOG_DB" -json 'SELECT id, name, jt_id FROM cost_types' > "$TEMP_DIR/cost_types.json"

sqlite3 "$CATALOG_DB" -json 'SELECT id, name, abbreviation, jt_id FROM units' > "$TEMP_DIR/units.json"

sqlite3 "$CATALOG_DB" -json 'SELECT key, category, value_type, default_value, options, unit, description, project_type FROM state_keys ORDER BY category, key' > "$TEMP_DIR/state_keys.json"

sqlite3 "$CATALOG_DB" -json 'SELECT id, name FROM categories ORDER BY name' > "$TEMP_DIR/categories.json"

# Combine into single JSON
jq -n \
  --arg timestamp "$(date -Iseconds)" \
  --slurpfile items "$TEMP_DIR/items.json" \
  --slurpfile costCodes "$TEMP_DIR/cost_codes.json" \
  --slurpfile costTypes "$TEMP_DIR/cost_types.json" \
  --slurpfile units "$TEMP_DIR/units.json" \
  --slurpfile stateKeys "$TEMP_DIR/state_keys.json" \
  --slurpfile categories "$TEMP_DIR/categories.json" \
  '{
    exportedAt: $timestamp,
    version: "1.0",
    items: $items[0],
    costCodes: $costCodes[0],
    costTypes: $costTypes[0],
    units: $units[0],
    stateKeys: $stateKeys[0],
    categories: $categories[0]
  }' > "$OUTPUT_FILE"

rm -rf "$TEMP_DIR"

echo "Output: $OUTPUT_FILE"
echo ""
echo "=== Export Summary ==="
jq '{
  exportedAt: .exportedAt,
  items: (.items | length),
  costCodes: (.costCodes | length),
  costTypes: (.costTypes | length),
  units: (.units | length),
  stateKeys: (.stateKeys | length),
  categories: (.categories | length)
}' "$OUTPUT_FILE"

echo ""
echo "To rebuild: cd $APP_DIR && npm run build"
