#!/usr/bin/env python3
"""Populate assembly logic on catalog_items from assembler.js add() calls.

For items already in catalog: UPDATE assembly fields.
For items NOT in catalog: INSERT with assembly logic + pricing from trade_rates.

Also transfers Craftsman production rates where they differ from assembler hardcodes.

Usage: sudo python3 populate_assembly_logic.py
"""
import subprocess
import json
import sys

DB = "hwc"

# ─── Craftsman production rates (from deactivated rows) ─────────────────────
# These override assembler hardcodes where they exist
CRAFTSMAN_RATES = {
    "Labor | Demo | Floor Tile": 0.08,
    "Labor | Demo | Shower Surround": 0.06,
    "Labor | Drywall | Remove and Replace": 0.05,
    "Labor | Tile | Floor Installation": 0.28,
    "Labor | Tile | Shower Installation": 0.33,
    "Labor | Waterproofing | Membrane Application": 0.15,
    "Labor | Framing | General": 0.05,
    "Labor | Painting | Prime and Finish": 0.02,
    "Labor | Finish Carpentry | Trim and Baseboard": 0.15,
}

# ─── JT reference ID lookups ────────────────────────────────────────────────
# Cost code display_name → JT ID (from jt_cost_codes table)
COST_CODE_MAP = {
    "0100": "22Nm3uGRAMmH",  # Planning
    "0110": "22NxeGLaJCQT",  # Site Preparation
    "0200": "22Nm3uGRAMmJ",  # Demolition
    "0600": "22Nm3uGRAMmN",  # Framing
    "0800": "22Nm3uGRAMmQ",  # Siding
    "1000": "22Nm3uGRAMmS",  # Electrical
    "1100": "22Nm3uGRAMmT",  # Plumbing
    "1400": "22Nm3uGRAMmW",  # Drywall
    "1500": "22Nm3uGRAMmX",  # Doors & Windows
    "1700": "22Nm3uGRAMmZ",  # Flooring
    "1800": "22Nm3uGRAMma",  # Tiling
    "1900": "22Nm3uGRAMmb",  # Cabinetry
    "2000": "22Nm3uGRAMmc",  # Countertops
    "2100": "22Nm3uGRAMmd",  # Trimwork
    "2200": "22Nm3uGRAMme",  # Specialty Finishes
    "2300": "22Nm3uGRAMmf",  # Painting
    "2400": "22Nm3uGRAMmg",  # Appliances
    "2500": "22Nm3uGRAMmh",  # Decking
    "2800": "22Nm3uGRAMmk",  # Concrete
    "3000": "22Nm3uGRAMmn",  # Furnishings
    "3100": "22Nm3uGRAMmp",  # Miscellaneous
}

COST_TYPE_MAP = {
    "Labor": "22Nm3uGRAMmq",
    "Materials": "22Nm3uGRAMmr",
    "Other": "22Nm3uGRAMmt",
    "Selections": "22PQ4KZExZjP",
}

UNIT_MAP = {
    "Hours": "22Nm3uGRAMm9",
    "Each": "22Nm3uGRAMm7",
    "Lump Sum": "22Nm3uGRAMmB",
    "Square Feet": "22Nm3uGRAMmD",
    "Linear Feet": "22Nm3uGRAMmA",
    "Gallons": "22Nm3uGRAMm8",
}


def psql(sql: str) -> str:
    cmd = ["sudo", "-u", "postgres", "psql", "-d", DB, "-t", "-A", "-c", sql]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"SQL ERROR: {r.stderr.strip()}", file=sys.stderr)
    return r.stdout.strip()


def escape(val):
    if val is None:
        return "NULL"
    s = str(val).replace("'", "''")
    return f"'{s}'"


# ─── All assembler add() items ──────────────────────────────────────────────
# Extracted from assembler.js buildCatalog() + buildDeckCatalog()
#
# Format: (name, group, code, cost_type, unit, default_qty_expr,
#          material_cost, trade_key, condition_trigger, qty_formula,
#          qty_driver, production_rate, sort_order, project_type)
#
# For Labor items: material_cost=0 (pricing from trade_rates)
# For Material items: material_cost = unit cost

