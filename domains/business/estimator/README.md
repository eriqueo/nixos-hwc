# domains/business/estimator/

## Purpose

Heartwood Estimate Assembler — internal React PWA for building line-item estimates from real measurements. Supports bathroom and deck projects. Produces JT-pushable budgets via n8n webhook.

## How It Works

```
User enters measurements → assembler.js derives geometry + scope items
  → pricing.js applies trade rates → line items with cost/price
  → EstimateTab pushes to JT via /webhook/estimate-push (n8n #08b)
```

### Data pipeline

```
hwc Postgres DB (trade_rates, catalog_items, estimate_templates)
  → export_estimator_data.py (domains/business/databases/)
  → JSON files in app/src/data/ (tradeRates.json, templates.json, catalog_export.json)
  → Vite bundles into the app at build time
```

### Supported project types

- **Bathroom**: 50+ scope items — demo, framing, plumbing, electrical, waterproofing, tile, drywall, painting, finish carpentry, allowances. Production rates from Craftsman R&R 2023 + JT Jobs #257/#306.
- **Deck**: 36+ scope items — footings, framing, decking, stairs, railing, close-out. Material pricing for PT/cedar/redwood/composite. Production rates from JT Job #265.

### Templates

8 pre-configured state snapshots (4 bathroom, 4 deck) stored in `estimate_templates` table. One-click loading in the ScopeTab UI, filtered by project type. Add/update via `hwc_estimator_save_template` MCP tool.

### Trade rates (from JT Job #306)

| Trade | Cost/hr | Price/hr |
|-------|---------|----------|
| Demo/Drywall/Paint | $47.25 | $94.50 |
| Framing/Finish Carp | $51.30 | $94.91 |
| Plumbing | $56.70 | $99.23 |
| Electrical | $60.75 | $106.31 |
| Tile/Waterproofing | $60.75 | $121.50 |

Material markup: cost x 1.429

## Boundaries

- **Manages**: Caddy virtual host, firewall rules, SPA routing, build service, React app source
- **Does NOT manage**: Catalog data (→ `domains/business/databases/`), Caddy service (→ `domains/networking/`), n8n workflows, MCP tools (→ `domains/system/mcp/`)

## Structure

```
domains/business/estimator/
├── index.nix              # NixOS module: build service, Caddy, firewall
├── src/
│   ├── engine/
│   │   ├── assembler.js   # Core: buildCatalog(), buildDeckCatalog(), geometry, parameters
│   │   └── pricing.js     # tradeRate(), matPrice() — reads tradeRates.json
│   ├── data/
│   │   ├── tradeRates.json     # Exported from DB by export_estimator_data.py
│   │   ├── templates.json      # Exported from DB
│   │   ├── catalog_export.json # Exported from DB (reference, not yet consumed by app)
│   │   ├── parameters.json     # JT parameter definitions (bathroom + deck)
│   │   └── stateKeys.json      # State key schema (informational)
│   ├── hooks/
│   │   ├── useProjectState.js  # State management + localStorage persistence
│   │   ├── useCatalog.js       # Routes to bathroom/deck catalog, applies edits
│   │   └── useIsMobile.js      # Responsive breakpoint
│   ├── components/
│   │   ├── ScopeTab.jsx        # Measurement form (bathroom + deck), template selector
│   │   ├── EstimateTab.jsx     # Line item table, JT push button
│   │   ├── DetailsTab.jsx      # Allowances and custom items
│   │   ├── JobSelector.jsx     # JT job/customer picker
│   │   └── ...                 # NumInput, Select, Section
│   ├── styles/theme.js         # Gruvbox Material Dark colors
│   └── App.jsx                 # Main layout, tab routing
├── package.json, vite.config.js, index.html
└── README.md
```

### Runtime paths (on server)

```
/var/lib/estimator/dist          # Symlink → current build
/var/lib/estimator/builds/       # Versioned builds (last 3 kept)
/var/lib/estimator-build/app/    # Working directory for npm builds
```

## Namespace

`hwc.business.estimator.*`

## Configuration

```nix
hwc.business.estimator = {
  enable     = true;
  port       = 13443;
  webhookUrl = "https://hwc.ocelot-wahoo.ts.net/webhook/estimate-push";
  apiKeyFile = config.age.secrets.estimator-api-key.path;
};
```

## Build + Deploy

```bash
# After changing rates/templates in DB:
python3 ~/.nixos/domains/business/databases/export_estimator_data.py

# After changing app source, nixos-rebuild first (Nix store source):
sudo nixos-rebuild switch --flake ~/.nixos#hwc-server
sudo systemctl start estimator-build

# Force rebuild (bypass hash check):
sudo rm /var/lib/estimator-build/.last-build-hash
sudo systemctl start estimator-build

# Quick deploy without nixos-rebuild (manual, overwritten next estimator-build):
cd app && npm run build
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
sudo cp -r dist /var/lib/estimator/builds/dist-$TIMESTAMP
sudo ln -sfn /var/lib/estimator/builds/dist-$TIMESTAMP /var/lib/estimator/dist
```

## MCP Tools

8 tools in `hwc_estimator_*` namespace (defined in `domains/system/mcp/src/src/tools/estimator.ts`):

| Tool | Purpose |
|------|---------|
| `hwc_estimator_rates` | List trade rates |
| `hwc_estimator_update_rate` | Update a trade's wage/burden/markup |
| `hwc_estimator_templates` | List templates |
| `hwc_estimator_save_template` | Create/update template |
| `hwc_estimator_delete_template` | Soft-delete template |
| `hwc_estimator_catalog` | Query catalog items |
| `hwc_estimator_export` | Run export scripts (estimator + calculator) |
| `hwc_estimator_build` | Trigger systemd rebuild |

## Access

`https://hwc.ocelot-wahoo.ts.net:13443`

## Changelog

- 2026-05-01: Bottom-up pricing engine — Job #306 rates, Craftsman production rates, 8 new scope items, deck assembler, templates, MCP tools, DB export pipeline
- 2026-04-22: NixOS-managed build service with baked-in secrets, versioned deploys
- 2026-03-25: Created README per Law 12
- 2026-03-23: Moved from webapps domain into business domain
