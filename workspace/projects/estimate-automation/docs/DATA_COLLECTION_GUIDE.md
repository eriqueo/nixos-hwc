# Data Collection Guide

This guide will help you gather all the information needed to populate your estimate automation system.

## Overview

You need to collect four types of data:
1. **Material Costs** - What you pay suppliers
2. **Labor Rates** - What you pay workers/subs
3. **Assemblies** - How you typically bundle work
4. **Markup Rules** - Your pricing strategy

## 1. Material Costs

### Where to Find This Information

- Recent invoices from suppliers
- Current price lists
- Online supplier catalogs
- Your purchasing records

### What You Need for Each Material

| Field | Description | Example |
|-------|-------------|---------|
| **Code** | Your internal code | LBR-2X4-8 |
| **Name** | What you call it | 2x4x8 Stud |
| **Category** | Material type | Lumber |
| **Subcategory** | More specific | Dimensional |
| **Unit** | How you buy it | each, sq_ft, linear_ft |
| **Base Cost** | What you pay | $4.50 |
| **Current Price** | Latest price | $4.75 |
| **Waste Factor** | Expected waste % | 0.15 (15%) |

### Material Categories to Collect

#### Lumber (if you do framing/decking)
- [ ] 2x4 studs (8', 10', 12' lengths)
- [ ] 2x6 joists (8', 10', 12' lengths)
- [ ] 2x8, 2x10, 2x12 (various lengths)
- [ ] 4x4 posts (various lengths)
- [ ] Pressure-treated lumber
- [ ] Plywood (1/2", 3/4")
- [ ] OSB sheathing

#### Bathroom Materials
- [ ] Toilets (basic, mid-range, premium)
- [ ] Vanities (24", 36", 48", 60")
- [ ] Sinks and faucets
- [ ] Tubs and shower pans
- [ ] Tile (floor and wall)
- [ ] Grout and thinset
- [ ] Cement board
- [ ] Plumbing fixtures
- [ ] Lighting and ventilation

#### Decking Materials
- [ ] Deck boards (PT, composite, cedar)
- [ ] Deck screws and fasteners
- [ ] Joist hangers
- [ ] Post anchors
- [ ] Railing systems
- [ ] Concrete for footings

#### Siding Materials
- [ ] Siding (vinyl, fiber cement, wood)
- [ ] House wrap
- [ ] Trim boards
- [ ] J-channel, corner posts
- [ ] Soffit and fascia

#### Common Materials
- [ ] Drywall (1/2", 5/8")
- [ ] Joint compound
- [ ] Paint (primer and finish)
- [ ] Nails and screws
- [ ] Caulk and adhesives

### Data Collection Worksheet: Materials

Create a spreadsheet with these columns and fill in for each material you use:

```
Code | Name | Category | Unit | Your Cost | Waste % | Notes
-----|------|----------|------|-----------|---------|------
     |      |          |      |           |         |
```

**Tips:**
- Start with your most common materials
- Check 2-3 recent invoices for accurate pricing
- Include seasonal price variations in notes
- Note which supplier you use

## 2. Labor Rates

### Where to Find This Information

- Payroll records
- Subcontractor agreements
- Worker's comp classifications
- Industry standards for your area

### What You Need for Each Labor Category

| Field | Description | Example |
|-------|-------------|---------|
| **Code** | Your internal code | CARP-FRAMING |
| **Name** | Job title | Framing Carpenter |
| **Trade** | Trade type | Carpentry |
| **Skill Level** | Experience level | Journeyman |
| **Hourly Rate** | What you pay | $45.00/hr |
| **Burden Rate** | Benefits/taxes % | 0.30 (30%) |

### Understanding Burden Rate

The burden rate covers costs beyond wages:

**Include in burden calculation:**
- Payroll taxes (FICA, unemployment): ~10-12%
- Worker's compensation insurance: varies by trade (5-30%)
- Health insurance/benefits: varies
- Paid time off: ~4-8%
- Vehicle/tool allowances
- Training and certifications

**Example calculation:**
```
Base wage: $45/hr
Payroll taxes (11%): $4.95/hr
Workers comp (8%): $3.60/hr
Benefits (7%): $3.15/hr
PTO (4%): $1.80/hr
Total burden: $13.50/hr (30% of base)

Your total cost: $58.50/hr
```

### Labor Categories to Collect

#### Carpentry
- [ ] Framing carpenter ($/hr, burden %)
- [ ] Finish carpenter ($/hr, burden %)
- [ ] General carpenter ($/hr, burden %)
- [ ] Carpenter helper ($/hr, burden %)

#### Plumbing
- [ ] Master plumber ($/hr, burden %)
- [ ] Journeyman plumber ($/hr, burden %)
- [ ] Plumbing helper ($/hr, burden %)

#### Electrical
- [ ] Master electrician ($/hr, burden %)
- [ ] Journeyman electrician ($/hr, burden %)
- [ ] Electrical helper ($/hr, burden %)

#### Other Trades
- [ ] Drywall installer ($/hr, burden %)
- [ ] Drywall finisher ($/hr, burden %)
- [ ] Painter ($/hr, burden %)
- [ ] Tile setter ($/hr, burden %)
- [ ] HVAC technician ($/hr, burden %)
- [ ] Siding installer ($/hr, burden %)
- [ ] Demo laborer ($/hr, burden %)
- [ ] General laborer ($/hr, burden %)

### Data Collection Worksheet: Labor

```
Code | Name | Trade | Skill | $/hr | Burden % | Total $/hr | Notes
-----|------|-------|-------|------|----------|------------|------
     |      |       |       |      |          |            |
```

**Tips:**
- Use your actual costs, not what you bill
- Check workers comp classifications
- Review last year's payroll + burden costs
- Consider if you use W2 employees or 1099 subs
- 1099 subs: lower burden (no payroll taxes)
- W2 employees: higher burden (all taxes/insurance)

## 3. Assembly Definitions

Assemblies save time by bundling common tasks.

### Common Bathroom Assemblies

For each assembly, define:
- Materials needed (with quantities)
- Labor hours required (by trade)

#### Example: Standard Bathroom Demo
**Materials:**
- Dumpster rental: 0.25 share (if shared across job)

**Labor:**
- Demo laborer: 12 hours

**How to determine hours:**
- Review past jobs
- Time your crews
- Ask experienced workers
- Start conservative, adjust later

### Bathroom Assembly Checklist

- [ ] **Demo** - Full bathroom demo
  - Labor hours: ___ hrs (demo laborer)

- [ ] **Rough Plumbing** - Toilet, sink, tub/shower
  - Materials: PEX, fittings, valves
  - Labor hours: ___ hrs (plumber), ___ hrs (helper)

- [ ] **Rough Electrical** - Lights, fan, outlets
  - Materials: wire, boxes, devices
  - Labor hours: ___ hrs (electrician)

- [ ] **Vanity Install (36")** - Cabinet, top, sink, faucet
  - Materials: vanity, sink, faucet
  - Labor hours: ___ hrs (carpenter), ___ hrs (plumber)

- [ ] **Toilet Install**
  - Materials: toilet, wax ring, supply line
  - Labor hours: ___ hrs (plumber)

- [ ] **Tub/Shower Install**
  - Materials: tub or shower pan
  - Labor hours: ___ hrs (plumber), ___ hrs (carpenter)

- [ ] **Floor Tile** (per sq ft)
  - Materials: cement board, tile, thinset, grout
  - Labor hours: ___ hrs per sq ft (tile setter)

- [ ] **Wall Tile** (per sq ft)
  - Materials: cement board, tile, thinset, grout
  - Labor hours: ___ hrs per sq ft (tile setter)

### Deck Assembly Checklist

- [ ] **Deck Framing** (per sq ft)
  - Materials: varies by design
  - Labor hours: ___ hrs per sq ft (framer + helper)

- [ ] **Deck Surface - PT** (per sq ft)
  - Materials: PT boards, screws
  - Labor hours: ___ hrs per sq ft (carpenter)

- [ ] **Deck Surface - Composite** (per sq ft)
  - Materials: composite boards, fasteners
  - Labor hours: ___ hrs per sq ft (carpenter)

- [ ] **Deck Railing** (per linear ft)
  - Materials: rail kit
  - Labor hours: ___ hrs per linear ft (carpenter)

- [ ] **Post Footing** (per post)
  - Materials: concrete, post anchor
  - Labor hours: ___ hrs (concrete finisher)

### Siding Assembly Checklist

- [ ] **Vinyl Siding Install** (per sq ft)
  - Materials: house wrap, siding
  - Labor hours: ___ hrs per sq ft (siding installer)

- [ ] **Fiber Cement Install** (per sq ft)
  - Materials: house wrap, siding
  - Labor hours: ___ hrs per sq ft (siding installer)

- [ ] **Siding Removal** (per sq ft)
  - Labor hours: ___ hrs per sq ft (demo laborer)

### Data Collection Worksheet: Assemblies

For each assembly you want to create:

```
Assembly Name: ________________________________

Materials Needed:
1. Material: ______________ Qty: ____ Unit: ____
2. Material: ______________ Qty: ____ Unit: ____
3. Material: ______________ Qty: ____ Unit: ____

Labor Needed:
1. Trade: _________________ Hours: ____ per ____
2. Trade: _________________ Hours: ____ per ____

Notes: ________________________________________
```

## 4. Markup Rules

This is your pricing strategy - how you convert costs into prices.

### Questions to Answer

#### Material Markup
**What percentage markup do you typically add to materials?**
- Industry standard: 15-35%
- Small items (fasteners, caulk): higher markup (30-50%)
- Large items (cabinets, appliances): lower markup (15-25%)

Your typical material markup: ____%

#### Labor Markup
**What percentage markup do you add to labor (beyond burden)?**
- Industry standard: 10-20%
- Remember: burden is already included in labor cost
- This markup covers office overhead and profit on labor

Your typical labor markup: ____%

#### Overhead
**What percentage of each job covers general overhead?**
- Office rent, utilities
- Office staff salaries
- Insurance (general liability, etc.)
- Vehicles, tools, equipment
- Marketing and advertising
- Software and subscriptions
- Industry standard: 8-15%

Your overhead percentage: ____%

#### Profit
**What profit margin do you target?**
- Net profit after all costs
- Industry standard: 10-20%
- May vary by job type or size

Your target profit: ____%

### Example Pricing Calculation

Let's price a job with these numbers:

**Costs:**
- Materials: $5,000
- Labor: $3,000 (already includes burden)

**Your Markups:**
- Material markup: 25%
- Labor markup: 15%
- Overhead: 10%
- Profit: 15%

**Calculation:**
```
Materials: $5,000
  + Material markup (25%): $1,250
  = Material subtotal: $6,250

Labor: $3,000
  + Labor markup (15%): $450
  = Labor subtotal: $3,450

Combined subtotal: $9,700

Overhead (10% of subtotal): $970
  = Subtotal after overhead: $10,670

Profit (15% of subtotal): $1,600
  = FINAL PRICE: $12,270
```

**Breakdown:**
- Customer pays: $12,270
- Your costs: $8,000 (materials + labor)
- Gross profit: $4,270 (35%)
- Overhead: $970
- Net profit: $3,300 (27% of costs, 15% of price)

### Data Collection Worksheet: Markup Rules

```
Rule Name: __________________ (e.g., "Default" or "Bathroom Jobs")
Job Type: ___________________ (leave blank for default)

Material Markup: _____%
Labor Markup: _____%
Overhead: _____%
Profit: _____%

Minimum job total: $_____
Minimum profit margin: $_____

Notes: ________________________________________
```

Create separate rules for:
- [ ] Default (all jobs)
- [ ] Bathroom remodels
- [ ] Deck construction
- [ ] Siding jobs
- [ ] Small jobs (under $5k)
- [ ] Large jobs (over $50k)

## Data Collection Action Plan

### Week 1: Gather Materials Data
- [ ] Pull invoices from last 3 months
- [ ] List all materials you commonly use
- [ ] Record current prices
- [ ] Estimate waste factors
- [ ] Enter into `materials_template.csv`

### Week 2: Gather Labor Data
- [ ] Review payroll records
- [ ] Calculate burden rates
- [ ] List all trades/skill levels you use
- [ ] Determine hourly costs
- [ ] Enter into `labor_template.csv`

### Week 3: Define Assemblies
- [ ] Review past estimates
- [ ] Identify common task bundles
- [ ] Time typical tasks or ask crews
- [ ] List materials per assembly
- [ ] Calculate labor hours per assembly
- [ ] Enter into `assemblies_template.json`

### Week 4: Set Markup Rules
- [ ] Review last year's P&L
- [ ] Calculate actual overhead %
- [ ] Determine target profit margins
- [ ] Create job-type specific rules
- [ ] Enter into `markup_rules_template.csv`

## Tips for Accuracy

### Materials
✅ Use recent invoices (prices change!)
✅ Include delivery fees in cost
✅ Account for bulk discounts
✅ Note seasonal price variations
❌ Don't use retail prices
❌ Don't forget small items (screws, caulk)

### Labor
✅ Include ALL burden costs
✅ Use actual payroll data
✅ Consider productivity differences
✅ Account for travel time if applicable
❌ Don't use billing rates
❌ Don't forget helpers/assistants

### Assemblies
✅ Base on real job data
✅ Include setup and cleanup time
✅ Account for complexity variations
✅ Start conservative, adjust later
❌ Don't underestimate time
❌ Don't forget small materials

### Markups
✅ Review annually
✅ Track actual vs. estimated
✅ Adjust based on results
✅ Consider market competition
❌ Don't race to bottom
❌ Don't forget overhead

## Getting Help

If you're unsure about any values:

1. **Materials**: Call your supplier for current pricing
2. **Labor**: Check industry standard rates for your area
3. **Burden**: Consult your accountant
4. **Markups**: Review last year's profit margins
5. **Assemblies**: Time a few jobs to get baselines

## Next Steps

Once you've collected this data:

1. Fill in the template CSV/JSON files
2. Import into the system
3. Create a test estimate
4. Compare to your manual estimates
5. Adjust as needed

Remember: This system is only as accurate as the data you put in. Take time to get it right!

---

**Questions or need help?** Review the main README.md for detailed instructions on using the templates.