ITEMS = [
    # ══════════════════════════════════════════════════════════════════════
    # BATHROOM ASSEMBLER — buildCatalog() lines 108-353
    # ══════════════════════════════════════════════════════════════════════

    # ── PRECONSTRUCTION ──────────────────────────────────────────────────
    ("Admin | Planning | Site Walkthrough", "Preconstruction", "0100", "Labor", "Hours",
     2, 0, "planning", "always", None, None, None, 100, "bathroom"),

    ("Labor | Admin | Project Management", "Preconstruction", "0100", "Labor", "Hours",
     4, 0, "planning", "always", None, None, None, 101, "bathroom"),

    ("Other | Admin | Building Permit", "Preconstruction", "0100", "Other", "Each",
     1, 350, None,
     'demo_scope == "full_gut" OR new_tub == "yes"',
     None, None, None, 102, "bathroom"),

    # ── DEMO ─────────────────────────────────────────────────────────────
    ("Labor | Demo | Install Floor Protection", "Demo > Labor", "0200", "Labor", "Hours",
     3, 0, "demo", "always", None, None, None, 200, "bathroom"),

    ("Labor | Demo | Floor Tile", "Demo > Labor", "0200", "Labor", "Hours",
     None, 0, "demo",
     'demo_scope == "shower_and_floors" OR demo_scope == "full_gut"',
     "ceil(0.08 * bathroom_floor_sqft)", "bathroom_floor_sqft", 0.08, 201, "bathroom"),

    ("Labor | Demo | Shower Surround", "Demo > Labor", "0200", "Labor", "Hours",
     4, 0, "demo", 'has_shower_tile == "yes"', None, None, None, 202, "bathroom"),

    ("Labor | Demo | Bathtub Surround", "Demo > Labor", "0200", "Labor", "Hours",
     6, 0, "demo", 'new_tub == "yes" AND demo_scope == "full_gut"',
     None, None, None, 203, "bathroom"),

    ("Material | Protection | Floor Protection Roll", "Demo > Materials", "0100", "Materials", "Each",
     1, 35, None, "always", None, None, None, 210, "bathroom"),

    ("Material | Protection | Sheeting Tape", "Demo > Materials", "0100", "Materials", "Each",
     2, 13, None, "always", None, None, None, 211, "bathroom"),

    ("Material | Protection | Dust Control Sheeting", "Demo > Materials", "0100", "Materials", "Each",
     1, 20, None, "always", None, None, None, 212, "bathroom"),

    ("Material | Protection | Trash Bags", "Demo > Materials", "0100", "Materials", "Each",
     None, 27, None, "always",
     "if(bathroom_floor_sqft > 80, 2, 1)", "bathroom_floor_sqft", None, 213, "bathroom"),

    ("Material | Demo | Dump Trailer", "Demo > Materials", "0200", "Other", "Each",
     1, 200, None,
     'demo_scope == "shower_and_floors" OR demo_scope == "full_gut"',
     None, None, None, 214, "bathroom"),

    # ── CLOSE-OUT ────────────────────────────────────────────────────────
    ("Labor | Admin | Final Cleanup", "Close-Out", "0100", "Labor", "Hours",
     3, 0, "planning", "always", None, None, None, 1100, "bathroom"),

    # ── FRAMING ──────────────────────────────────────────────────────────
    ("Labor | Framing | General", "Rough Carpentry > Labor", "0600", "Labor", "Hours",
     4, 0, "framing", "always", None, None, 0.05, 300, "bathroom"),

    ("Labor | Framing | Niche Blocking", "Rough Carpentry > Labor", "0600", "Labor", "Hours",
     None, 0, "framing", "shower_niches > 0",
     "shower_niches * 2", "shower_niches", None, 301, "bathroom"),

    ("Labor | Framing | Install Tub", "Rough Carpentry > Labor", "0600", "Labor", "Hours",
     5, 0, "framing", 'new_tub == "yes"', None, None, None, 302, "bathroom"),

    ("Material | Framing | Screws 3\" Exterior 5lb", "Rough Carpentry > Materials", "3100", "Materials", "Each",
     1, 32.98, None, "always", None, None, None, 310, "bathroom"),

    ("Material | Framing | 2x4x8 KD SPF", "Rough Carpentry > Materials", "0600", "Materials", "Each",
     None, 13, None, "always",
     "max(2, ceil(bathroom_perimeter_lf / 8))", "bathroom_perimeter_lf", None, 311, "bathroom"),

    ("Material | Framing | Plywood 3/4\" ACX", "Rough Carpentry > Materials", "0600", "Materials", "Each",
     1, 95, None, "always", None, None, None, 312, "bathroom"),

    # ── PLUMBING ─────────────────────────────────────────────────────────
    ("Labor | Plumbing | Install Mixer Valve", "Plumbing > Labor", "1100", "Labor", "Hours",
     4, 0, "plumbing", 'has_shower_tile == "yes"', None, None, None, 400, "bathroom"),

    ("Labor | Plumbing | Install Shower Trim", "Plumbing > Labor", "1100", "Labor", "Hours",
     2, 0, "plumbing", 'has_shower_tile == "yes"', None, None, None, 401, "bathroom"),

    ("Labor | Plumbing | Run Showerhead Copper", "Plumbing > Labor", "1100", "Labor", "Hours",
     4, 0, "plumbing", 'has_shower_tile == "yes"', None, None, None, 402, "bathroom"),

    ("Material | Plumbing | Posi-Temp Rough-In Valve", "Plumbing > Materials", "1100", "Materials", "Each",
     1, 135, None, 'has_shower_tile == "yes"', None, None, None, 410, "bathroom"),

    ("Material | Plumbing | 1/2\" Copper Pipe", "Plumbing > Materials", "1100", "Materials", "Each",
     2, 8, None, 'has_shower_tile == "yes"', None, None, None, 411, "bathroom"),

    ("Material | Plumbing | Copper Fittings", "Plumbing > Materials", "1100", "Materials", "Lump Sum",
     1, 50, None, 'has_shower_tile == "yes"', None, None, None, 412, "bathroom"),

    ("Labor | Plumbing | Tub Drain Hookup", "Plumbing > Labor", "1100", "Labor", "Hours",
     4, 0, "plumbing", 'new_tub == "yes"', None, None, None, 403, "bathroom"),

    ("Labor | Plumbing | Install Toilet", "Plumbing > Labor", "1100", "Labor", "Hours",
     2, 0, "plumbing", "always", None, None, None, 404, "bathroom"),

    ("Material | Plumbing | PVC Fittings", "Plumbing > Materials", "1100", "Materials", "Each",
     6, 3, None, "always", None, None, None, 413, "bathroom"),

    ("Labor | Plumbing | Vanity Sink Hookup", "Plumbing > Labor", "1100", "Labor", "Hours",
     3, 0, "plumbing", 'has_vanity == "yes"', None, None, None, 405, "bathroom"),

    ("Material | Plumbing | Vanity Faucet Assembly", "Plumbing > Materials", "1100", "Materials", "Each",
     1, 85, None, 'has_vanity == "yes"', None, None, None, 414, "bathroom"),

    ("Material | Plumbing | Toilet Supply Line", "Plumbing > Materials", "1100", "Materials", "Each",
     1, 25, None, "always", None, None, None, 415, "bathroom"),

    # ── ELECTRICAL ───────────────────────────────────────────────────────
    ("Labor | Electrical | General", "Electrical > Labor", "1000", "Labor", "Hours",
     4, 0, "electrical", 'new_electrical == "yes"', None, None, None, 450, "bathroom"),

    ("Material | Electrical | GFCI Outlet", "Electrical > Materials", "1000", "Materials", "Each",
     1, 25, None, 'new_electrical == "yes"', None, None, None, 460, "bathroom"),

    ("Labor | Electrical | Exhaust Fan", "Electrical > Labor", "1000", "Labor", "Hours",
     3, 0, "electrical", 'new_fan == "yes"', None, None, None, 451, "bathroom"),

    # ── WATERPROOFING ────────────────────────────────────────────────────
    ("Labor | Waterproofing | Membrane Application", "Waterproofing > Labor", "1800", "Labor", "Hours",
     None, 0, "waterproofing", 'has_shower_tile == "yes"',
     "max(6, ceil((shower_wall_tile_sqft + bathroom_floor_sqft * 0.3) * 0.15))",
     "shower_wall_tile_sqft", 0.15, 500, "bathroom"),

    # ── TILEWORK ─────────────────────────────────────────────────────────
    ("Labor | Tile | Floor Installation", "Tilework > Floor Tile Labor", "1800", "Labor", "Hours",
     None, 0, "tiling", 'has_floor_tile == "yes"',
     "max(8, ceil(bathroom_floor_sqft * 0.28))", "bathroom_floor_sqft", 0.28, 550, "bathroom"),

    ("Labor | Tile | Shower Installation", "Tilework > Shower Tile Labor", "1800", "Labor", "Hours",
     None, 0, "tiling", 'has_shower_tile == "yes"',
     "max(12, ceil(shower_wall_tile_sqft * 0.33))", "shower_wall_tile_sqft", 0.33, 551, "bathroom"),

    ("Labor | Tile | Shower Pan", "Tilework > Shower Tile Labor", "1800", "Labor", "Hours",
     None, 0, "tiling", 'has_shower_tile == "yes"',
     "max(4, ceil(shower_pan_tile_sqft * 0.25))", "shower_pan_tile_sqft", 0.25, 552, "bathroom"),

    ("Labor | Tile | Shower Curb", "Tilework > Shower Tile Labor", "1800", "Labor", "Hours",
     None, 0, "tiling", 'has_shower_tile == "yes"',
     "max(2, ceil(shower_curb_tile_sqft * 0.3))", "shower_curb_tile_sqft", 0.30, 553, "bathroom"),

    ("Labor | Tile | Niche Installation", "Tilework > Shower Tile Labor", "1800", "Labor", "Hours",
     None, 0, "tiling", "shower_niches > 0",
     "shower_niches * 4", "shower_niches", None, 554, "bathroom"),

    ("Labor | Tile | Accent Band Installation", "Tilework > Accent Tile Labor", "1800", "Labor", "Hours",
     None, 0, "tiling", 'has_accent_tile == "yes" AND has_shower_tile == "yes"',
     "max(4, ceil(shower_accent_tile_sqft * 0.25))", "shower_accent_tile_sqft", 0.25, 560, "bathroom"),

    # Tile materials
    ("Material | Tile | Waterproof Backer Board 1/2\" 4x8", "Tilework > Materials", "1800", "Materials", "Each",
     None, 98.99, None, 'has_shower_tile == "yes"',
     "max(2, ceil(shower_wall_tile_sqft / 32))", "shower_wall_tile_sqft", None, 570, "bathroom"),

    ("Material | Tile | Schluter Banding 16'", "Tilework > Materials", "1800", "Materials", "Each",
     None, 20.75, None, "always",
     "max(1, ceil(bathroom_perimeter_lf / 16))", "bathroom_perimeter_lf", None, 571, "bathroom"),

    ("Material | Tile | Permacolor Grout", "Tilework > Materials", "1800", "Materials", "Each",
     1, 95, None, "always", None, None, None, 572, "bathroom"),

    ("Material | Tile | Schluter 1/4\" Aluminum Trim", "Tilework > Materials", "1800", "Materials", "Each",
     None, 24, None, "always",
     "max(2, ceil(bathroom_perimeter_lf / 8))", "bathroom_perimeter_lf", None, 573, "bathroom"),

    ("Material | Tile | Thinset Mortar 50#", "Tilework > Materials", "1800", "Materials", "Each",
     None, 28.5, None, "always",
     "max(2, ceil((bathroom_floor_sqft + shower_wall_tile_sqft) / 80))", "bathroom_floor_sqft", None, 574, "bathroom"),

    ("Material | Tile | Silicone Sealant", "Tilework > Materials", "1800", "Materials", "Each",
     None, 22, None, "always",
     "max(2, ceil(bathroom_perimeter_lf / 12))", "bathroom_perimeter_lf", None, 575, "bathroom"),

    ("Material | Tile | Grout Sealer", "Tilework > Materials", "1800", "Materials", "Each",
     1, 20, None, "always", None, None, None, 576, "bathroom"),

    # ── DRYWALL ──────────────────────────────────────────────────────────
    ("Labor | Drywall | Remove and Replace", "Drywall > Labor", "1400", "Labor", "Hours",
     None, 0, "drywall", "bathroom_wall_repair_sqft > 0",
     "max(2, ceil(bathroom_wall_repair_sqft * 0.05))", "bathroom_wall_repair_sqft", 0.05, 700, "bathroom"),

    ("Material | Drywall | Drywall 1/2\" 4x8", "Drywall > Materials", "1400", "Materials", "Each",
     None, 20.48, None, "bathroom_wall_repair_sqft > 0",
     "max(1, floor(ceil(bathroom_wall_repair_sqft / 32) * 0.6))", "bathroom_wall_repair_sqft", None, 710, "bathroom"),

    ("Material | Drywall | Mold Resistant 1/2\" 4x8", "Drywall > Materials", "1400", "Materials", "Each",
     None, 19.2, None, "bathroom_wall_repair_sqft > 0",
     "max(1, ceil(ceil(bathroom_wall_repair_sqft / 32) * 0.4))", "bathroom_wall_repair_sqft", None, 711, "bathroom"),

    ("Material | Drywall | Mud 4.5 gal", "Drywall > Materials", "1400", "Materials", "Each",
     1, 15.48, None, "bathroom_wall_repair_sqft > 0", None, None, None, 712, "bathroom"),

    ("Material | Drywall | Tape Mesh 500ft", "Drywall > Materials", "1400", "Materials", "Each",
     1, 11.98, None, "bathroom_wall_repair_sqft > 0", None, None, None, 713, "bathroom"),

    ("Material | Drywall | Screws 1-5/8\" 1lb", "Drywall > Materials", "1400", "Materials", "Each",
     1, 7.98, None, "bathroom_wall_repair_sqft > 0", None, None, None, 714, "bathroom"),

    # ── PAINTING ─────────────────────────────────────────────────────────
    ("Labor | Painting | Prep", "Painting > Labor", "2300", "Labor", "Hours",
     None, 0, "painting", 'has_paint == "yes"',
     "max(4, ceil(bathroom_wall_paint_sqft / 40 * 0.30))", "bathroom_wall_paint_sqft", None, 750, "bathroom"),

    ("Labor | Painting | Caulking", "Painting > Labor", "2300", "Labor", "Hours",
     None, 0, "painting", 'has_paint == "yes"',
     "max(2, ceil(bathroom_wall_paint_sqft / 40 * 0.15))", "bathroom_wall_paint_sqft", None, 751, "bathroom"),

    ("Labor | Painting | Prime Coat", "Painting > Labor", "2300", "Labor", "Hours",
     None, 0, "painting", 'has_paint == "yes"',
     "max(3, ceil(bathroom_wall_paint_sqft / 40 * 0.25))", "bathroom_wall_paint_sqft", None, 752, "bathroom"),

    ("Labor | Painting | Finish Coats", "Painting > Labor", "2300", "Labor", "Hours",
     None, 0, "painting", 'has_paint == "yes"',
     "max(4, ceil(bathroom_wall_paint_sqft / 40 * 0.50))", "bathroom_wall_paint_sqft", None, 753, "bathroom"),

    ("Material | Painting | BIN Shellac Primer", "Painting > Materials", "2300", "Materials", "Gallons",
     None, 75, None, 'has_paint == "yes"',
     "ceil(bathroom_wall_paint_sqft / 350)", "bathroom_wall_paint_sqft", None, 760, "bathroom"),

    ("Material | Painting | SW Emerald Urethane Semi Gloss", "Painting > Materials", "2300", "Materials", "Each",
     None, 110, None, 'has_paint == "yes"',
     "ceil(bathroom_wall_paint_sqft / 350)", "bathroom_wall_paint_sqft", None, 761, "bathroom"),

    ("Material | Painting | Painters Tape Blue", "Painting > Materials", "2300", "Materials", "Each",
     None, 6.98, None, 'has_paint == "yes"',
     "max(2, ceil(bathroom_perimeter_lf / 12))", "bathroom_perimeter_lf", None, 762, "bathroom"),

    ("Material | Painting | Caulking", "Painting > Materials", "2300", "Materials", "Each",
     None, 11.19, None, 'has_paint == "yes"',
     "max(2, ceil(bathroom_perimeter_lf / 12))", "bathroom_perimeter_lf", None, 763, "bathroom"),

    # ── FINISH CARPENTRY ─────────────────────────────────────────────────
    ("Labor | Finish Carpentry | Install Vanity", "Finish Carpentry > Labor", "1900", "Labor", "Hours",
     4, 0, "cabinetry", 'has_vanity == "yes"', None, None, None, 850, "bathroom"),

    ("Labor | Finish Carpentry | General", "Finish Carpentry > Labor", "1900", "Labor", "Hours",
     8, 0, "cabinetry", "always", None, None, None, 851, "bathroom"),

    ("Labor | Finish Carpentry | Mirror Install", "Finish Carpentry > Labor", "1900", "Labor", "Hours",
     2, 0, "cabinetry", 'has_mirror == "yes"', None, None, None, 852, "bathroom"),

    ("Labor | Finish Carpentry | Shower Door Install", "Finish Carpentry > Labor", "1900", "Labor", "Hours",
     3, 0, "cabinetry", 'has_shower_tile == "yes"', None, None, None, 853, "bathroom"),

    ("Labor | Finish Carpentry | Accessories Install", "Finish Carpentry > Labor", "1900", "Labor", "Hours",
     4, 0, "cabinetry", "always", None, None, None, 854, "bathroom"),

    # ── ALLOWANCES ───────────────────────────────────────────────────────
    ("Allowance | Bathtub", "Allowances", "2400", "Materials", "Lump Sum",
     1, None, None, 'new_tub == "yes"', None, None, None, 950, "bathroom"),

    ("Allowance | Shower Trim", "Allowances", "1100", "Materials", "Lump Sum",
     1, None, None, 'has_shower_tile == "yes"', None, None, None, 951, "bathroom"),

    ("Allowance | Shower Tile", "Allowances > Tile", "1800", "Materials", "Lump Sum",
     1, None, None, 'has_shower_tile == "yes"',
     "max(800, round(shower_wall_tile_sqft * 12))", "shower_wall_tile_sqft", None, 952, "bathroom"),

    ("Allowance | Floor Tile", "Allowances > Tile", "1800", "Materials", "Lump Sum",
     1, None, None, 'has_floor_tile == "yes"',
     "max(400, round(bathroom_floor_sqft * 10))", "bathroom_floor_sqft", None, 953, "bathroom"),

    ("Allowance | Toilet", "Allowances", "2400", "Materials", "Lump Sum",
     1, None, None, "always", None, None, None, 954, "bathroom"),

    ("Allowance | Vanity", "Allowances", "3000", "Materials", "Lump Sum",
     1, None, None, 'has_vanity == "yes"', None, None, None, 955, "bathroom"),

    ("Allowance | Bathroom Accessories", "Allowances", "3000", "Materials", "Lump Sum",
     1, None, None, "always", None, None, None, 956, "bathroom"),

    ("Allowance | Electrical", "Allowances", "1000", "Materials", "Lump Sum",
     1, 800, None, 'new_electrical == "yes"', None, None, None, 957, "bathroom"),

    # ══════════════════════════════════════════════════════════════════════
    # DECK ASSEMBLER — buildDeckCatalog() lines 402-565
    # ══════════════════════════════════════════════════════════════════════

    # ── PRECONSTRUCTION ──────────────────────────────────────────────────
    ("Labor | Admin | Site Walkthrough", "Preconstruction", "0100", "Labor", "Hours",
     2, 0, "planning", "always", None, None, None, 100, "deck"),

    # Note: "Labor | Admin | Project Management" reuses bathroom entry (sort 101)
    # Note: "Other | Admin | Building Permit" reuses bathroom entry (sort 102)

    ("Material | Admin | Jobsite Mobilization", "Preconstruction", "0100", "Materials", "Lump Sum",
     1, 330, None, "always", None, None, None, 103, "deck"),

    # ── SITEWORK ─────────────────────────────────────────────────────────
    ("Labor | Sitework | Cleanup", "Sitework > Labor", "0110", "Labor", "Hours",
     None, 0, "demo", "always",
     "max(4, ceil(deck_sqft * 0.04))", "deck_sqft", 0.04, 110, "deck"),

    ("Material | Sitework | Trash Bags", "Sitework > Materials", "0100", "Materials", "Each",
     2, 27, None, "always", None, None, None, 111, "deck"),

    ("Material | Sitework | Dump Trailer", "Sitework > Materials", "0200", "Other", "Each",
     1, 200, None, "always", None, None, None, 112, "deck"),

    # ── DEMO ─────────────────────────────────────────────────────────────
    ("Labor | Demo | Deck Removal", "Demolition > Labor", "0200", "Labor", "Hours",
     None, 0, "demo",
     'project_scope == "full_rebuild"',
     "max(4, ceil(deck_sqft * 0.06))", "deck_sqft", 0.06, 200, "deck"),

    ("Labor | Demo | Move Furnishings", "Demolition > Labor", "0200", "Labor", "Hours",
     2, 0, "demo", 'project_scope == "full_rebuild"', None, None, None, 201, "deck"),

    # ── FOOTINGS ─────────────────────────────────────────────────────────
    ("Labor | Concrete | Pour Footings", "Footings > Labor", "2800", "Labor", "Hours",
     None, 0, "framing",
     'project_scope == "new_build" OR project_scope == "full_rebuild"',
     "deck_footing_count * 1.5", "deck_footing_count", None, 280, "deck"),

    ("Material | Concrete | Sonotubes 12\"x4'", "Footings > Materials", "2800", "Materials", "Each",
     None, 17.47, None,
     'project_scope == "new_build" OR project_scope == "full_rebuild"',
     "deck_footing_count", "deck_footing_count", None, 281, "deck"),

    ("Material | Concrete | Concrete Mix 80lb", "Footings > Materials", "2800", "Materials", "Each",
     None, 4.38, None,
     'project_scope == "new_build" OR project_scope == "full_rebuild"',
     "deck_footing_count * 3", "deck_footing_count", None, 282, "deck"),

    ("Material | Concrete | Post Bases", "Footings > Materials", "2800", "Materials", "Each",
     None, 54, None,
     'project_scope == "new_build" OR project_scope == "full_rebuild"',
     "deck_footing_count", "deck_footing_count", None, 283, "deck"),

    ("Material | Concrete | Anchor Bolts", "Footings > Materials", "2800", "Materials", "Each",
     None, 2, None,
     'project_scope == "new_build" OR project_scope == "full_rebuild"',
     "deck_footing_count", "deck_footing_count", None, 284, "deck"),

    # ── FRAMING ──────────────────────────────────────────────────────────
    ("Labor | Framing | Deck Frame", "Framing > Labor", "0600", "Labor", "Hours",
     None, 0, "framing",
     'project_scope == "new_build" OR project_scope == "full_rebuild"',
     "max(8, ceil(deck_sqft * 0.27))", "deck_sqft", 0.27, 300, "deck"),

    ("Labor | Framing | Temporary Bracing", "Framing > Labor", "0600", "Labor", "Hours",
     None, 0, "framing",
     '(project_scope == "new_build" OR project_scope == "full_rebuild") AND deck_height_ft >= 3',
     "max(4, ceil(deck_sqft * 0.10))", "deck_sqft", 0.10, 301, "deck"),

    ("Material | Framing | Joists 2x8", "Framing > Lumber", "0600", "Materials", "Each",
     None, 23.15, None,
     'project_scope == "new_build" OR project_scope == "full_rebuild"',
     "deck_joist_count", "deck_joist_count", None, 310, "deck"),

    ("Material | Framing | Rim Joists 2x8", "Framing > Lumber", "0600", "Materials", "Each",
     4, 23.15, None,
     'project_scope == "new_build" OR project_scope == "full_rebuild"',
     None, None, None, 311, "deck"),

    ("Material | Framing | Blocking 2x8", "Framing > Lumber", "0600", "Materials", "Each",
     None, 23.15, None,
     'project_scope == "new_build" OR project_scope == "full_rebuild"',
     "max(1, ceil(deck_sqft / 48))", "deck_sqft", None, 312, "deck"),

    ("Material | Framing | Ledger Board 2x8", "Framing > Lumber", "0600", "Materials", "Each",
     None, 23.15, None,
     'project_scope == "new_build" OR project_scope == "full_rebuild"',
     "ceil(deck_width_ft / 16) + 1", "deck_width_ft", None, 313, "deck"),

    ("Material | Framing | Fascia 1x8", "Framing > Lumber", "2500", "Materials", "Each",
     None, 31.44, None, "always",
     "ceil(deck_perimeter_lf / 16) + 1", "deck_perimeter_lf", None, 314, "deck"),

    ("Material | Framing | Joist Hangers", "Framing > Hardware", "2500", "Materials", "Each",
     None, 2.98, None,
     'project_scope == "new_build" OR project_scope == "full_rebuild"',
     "deck_joist_count * 2", "deck_joist_count", None, 320, "deck"),

    ("Material | Framing | Hurricane Ties", "Framing > Hardware", "2500", "Materials", "Each",
     None, 0.98, None,
     'project_scope == "new_build" OR project_scope == "full_rebuild"',
     "deck_joist_count", "deck_joist_count", None, 321, "deck"),

    ("Material | Framing | Structural Screws 5lb", "Framing > Hardware", "3100", "Materials", "Each",
     1, 46.02, None, "always", None, None, None, 322, "deck"),

    ("Material | Framing | Joist Hanger Nails", "Framing > Hardware", "2500", "Materials", "Each",
     2, 7.38, None,
     'project_scope == "new_build" OR project_scope == "full_rebuild"',
     None, None, None, 323, "deck"),

    ("Material | Framing | Bolts 1/2\"x6\"", "Framing > Hardware", "2500", "Materials", "Each",
     4, 2, None,
     'project_scope == "new_build" OR project_scope == "full_rebuild"',
     None, None, None, 324, "deck"),

    ("Material | Framing | Flashing / Ledger Tape", "Framing > Hardware", "2500", "Materials", "Each",
     1, 130.55, None,
     'project_scope == "new_build" OR project_scope == "full_rebuild"',
     None, None, None, 325, "deck"),

    # ── DECKING ──────────────────────────────────────────────────────────
    ("Labor | Decking | Install Decking", "Decking > Labor", "2500", "Labor", "Hours",
     None, 0, "framing", "always",
     "max(6, ceil(deck_sqft * 0.08))", "deck_sqft", 0.08, 500, "deck"),

    ("Material | Decking | Deck Boards", "Decking > Materials", "2500", "Materials", "Linear Feet",
     None, None, None, "always",
     "ceil(deck_decking_lf * 1.1)", "deck_decking_lf", None, 510, "deck"),

    ("Material | Decking | Hidden Fasteners", "Decking > Materials", "2500", "Materials", "Each",
     None, 319.99, None, 'decking_material == "composite_mid" OR decking_material == "composite_premium"',
     "if(deck_sqft < 500, 1, 2)", "deck_sqft", None, 511, "deck"),

    ("Material | Decking | Deck Screws 350ct", "Decking > Materials", "2500", "Materials", "Each",
     None, 63.33, None, 'decking_material != "composite_mid" AND decking_material != "composite_premium"',
     "ceil(deck_sqft / 100)", "deck_sqft", None, 512, "deck"),

    # ── STAIRS ───────────────────────────────────────────────────────────
    ("Labor | Decking | Install Stairs", "Stairs > Labor", "2500", "Labor", "Hours",
     None, 0, "framing", "stair_tread_count > 0",
     "max(4, stair_tread_count * 1.5)", "stair_tread_count", None, 530, "deck"),

    ("Material | Stairs | Stringers 2x12x14", "Stairs > Materials", "0600", "Materials", "Each",
     3, 30, None, "stair_tread_count > 0", None, None, None, 531, "deck"),

    ("Material | Stairs | Tread Stock", "Stairs > Materials", "2500", "Materials", "Linear Feet",
     None, None, None, "stair_tread_count > 0",
     "ceil(stair_tread_count * stair_width_ft * 1.1)", "stair_tread_count", None, 532, "deck"),

    ("Material | Stairs | Stringer Connectors", "Stairs > Materials", "2500", "Materials", "Each",
     3, 1.98, None, "stair_tread_count > 0", None, None, None, 533, "deck"),

    # ── RAILING ──────────────────────────────────────────────────────────
    ("Labor | Decking | Install Railing", "Railing > Labor", "2500", "Labor", "Hours",
     None, 0, "framing", 'railing_type != "no" AND railing_lf > 0',
     "max(4, ceil(railing_lf * 0.33))", "railing_lf", 0.33, 540, "deck"),

    ("Material | Railing | Railing Package", "Railing > Materials", "2500", "Materials", "Linear Feet",
     None, None, None, 'railing_type != "no" AND railing_lf > 0',
     "ceil(railing_lf * 1.1)", "railing_lf", None, 541, "deck"),

    ("Material | Railing | Post Caps", "Railing > Materials", "2500", "Materials", "Each",
     None, 20, None, 'railing_type != "no" AND railing_lf > 0',
     "ceil(railing_lf / 6) + 1", "railing_lf", None, 542, "deck"),

    # ── DECK CLOSE-OUT ───────────────────────────────────────────────────
    # Reuses "Labor | Admin | Final Cleanup" from bathroom (sort 1100)
]


