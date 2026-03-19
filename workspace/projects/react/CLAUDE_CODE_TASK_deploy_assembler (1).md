# CLAUDE CODE TASK: Deploy Heartwood Estimate Assembler

## Context

Eric runs Heartwood Craft, a remodeling business in Bozeman, Montana. He built a React estimate assembler app that takes job-site parameters (room dimensions, toggles for features like tub/shower/niches, tile complexity, etc.) and assembles a JT-ready bathroom remodel budget with canonical pipe-delimited naming, per-trade labor rates, and condition-triggered line items.

The app currently exists as a single React JSX file (artifact from Claude.ai). It needs to be turned into a deployable application hosted on Eric's NixOS homeserver behind Caddy + Tailscale, accessible as a PWA from his phone, laptop, and iPad.

## Eric's Infrastructure

- **Homeserver**: NixOS, flake-based config at `github.com/eriqueo/nixos-multi-host`
- **Reverse proxy**: Caddy, already running on the homeserver
- **Network**: Tailscale mesh, services accessed via `*.ocelot-wahoo.ts.net` or similar
- **Automation**: n8n running on the homeserver, connected to Slack
- **Database**: SQLite for the cost catalog (`heartwood_catalog.db`), plans for Postgres later

## What to Build

### 1. React App (Vite + React)

Convert the single JSX artifact into a proper Vite + React project:

```
heartwood-assembler/
├── index.html
├── vite.config.js
├── package.json
├── public/
│   ├── manifest.json          # PWA manifest
│   ├── icon-192.png           # Generate a simple hex icon
│   └── icon-512.png
├── src/
│   ├── main.jsx
│   ├── App.jsx                # Main app component
│   ├── data/
│   │   ├── catalog.json       # Cost catalog (exported from SQLite)
│   │   ├── tradeRates.json    # Per-trade labor rates
│   │   ├── stateKeys.json     # Project state key definitions
│   │   └── jtMappings.json    # JobTread ID mappings (cost codes, types, units)
│   ├── engine/
│   │   ├── assembler.js       # Assembly logic: state → filtered catalog → priced estimate
│   │   ├── triggers.js        # Condition trigger evaluation
│   │   ├── quantities.js      # Quantity derivation from state + production rates
│   │   └── pricing.js         # Cost/price calculation (wage × burden, material markup)
│   ├── components/
│   │   ├── ScopeTab.jsx       # Hierarchical toggle tree for job state input
│   │   ├── DetailsTab.jsx     # Allowances, custom items, trade rate reference
│   │   ├── EstimateTab.jsx    # Assembled budget with editable quantities
│   │   ├── Toggle.jsx         # Toggle switch component
│   │   ├── NumInput.jsx       # Numeric input with unit label
│   │   ├── Select.jsx         # Dropdown select
│   │   └── Section.jsx        # Labeled section with accent bar
│   ├── hooks/
│   │   ├── useProjectState.js # State management with localStorage persistence
│   │   └── useCatalog.js      # Catalog loading (from JSON, later from API)
│   └── styles/
│       └── theme.js           # Color palette, typography constants
└── sw.js                      # Service worker for offline PWA support
```

**Key architecture decisions:**

- The catalog data lives in JSON files under `src/data/`, NOT hardcoded in components. This makes it easy to regenerate from the SQLite database without touching app code.
- The assembly engine is pure functions with no React dependencies — it can be tested independently and later reused in the public website version.
- State persists to localStorage so Eric can close the browser and come back to an in-progress estimate.
- The app should work fully offline once loaded (service worker caches all assets).

### 2. SQLite → JSON Export Script

Create a Python script that exports the SQLite catalog to the JSON files the app consumes:

```python
# scripts/export_catalog.py
# Reads heartwood_catalog.db and writes:
#   - src/data/catalog.json (all active cost items)
#   - src/data/tradeRates.json (per-trade wage/burden/markup)
#   - src/data/stateKeys.json (state key definitions)
#   - src/data/jtMappings.json (JT IDs for cost codes, types, units)
```

This lets Eric update the database (add Craftsman data, tweak rates) and run one command to update the app.

### 3. n8n Webhook Integration

Add a "Push to JT" button that POSTs the assembled estimate to an n8n webhook:

