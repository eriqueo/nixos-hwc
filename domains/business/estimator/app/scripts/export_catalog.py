#!/usr/bin/env python3
"""
export_catalog.py — Export heartwood_catalog.db → src/data/*.json

Run from project root:
    python3 scripts/export_catalog.py
    # or:
    npm run export-catalog

Writes:
    src/data/catalog.json      — all active cost items
    src/data/tradeRates.json   — per-trade wage/burden/markup
    src/data/stateKeys.json    — project state key definitions
    src/data/jtMappings.json   — JobTread IDs for codes, types, units
"""

import json
import sqlite3
import sys
from pathlib import Path

ROOT   = Path(__file__).parent.parent
DB     = ROOT.parent / 'heartwood_catalog.db'
OUT    = ROOT / 'src' / 'data'

# ── JT type IDs (sourced from JobTread org — update if they change) ───────────
COST_TYPE_JT_IDS = {
    'Admin':         '22PJuNqewZmV',
    'Labor':         '22Nm3uGRAMmq',
    'Materials':     '22Nm3uGRAMmr',
    'Other':         '22Nm3uGRAMmt',
    'Selections':    '22PQ4KZExZjP',
    'Subcontractor': '22Nm3uGRAMms',
}


def export_jt_mappings(db: sqlite3.Connection) -> dict:
    codes = {r['code']: r['jt_id']
             for r in db.execute('SELECT code, jt_id FROM cost_codes WHERE jt_id IS NOT NULL')}
    types = COST_TYPE_JT_IDS
    units = {r['name']: r['jt_id']
             for r in db.execute('SELECT name, jt_id FROM units WHERE jt_id IS NOT NULL')}
    return {'codes': codes, 'types': types, 'units': units}


def export_trade_rates(db: sqlite3.Connection) -> dict:
    """
    Trade rates stored in DB (if present) or hardcoded defaults.
    Add a `trade_rates` table to the DB to override these.
    """
    defaults = {
        'planning':      {'wage': 35, 'burden': 1.35, 'markup': 1.43},
        'demo':          {'wage': 35, 'burden': 1.35, 'markup': 2.00},
        'framing':       {'wage': 38, 'burden': 1.35, 'markup': 1.85},
        'plumbing':      {'wage': 42, 'burden': 1.35, 'markup': 1.75},
        'electrical':    {'wage': 45, 'burden': 1.35, 'markup': 1.75},
        'tiling':        {'wage': 45, 'burden': 1.35, 'markup': 2.00},
        'drywall':       {'wage': 35, 'burden': 1.35, 'markup': 2.00},
        'painting':      {'wage': 35, 'burden': 1.35, 'markup': 2.00},
        'cabinetry':     {'wage': 38, 'burden': 1.35, 'markup': 1.85},
        'waterproofing': {'wage': 42, 'burden': 1.35, 'markup': 1.75},
    }
    # Check if DB has a trade_rates table to override defaults
    tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    if 'trade_rates' in tables:
        for r in db.execute('SELECT trade, wage, burden, markup FROM trade_rates'):
            defaults[r['trade']] = {'wage': r['wage'], 'burden': r['burden'], 'markup': r['markup']}
    return defaults


def export_state_keys(db: sqlite3.Connection) -> list:
    rows = db.execute('SELECT * FROM state_keys ORDER BY id').fetchall()
    return [
        {
            'key':         r['key'],
            'category':    r['category'],
            'valueType':   r['value_type'],
            'default':     r['default_value'],
            'options':     json.loads(r['options']) if r['options'] else None,
            'unit':        r['unit'],
            'description': r['description'],
            'drives':      r['drives'],
            'required':    bool(r['required']),
            'projectType': r['project_type'],
        }
        for r in rows
    ]


def export_catalog(db: sqlite3.Connection) -> list:
    rows = db.execute('''
        SELECT
            ci.*,
            cc.code  AS code_str,
            ct.name  AS type_name,
            u.name   AS unit_name,
            u.abbreviation AS unit_abbr
        FROM cost_items ci
        LEFT JOIN cost_codes cc ON ci.cost_code_id = cc.id
        LEFT JOIN cost_types  ct ON ci.cost_type_id = ct.id
        LEFT JOIN units        u  ON ci.unit_id      = u.id
        WHERE ci.is_active = 1
        ORDER BY ci.id
    ''').fetchall()

    return [
        {
            'id':              r['id'],
            'name':            r['canonical_name'],
            'group':           r['budget_group_path'],
            'code':            r['code_str'],
            'type':            r['type_name'],
            'unit':            r['unit_name'],
            'unitAbbr':        r['unit_abbr'],
            'defaultQty':      r['default_qty'],
            'unitCost':        r['unit_cost'],
            'unitPrice':       r['unit_price'],
            'laborWage':       r['labor_wage'],
            'laborBurden':     r['labor_burden'],
            'wasteFactor':     r['waste_factor'],
            'productionRate':  r['production_rate'],
            'qtyDriverKey':    r['qty_driver_key'],
            'qtyFormula':      r['qty_formula'],
            'conditionTrigger':r['condition_trigger'],
            'notes':           r['notes'],
        }
        for r in rows
    ]


def write(path: Path, data) -> None:
    path.write_text(json.dumps(data, indent=2))
    print(f'  ✓ {path.relative_to(ROOT)}')


def main():
    if not DB.exists():
        print(f'ERROR: database not found at {DB}', file=sys.stderr)
        print('Expected location: heartwood_catalog.db (sibling of heartwood-assembler/)', file=sys.stderr)
        sys.exit(1)

    OUT.mkdir(parents=True, exist_ok=True)

    db = sqlite3.connect(DB)
    db.row_factory = sqlite3.Row

    print(f'Exporting from {DB.name}...')
    write(OUT / 'jtMappings.json',  export_jt_mappings(db))
    write(OUT / 'tradeRates.json',  export_trade_rates(db))
    write(OUT / 'stateKeys.json',   export_state_keys(db))
    write(OUT / 'catalog.json',     export_catalog(db))
    print('Done.')
    db.close()


if __name__ == '__main__':
    main()
