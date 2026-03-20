# Heartwood Estimate Assembler

A modular, state-driven estimating tool for Heartwood Craft — a remodeling business in Bozeman, Montana specializing in bathroom remodels, decks, and custom carpentry.

## What This Is

This is the internal estimate assembly tool for Heartwood Craft. It takes structured job-site observations (room dimensions, feature toggles, material selections) and assembles a fully priced, JT-ready budget in minutes instead of hours.

It is **not** a general-purpose estimating platform. It is a purpose-built tool that encodes one contractor's knowledge, pricing, and workflow into a repeatable system.

## The Problem It Solves

Remodeling estimates are time-consuming and inconsistent when built from scratch every time. A bathroom remodel has ~60 line items across 10 phases. Most of those items are predictable — they're driven by whether the job has a tub, a shower, niches, what the demo scope is, and what the room dimensions are. But without a system, the estimator (Eric) reinvents the wheel on every bid, risking missed items, inconsistent naming, and slow turnaround.

The assembler solves this by treating an estimate as a **function of project state**:

```
project state (measurements + conditions + selections)
  → assembly engine (trigger evaluation + quantity derivation)
    → priced line items (canonical names + JT-compatible structure)
      → push to JobTread
```

The estimator's job shifts from "build 60 line items from memory" to "fill in 15-20 site visit observations and review the output."

## Philosophy

### Store once, reuse everywhere

A single project state record — the measurements, conditions, counts, and selections for a job — drives budgets, estimates, change orders, and job costing. The state is the source of truth. Everything else is derived.

### The input is the variable, the catalog is the constant

The cost catalog (items, rates, triggers, formulas) is stable knowledge that changes slowly. The project state is what varies per job. The assembly engine bridges them. This separation means adding a new job is fast (fill in state), while improving accuracy is systematic (refine the catalog).

### Structure prevents reinvention

The hierarchical toggle tree enforces a consistent scope definition process. Every bathroom estimate considers the same phases, the same decision points, the same line items — unless a toggle explicitly excludes them. This eliminates the "artisan trap" of treating every project as unique when 80% of the work is standard.

### Pipe-delimited canonical naming

All items follow a consistent naming convention:

- **Labor**: `Labor | Trade | Task` (e.g., `Labor | Tile | Shower Installation`)
- **Materials**: `Material | Trade | Item` (e.g., `Material | Plumbing | Posi-Temp Rough-In Valve`)
- **Allowances**: `Allowance | Category` (e.g., `Allowance | Shower Trim`)

This naming is parseable by machines, readable by humans, and consistent in JobTread's autocomplete. The pipe delimiter encodes trade and task hierarchy directly in the name.

### Base wage × burden pricing model

Labor items are priced using a per-trade base wage multiplied by a burden factor (overhead, insurance, profit). This separates the cost of the work from the cost of running the business. When Eric hires an employee or subcontractor at a different base rate, only the wage changes — the burden and markup logic remain the same.

```
unit_cost = wage × burden
unit_price = unit_cost × trade_markup
```

Trade rates vary: demo labor costs less than tile labor, which costs less than plumbing. The catalog encodes this per-trade, not as a single global rate.

## Where This Fits in the System

The assembler is one piece of a larger business operating system:

```
┌─────────────────────────────────────────────────────┐
│                   DATA LAYER                         │
│                                                      │
│  SQLite Catalog DB          JobTread (CRM + PM)      │
│  ├── cost_items             ├── customers             │
│  ├── state_keys             ├── jobs                  │
│  ├── trade_rates            ├── budgets               │
│  ├── assembly_rules         ├── documents             │
│  └── jt_mappings            └── cost catalog          │
│                                                      │
├─────────────────────────────────────────────────────┤
│                 APPLICATION LAYER                     │
│                                                      │
│  Estimate Assembler (this app)                       │
│  ├── Scope Tab: hierarchical toggle tree input       │
│  ├── Details Tab: allowances, custom items, rates    │
│  ├── Budget Tab: assembled estimate, editable        │
│  └── Push: sends to n8n webhook                      │
│                                                      │
│  Public Cost Calculator (future)                     │
│  ├── Simplified toggle tree for consumers            │
│  ├── Shows price ranges, not exact cost/margin       │
│  ├── Email capture → lead generation                 │
│  └── Posts structured state to n8n → JT + Slack      │
│                                                      │
├─────────────────────────────────────────────────────┤
│                INTEGRATION LAYER                     │
│                                                      │
│  n8n (automation hub on homeserver)                  │
│  ├── Webhook: receives assembled estimate JSON       │
│  ├── Branch 1: POST to JT API (create/update job    │
│  │   + push budget line items)                       │
│  ├── Branch 2: Write to local Postgres/SQLite        │
│  │   (project state + estimate archive)              │
│  ├── Branch 3: Slack notification with summary       │
│  └── Branch 4: (future) Twilio SMS lead response     │
│                                                      │
├─────────────────────────────────────────────────────┤
│                INFRASTRUCTURE                        │
│                                                      │
│  NixOS homeserver                                    │
│  ├── Caddy (reverse proxy)                           │
│  ├── Tailscale (mesh VPN — all device access)        │
│  ├── n8n (automation)                                │
│  ├── Postgres/SQLite (local data)                    │
│  └── Static hosting for this app (PWA)               │
│                                                      │
└─────────────────────────────────────────────────────┘
```