```javascript
// POST to n8n webhook URL (configurable in .env or settings)
const payload = {
  action: "push_estimate",
  project: {
    customer: state.customer,
    address: state.address,
    jobName: state.job_name,
  },
  state: state,           // Full project state for local DB storage
  estimate: estimate,     // Assembled line items
  jtPayload: estimate.map(item => ({
    name: item.name,
    groupName: item.group,
    costCodeId: jtMappings.codes[item.code],
    costTypeId: jtMappings.types[item.type],
    unitId: jtMappings.units[item.unit],
    quantity: item.qty,
    unitCost: item.uc,
    unitPrice: item.up,
  }))
};

fetch(WEBHOOK_URL, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify(payload)
});
```

The n8n workflow (built separately) handles:
- Branch 1: Push jtPayload to JobTread API (create job + add budget items)
- Branch 2: Write state + estimate to local Postgres/SQLite
- Branch 3: Send Slack notification with summary

### 4. PWA Manifest

```json
{
  "name": "Heartwood Estimator",
  "short_name": "HWC Estimate",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#0c0e11",
  "theme_color": "#c9956b",
  "icons": [
    { "src": "/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icon-512.png", "sizes": "512x512", "type": "image/png" }
  ]
}
```

### 5. NixOS / Caddy Deployment

The app builds to static files (`dist/` from `vite build`). Serve via Caddy on the homeserver:

```
# Caddyfile addition
estimate.hwc.{tailscale_domain} {
    root * /var/www/heartwood-assembler
    file_server
    try_files {path} /index.html
}
```

Or if Eric prefers NixOS declarative config, a simple static site service.

### 6. Design Requirements

- **Color palette**: Dark theme matching Eric's preferences (gruvbox-inspired, warm accents)
  - Background: #0c0e11
  - Cards: #14171c / #1a1e25
  - Borders: #262b33
  - Text: #9ca3af (body), #e2e5ea (bright), #5a6270 (dim)
  - Accent: #c9956b (warm copper/wood tone — "heartwood")
  - Phase colors: Demo=red, Plumbing=blue, Tilework=purple, Painting=green, etc.
- **Typography**: JetBrains Mono throughout (monospace, clean, technical)
- **Layout**: Responsive — works on desktop and mobile (phone at job site)
- **Interactions**: Toggles animate, derived values update in real-time, estimate regenerates on every state change

## The Source JSX

The complete working React component is in the file `heartwood-assembler-v2.jsx` delivered alongside this task file. It contains:
- Full catalog data (62 bathroom items)
- Assembly engine (buildCatalog function with trigger evaluation and quantity derivation)
- Per-trade labor rates
- JT ID mappings
- Three-tab UI (Scope, Details, Budget)
- Custom line item support
- Clipboard copy of JT payload

All of this should be decomposed into the module structure described above.

## JobTread Reference IDs

These are the actual JT IDs for Eric's organization:

### Cost Codes
- 0100 Planning: 22Nm3uGRAMmH
- 0200 Demolition: 22Nm3uGRAMmJ
- 0600 Framing: 22Nm3uGRAMmN
- 1000 Electrical: 22Nm3uGRAMmS
- 1100 Plumbing: 22Nm3uGRAMmT
- 1400 Drywall: 22Nm3uGRAMmW
- 1800 Tiling: 22Nm3uGRAMma
- 1900 Cabinetry: 22Nm3uGRAMmb
- 2100 Trimwork: 22Nm3uGRAMmd
- 2300 Painting: 22Nm3uGRAMmf
- 2400 Appliances: 22Nm3uGRAMmg
- 3000 Furnishings: 22Nm3uGRAMmn
- 3100 Miscellaneous: 22Nm3uGRAMmp

### Cost Types
- Admin: 22PJuNqewZmV
- Labor: 22Nm3uGRAMmq
- Materials: 22Nm3uGRAMmr
- Other: 22Nm3uGRAMmt
- Selections: 22PQ4KZExZjP
- Subcontractor: 22Nm3uGRAMms

### Units
- Hours: 22Nm3uGRAMm9
- Each: 22Nm3uGRAMm7
- Gallons: 22Nm3uGRAMm8
- Lump Sum: 22Nm3uGRAMmB
- Square Feet: 22Nm3uGRAMmD
- Linear Feet: 22Nm3uGRAMmA

## Success Criteria

1. `npm run dev` serves the app locally
2. `npm run build` produces a static `dist/` folder
3. The app works offline after first load (service worker)
4. "Add to Home Screen" works on iOS Safari and shows the HWC icon
5. Changing a toggle immediately updates the estimate
6. The "Push" button sends valid JSON to a configurable webhook URL
7. The SQLite export script regenerates all JSON data files
8. The app is responsive and usable on a phone screen
