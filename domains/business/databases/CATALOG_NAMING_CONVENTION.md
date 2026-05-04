# Heartwood Craft — Catalog Naming Convention

## Purpose

One deterministic rule for naming every item in the catalog. Given an item's attributes (type, trade, what it is, key specs), the rule produces exactly one canonical name. Two people writing the same logical item in different years produce the same string.

This name is the shared key between JobTread (displayed as `name`), the Postgres catalog (`canonical_name`, generated column), and the assembler engine (queries by structured fields, pushes to JT by `jt_catalog_id`).

-----

## Name Structure

```
{Type} | {Trade} | {Subject} [| {Spec}]
```

**Segments are separated by `|` (space-pipe-space).** Always.

### Segment 1: Type (required)

Exactly one of:

|Value        |When to use                                          |
|-------------|-----------------------------------------------------|
|`Labor`      |Hours billed at a trade's labor rate                 |
|`Material`   |Physical product purchased from a supplier           |
|`Subcontract`|Work performed by a sub, billed as a line item       |
|`Allowance`  |Client selection placeholder (tile, fixtures, vanity)|
|`Other`      |Permits, fees, rentals, dump fees, design fees       |

### Segment 2: Trade (required)

The trade determines the cost code AND the labor rate (for Labor items). Exactly one of:

|Trade            |Cost Code|Notes                                                                  |
|-----------------|---------|-----------------------------------------------------------------------|
|`Planning`       |0100     |Walkthroughs, estimating, material ordering, design fees, permits      |
|`Sitework`       |0110     |Protection, scaffolding, dump trailer, temporary bracing               |
|`Demo`           |0200     |All demolition regardless of what's being removed                      |
|`Framing`        |0600     |Rough carpentry, structural lumber, blocking, subfloor                 |
|`Siding`         |0800     |Siding, fascia, soffit, gutters, house wrap, flashing                  |
|`Electrical`     |1000     |Wiring, outlets, switches, panels, fixtures, low-volt                  |
|`Plumbing`       |1100     |Pipe, fittings, valves, drains, fixtures (tubs, toilets, faucets)      |
|`Insulation`     |1300     |Batt, spray foam, rigid foam, fireblocking                             |
|`Drywall`        |1400     |Sheets, mud, tape, screws, corner bead                                 |
|`Doors & Windows`|1500     |Doors, windows, hardware, pocket door frames                           |
|`Flooring`       |1700     |LVP, hardwood, carpet, underlayment                                    |
|`Tile`           |1800     |Tile, backer board, waterproofing, thinset, grout, trim, drains, niches|
|`Cabinetry`      |1900     |Cabinets, vanities, shelving systems                                   |
|`Countertop`     |2000     |Countertop slabs, templating, installation                             |
|`Trimwork`       |2100     |Baseboard, casing, crown, door trim, window trim                       |
|`Specialty`      |2200     |Masonry, stucco, fireplace work                                        |
|`Painting`       |2300     |Paint, primer, caulk, tape, prep, spray, brush                         |
|`Appliances`     |2400     |Appliance units and installation                                       |
|`Decking`        |2500     |Deck boards, railing, stairs, post bases, deck fasteners               |
|`Concrete`       |2800     |Footings, sonotubes, concrete mix, post bases                          |
|`Furnishings`    |3000     |Mirrors, towel bars, accessories, bath hardware                        |
|`Miscellaneous`  |3100     |General fasteners, adhesives, items that don't fit elsewhere           |
|`Cleanup`        |0100     |Daily cleanup, final clean, punch list (shares Planning cost code)     |
|`HVAC`           |3100     |Ductwork, vents, HVAC rough/trim (shares Misc cost code)               |

### Segment 3: Subject (required)

**What it is.** The product family or labor task.

Rules:

- For **Labor**: verb-noun phrase describing the task. Examples: `Install Mixer Valve`, `Demo Floor Tile`, `Frame Wall`, `Run Showerhead Copper`, `Hang Drywall`.
- For **Material**: product family name — the words you'd search for at the supplier. Examples: `Copper Pipe`, `Drywall Sheet`, `Joist Hanger`, `Lumber SPF`, `Paint`, `Primer`.
- For **Allowance**: the thing the client selects. Examples: `Shower Tile`, `Vanity`, `Toilet`, `Bathtub`, `Faucet`.
- For **Other**: the fee/service. Examples: `Remodeling Permit`, `Dump Fee`, `Design Fee`, `Building Plans`.
- **No dimensions, sizes, or specs in the Subject.** Those go in Segment 4.
- **No brand names in the Subject** unless the brand IS the product identity (e.g., `Kerdi-Shower Tray` — "Kerdi-Shower" is how you'd search for it, not "Schluter foam shower tray").

### Segment 4: Spec (optional, repeatable)

**What makes this SKU different from another in the same product family.**

Only present when the catalog has multiple items with the same Type + Trade + Subject. If there's only one `Material | Plumbing | Copper Pipe` in the catalog, no spec needed. If there are two sizes, add the spec.

Rules:

- Specs follow the Subject after another `|` separator.
- Multiple spec values are separated by `|`.
- Specs follow a deterministic order per trade (see Spec Conventions below).
- **Finish/color is NOT a spec** — it's a JT selection field on the item. One canonical item, multiple finish options as selections.
- **Dimensions ARE specs** when they represent different SKUs at the supplier.

-----

## Spec Conventions by Trade

### Lumber / Framing

Format: `{nominal thickness}x{width}x{length}[ {species}]`

- `Material | Framing | Lumber SPF | 2x4x8`
- `Material | Framing | Lumber SPF | 2x8x16`
- `Material | Framing | Plywood ACX | 3/4" 4x8`
- `Material | Decking | Lumber WRC | 1x6x16` (Western Red Cedar)
- `Material | Decking | Lumber WRC | 4x4x12`

### Sheet Goods (Drywall, Backer Board)

Format: `{thickness} {WxH}`

- `Material | Drywall | Drywall Sheet | 1/2" 4x8`
- `Material | Drywall | Drywall Sheet Mold Resistant | 1/2" 4x8`
- `Material | Tile | HydroBan Board | 1/2" 4x8`
- `Material | Tile | HydroBan Board | 1/2" 3x5`

### Pipe

Format: `{diameter}[ {material}]`

- `Material | Plumbing | Copper Pipe | 1/2"`
- `Material | Plumbing | PVC Drain Pipe | 2" 10'`
- `Material | Plumbing | PEX Pipe | 1/2" 100'`

### Fasteners / Screws

Format: `{size} {length}[ {qty}]`

- `Material | Miscellaneous | Screws Exterior | #9 3" 5lb`
- `Material | Drywall | Drywall Screws | 1-5/8" 1lb`
- `Material | Drywall | Drywall Screws | 1-5/8" 5lb`
- `Material | Decking | Composite Deck Screws | 2-1/2"`

### Tile Products (Schluter / Kerdi)

Format: `{product line}[ {dimensions}]`

- `Material | Tile | Kerdi-Shower Tray | 38x60`
- `Material | Tile | Kerdi-Shower Tray | 48x48`
- `Material | Tile | Kerdi-Shower Tray Sloped | 48x60`
- `Material | Tile | Kerdi-Shower Kit | 38x60`
- `Material | Tile | Kerdi-Board Niche | 12x12`
- `Material | Tile | Kerdi-Board Niche | 12x20`
- `Material | Tile | Kerdi-Board Shower Curb | 48"`
- `Material | Tile | Kerdi-Board Shower Curb | 60"`
- `Material | Tile | Kerdi-Drain Grate | 4"` (finish is a selection, not a spec)
- `Material | Tile | Kerdi Membrane | 3'3"x16'5"`
- `Material | Tile | Kerdi Corner Inside | 2-Pack`
- `Material | Tile | Kerdi Corner Outside | 2-Pack`
- `Material | Tile | Schluter Banding | 16'`
- `Material | Tile | Schluter Trim Aluminum | 1/4"`

### Tile Selections (for client selection catalogs)

Format: `{brand} {collection}[ {pattern}]`

- `Material | Tile | Merola Hudson | Hex`
- `Material | Tile | Merola Hudson | Kite`
- `Material | Tile | Merola Hudson | Due`
- `Material | Tile | Merola Metro | Soho`
- `Material | Tile | MSI Arabescato Venato | 12x12 Honed`
- `Material | Tile | MSI Arabescato Venato | 4x12 Subway`
- `Material | Tile | Daltile Brickwork | 2x8`
- `Material | Tile | Daltile Brickwork | 4x8`

### Paint / Coatings

Format: `{brand} {line}[ {sheen/type}]`

- `Material | Painting | Primer | BIN Shellac`
- `Material | Painting | Paint Interior | SW Emerald Urethane Semi-Gloss`
- `Material | Painting | Paint Exterior | SW Duration Acrylic`

### Plumbing Fixtures

Format: `{brand} {line}[ {size}]`

- `Material | Plumbing | Shower Valve | Moen Posi-Temp`
- `Material | Plumbing | Bathtub Alcove | Delta Classic`
- `Material | Plumbing | Toilet Seat | Kohler Brevia`
- `Material | Plumbing | Faucet | Delta Nicoli` (finish is a selection)

### Bath Accessories / Furnishings

Format: `{brand} {line}[ {item}]`

- `Material | Furnishings | Towel Bar | Kohler Tempered 24"`
- `Material | Furnishings | Towel Bar | Signature Hardware Lentz 24"`
- `Material | Furnishings | Towel Ring | Franklin Brass Maxted`
- `Material | Furnishings | Mirror | Metal Arch Wall`

### Cabinetry / Vanities

Format: `{brand} {line} {size}`

- `Material | Cabinetry | Vanity | James Martin Brittany 30"`
- `Material | Cabinetry | Vanity | Wyndham Miranda 30"`
- `Material | Cabinetry | Closet System | ClosetMaid Selectives 16"`
- `Material | Cabinetry | Closet Drawer | ClosetMaid Selectives 16"`

### Decking (composite / engineered)

Format: `{material} {brand} {line} {size}`

- `Material | Decking | Composite Board | Trex Enhance 1x6x16`
- `Material | Decking | Composite Board | Trex Transcend 1x6x16`
- `Material | Decking | Composite Board | TimberTech Legacy 1x6x16`
- `Material | Decking | Composite Board | TimberTech Reserve 1x6x16`
- `Material | Decking | Wood Board | Alaskan Yellow Cedar 1x6x16`

### Connectors / Hardware

Format: `{type} {size}`

- `Material | Framing | Joist Hanger | 2x6`
- `Material | Framing | Joist Hanger | 2x8`
- `Material | Framing | Joist Hanger | 4x10`
- `Material | Decking | Post Base | 4x4`
- `Material | Decking | Post Base | 6x6`

### Siding

Format: `{brand} {product} {size}`

- `Material | Siding | LP SmartSide Trim | 4/4 2" 8'`
- `Material | Siding | LP SmartSide Trim | 5/4 4" 8'`

-----

## Special Rules

### Finish / Color → JT Selection Field, Not a Spec

When the same product exists in multiple finishes at the same (or similar) price, catalog ONE item with the base name and add finishes as a JT "Available Finishes" custom field or Selections. Do NOT create separate catalog items for each finish.

Examples:

- ONE `Material | Tile | Kerdi-Drain Grate | 4"` — with Available Finishes: Stainless Steel, Brushed Stainless, Matte Black, Matte White, Floral Stainless, Floral Matte Black, Floral Matte White
- ONE `Material | Plumbing | Faucet | Delta Nicoli` — with Available Finishes: Chrome, Matte Black, Brushed Nickel

### Allowances Don't Have Specs

Allowances are placeholders for client selections. They don't have specs — the client will choose a specific product later.

- `Allowance | Tile | Shower Tile`
- `Allowance | Plumbing | Bathtub`
- `Allowance | Cabinetry | Vanity`
- `Allowance | Electrical | Fixtures`

### Labor Items Never Have Spec Segments

Labor items are fully described by Type + Trade + Subject. The production rate, quantity driver, and formula are metadata on the item, not part of the name.

- `Labor | Demo | Demo Floor Tile`
- `Labor | Plumbing | Install Mixer Valve`
- `Labor | Tile | Tile Floor Installation`

### Other Items

Permits, fees, and rentals — no specs unless there are size/duration variants.

- `Other | Planning | Remodeling Permit`
- `Other | Sitework | Dump Trailer`
- `Other | Planning | Design Fee`

-----

## Validation Rules

A canonical name is valid if and only if:

1. Has exactly 3 or 4 pipe-separated segments (no more, except decking board variants which may have 4-5)
1. Segment 1 is one of the 5 valid Type values
1. Segment 2 is one of the valid Trade values
1. Segment 3 (Subject) is non-empty, no leading/trailing whitespace
1. If Segment 4 (Spec) exists, it's non-empty and follows the per-trade convention
1. No duplicate item exists with the same (Type, Trade, Subject, Spec) tuple

-----

## Postgres Schema

```sql
CREATE TABLE catalog_items (
    id SERIAL PRIMARY KEY,
    jt_catalog_id VARCHAR(50) UNIQUE,
    
    -- Canonical name segments
    item_type VARCHAR(20) NOT NULL,         -- Labor/Material/Subcontract/Allowance/Other
    trade VARCHAR(50) NOT NULL,             -- Demo/Framing/Plumbing/etc.
    subject VARCHAR(200) NOT NULL,          -- Product family or labor task
    spec VARCHAR(200) DEFAULT '',           -- SKU differentiator (empty if none)
    
    -- Generated canonical name
    canonical_name TEXT GENERATED ALWAYS AS (
        item_type || ' | ' || trade || ' | ' || subject ||
        CASE WHEN spec != '' THEN ' | ' || spec ELSE '' END
    ) STORED,
    
    -- Cost data
    cost_code VARCHAR(20) NOT NULL,
    cost_type VARCHAR(20) NOT NULL,
    unit VARCHAR(20),
    unit_cost DECIMAL(10,2),
    unit_price DECIMAL(10,2),
    
    -- Assembler metadata (Labor items)
    labor_wage DECIMAL(10,2),
    labor_burden DECIMAL(5,3),
    production_rate DECIMAL(8,4),
    qty_driver_key VARCHAR(100),
    qty_formula VARCHAR(200),
    condition_trigger VARCHAR(200),
    waste_factor DECIMAL(5,3),
    
    -- Material metadata
    vendor VARCHAR(100),
    url TEXT,
    available_finishes TEXT,        -- comma-separated finish options
    
    -- Lifecycle
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE(item_type, trade, subject, spec)
);

CREATE INDEX idx_catalog_trade ON catalog_items(trade);
CREATE INDEX idx_catalog_type ON catalog_items(item_type);
CREATE INDEX idx_catalog_jt_id ON catalog_items(jt_catalog_id);
CREATE INDEX idx_catalog_active ON catalog_items(is_active);
```

This schema enforces the naming convention structurally — the UNIQUE constraint on `(item_type, trade, subject, spec)` physically prevents duplicate canonical names.