def parse_name(name):
    """Parse canonical name into (item_type, trade, subject, spec)."""
    parts = [p.strip() for p in name.split(" | ")]
    item_type = parts[0] if len(parts) > 0 else ""
    trade = parts[1] if len(parts) > 1 else ""
    subject = parts[2] if len(parts) > 2 else ""
    spec = parts[3] if len(parts) > 3 else ""
    return item_type, trade, subject, spec


def main():
    # Get active catalog names
    active_raw = psql("SELECT canonical_name FROM catalog_items WHERE is_active = true;")
    active_names = set(active_raw.split("\n")) if active_raw else set()

    # Get trade rates for labor pricing
    rates_raw = psql("SELECT trade, base_wage, burden_factor, markup_factor FROM trade_rates;")
    trade_rates = {}
    for line in rates_raw.split("\n"):
        parts = line.split("|")
        if len(parts) == 4:
            trade_rates[parts[0]] = {
                "wage": float(parts[1]),
                "burden": float(parts[2]),
                "markup": float(parts[3]),
            }

    updated = 0
    inserted = 0
    errors = []
    rate_diffs = []

    for item in ITEMS:
        (name, group, code, cost_type, unit, default_qty,
         mat_cost, trade_key, condition, formula,
         driver, prod_rate, sort, proj_type) = item

        item_type, trade, subject, spec = parse_name(name)

        # Check Craftsman rate override
        craftsman_rate = CRAFTSMAN_RATES.get(name)
        if craftsman_rate and prod_rate and abs(craftsman_rate - prod_rate) > 0.001:
            rate_diffs.append((name, prod_rate, craftsman_rate))
            # Use Craftsman rate (more carefully sourced)
            prod_rate = craftsman_rate

        # Compute pricing for labor items
        unit_cost = None
        unit_price = None
        if cost_type == "Labor" and trade_key:
            r = trade_rates.get(trade_key, trade_rates.get("planning"))
            if r:
                unit_cost = round(r["wage"] * r["burden"], 2)
                unit_price = round(unit_cost * r["markup"], 2)
        elif mat_cost and mat_cost > 0:
            unit_cost = mat_cost
            unit_price = round(mat_cost * 1.4286, 2)

        # JT reference IDs
        jt_cost_code_id = COST_CODE_MAP.get(code)
        jt_cost_type_id = COST_TYPE_MAP.get(cost_type)
        jt_unit_id = UNIT_MAP.get(unit)

        if name in active_names:
            # UPDATE existing row — add assembly logic, preserve existing pricing
            sql = f"""
                UPDATE catalog_items SET
                    budget_group_path = {escape(group)},
                    condition_trigger = {escape(condition)},
                    qty_formula = {escape(formula)},
                    qty_driver = {escape(driver)},
                    default_qty = {default_qty if default_qty is not None else 'NULL'},
                    production_rate = {prod_rate if prod_rate is not None else 'NULL'},
                    sort_order = {sort},
                    project_type = {escape(proj_type)},
                    updated_at = now()
                WHERE canonical_name = {escape(name)} AND is_active = true;
            """
            result = psql(sql)
            updated += 1
        else:
            # INSERT new item
            display_name = name  # Use canonical name as display name
            sql = f"""
                INSERT INTO catalog_items (
                    item_type, trade, subject, spec, display_name,
                    jt_cost_code_id, jt_cost_type_id, jt_unit_id,
                    unit_cost, unit_price,
                    budget_group_path, condition_trigger, qty_formula, qty_driver,
                    default_qty, production_rate, sort_order, project_type,
                    source, is_active
                ) VALUES (
                    {escape(item_type)}, {escape(trade)}, {escape(subject)}, {escape(spec)},
                    {escape(display_name)},
                    {escape(jt_cost_code_id)}, {escape(jt_cost_type_id)}, {escape(jt_unit_id)},
                    {unit_cost if unit_cost is not None else 'NULL'},
                    {unit_price if unit_price is not None else 'NULL'},
                    {escape(group)}, {escape(condition)}, {escape(formula)}, {escape(driver)},
                    {default_qty if default_qty is not None else 'NULL'},
                    {prod_rate if prod_rate is not None else 'NULL'},
                    {sort}, {escape(proj_type)},
                    'heartwood', true
                )
                ON CONFLICT (item_type, trade, subject, spec) DO UPDATE SET
                    budget_group_path = EXCLUDED.budget_group_path,
                    condition_trigger = EXCLUDED.condition_trigger,
                    qty_formula = EXCLUDED.qty_formula,
                    qty_driver = EXCLUDED.qty_driver,
                    default_qty = EXCLUDED.default_qty,
                    production_rate = EXCLUDED.production_rate,
                    sort_order = EXCLUDED.sort_order,
                    project_type = EXCLUDED.project_type,
                    updated_at = now();
            """
            result = psql(sql)
            inserted += 1

    print(f"Updated: {updated} existing items")
    print(f"Inserted: {inserted} new items")

    if rate_diffs:
        print(f"\nCraftsman rate overrides ({len(rate_diffs)}):")
        for name, assembler_rate, craftsman_rate in rate_diffs:
            print(f"  {name}: assembler={assembler_rate} → craftsman={craftsman_rate}")

    if errors:
        print(f"\nErrors ({len(errors)}):")
        for e in errors:
            print(f"  {e}")

    # Final stats
    total = psql("SELECT count(*) FROM catalog_items WHERE is_active = true;")
    has_formula = psql("SELECT count(*) FROM catalog_items WHERE is_active = true AND qty_formula IS NOT NULL;")
    has_cond = psql("SELECT count(*) FROM catalog_items WHERE is_active = true AND condition_trigger IS NOT NULL;")
    has_group = psql("SELECT count(*) FROM catalog_items WHERE is_active = true AND budget_group_path IS NOT NULL;")
    has_rate = psql("SELECT count(*) FROM catalog_items WHERE is_active = true AND production_rate IS NOT NULL;")

    print(f"\nCatalog: {total} active items")
    print(f"  With formula: {has_formula}")
    print(f"  With condition: {has_cond}")
    print(f"  With group: {has_group}")
    print(f"  With production rate: {has_rate}")


if __name__ == "__main__":
    main()
