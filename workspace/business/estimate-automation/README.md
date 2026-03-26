# Estimate Automation System

**Version:** 0.1.0
**Purpose:** Automated estimation system for remodeling business with JobTread integration

## Overview

This system provides a modular, robust backend for creating detailed remodeling estimates. It supports multiple job types (bathrooms, decks, siding, etc.) and generates CSV exports ready for JobTread import.

### Key Features

- **Modular Job Types**: Easily add new job types with specialized calculators
- **Assembly System**: Pre-configured bundles of materials and labor
- **Dynamic Pricing**: Configurable markups, overhead, and profit margins
- **Database-Driven**: All pricing stored in database for easy updates
- **CSV Export**: JobTread-compatible CSV output
- **CLI Interface**: Command-line tool for all operations

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    User Interface (CLI)                  │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│              Estimation Engine                           │
│  (Job Types → Assemblies → Materials + Labor)            │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│                   Database Layer                         │
│  Materials | Labor | Assemblies | Projects | Markups    │
└─────────────────────────────────────────────────────────┘
```

## Technology Stack

- **Language**: Python 3.11+
- **Framework**: FastAPI (API capability), Typer (CLI)
- **Database**: PostgreSQL (recommended) or SQLite (local development)
- **ORM**: SQLAlchemy 2.0
- **Validation**: Pydantic v2
- **CLI**: Typer + Rich (beautiful terminal output)
- **Export**: Pandas (CSV generation)

## Installation

### Prerequisites

- Python 3.11 or higher
- PostgreSQL (optional, can use SQLite)
- Poetry (recommended) or pip

### Setup with Poetry (Recommended)

```bash
# Install Poetry if you don't have it
curl -sSL https://install.python-poetry.org | python3 -

# Navigate to project directory
cd estimate-automation

# Install dependencies
poetry install

# Activate virtual environment
poetry shell
```

### Setup with pip

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt  # You'll need to generate this from pyproject.toml
```

### Database Setup

#### Option 1: SQLite (Simple, Local)

```bash
# Copy environment template
cp .env.example .env

# Edit .env to use SQLite (default)
# DATABASE_URL=sqlite:///./estimate_automation.db

# Initialize database
estimate init
```

#### Option 2: PostgreSQL (Production)

```bash
# Install PostgreSQL
# Ubuntu/Debian: sudo apt install postgresql postgresql-contrib
# macOS: brew install postgresql

# Create database and user
sudo -u postgres psql
CREATE DATABASE estimate_automation;
CREATE USER estimate_user WITH PASSWORD 'your_secure_password';
GRANT ALL PRIVILEGES ON DATABASE estimate_automation TO estimate_user;
\q

# Configure environment
cp .env.example .env
# Edit .env:
# DATABASE_URL=postgresql://estimate_user:your_secure_password@localhost:5432/estimate_automation

# Initialize database
estimate init
```

## Data Setup

### Understanding the Data Structure

The system uses four main data types:

1. **Materials**: Individual items with pricing (lumber, fixtures, etc.)
2. **Labor Categories**: Labor rates by trade and skill level
3. **Assemblies**: Pre-configured bundles of materials + labor
4. **Markup Rules**: Pricing calculations (overhead, profit, etc.)

### Data Templates

The `data/` directory contains template CSV/JSON files with examples:

- `materials_template.csv`: ~70 example materials
- `labor_template.csv`: ~27 labor categories
- `assemblies_template.json`: ~20 pre-configured assemblies
- `markup_rules_template.csv`: Standard markup configurations

### Customizing Your Data

#### 1. Materials (`data/materials_template.csv`)

**Required fields:**
- `code`: Unique identifier (e.g., "LBR-2X4-8")
- `name`: Display name
- `category`: Material category (Lumber, Bathroom, Decking, etc.)
- `unit`: Unit of measure (each, sq_ft, linear_ft, etc.)
- `base_cost`: Your cost per unit
- `current_price`: Current cost (for tracking price changes)
- `waste_factor`: Waste percentage (0.10 = 10%)

**Steps to customize:**

1. Open `data/materials_template.csv` in Excel or Google Sheets
2. Update prices to match your supplier costs
3. Add your specific materials following the same format
4. Remove materials you don't use
5. Save as CSV

