# Bathroom Remodel Planner API

A modular, config-driven cost estimation tool for bathroom remodels. Built with FastAPI, PostgreSQL, and designed for self-hosting on NixOS.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Frontend (Future)                     │
│              Static React/Vue/Svelte App                 │
└────────────────────┬────────────────────────────────────┘
                     │ HTTP/JSON
┌────────────────────┴────────────────────────────────────┐
│                    FastAPI Backend                       │
│  ┌────────────────────────────────────────────────┐     │
│  │  /api/projects        - Create project         │     │
│  │  /api/projects/{id}/estimate - Get estimate    │     │
│  └────────────────────────────────────────────────┘     │
│                          │                               │
│  ┌────────────────────────────────────────────────┐     │
│  │        BathroomCostEngine                      │     │
│  │  - Load rules from database                    │     │
│  │  - Match rules to user answers                 │     │
│  │  - Calculate costs per module                  │     │
│  │  - Aggregate totals                            │     │
│  │  - Compute complexity score                    │     │
│  └────────────────────────────────────────────────┘     │
└────────────────────┬────────────────────────────────────┘
                     │ asyncpg
┌────────────────────┴────────────────────────────────────┐
│                   PostgreSQL                             │
│  - clients                                               │
│  - projects                                              │
│  - project_answers                                       │
│  - project_cost_items                                    │
│  - cost_rules (pricing engine)                           │
└──────────────────────────────────────────────────────────┘
```

## Key Features

### 1. **Config-Driven Question Tree**
- All questions defined in `config/bathroom_questions.yaml`
- Add/remove questions without touching code
- Includes educational content, images, conditional logic

### 2. **Modular Cost Engine**
- Rules-based calculation stored in `cost_rules` table
- Each rule has:
  - `module_key`: Groups related costs (e.g., "tub_to_shower")
  - `applies_when`: Conditional logic (e.g., `{"goals_contains": "convert_tub_to_shower"}`)
  - Cost components: base cost, per-sqft cost, labor fraction
  - Complexity points
- Easy to update pricing: just edit the database

### 3. **Deterministic First, LLM Later**
- Core cost calculations are pure logic (no AI required)
- `project_analysis` table reserved for future LLM insights
- "Builder Analysis" and "Designer Analysis" can be added without touching cost logic

### 4. **JobTread-Ready**
- Database schema designed to sync with JobTread API
- Fields for `jobtread_account_id`, `jobtread_job_id`
- Sync logic stubbed but not implemented in MVP

## Project Structure

```
remodel-api/
├── app/
│   ├── __init__.py
│   ├── main.py                    # FastAPI application
│   ├── database.py                # Database connection
│   ├── models.py                  # Pydantic models
│   ├── routers/
│   │   └── projects.py            # API endpoints
│   └── engines/
│       └── bathroom_cost_engine.py # Cost calculation logic
├── config/
│   ├── bathroom_questions.yaml    # Question tree config
│   └── cost_rules_seed.sql        # Sample pricing data
├── migrations/
│   └── 001_initial_schema.sql     # Database schema
├── nix/
│   └── container.nix              # NixOS deployment module
├── Dockerfile
├── requirements.txt
└── README.md
```

## Setup Instructions

### 1. Database Setup

Create the database and run migrations:

```bash
# Create PostgreSQL database
createdb remodel

# Run schema migration
psql -U postgres -d remodel -f migrations/001_initial_schema.sql

# Seed cost rules
psql -U postgres -d remodel -f config/cost_rules_seed.sql
```

**Important:** Adjust the cost values in `cost_rules_seed.sql` to match your local market rates before seeding!

### 2. Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Set database URL
export DATABASE_URL="postgresql://user:password@localhost:5432/remodel"

# Run the API
uvicorn app.main:app --reload

# API will be available at http://localhost:8000
```

### 3. Docker Build

```bash
# Build the image
docker build -t remodel-api:latest .

# Run with Docker
docker run -d \
  -p 8000:8000 \
  -e DATABASE_URL="postgresql://user:password@host.docker.internal:5432/remodel" \
  remodel-api:latest
```

### 4. NixOS Deployment

```nix
# In your NixOS configuration
{
  imports = [ ./remodel-api/nix/container.nix ];

  services.remodel-api = {
    enable = true;
    domain = "remodel.yourdomain.com";
    port = 8001;
    databasePassword = "your-secure-password";  # Use agenix in production
  };
}
```

Then rebuild:

```bash
sudo nixos-rebuild switch
```

## API Usage

### Create a Project

```bash
curl -X POST http://localhost:8000/api/projects \
  -H "Content-Type: application/json" \
  -d '{
    "client": {
      "name": "Jane Doe",
      "email": "jane@example.com",
      "phone": "406-555-1234"
    },
    "project_type": "bathroom"
  }'
```

