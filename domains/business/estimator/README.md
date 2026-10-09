# domains/business/estimator/

## Purpose

Heartwood Estimate Assembler — internal React PWA for building line-item estimates from real measurements. Supports bathroom, deck and multi-area flooring projects. Produces JT-pushable budgets via n8n webhook.

## How It Works

Phones use one form column and budget cards. Tablets use two form columns and budget cards. Desktop uses two form columns and a budget table. Editable controls have 44px targets, with a 16px font floor below 1024px.

For panel showers and vinyl/Marmoleum, enter installation hours and supplier costs. Missing inputs block JobTread push and label the price as a draft. In Details, a checked supply box means HWC buys materials; unchecked means the customer buys them. Installation remains included. Keep the existing shower valve only after checking compatibility.

In Details, Additional scope supports material quantities, labor hours at an existing trade rate, and subcontractor lump-sum quotes. Select the JobTread cost code, cost type and unit. Custom costs use the standard material markup unless a labor trade is selected. Blank costs remain visible but block sending while the item is included. Edit and Save preserve the item identity and replace its effective quantity, including earlier Budget edits. Cancel leaves the saved item intact. Editing an excluded item does not restore it; use Restore removed items in Budget. Download the draft to back up custom work.

Drafts are CRITICAL device-local data: a working draft plus up to 50 saved job drafts, with version 3 JSON download/import backups. Switching saves the previous job before restoring the selected job; a full or unavailable store blocks switching rather than discarding drafts. Reset removes the selected job's saved draft. Download before reset, switching devices, or clearing browser data. Budget quantity edits and removals persist through reassembly and reload. Catalogue files are REPLACEABLE exports from Postgres; regenerate them instead of editing JSON. Run `npm run test:site-visit`, `npm run test:golden`, and `npm run lint:ui` for engine and token checks. `npm run test:browser` starts a local dev server and checks three viewport widths with mocked CRM responses and intercepted writes. Set `CHROMIUM_PATH` to your browser executable outside HWC NixOS.

Flooring Scope supports up to 50 named areas per job. Each area uses click-lock LVT/LVP or tile with net square feet, entered waste, optional box coverage, supplier cost and entered labor hours. Product quantities round up to whole boxes; enter 0 box coverage for loose product. Waste never increases labor hours. Removal, subfloor preparation, underlayment/membrane, trim, transitions, tile setting materials and grout have separate inputs. Moving/protection labor, cleanup and hauling apply once per job. Include protection materials and unusual work through Additional scope. Customer supply removes only the finished floor product. Unknown inputs block sending; enter 0 only for checked, unnecessary work. Existing trade rates and material markup apply; no new productivity rates are assumed. Public calculators remain bathroom/deck only.

Draft v3 writes `hwc-estimate-state-v3` and `hwc-estimate-job-drafts-v3`. It reads unversioned/v2 drafts and the legacy keys only as a migration fallback. Legacy keys remain read-only recovery snapshots so an older bundle cannot overwrite new flooring data. These CRITICAL snapshots are retained until explicit backup/disposition; do not clear them automatically. Unsupported or corrupt active data blocks editing/autosave and offers its raw download plus valid import. Invalid job drafts block switching. Download backups before clearing browser data or rolling back; edits made under v3 do not appear in an older bundle.

Selecting an existing JobTread job reads its calculator inputs from the CRM through same-origin `/api/jobs/{job_id}/calculator-intake` (schema version 1). CRM owns the retained answers and resolves only the exact active canonical job link; ambiguity and read failures appear in Scope. No job or budget is created by this read. Bathroom feature choices prefill explicit work flags; deck material, railing and project choices translate to estimator picklists. Original size, arrangement, quality, timeline and unpriced features remain visible as customer preferences, with the original rough range. Unknown measurements and costs stay empty. Existing saved or imported edits take precedence; fresh drafts apply untouched fields once. Review customer selections and measure on site before sending. Version 2 optionally supplies customer-reported feet, counts and finishes from the shared `CALCULATOR_FIELDS` vocabulary. Blank values remain unknown; neither categories nor these reports count as site verification. The rough public range still uses its category model.

