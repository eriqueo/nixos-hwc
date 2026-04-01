# Heartwood Craft — Business Operating System
## Living Reference Document

**Owner:** Eric | **Location:** Bozeman, MT | **Entity:** Single-member LLC
**Business:** Bathroom remodels, decks, custom carpentry | **Revenue target:** $150K
**Last updated:** March 20, 2026

---

## Business snapshot

- ~1 lead/month (as of March 2026, working to fix this)
- 26 total JT jobs, mostly repeat customers (Overbrook 5x, Ray Ring 3x)
- Good margins per job (~30%), not enough jobs for consistent cash flow
- QuickBooks + JobTread (Stripe) for payments, no bookkeeper
- Website: iheartwoodcraft.com (WordPress, agency-built, SEO-optimized, Eric getting admin access)
- Portfolio page exists but is empty (critical conversion gap)
- Eric does real 3D renderings — key differentiator, not yet monetized
- LSA running at $210/week as of March 2026
- Facebook ads paused (zero leads after $1,500+ spent)
- Joined Bozeman Chamber of Commerce
- NixOS homeserver running n8n, Caddy, Tailscale, various services

---

## Infrastructure stack

| System | Role |
|--------|------|
| JobTread | CRM, project management, budgets, invoicing, customer portal |
| QuickBooks | Accounting, tax reporting, expense tracking |
| Stripe | Payment processing (via JT portal) |
| n8n | Automation hub (webhooks, JT API, Slack, Postgres) |
| NixOS homeserver | Hosts all self-hosted services via Caddy + Tailscale |
| SQLite / Postgres | Local data storage (catalog, estimates, project state) |
| Slack | Notifications from n8n automations |
| Google LSA | Primary paid lead channel |
| Google Business Profile | Organic visibility + LSA ranking driver |

---

## System 1: Estimate assembler

### Architecture
```
Project State (measurements + conditions + selections)
  → Assembly Engine (trigger evaluation + quantity derivation)
    → Priced Line Items (canonical names + JT-compatible)
      → Push to JT (via n8n webhook)
      → Archive to Postgres
      → Slack notification
```

### Key decisions
- **Pipe-delimited naming:** `Labor | Trade | Task`, `Material | Trade | Item`, `Allowance | Category`
- **Per-trade wage × burden model:** $35 base × 1.35 burden = $47.25 cost × 2.0 markup = $94.50 price
- **Condition triggers:** every catalog item has a boolean condition that determines inclusion
- **Quantity drivers:** formulas derive quantities from project state (e.g., floor_sqft × 0.25 = tile labor hours)
- **Allowances** for undecided selections (client picks tile later, budget holds $1,500)
- **Assembly engine is pure functions** — no React dependencies, reusable across internal app and public calculator

### Catalog
- 62 canonical bathroom items in SQLite database
- 31 state keys (measurements, conditions, counts, selections, constraints)
- All JT reference IDs baked in (cost codes, cost types, units, custom fields)
- Source column distinguishes `heartwood` (field-validated) vs `craftsman` (reference data, future)

### JT reference IDs
- Cost codes: Planning=22Nm3uGRAMmH, Demo=22Nm3uGRAMmJ, Framing=22Nm3uGRAMmN, Electrical=22Nm3uGRAMmS, Plumbing=22Nm3uGRAMmT, Drywall=22Nm3uGRAMmW, Tiling=22Nm3uGRAMma, Cabinetry=22Nm3uGRAMmb, Painting=22Nm3uGRAMmf, Appliances=22Nm3uGRAMmg, Furnishings=22Nm3uGRAMmn, Misc=22Nm3uGRAMmp
- Cost types: Admin=22PJuNqewZmV, Labor=22Nm3uGRAMmq, Materials=22Nm3uGRAMmr, Other=22Nm3uGRAMmt, Selections=22PQ4KZExZjP, Sub=22Nm3uGRAMms
- Units: Hours=22Nm3uGRAMm9, Each=22Nm3uGRAMm7, Gallons=22Nm3uGRAMm8, Lump Sum=22Nm3uGRAMmB, SqFt=22Nm3uGRAMmD, LinFt=22Nm3uGRAMmA
- Job custom fields: Job Type=22P4fgU4XmLY, Phase=22P4fguBu3Ub
- Customer custom fields: Source=22PU427xzLaS, Status=22Nnj9KwwePZ, Project Type=22Nnj9KMKEPC, Lead Lost Reason=22Nnj9Kk4CLH, Referred By=22Nnj9KfuSgp, Appointment=22NnjWw3NTGc

