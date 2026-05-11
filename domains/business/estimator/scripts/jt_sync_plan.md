# JT Catalog Sync Plan

Generated: 2026-05-03

## Current State

| Source | Items | Notes |
|--------|-------|-------|
| Postgres `catalog_items` | 727 active | Canonically named, clean cost codes |
| JT org catalog (API) | 5,130 | 1,228 unique names, 3,902 duplicates |
| JT org catalog (CSV UI) | 797 | Subset visible in JT UI |

## Phase 1: Dedup (clean JT catalog)

The JT org catalog has massive duplication — items are created every time
a budget line is "saved to catalog," resulting in e.g. "Trash Bags" × 65.

| Category | Count |
|----------|-------|
| Unique names (keepers) | 1,228 |
| Deletion candidates | 3,902 |
| Safe to delete (not in CSV) | 3,877 |
| In CSV export (need care) | 25 |

**Keeper selection:** CSV export items preferred (772), then by pricing (432), then by age (24).

**Action required:**
- [ ] Review `jt_dedup_deletions.json` — spot-check a few entries
- [ ] Determine if JT supports bulk delete via API or if manual cleanup needed
- [ ] The 25 CSV items marked for deletion are name-duplicates within the CSV itself — verify these are OK to consolidate

## Phase 2: Reconciliation (sync Postgres → JT)

| Action | Count | Details |
|--------|-------|---------|
| Already linked (exact ID match) | 576 | `jt_catalog_id` already points to keeper |
| Redirected to keeper | 7 | Was pointing to a dupe, now points to keeper |
| Matched by name (exact) | 53 | 50 single-match + 3 via keeper preference |
| Matched by name (fuzzy) | 19 | Scores 0.83–1.00, **review required** |
| **Total matched** | **655** | All matched to keepers |
| Rename in JT | 601 | Old-style → canonical name |
| Update pricing in JT | 26 | Postgres pricing differs from JT |
| Create in JT | 72 | New items with no JT equivalent |
| Many-to-one conflicts | 44 | Multiple PG items → same JT item (mostly allowance tiers) |

**Action required:**
- [ ] Review the 19 fuzzy matches in `jt_catalog_map.json` — some may be wrong
- [ ] Decide on many-to-one conflicts (44 items) — allowance tiers need separate JT catalog entries
- [ ] Add bad fuzzy matches to `jt_manual_overrides.json` to exclude them
- [ ] Run `--sync --execute` after review

## Phase 3: Verify

After execution:

- [ ] All 727 Postgres items have `jt_catalog_id` populated
- [ ] `SELECT count(*) FROM catalog_items WHERE jt_catalog_id IS NULL AND is_active = true` returns 0
- [ ] Test budget push creates line items linked to correct JT catalog entries
- [ ] JT reporting aggregates correctly across jobs
- [ ] Consolidate `jt_org_cost_item_id` column → `jt_catalog_id` (separate migration)

## Scripts

| Script | Purpose |
|--------|---------|
| `dedup_jt_catalog.py` | Dedup analysis → keepers + deletions JSON |
| `reconcile_jt_catalog.py` | Match PG→JT, sync with DRY_RUN |
| `reconcile_jt_catalog.py --dedup-first` | Run both in sequence |
| `reconcile_jt_catalog.py --sync` | Show sync plan (DRY_RUN) |
| `reconcile_jt_catalog.py --sync --execute` | **LIVE — makes changes** |

## Files

| File | Purpose |
|------|---------|
| `jt_catalog_cache.json` | Cached API data (5,130 items with createdAt) |
| `jt_dedup_keepers.json` | One keeper per unique name (1,228 entries) |
| `jt_dedup_deletions.json` | Deletion candidates (3,902 entries) |
| `jt_catalog_map.json` | PG↔JT mapping with match methods |
| `jt_manual_overrides.json` | Manual PG ID → JT ID overrides |
| `catalog-2026-05-03.csv` | JT UI export (797 items, ground truth) |