New calculator jobs may already have an automatic preliminary budget created by CRM. Scope shows that status, and manual Send reads it again. Review and update the existing budget in JobTread; the current append-only sender cannot replace it.

JobTread receives numeric quantities from the reviewed budget, including waste and edits. Sending adds budget lines and is a manual effect without automatic retries. A saved send lock prevents repeat sends until the user explicitly checks JobTread and allows another attempt. If a request fails, inspect the job before sending again. Measurements must be marked checked before push. Customer purchases and the combined project total display separately from HWC's price.

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
- **Flooring**: Multiple named click-lock LVT/LVP and tile areas. Measured net areas, product waste/box rounding, supplier costs and explicit labor hours. Stable area identities group exact reviewed quantities in JobTread.
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
│   ├── api/crm.js         # Calculator↔estimator contract: v2 fields, deck answer estimates, CRM intake parsing
│   ├── engine/
│   │   ├── assembler.js   # Core: buildCatalog(), buildDeckCatalog(), geometry, parameters
│   │   ├── flooring.js    # Versioned area inputs, quantities, validation and mapped composition
│   │   ├── intake.js      # Pure shared translation and browser state defaults
│   │   ├── preliminary.js # Bounded Node plan port, scope-filtered template/preset assumptions, no provider calls
│   │   └── pricing.js     # tradeRate(), matPrice() — reads tradeRates.json
│   ├── data/
│   │   ├── tradeRates.json     # Exported from DB by export_estimator_data.py
│   │   ├── templates.json      # Exported from DB
│   │   ├── catalog_export.json # Exported from DB (reference, not yet consumed by app)
│   │   ├── parameters.json     # JT parameter definitions (bathroom + deck)
│   │   └── stateKeys.json      # State key schema (informational)
│   ├── hooks/
│   │   ├── useProjectState.js  # State, calculator translation, bounded per-job drafts
│   │   ├── useCatalog.js       # Routes supported project types, applies edits
│   │   └── useIsMobile.js      # Responsive breakpoint
│   ├── components/
│   │   ├── ScopeTab.jsx        # Project forms and template selector
│   │   ├── FlooringScope.jsx   # Named-area editor and whole-job flooring costs
│   │   ├── EstimateTab.jsx     # Line item table, JT push button
│   │   ├── DetailsTab.jsx      # Allowances, mapped custom scope and saved-item editing
│   │   ├── JobSelector.jsx     # JT picker + linked CRM calculator preferences
│   │   └── ...                 # NumInput, Select, Section
│   ├── styles/theme.js         # Gruvbox Material Dark colors
│   └── App.jsx                 # Main layout, tab routing
├── test/
│   ├── golden-master.test.js   # Parity oracle: live engine vs golden snapshots (exits non-zero on diff)
│   ├── json-import-hook.mjs    # Node resolve hook so Vite-style JSON imports load under plain Node
│   ├── golden/                 # 8 golden snapshots, one per template (npm run test:golden -- --update)
│   └── rate-audit.test.js      # P0 rate-fix validation (self-contained)
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
  webhookUrl = "https://hwc-server.ocelot-wahoo.ts.net/webhook/estimate-push";
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

`https://estimator.hwc.iheartwoodcraft.com`

## Testing

```bash
npm run test:golden                          # diff live engine vs golden snapshots; exit 1 on any drift
node test/golden-master.test.js --update     # recapture snapshots (only after an INTENDED output change)
node test/golden-master.test.js --perturb    # self-test: in-memory perturbation must go red
```

The golden-master oracle is the gate for estimator refactors: it runs the
real `src/engine/*` modules (via `test/json-import-hook.mjs`) against all 8
templates and fails the exit code on any item/qty/price/total diff beyond
±0.01. `test_comparison.mjs` (old vs new assembler comparison) always exits 0
and is NOT a refactor gate.