### Deployment
- React app (v2) deployed on NixOS homeserver as PWA via Caddy + Tailscale
- Accessible from phone, laptop, iPad across Tailnet
- Test budget pushed to Master Bathrooms job #281 (61 items, verified)

### n8n integration
- Workflow 08a: JT Data Provider — GET customers/jobs for app dropdowns
- Workflow 08b: Estimate Router — POST estimate-push with validation, JT push, Postgres archive, Slack notification
- Duplicate push prevention: Postgres pre-check before JT push, confirmation dialog if job already has items
- API key authentication on all webhooks

### To-do
- [ ] Calibrate production rates from real job hour data (Dempsey/Hendrix/Margulies/Jaclyn)
- [ ] Wire n8n webhook for dual-push to JT + local DB
- [ ] Add Craftsman National Estimator data for non-bathroom jobs
- [ ] Expand toggle trees for deck/kitchen/general
- [ ] Build public website cost calculator (lead magnet — see System 5)

---

## System 2: Client journey funnel

### Structure
7 stages, each modeled as a decision tree with specific goals, branching questions, and tagged deliverables.

### Stages
1. **Attract** — generate inbound contact. Channels: LSA, GBP, referrals, PM outreach, print, website calculator. Goal: 4-6 leads/month.
2. **Qualify** — 5-15 min phone call. 4 questions (scope, timing, other quotes, budget). Identify entry type, determine fit. Goal: 70%+ → site visit.
3. **Discover** — 45-90 min site visit. All entry types converge. Structured: Connect → Listen → Assess → Educate → Set Expectations → Photos. Captures complete project state for estimator. Goal: 90%+ → estimate.
4. **Propose** — assemble estimate via app (<30 min), present in person/call (never just email), follow-up cadence (Day 3/7/14/21). Goal: 30-50% close rate.
5. **Deliver** — pre-con meeting, daily photo+text updates, milestone invoicing (30/20/40/10), formal change orders only. Goal: on-time, on-budget.
6. **Close** — final walkthrough, punch list within 48 hrs, final payment, post-project package (warranty, care, cards, thank-you note). Goal: 100% collected.
7. **Multiply** — automated: Day 1 review request, Day 14 referral ask, Day 30 GBP content, 6-month check-in, 1-year anniversary. Goal: 1 review + 0.5 referrals per job. Output feeds Stage 1.

### Five client entry types
- **A: Emergency** — leak/damage/broke. Empathy first, schedule 24-48 hrs. Repairs → full remodels.
- **B: Dreamer** — Pinterest boards, years planning. Be the guide. Ask for board before visit. Highest budgets.
- **C: Pain point** — "I hate my bathtub." Validate, expand scope on site. Hidden scope surfaces.
- **D: Designer-led** — has specs/drawings. Make designers look good. Clear scope, referral channel.
- **E: Property manager** — manages properties. Lead with process/reliability. 1 PM = 3-5 jobs/yr.

### Resource gates
- **Design resource gate:** if client needs design help but has no designer → route to partner designer or offer paid 3D visualization ($500-1,000 credited toward project). Do NOT do free design work before contract. This protects Eric's time (historically a major time/money sink).

### Deliverable tagging
Every stage output is tagged by downstream destination: Estimator, JT, Marketing, Next Stage, or Data. Ensures no information gets lost between stages.

### JT phase mapping
Contacted → Visited → Budgeting → Budget Sent → Budget Approved → Work Start → First Milestone → Second Milestone → Final Milestone

---

## System 3: Financial operations

