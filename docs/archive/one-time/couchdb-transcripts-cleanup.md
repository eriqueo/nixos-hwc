# CouchDB Transcripts Database Cleanup TODO

**Date Created**: 2025-11-16
**Status**: NEEDS CLEANUP
**Priority**: Medium

## Issue

The CouchDB database `obsidian-transcripts` contains mixed/orphaned content that needs cleanup.

### Database Contents Analysis

**Database**: `obsidian-transcripts`
- Total documents: 1,513
- Markdown files: 454

**Content Breakdown**:
- **YouTube transcripts**: Only 4 files in `individual/` folders:
  - `individual/2025-08-07/cal-newport-the-secrets-of-slow-productivity.md`
  - `individual/2025-08-07/placeholder-video.md`
  - `individual/2025-08-07/rick-astley-never-gonna-give-you-up-official-video-4k-remaster.md`
  - `individual/2025-08-08/easiest-tool-for-drawing-walls-in-blender-the-archipack-draw-walls-tool.md`

- **Business/work documents**: 210+ files including:
  - `00_business overview/` - KPIs, financial, marketing, operations
  - `01_jobtread/` - Estimates, API docs, budget templates
  - `01_work/` - Licenses, W9s, tax prep
  - `01_linux/` - Scripts and automation tools
  - `00_prompts/` - AI prompts and instructions

- **Other files**: 240+ miscellaneous files

### Problem

The database appears to be wrongly synced - it was likely intended for YouTube transcripts but got connected to a business/work Obsidian vault. The business documents **do not exist locally** on the current machine and appear to be orphaned in the database.

## Solution Implemented

Created a **new, fresh database** for YouTube transcripts:

### New Database
- **Name**: `yt-transcripts-vault`
- **Purpose**: Clean database exclusively for YouTube transcript storage
- **Location**: CouchDB on hwc-server at `http://127.0.0.1:5984`
- **Synced to**: `/home/eric/01-documents/01-vaults/04-transcripts` (Obsidian vault)

### Configuration Updated
- `yt-transcript-api.py`: Changed default database to `yt-transcripts-vault`
- `transcript-api.nix`: Updated service environment variable `COUCHDB_DATABASE=yt-transcripts-vault`

## Cleanup TODO

The old `obsidian-transcripts` database needs to be addressed:

### Option 1: Archive and Delete (Recommended)
1. Export all documents from `obsidian-transcripts` for backup
2. Identify which Obsidian vault (if any) should own the business docs
3. Delete the `obsidian-transcripts` database
4. Re-sync the correct vault to a properly named database (e.g., `obsidian-business`)

### Option 2: Clean and Repurpose
1. Delete all non-transcript documents from `obsidian-transcripts`
2. Keep the 4 YouTube transcript files
3. Use it as the transcript database instead of creating `yt-transcripts-vault`

### Option 3: Leave as-is (Not Recommended)
- Keep both databases
- Accept the naming confusion
- Risk: Future sync conflicts or confusion

## Commands for Cleanup

### View all databases:
```bash
COUCHDB_USER=$(sudo cat /run/agenix/couchdb-admin-username)
COUCHDB_PASS=$(sudo cat /run/agenix/couchdb-admin-password)
curl -s -u "$COUCHDB_USER:$COUCHDB_PASS" http://127.0.0.1:5984/_all_dbs
```

### Export database for backup:
```bash
curl -s -u "$COUCHDB_USER:$COUCHDB_PASS" \
  "http://127.0.0.1:5984/obsidian-transcripts/_all_docs?include_docs=true" \
  > obsidian-transcripts-backup-$(date +%Y%m%d).json
```

### Delete database (CAREFUL):
```bash
curl -X DELETE -u "$COUCHDB_USER:$COUCHDB_PASS" \
  http://127.0.0.1:5984/obsidian-transcripts
```

## Related Files

- `/home/eric/.nixos/workspace/productivity/transcript-formatter/yt-transcript-api.py`
- `/home/eric/.nixos/domains/server/networking/parts/transcript-api.nix`
- `/home/eric/.nixos/domains/server/couchdb/index.nix`

## Notes

- Current CouchDB databases (as of 2025-11-16):
  - `obsidian-hwc`: 10,182 docs
  - `obsidian-nixos`: 0 docs (empty)
  - `obsidian-personal`: 8,027 docs
  - `obsidian-tech`: 38,746 docs
  - `obsidian-templates`: 101 docs
  - `obsidian-website`: 716 docs
  - `obsidian-transcripts`: 1,513 docs (MIXED/ORPHANED)
  - `yt-transcripts-vault`: NEW (will be created on first transcript sync)