## Architecture Decisions

### JT is the customer/job source of truth

Customers, jobs, and budgets live in JobTread. The assembler reads from JT (via n8n middleware) to select existing customers and jobs, and writes to JT to push assembled budgets. The app never duplicates JT's CRM functionality.

### Project state lives locally

The measurements, conditions, counts, and selections that define a specific job's scope do not exist in JT. This data is stored locally (currently in the browser, planned for Postgres on the homeserver). Project state is the input that drives assembly — it needs to persist for change orders, scope revisions, and historical comparison.

### n8n is the middleware for all external communication

The app does not call the JT API directly. All pushes go through an n8n webhook, which handles fan-out (JT + local DB + Slack) and error handling. This keeps the app simple and the integration logic centralized.

### Catalog data is static at runtime, updated offline

The cost catalog is exported from SQLite to JSON files that the app bundles at build time. Updating the catalog (adding Craftsman data, tweaking rates, adding new project types) means editing the database and running the export script — not editing app code. This separation is critical for maintainability.

### The assembly engine is pure functions

The core logic — trigger evaluation, quantity derivation, pricing — has no React dependencies. It takes a state object and returns an array of priced line items. This makes it testable, reusable (same engine powers the future public calculator), and independent of the UI framework.

## Project State Model

A job's state is captured as a flat set of typed key-value pairs:

| Category    | Examples                                      | Drives                              |
|-------------|-----------------------------------------------|-------------------------------------|
| measurement | room_length, room_width, tile_height          | Sqft calculations, material qty     |
| condition   | has_tub, has_shower, demo_scope, permit_required | Which items appear on the budget   |
| count       | niche_count, fixture_count                    | Multiplied quantities (niches × 4hrs) |
| selection   | wall_tile_family, shower_trim_family          | Allowance resolution, material cost |
| constraint  | occupied_home, lead_safe_required             | Protection scope, procedures        |
| derived     | floor_sqft, wall_tile_sqft, perimeter         | Computed from measurements          |

State keys follow a canonical naming convention: `zone.attribute` (e.g., `bathroom.tile_height`, `bathroom.has_tub`). This allows the same schema to extend to other project types (deck, kitchen) by adding zone-specific keys.

## Catalog Structure

Each catalog item has:

- **canonical_name**: Pipe-delimited name (`Labor | Trade | Task`)
- **budget_group_path**: JT group hierarchy (`Tilework > Shower Tile Labor`)
- **cost_code / cost_type / unit**: JT classification with actual JT IDs
- **condition_trigger**: Boolean expression on project state that determines inclusion
- **qty_driver + qty_formula**: How quantity is computed from state (e.g., `floor_sqft × 0.25`)
- **pricing fields**: wage, burden, production_rate, waste_factor, unit_cost
- **source**: `heartwood` (field-validated) or `craftsman` (reference data)

## Roadmap

### Immediate
- [x] Core assembler with hierarchical toggle tree
- [x] Per-trade labor rates (wage × burden)
- [x] JT API push (tested on job #281)
- [x] Deployed on homeserver via Caddy + Tailscale
- [ ] n8n webhook integration for dual-push (JT + local DB)
- [ ] Pull existing JT customers/jobs into app dropdowns via n8n

### Near-term
- [ ] Calibrate production rates from real job hour data
- [ ] Add Craftsman National Estimator data for non-bathroom trades
- [ ] Expand toggle trees for deck and kitchen project types
- [ ] Saved estimates with version history (local DB)
- [ ] Change order generation from state diffs

### Future
- [ ] Public "bathroom remodel cost calculator" on heartwoodcraft.com
  - Simplified toggle tree, price ranges (not exact margins)
  - Email capture → n8n webhook → JT job creation + Slack notification
  - Lead gen tool that captures structured scope intent before first contact
- [ ] Blender integration: same project state keys drive 3D visualization
- [ ] Voice memo / photo → state extraction (AI-assisted intake)