### Key numbers (from real JT data — Dempsey #257)
- $31,542 cost / $44,825 price / 29.6% margin / 97 line items
- Cost breakdown: 25% labor, 15% fixed materials, 41% selections, 18% allowances, 2% other
- Target margin: 30% minimum (43% markup on cost)
- Estimated annual overhead: ~$27K
- Break-even: $90K revenue. At $150K target: ~$18K owner's take after overhead and taxes.

### Payment milestone structure
- 30% deposit at signing (must cover all material orders + 1-2 weeks labor)
- 20% at rough-in complete
- 40% at substantial completion
- 10% at final walkthrough

### Cash flow buffer rule
Maintain $10K minimum in business account at all times.

### Tax obligations (MT single-member LLC)
- Self-employment tax: 15.3%
- Federal income: 10-22% bracket
- Montana state: 4.7-6.75%
- Quarterly estimated payments (April 15, June 15, Sept 15, Jan 15)
- Rule: set aside 30% of net profit into separate savings for taxes

### QB + JT + Stripe workflow
- JT: estimates, budgets, invoicing (source of truth for project cost)
- Stripe: payment collection via JT portal
- QB: accounting, taxes, expense tracking, bank reconciliation, P&L

### Hiring threshold
Hire when: booked 2+ months ahead, turning away 1+ leads/month, $20K+ buffer, trailing 6-month revenue $20K+/month. An employee costs $62-80K fully loaded, requires $233K additional revenue at 30% margin to break even.

### 3D renderings as revenue
- Paid pre-construction service: $500-1,000
- Credited toward project if client signs
- Client keeps renderings if they choose another contractor
- Addresses the design resource gate problem
- Every rendering becomes portfolio content

---

## System 4: Marketing operations

### Website audit (iheartwoodcraft.com)
- **Working:** SEO structure (location + service pages), reviews widget, contact form, professional branding, 3D renderings mentioned in copy
- **Broken/missing:** Portfolio page empty (biggest conversion killer), 3D capability buried in paragraph text, contact form may not be connected to Eric, no analytics, blog likely empty
- **Priority fix:** Get WordPress admin access, upload 3-4 project galleries, add 3D rendering showcase to homepage, install GA4 + Search Console, verify form submissions reach Eric

### Channel priority (20% that does 80%)
1. **Google LSA** ($840/mo, 2-5 leads/mo) — CRITICAL, running now
2. **Google Business Profile** ($0, 1-2 leads/mo) — CRITICAL, post 1 photo/week
3. **Referral system** ($50-100/mo, 0.5-1 leads/mo) — CRITICAL, automated via JT tasks
4. **PM outreach** ($0, 0.5-1 leads/mo) — HIGH, 5 emails/week from target list
5. **Website portfolio** ($0, indirect) — HIGH, fill the empty page
6. Everything else — MEDIUM to LOW

### Advertising funnel (how channels map to buyer awareness)
Unaware (door hangers/signs) → Problem-aware (social/GBP posts) → Solution-aware (website/blog/SEO) → Provider-aware (LSA/GBP reviews) → Ready to act (LSA/form/referral → Stage 1)

### Content system
- Capture per job: before photo, progress photo, detail photo, after photo, 3D rendering if applicable
- Post 1 photo/week to GBP (Monday morning block)
- Upload galleries to website after each project
- Cross-post to Instagram/Facebook when ready (not priority)
- 3D render + completed photo = highest-value unique content

### Monthly marketing budget: $920-1,070
- LSA: $840, Referral gifts: $50-100, Print: $50-100, Chamber: $30, Everything else: $0
- Expected: 4-8 leads/month at full maturity
- ROI: $500-715 marketing cost per closed $30K job

---

## System 5: Public bathroom cost calculator (lead magnet)

### Purpose
Simplified version of the estimate assembler hosted on iheartwoodcraft.com. Visitors configure their project through 7 questions, see a ballpark price range, and submit contact info. Creates a pre-qualified lead with structured scope data.

