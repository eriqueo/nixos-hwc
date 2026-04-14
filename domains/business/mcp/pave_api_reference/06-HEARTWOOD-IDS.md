# Heartwood Craft — Organization IDs

All Heartwood-specific IDs needed for Pave operations. These are constant for the org.

---

## Core

| Key | Value |
|---|---|
| Organization ID | `22Nm3uFevXMb` |
| Eric's User ID | `22Nm3uFeRB7s` |
| Eric's Email | eric@iheartwoodcraft.com |

---

## Cost Codes

| ID | Code | Name |
|---|---|---|
| `22Nm3uGRAMmG` | 0000 | Uncategorized |
| `22Nm3uGRAMmH` | 0100 | Planning |
| `22NxeGLaJCQT` | 0110 | Site Preparation |
| `22Nm3uGRAMmJ` | 0200 | Demolition |
| `22Nm3uGRAMmL` | 0400 | Utilities |
| `22Nm3uGRAMmM` | 0500 | Foundation |
| `22Nm3uGRAMmN` | 0600 | Framing |
| `22Nm3uGRAMmQ` | 0800 | Siding |
| `22Nm3uGRAMmS` | 1000 | Electrical |
| `22Nm3uGRAMmT` | 1100 | Plumbing |
| `22Nm3uGRAMmV` | 1300 | Insulation |
| `22Nm3uGRAMmW` | 1400 | Drywall |
| `22Nm3uGRAMmX` | 1500 | Doors & Windows |
| `22Nm3uGRAMmZ` | 1700 | Flooring |
| `22Nm3uGRAMma` | 1800 | Tiling |
| `22Nm3uGRAMmb` | 1900 | Cabinetry |
| `22Nm3uGRAMmc` | 2000 | Countertops |
| `22Nm3uGRAMmd` | 2100 | Trimwork |
| `22Nm3uGRAMme` | 2200 | Specialty Finishes |
| `22Nm3uGRAMmf` | 2300 | Painting |
| `22Nm3uGRAMmg` | 2400 | Appliances |
| `22Nm3uGRAMmh` | 2500 | Decking |
| `22Nm3uGRAMmi` | 2600 | Fencing |
| `22Nm3uGRAMmk` | 2800 | Concrete |
| `22Nm3uGRAMmn` | 3000 | Furnishings |
| `22Nm3uGRAMmp` | 3100 | Miscellaneous |

---

## Cost Types

| ID | Name | Markup |
|---|---|---|
| `22PJuNqewZmV` | Admin | 50% |
| `22Nm3uGRAMmq` | Labor | 50% |
| `22Nm3uGRAMmr` | Materials | 50% |
| `22Nm3uGRAMmt` | Other | 50% |
| `22PQ4KZExZjP` | Selections | 30% |
| `22Nm3uGRAMms` | Subcontractor | 30% |

---

## Units

| ID | Name | Use |
|---|---|---|
| `22Nm3uGRAMm5` | Cubic Yards | Concrete, fill |
| `22Nm3uGRAMm6` | Days | Day-rate labor |
| `22Nm3uGRAMm7` | Each | Fixtures, materials by unit |
| `22Nm3uGRAMm8` | Gallons | Paint, sealers |
| `22Nm3uGRAMm9` | Hours | All labor line items |
| `22Nm3uGRAMmA` | Linear Feet | Trim, baseboard |
| `22Nm3uGRAMmB` | Lump Sum | Allowances, misc |
| `22Nm3uGRAMmC` | Pounds | Misc materials |
| `22Nm3uGRAMmD` | Square Feet | Tile, flooring, paint areas |
| `22Nm3uGRAMmE` | Squares | Roofing |
| `22Nm3uGRAMmF` | Tons | Gravel, aggregate |

---

## Custom Fields — Customer Account

| ID | Name | Type | Options |
|---|---|---|---|
| `22Nnj9KMKEPC` | Project Type | option | Bathroom Remodel, Full Remodel, Kitchen Remodel, Addition, Exterior, Interior, Custom |
| `22Nnj9KTwMCe` | Notes | text | |
| `22Nnj9KfuSgp` | Referred By | text | |
| `22Nnj9Kk4CLH` | Lead Lost Reason | option | Price, Competition, Timing, Not a good fit, Customer changed mind, Unknown |
| `22Nnj9KwwePZ` | Status | option | New Lead, Appointment Set, Lead Lost, Active Customer |
| `22NnjWw3NTGc` | Appointment | date | |
| `22NnjXKR5868` | Days Choice | option | Monday–Friday |
| `22NnjXZhpFXn` | Time Choice | option | 8am-10am, 10am-12pm, 12pm-2pm, 2pm-4pm, 4pm-530pm |
| `22PU427xzLaS` | Source | option | Local Service, Google, Referral, Short Term Rental, Chamber, Facebook, Repeat, Other |
| `22PUGvBnXeYs` | Lead Source | option | **REQUIRED.** Must set via `updateAccount` after creation. |

---

## Custom Fields — Customer Contact

| ID | Name | Type |
|---|---|---|
| `22Nm3uGRBrPX` | Email | emailAddress |
| `22Nm3uGb7WT2` | Phone | phoneNumber |
| `22NnjDZ39w8C` | Mobile | phoneNumber |
| `22NnjDZS2Sy8` | Secondary Email | emailAddress |

---

## Custom Fields — Job

| ID | Name | Type | Options |
|---|---|---|---|
| `22P4fgU4XmLY` | Job Type | option | Bathroom, Kitchen, Basement, Deck, Interior General, Exterior General |
| `22P4fguBu3Ub` | Phase | option | 1. Contacted → 2. Visited → 3. Budgeting → 4. Budget Sent → 5. Budget Approved → 6. Work Start → 7. First Milestone → 8. Second Milestone Complete → 9. Final Milestone → 10. Job Complete |

> **Note (2026-04-04):** Phase values in production have "Complete" suffixes on later phases (e.g., "8. Second Milestone Complete" not "8. Second Milestone"). The "10. Job Complete" phase is used for finished jobs that sometimes lack a `closedOn` date. When filtering by phase, parse the numeric prefix with `parseInt()` rather than matching exact strings.

---

## Dashboard IDs

| Name | ID |
|---|---|
| Sales Pipeline & Lead Tracker | `22PU2MtJJiM7` |
| Lead Source & Conversion Tracker | `22PU7MUwuq3A` |

---

## Voice Pipeline — Trade → Cost Code Map

| Trade (natural language) | Cost Code ID |
|---|---|
| Demo | `22Nm3uGRAMmJ` |
| Framing | `22Nm3uGRAMmN` |
| Plumbing | `22Nm3uGRAMmT` |
| Electrical | `22Nm3uGRAMmS` |
| Tile | `22Nm3uGRAMma` |
| Drywall | `22Nm3uGRAMmW` |
| Painting | `22Nm3uGRAMmf` |
| Finish Carpentry | `22Nm3uGRAMmb` |
| Admin | `22Nm3uGRAMmH` |