**Example material entry:**
```csv
LBR-2X4-8,2x4x8 Stud,Standard framing stud,Lumber,Dimensional,each,4.50,4.75,0.15,true,true,Standard framing
```

#### 2. Labor Rates (`data/labor_template.csv`)

**Required fields:**
- `code`: Unique identifier (e.g., "CARP-FRAMING")
- `name`: Display name
- `trade`: Trade type (Carpentry, Plumbing, Electrical, etc.)
- `skill_level`: Skill level (Helper, Journeyman, Master)
- `hourly_rate`: Base hourly rate (your labor cost, not billed rate)
- `burden_rate`: Burden percentage (0.30 = 30% for taxes, insurance, benefits)

**Steps to customize:**

1. Open `data/labor_template.csv`
2. Update `hourly_rate` to match what you pay your workers/subcontractors
3. Update `burden_rate` based on your actual burden costs:
   - Workers comp insurance
   - Payroll taxes
   - Benefits
   - Equipment/truck costs
4. Add any specialized trades you use
5. Save as CSV

**Example labor entry:**
```csv
CARP-FRAMING,Framing Carpenter,Rough framing,Carpentry,Journeyman,45.00,0.30,1.5,true,Framing walls floors roofs
```

**Calculating total cost:** The system automatically calculates total hourly cost:
- Base rate: $45/hr
- Burden (30%): $13.50/hr
- **Total cost: $58.50/hr**
- Your markup is applied on top of this

#### 3. Assemblies (`data/assemblies_template.json`)

Assemblies are pre-configured bundles that make estimating faster. For example, "Standard Bathroom Demo" includes:
- Materials: dumpster rental share
- Labor: 12 hours of demo laborer

**Steps to customize:**

1. Open `data/assemblies_template.json`
2. Review each assembly for your typical jobs
3. Adjust quantities based on your experience
4. Add new assemblies for your common tasks

**Example assembly:**
```json
{
  "code": "BATH-VANITY-36-INSTALL",
  "name": "36\" Vanity Installation",
  "job_type": "bathroom",
  "unit": "each",
  "materials": [
    {"material_code": "BATH-VANITY-36", "quantity_per_unit": 1},
    {"material_code": "BATH-SINK-UNDERMOUNT", "quantity_per_unit": 1},
    {"material_code": "BATH-FAUCET-MID", "quantity_per_unit": 1}
  ],
  "labor": [
    {"labor_code": "CARP-FINISH", "hours_per_unit": 3.0},
    {"labor_code": "PLUMB-JOURNEY", "hours_per_unit": 2.0}
  ]
}
```

#### 4. Markup Rules (`data/markup_rules_template.csv`)

**Required fields:**
- `name`: Rule name
- `job_type`: Job type or blank for default
- `material_markup_percent`: Material markup (25.0 = 25%)
- `labor_markup_percent`: Labor markup
- `overhead_percent`: Overhead allocation
- `profit_percent`: Profit margin

**Steps to customize:**

1. Open `data/markup_rules_template.csv`
2. Set your default markups in the "Default Markup" row
3. Create job-type-specific markups if needed
4. **Important**: These percentages should cover:
   - Material markup: profit on materials
   - Labor markup: markup on labor (beyond burden rate)
   - Overhead: office, admin, insurance, etc.
   - Profit: final profit margin

**Example markup calculation:**
```
Material cost: $1000
Material markup (25%): $250
Subtotal: $1250

Labor cost: $500 (already includes burden)
Labor markup (15%): $75
Subtotal: $575

Combined subtotal: $1825
Overhead (10%): $182.50
Profit (15%): $273.75

TOTAL PRICE: $2281.25
```

### Importing Your Data

Once you've customized the templates:

```bash
# Import materials
estimate import materials data/materials_template.csv

# Import labor rates
estimate import labor data/labor_template.csv

# Import assemblies
estimate import assemblies data/assemblies_template.json

# Import markup rules
estimate import markups data/markup_rules_template.csv
```

## Usage

### Creating an Estimate