### 7 questions
1. Project type (full gut / refresh / tub-to-shower / specific fix)
2. Bathroom size (small / medium / large / XL)
3. Shower/tub configuration
4. Tile level (basic / mid / high)
5. Fixture level (standard / upgraded / premium)
6. Special features (multi-select: heated floor, niches, bench, double vanity, lighting, ventilation)
7. Timeline (ASAP / 1-3 months / 3-6 months / exploring)

### What Eric receives on submission
Slack notification with: name, phone, email, full project configuration, ballpark range, timeline. Half of Stage 2 and Stage 3 data captured before the phone call.

### n8n webhook flow
Form submit → n8n webhook → create JT customer (Source: Website Calculator) → create JT contact → create JT job (Phase 1, Type: Bathroom) → Slack notification → Postgres archive

### Pricing engine
Base ranges from real job data, multiplied by size, adjusted for config, plus feature adds. Ranges intentionally conservative (better to surprise low than overpromise).

---

## System 6: n8n automation stack

### Deployed/planned workflows
| # | Name | Status | Trigger | Action |
|---|------|--------|---------|--------|
| 08a | JT Data Provider | Built | GET webhook | Fetch JT customers/jobs for app dropdowns |
| 08b | Estimate Router | Built | POST webhook | Validate → push to JT + Postgres + Slack |
| 09 | Calculator Lead | Planned | POST webhook | Create JT customer/job + Slack notification |
| 10 | Lead Response SMS | Planned | New JT customer | Twilio SMS: "Got your message, calling within 1 hour" |
| 11 | Follow-Up Reminders | Planned | Cron/JT monitor | Slack alert when lead stale 7+ days |

---

## JT dashboards (live)

1. **Sales Pipeline & Lead Tracker** (id:22PU2MtJJiM7) — job-level: open jobs, monthly jobs, revenue, margin, pipeline detail
2. **Lead Source & Conversion Tracker** (id:22PU7MUwuq3A) — customer-level: leads by source (pie), leads by status (bar), lost reasons (bar), project types (pie), LSA/referral counts

---

## STR property manager targets (Bozeman)

10 researched: The Arrival Co, Mountain Home Montana, Bozeman MT Vacation Rentals (Reno), Above & Beyond, Best Bozeman PM, Platinum PM, BPM, Connect PM, Peak Property, Awning. Tracked in outreach spreadsheet with outreach log and review request tracker (13 past customers pre-loaded).

---

## Weekly operating rhythm

### Monday Morning block (30 min, recurring)
1. Pipeline review in JT dashboard (5 min)
2. Follow-up texts to stale leads (5 min)
3. Review check — any completed jobs? Send request (3 min)
4. GBP photo post (2 min)
5. 2-3 PM outreach emails (10 min)
6. LSA dashboard check (5 min)
7. Money check: Stripe cleared? Expenses logged in QB? Buffer above $10K? (added from financial system)

---

## Deliverables index

| File | Type | Contents |
|------|------|----------|
| heartwood_jt_analysis.xlsx | Spreadsheet | 6-tab cross-job pattern analysis |
| heartwood_bathroom_catalog.xlsx | Spreadsheet | 60 canonical items + state input template |
| heartwood_catalog.db | SQLite | 10 tables, 62 items, 31 state keys, all JT IDs |
| heartwood-estimate-assembler.jsx | React | v1 estimator app |
| heartwood-assembler-v2.jsx | React | v2 with toggle tree, per-trade rates, 3-tab flow |
| heartwood_growth_playbook.docx | Word | 8-section lead gen + sales manual |
| heartwood_outreach_tracker.xlsx | Spreadsheet | PM targets, outreach log, review tracker |
| heartwood_client_journey.docx | Word | 7-stage process map with scripts |
| heartwood_journey_v3.html | HTML | Interactive funnel with clickable stages + entry types |
| heartwood_funnel_print.pdf | PDF | 7-page landscape printable (goals → flow → deliverables) |
| heartwood_financial_operations.docx | Word | Cash flow, pricing, QB/JT/Stripe workflow, taxes, hiring |
| heartwood_marketing_operations.docx | Word | Website audit, channels, content, LSA, GBP, social, budget |
| heartwood-bathroom-calculator.jsx | React | Public website cost calculator (lead magnet) |
| CLAUDE_CODE_TASK_deploy_assembler.md | Markdown | Deployment spec for estimator PWA |
| CLAUDE_CODE_TASK_calculator.md | Markdown | Deployment spec for website calculator |
| README.md | Markdown | System architecture, philosophy, data flow, roadmap |

