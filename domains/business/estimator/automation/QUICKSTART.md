# Quick Start Guide

Get up and running with the Estimate Automation System in 30 minutes.

## Prerequisites

- Python 3.11+ installed
- Basic command line knowledge
- Your pricing data ready

## Step 1: Install (5 minutes)

```bash
# Navigate to project
cd workspace/projects/estimate-automation

# Install dependencies with Poetry
poetry install

# Or with pip
python3 -m venv venv
source venv/bin/activate
pip install -e .

# Activate environment
poetry shell  # if using Poetry
```

## Step 2: Initialize Database (2 minutes)

```bash
# Copy environment template
cp .env.example .env

# Initialize SQLite database (default)
estimate init

# You should see: "✓ Database initialized successfully!"
```

## Step 3: Customize Your Data (15 minutes)

### Quick Path - Use Templates As-Is

The templates include realistic example data. You can start with these and refine later:

```bash
# Import example materials
estimate import materials data/materials_template.csv

# Import example labor rates
estimate import labor data/labor_template.csv

# Import example assemblies
estimate import assemblies data/assemblies_template.json

# Import markup rules
estimate import markups data/markup_rules_template.csv
```

### Better Path - Customize First

1. Open `data/materials_template.csv` in Excel/Sheets
2. Update prices to match YOUR costs
3. Open `data/labor_template.csv`
4. Update hourly rates to match YOUR labor costs
5. Save both files
6. Import (commands above)

**See `docs/DATA_COLLECTION_GUIDE.md` for detailed help**

## Step 4: Create Your First Estimate (5 minutes)

```bash
# Create a bathroom estimate
estimate estimate create bathroom \
  --client "Test Customer" \
  --length 8 \
  --width 10 \
  --fixtures-quality mid \
  --demo yes

# You should see: "Creating bathroom estimate for Test Customer"
```

## Step 5: View and Export (3 minutes)

```bash
# List all estimates
estimate estimate list

# View estimate details
estimate estimate show 1

# Export to JobTread CSV
estimate estimate export 1 --format jobtread --output ./exports/
```

## Next Steps

### Refine Your Data

1. Review first estimate accuracy
2. Compare to your manual estimates
3. Adjust material costs if needed
4. Adjust labor hours in assemblies
5. Update markup percentages

### Add More Assemblies

Create assemblies for your common tasks:
- Standard bathroom layouts
- Common deck sizes
- Typical siding jobs

### Create Templates

Save job templates for recurring estimates:
- 8x10 bathroom remodel
- 12x16 deck
- Full house siding

## Troubleshooting

**Import fails:**
```bash
# Check CSV format
head data/materials_template.csv

# Verify file path
ls -la data/
```

**Database errors:**
```bash
# Reset database
rm estimate_automation.db
estimate init
```

**Command not found:**
```bash
# Make sure you're in the virtual environment
poetry shell  # or: source venv/bin/activate

# Check installation
pip list | grep estimate
```

## Common Commands

```bash
# List materials
estimate materials list

# Add material interactively
estimate materials add

# List labor categories
estimate labor list

# Show estimate
estimate estimate show <id>

# Export estimate
estimate estimate export <id> -f jobtread -o ./exports/

# Help
estimate --help
estimate estimate --help
```

## File Locations

- **Database**: `./estimate_automation.db` (SQLite)
- **Templates**: `./data/*_template.csv`
- **Exports**: `./exports/*.csv`
- **Config**: `./.env`

## Tips

1. **Start Simple**: Use example data, create test estimates, refine
2. **Track Accuracy**: Compare to manual estimates, adjust
3. **Build Library**: Create assemblies for common tasks
4. **Update Regularly**: Review material costs quarterly
5. **Backup Data**: Export your database periodically

## Getting Help

- Main documentation: `README.md`
- Data collection help: `docs/DATA_COLLECTION_GUIDE.md`
- Project structure: See `README.md` → Project Structure

---

**Ready to build estimates faster? Start with Step 1!**