```bash
# Create a bathroom estimate
estimate estimate create bathroom \
  --client "John Smith" \
  --length 8 \
  --width 10 \
  --fixtures-quality mid \
  --demo yes

# Create a deck estimate
estimate estimate create deck \
  --client "Jane Doe" \
  --area 300 \
  --height 4 \
  --material composite

# Create a siding estimate
estimate estimate create siding \
  --client "Bob Johnson" \
  --area 1500 \
  --stories 2 \
  --material vinyl
```

### Managing Data

```bash
# List materials
estimate materials list
estimate materials list --category Lumber
estimate materials list --category Bathroom

# Add a material
estimate materials add

# List labor categories
estimate labor list
estimate labor list --trade Carpentry

# List estimates
estimate estimate list

# Export to JobTread CSV
estimate estimate export 12345 --format jobtread --output ./exports/
```

### Viewing Estimates

```bash
# Show estimate details
estimate estimate show 12345

# Show estimate with line items
estimate estimate show 12345 --detailed
```

## JobTread Integration

### CSV Export Format

The system exports estimates in JobTread-compatible CSV format with these columns:

- Item Code
- Description
- Quantity
- Unit
- Unit Cost
- Total Cost
- Category
- Subcategory

### Importing to JobTread

1. Generate CSV export:
   ```bash
   estimate estimate export 12345 --format jobtread -o ./exports/
   ```

2. In JobTread:
   - Navigate to Estimates
   - Click "Import"
   - Upload the generated CSV file
   - Map fields (if needed)
   - Import

## Project Structure

```
estimate-automation/
├── src/                         # Source code
│   ├── config/                  # Configuration, database setup
│   ├── models/                  # SQLAlchemy database models
│   ├── schemas/                 # Pydantic validation schemas
│   ├── repositories/            # Data access layer
│   ├── services/                # Business logic
│   ├── job_types/               # Modular job type handlers
│   │   ├── bathroom/
│   │   ├── deck/
│   │   └── siding/
│   ├── exporters/               # Export formatters (JobTread, Excel, etc.)
│   └── main.py                  # CLI entry point
├── data/                        # Data templates and seed data
├── exports/                     # Generated CSV files
├── migrations/                  # Database migrations
├── tests/                       # Unit and integration tests
└── docs/                        # Documentation
```

## Extending the System

### Adding a New Job Type

1. Create directory: `src/job_types/kitchen/`
2. Create handler: `src/job_types/kitchen/handler.py`
3. Define parameters: `src/job_types/kitchen/parameters.py`
4. Create assemblies: Add to `data/assemblies_template.json`
5. Register in CLI: Add command to `src/main.py`

### Adding a New Export Format

1. Create exporter: `src/exporters/quickbooks.py`
2. Implement `BaseExporter` interface
3. Register in CLI export command

## Development

### Running Tests

```bash
# Run all tests
pytest

# Run with coverage
pytest --cov=src

# Run specific test file
pytest tests/test_models/test_material.py
```

### Code Quality

```bash
# Format code
black src/

# Lint code
ruff check src/

# Type checking
mypy src/
```

## Troubleshooting

### Database Issues

**Error: "database does not exist"**
```bash
# Recreate database
sudo -u postgres psql
DROP DATABASE estimate_automation;
CREATE DATABASE estimate_automation;
\q
estimate init
```

**Error: "table already exists"**
```bash
# Reset database (WARNING: deletes all data)
estimate db reset
estimate init
```

### Import Issues

**Error: "material code already exists"**
- Update existing material instead of creating new one
- Or use unique codes in your CSV

**Error: "invalid CSV format"**
- Ensure CSV has header row
- Check for missing required fields
- Verify encoding is UTF-8

## Next Steps

### Phase 1: Initial Setup (Current)
- ✅ Project structure
- ✅ Database models
- ✅ Data templates
- ⏳ Data import tools
- ⏳ Basic CLI commands

### Phase 2: Estimation Engine
- Calculation service
- Job type handlers
- Assembly processing
- Pricing calculations

### Phase 3: Export System
- JobTread CSV formatter
- Field mapping
- Validation

### Phase 4: Additional Features
- Web UI (optional)
- Additional job types
- Advanced reporting
- Historical pricing

## Support

For issues or questions:
1. Check this README
2. Review data templates
3. Check error messages carefully
4. Verify database connection

## License

Proprietary - Internal use only

---

**Created:** 2025-11-21
**Author:** Eric with AI assistance