---

## Changelog

### 2026-03-20 — Initial build session

**Estimating system:**
- Pulled and analyzed 4 bathroom budgets from JT (Dempsey, Hendrix, Margulies, Jaclyn)
- Built canonical bathroom catalog (62 items, pipe-delimited, condition-triggered)
- Created SQLite database with full schema and JT ID mappings
- Built React estimate assembler v1 and v2 (hierarchical toggle tree)
- Pushed test budget to JT job #281 (61 items, $19.2K cost / $31K price / 38% margin)
- Created Claude Code deployment task file
- App deployed on homeserver via Tailscale/Caddy

**n8n integration:**
- Reviewed workflow 08a (JT data provider) and 08b (estimate router) built by other Claude instance
- Provided corrections: GraphQL (not REST), Postgres should store project state, Phase field filtering on dropdowns, error handling for JT push failures, API key auth, duplicate push prevention
- Implementation completed by other Claude instance

**Lead generation & marketing:**
- Created business growth playbook (Word doc, 8 sections)
- Created STR PM outreach tracker with 10 Bozeman PMs researched
- Created JT Sales Pipeline dashboard (live)
- Created JT Lead Source & Conversion dashboard (live)
- Walked through LSA setup (service types, area, budget, photos, response rules)
- Eric: texted 13 past customers for reviews, paused Facebook ads, LSA running at $210/week

**Client journey funnel:**
- Mapped 7 stages with goals, decision trees, and tagged deliverables
- Identified 5 client entry types (Emergency, Dreamer, Pain Point, Designer-Led, PM)
- Identified design resource gate (prevent unpaid design work pre-contract)
- Built interactive HTML version (v3) with clickable stages and entry types
- Built 7-page landscape PDF (printable, one stage per page)
- Built Word doc version with scripts and intent

**Financial operations system:**
- Built from real JT data (Dempsey #257: $31.5K cost / $44.8K price / 29.6% margin)
- Revenue target math at $100K/$150K/$250K levels
- Cash flow timeline for typical $35K bathroom remodel
- Payment milestone structure (30/20/40/10)
- Markup vs margin conversion table and rate card
- QB + JT + Stripe workflow documented
- Overhead analysis (~$27K/year) and break-even ($90K)
- Montana single-member LLC tax obligations and quarterly schedule
- Hiring threshold math ($233K additional revenue to fund one employee)
- 3D renderings as paid pre-construction service ($500-1,000)

**Marketing operations system:**
- Full website audit of iheartwoodcraft.com (working: SEO, reviews, form, branding; broken: empty portfolio, buried 3D capability, form connectivity, no analytics)
- Steps to get WordPress admin access from agency
- Channel strategy ranked by effort-to-results (LSA + GBP + referrals = 80% of results)
- Content capture system (4 photos per job + where each goes)
- Advertising funnel mapping channels to buyer awareness stages
- LSA optimization guide (ranking factors, lead processing, monthly review)
- GBP optimization checklist (one-time + weekly)
- Social media minimum viable plan (when ready)
- Monthly budget: $920-1,070 for expected 4-8 leads/month

**Public bathroom cost calculator:**
- Built React component with 7 funnel-style questions
- Pricing engine calibrated from real job data
- Lead capture form with n8n webhook integration
- Claude Code deployment task file with 3 hosting options
- Maps calculator fields to client journey funnel stages

**Actions completed by Eric during session:**
- ✅ Texted past customers for Google reviews
- ✅ Paused Facebook ads (No Excuses Media)
- ✅ LSA running at $210/week
- ✅ Source field added to JT customer accounts
- ✅ Estimator app deployed on homeserver

---

*To append: add new entries below the last changelog entry with date and summary of decisions, deliverables, and actions.*