Response:
```json
{
  "project_id": "123e4567-e89b-12d3-a456-426614174000",
  "client_id": "123e4567-e89b-12d3-a456-426614174001"
}
```

### Calculate Estimate

```bash
curl -X POST http://localhost:8000/api/projects/{project_id}/estimate \
  -H "Content-Type: application/json" \
  -d '{
    "answers": {
      "bathroom_type": "primary",
      "preferred_styles": ["modern", "industrial"],
      "ambience": "dark_dark",
      "goals": ["convert_tub_to_shower", "replace_wall_tile"],
      "size_sqft_band": "35_60",
      "layout_change_level": "non_structural_changes",
      "plumbing_changes": "moving_shower_or_tub",
      "electrical_scope": "add_lighting",
      "ventilation_scope": "upgrade_fan",
      "extras": ["shower_niche", "frameless_glass"],
      "shower_type": "custom_tiled_shower",
      "tile_level": "porcelain",
      "flooring_type": "tile",
      "vanity_type": "semi_custom",
      "countertop_type": "prefab_quartz",
      "budget_band": "15_to_30k",
      "timeline_readiness": "3_to_6_months"
    }
  }'
```

Response:
```json
{
  "project_id": "...",
  "summary": {
    "scope_text": "You are planning a primary bathroom remodel with converting the tub to a shower, replacing wall tile...",
    "complexity_band": "medium",
    "complexity_score": 5
  },
  "cost": {
    "total_min": 23000,
    "total_max": 34000,
    "labor_min": 15000,
    "labor_max": 22000,
    "materials_min": 8000,
    "materials_max": 12000
  },
  "modules": [
    {
      "module_key": "tub_to_shower",
      "label": "Tub to Shower Conversion",
      "total_min": 14000,
      "total_max": 22000
    }
  ],
  "education": {
    "cost_drivers": [
      "Custom tiled shower with frameless glass",
      "Moving plumbing for shower",
      "Upgraded wall tile materials"
    ],
    "questions_for_contractors": [...]
  },
  "analysis": {
    "builder": null,
    "designer": null
  }
}
```

## Updating Pricing

To adjust costs for your market:

1. Edit `config/cost_rules_seed.sql`
2. Re-seed the database:
   ```bash
   psql -U postgres -d remodel -f config/cost_rules_seed.sql
   ```

Or update rules directly in the database:

```sql
UPDATE cost_rules
SET base_cost_min = 3000, base_cost_max = 5000
WHERE module_key = 'tub_to_shower' AND rule_key = 'tiled_shower_pan';
```

## Adding New Modules

1. Add new rules to `cost_rules` table with a new `module_key`
2. Update the `_module_label()` method in `bathroom_cost_engine.py` to add a human-readable label
3. Optionally add to the question tree config if you want UI elements

Example: Adding a "wallpaper" module:

```sql
INSERT INTO cost_rules (
  engine, module_key, rule_key,
  applies_when,
  base_cost_min, base_cost_max,
  labor_fraction
)
VALUES (
  'bathroom', 'wallpaper', 'premium_wallpaper',
  '{"extras_contains": "premium_wallpaper"}'::jsonb,
  800, 1500,
  0.60
);
```

## Testing

```bash
# Install dev dependencies
pip install pytest pytest-asyncio

# Run tests (when implemented)
pytest
```

## Future Enhancements

### Phase 2: PDF Generation
- Add WeasyPrint to `requirements.txt`
- Create HTML templates in `app/templates/`
- Implement `/api/projects/{id}/generate-pdf` endpoint

### Phase 3: JobTread Integration
- Implement `JobTreadSync` service
- Add admin endpoints to manually trigger sync
- Set up webhook listeners for bi-directional sync

### Phase 4: LLM Analysis
- Add OpenAI/Anthropic API integration
- Implement `/api/projects/{id}/analysis` endpoint
- Generate "Builder Analysis" and "Designer Analysis" text

### Phase 5: Admin Dashboard
- Build simple admin UI to view projects
- Lead scoring and filtering
- Adjust pricing rules through UI

## Security Considerations

- **Database passwords**: Use agenix secrets in production, not environment variables
- **API rate limiting**: Add middleware to prevent abuse
- **CORS**: Restrict `allow_origins` to your domain
- **Input validation**: All inputs are validated by Pydantic models
- **SQL injection**: Protected by parameterized queries (asyncpg)

## Support

For issues or questions:
- Check the API docs at `http://localhost:8000/docs` (auto-generated by FastAPI)
- Review the database schema in `migrations/001_initial_schema.sql`
- Examine the question tree config in `config/bathroom_questions.yaml`

## License

(Add your license here)