## Changelog

- 2026-10-09: Preliminary plan lines carry `needsConfirmation` unless every input to their quantity traces to calculator answers (`geometry.js` `DERIVED_INPUTS` maps derived keys to raw inputs). Fixed quantities, template/preset inputs, fallbacks and allowances are marked; the CRM writes the mark to JobTread's `Needs Confirmation` cost item field.

- 2026-10-09: Deck calculator categories become rough dimensions where the customer gave no number: size → the calculator's own sq ft at a 2:3 footprint, height band → midpoint, stairs → treads at a 7.5" rise, a chosen railing → the exposed edge. Each is a "verify on site" assumption; customer numbers win. Taylor Chernock's XL L-shaped deck had priced as the 12×10 template with no railing ($11.3k against a $39–72k calculator range).

- 2026-10-08: Make site-review guidance apply to flooring, bathroom and deck work.

- 2026-10-08: Add multiple-area click-lock LVT/LVP and tile estimates with explicit prices/hours, product-only waste and box rounding, customer supply and scoped JobTread lines. Migrate device drafts to v3 keys while retaining legacy recovery snapshots; malformed active drafts stop autosave.

- 2026-10-08: Expose mapped custom scope and quote entry with saved-item editing, existing trade rates, stable draft identities and effective quantity edits. Included custom lines without costs block sending. Browser coverage checks saved drafts and exact payloads at phone, tablet and desktop widths.

- 2026-10-08: Scope preliminary preset notes with the existing parameter registry. Bathroom plans omit deck defaults; deck plans omit bathroom defaults. Regression checks retain relevant provenance and existing items/prices/warnings. Stored budgets are not rewritten.

- 2026-10-07: Share optional version 2 customer measurements, counts and finishes with the calculator. Add a server plan port using existing catalog/templates, visible assumptions and unpriced exclusions. Fresh job-budget status at manual Send blocks duplicate appends, including manual entry and saved drafts. CRM owns reservations and provider effects; customer proposals require review.

- 2026-10-07: App-owned `src/data/preparedDraft.json` loads Carrie's worksheet in fresh sessions and adds site questions once to an existing #411 draft without replacing field work. This file is separate from DB-owned templates because it is a prepared job worksheet, not a reusable template. Regenerate the downloadable worksheet from its `state` member; device edits remain local and exportable.
- 2026-10-07: Scope measurements use native dropdowns on phones, tablets, and desktop. Lengths use feet and quarter-inch choices; areas retain automatic calculations and exact saved values. Costs remain numeric inputs.
- 2026-09-24: The manual build service moves from unsupported Node 20 to
  Node 22. Both skip checks include the Node version so the next build
  reinstalls dependencies and rebakes the app under the new runtime.
- 2026-06-12: Golden-master parity oracle — `test/golden/*.json` snapshots for all 8 templates captured from the live engine, strict runner `test/golden-master.test.js` (exit 1 on diff, `--update` / `--perturb` modes), `test:golden` npm script. Safety net for estimator refactor steps 02–04.
- 2026-06-09: Access moved from the bespoke `services.caddy.extraConfig` PWA block on tailnet port `:13443` to a `vhost` route `estimator.hwc.iheartwoodcraft.com` under the shared `*.hwc.iheartwoodcraft.com` wildcard cert. PWA cache behaviour preserved by the vhost renderer's assets-only-immutable policy. See `domains/networking/README.md`.
- 2026-05-01: Bottom-up pricing engine — Job #306 rates, Craftsman production rates, 8 new scope items, deck assembler, templates, MCP tools, DB export pipeline
- 2026-04-22: NixOS-managed build service with baked-in secrets, versioned deploys
- 2026-03-25: Created README per Law 12
- 2026-03-23: Moved from webapps domain into business domain
