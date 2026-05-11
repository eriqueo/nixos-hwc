# fb-monitor

Merge pipeline for Facebook group monitoring data (JT Pros group).

## Data source

Tampermonkey script exports JSON from `https://facebook.com/groups/jobtreadpros`.
Drop the `.json` files in any convenient location and run the merge script.

## Apply schema (first deploy)

```sh
psql datax < domains/business/datax/fb-monitor/schema.sql
```

Or on the server:

```sh
psql -U datax datax < /path/to/schema.sql
```

## Run a merge

```sh
# System-installed wrapper (after NixOS rebuild):
fb-merge /path/to/fb-group-2026-05-08.json

# Or directly with DATABASE_URL override:
DATABASE_URL=postgresql://datax@localhost/datax \
  python3 domains/business/datax/fb-monitor/merge.py /path/to/export.json
```

## Output

```
posts total   : 45
posts new     : 12
posts updated : 3
comments new  : 87
```

## Tables

| Table | Purpose |
|-------|---------|
| `fb_posts` | One row per post. Tracks classification state. |
| `fb_comments` | Deduplicated comments (hash on author+body). |
| `fb_capture_log` | Audit log of every merge run. |

## Classification workflow

After merge, classify posts via direct SQL or a future UI:

```sql
UPDATE fb_posts
   SET classification = 'datax_mention',
       classification_tags = ARRAY['estimating', 'ai_usage']
 WHERE post_id = '1286089016487814';
```

Valid classification values: `datax_mention`, `related`, `not_related`.
