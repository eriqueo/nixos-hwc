# Media Library Cleanup Plan

## ⚡ Lessons Learned (TV Shows - Phase 1 Complete)

**What DIDN'T Work:**
- ❌ Sonarr/Radarr bulk rename API (fails with NULL exceptions)
- ❌ Over-complicated automation through APIs
- ❌ Trying to use `{Quality Full}` and other complex format tokens

**What DID Work:**
- ✅ Direct folder renames with bash/python
- ✅ Simple pattern-based file renaming (1x## → S##E##)
- ✅ Fix folder structure FIRST, then filenames
- ✅ Test on small samples before bulk operations
- ✅ Most files were already 90% clean - don't over-engineer

**Key Insight:** Your library is mostly clean. Focus on the 10-20% that needs work, not rebuilding everything.

**TV Results (Phase 1):**
- 16 series folders renamed to add years
- 108 season folders standardized (Season 01, Season 02...)
- 300+ episode files renamed to S##E## format
- Final: 98.5% compliance (3,665/3,741 files)
- Time: ~30 minutes actual work

---

## Risk Assessment

**Criticality**: HIGH - Bulk operations on ~TB of irreplaceable media
**Primary Risks**:
- Data loss from failed moves/renames
- Metadata corruption in Radarr/Sonarr/Beets databases
- Disk space exhaustion during reorganization
- Broken hardlinks (affects active torrents)
- Automation matching wrong files (e.g., similar titles)

**Mitigation Strategy**: Phased execution with backups, validation checkpoints, and rollback capability at each stage.

---

## Current State Analysis

### `/mnt/media/movies`
**Issues**:
- Mixed structure: well-formed folders vs. raw scene dumps
- Duplicates (same title, different releases)
- Un-indexed extras folders (`featurettes/`, `other/`)
- Unknown metadata (`Pinocchio (UNKNOWN)`)

**Risk Level**: MEDIUM - Radarr can handle most, but manual review needed for duplicates/unknowns

### `/mnt/media/tv`
**Issues**:
- Unpacked release folders (`South.Park.4x11...`)
- Inconsistent season numbering (missing zero-padding)
- Otherwise mostly compliant structure

**Risk Level**: LOW - Sonarr rename should handle most cases automatically

### `/mnt/media/music`
**Issues**:
- Mixed Beets-managed + unmanaged content
- Multi-disc rips not consolidated (`CD 01`, `CD 02`)
- Artist/album variations
- Existing duplicates staging area suggests past issues

**Risk Level**: MEDIUM - Beets import can be destructive; duplicate detection critical

### `/mnt/media/downloads*` & `/mnt/media/archive`
**Issues**:
- Legacy content never processed by automation
- Unknown quality/completeness
- Potential duplicates of existing library items

**Risk Level**: HIGH - Unknown content; could waste time importing low-quality dupes

---

## Target Structure

- **Movies**: `Title (Year)/Title (Year) [Resolution][Source][Codec][Audio].ext`
  - Extras: nested under `Title (Year)/extras/` or `Title (Year)/featurettes/`
  - All metadata managed by Radarr

- **TV**: `Show Name (Year)/Season 01/Show Name (Year) - S01E01 - Episode Title.ext`
  - Specials: `Show Name (Year)/Specials/` (season 00)
  - Sonarr handles all renaming and folder creation

- **Music**: `Artist/Year - Album/01 Track Title.ext`
  - Beets manages tagging, deduplication, and imports
  - Multi-disc: `Artist/Year - Album/Disc 1/01 Track.ext`

- **Staging**: `/mnt/hot/downloads` ONLY
  - Containers NEVER write directly to `/mnt/media/*`
  - All imports flow through automation tools

---

## Pre-Flight Safety Checklist

### 1. Backup Everything
```bash
# Stop all media services
systemctl stop radarr sonarr lidarr beets

# Backup databases
cp -a /var/lib/radarr /var/lib/radarr.backup.$(date +%Y%m%d)
cp -a /var/lib/sonarr /var/lib/sonarr.backup.$(date +%Y%m%d)
cp -a /var/lib/lidarr /var/lib/lidarr.backup.$(date +%Y%m%d)
cp -a /opt/beets/beets-library.db /opt/beets/beets-library.db.backup.$(date +%Y%m%d)

# Document current state
du -sh /mnt/media/* > /tmp/media-state-before.txt
find /mnt/media/movies -maxdepth 1 -type d | wc -l > /tmp/movie-folders-before.txt
find /mnt/media/tv -maxdepth 1 -type d | wc -l > /tmp/tv-folders-before.txt
find /mnt/media/music -maxdepth 2 -type d | wc -l > /tmp/music-folders-before.txt

# Restart services
systemctl start radarr sonarr lidarr beets
```

### 2. Verify Disk Space
```bash
# Need at least 20% free space for safe operations
df -h /mnt/media
df -h /mnt/hot

# If < 20% free, clean up staging areas first or expand storage
```

### 3. Test Automation Configuration
- Verify Radarr/Sonarr/Lidarr can reach download paths
- Test rename on a single item manually
- Confirm hardlink support (same filesystem for downloads → media)
- Check permissions (media services must own/write to all paths)

### 4. Create Quarantine Area
```bash
mkdir -p /mnt/media/.quarantine/{movies,tv,music,unknown}
```
Use for files that automation can't match or need manual review.

---

## Folder-by-Folder Strategy

### `/mnt/media/movies` - Simple Direct Approach (Based on TV Lessons)

**Step 1: Analyze Current State (5 min)**
```bash
# Check folder compliance
ls -1d /mnt/media/movies/*/ | python3 -c "
import sys, re
for line in sys.stdin:
    folder = line.strip().split('/')[-2]
    if not re.search(r'.+ \(\d{4}\)$', folder):
        print(f'Bad format: {folder}')
"

# Count scene dumps and problematic folders
find /mnt/media/movies -maxdepth 1 -type d -name "*RERIP*" -o -name "*UNKNOWN*"
```

**Step 2: Fix Folder Names (15 min)**
```bash
# 1. Get proper titles/years from Radarr API
curl http://localhost:7878/radarr/api/v3/movie | jq -r '.[] | "\(.id)|\(.title)|\(.year)|\(.path)"'

# 2. Rename folders to "Title (Year)" format
for movie in bad_format_list; do
    # Get year from Radarr or IMDB
    sudo mv "$old_name" "$proper_name (YEAR)"
done

# 3. Update Radarr paths
curl -X PUT "http://localhost:7878/radarr/api/v3/movie/$ID" -d '{"path": "/movies/New Path"}'
```

**Step 3: Fix Movie Filenames (10 min)**
```bash
# Most movie files are already in folders, just ensure format:
# "Title (Year)/Title (Year).ext" or "Title (Year)/Title (Year) - Quality.ext"

# Move scene dumps to quarantine
sudo mv "/mnt/media/movies/Toy.Story.RERIP.Scene.Release" /mnt/media/.quarantine/movies/

# Import via Radarr manual import if you want them
```

**Step 4: Handle Extras (5 min)**
```bash
# Move loose extras folders into parent movie folders
sudo mv "/mnt/media/movies/featurettes" "/mnt/media/movies/MovieName (Year)/extras/"

# Enable "Import Extra Files" in Radarr settings (srt, sub files)
```

**Step 5: Handle UNKNOWN folders**
- Use TheMovieDB/IMDB to identify
- If can't identify → quarantine
- If identified → rename and add to Radarr

**Expected Results:** Similar to TV (95%+ compliance in ~30-45 minutes)

### `/mnt/media/tv` - Simple Direct Approach (PROVEN ✅)

**Step 1: Analyze Current State (5 min)**
```bash
# Get series needing years
ls -1d /mnt/media/tv/*/ | python3 -c "
import sys, re
for line in sys.stdin:
    folder = line.strip().split('/')[-2]
    if not re.search(r'\(\d{4}\)', folder):
        print(f'Missing year: {folder}')
"

# Count season folder formats
find /mnt/media/tv -type d -name "Season [0-9]" | wc -l  # Need 2-digit format
```

**Step 2: Fix Folder Structure (10 min)**
```bash
# 1. Get years from Sonarr API, save to /tmp/sonarr-renames.json
# 2. Rename series folders
for series in missing_year_list; do
    sudo mv "$old_name" "$new_name (YEAR)"
done

# 3. Standardize season folders
find /mnt/media/tv -name "Season [0-9]" | while read path; do
    sudo mv "$path" "$(dirname $path)/Season 0X"
done

# 4. Update Sonarr paths via API
curl -X PUT "http://localhost:8989/sonarr/api/v3/series/$ID" -d '{"path": "/tv/New Path"}'
```

**Step 3: Fix Episode Filenames (15 min)**
```bash
# Fix 1x## → S##E## format
find /mnt/media/tv -name "*1x*" | rename "1x" to "S01E"

# Fix S##.E## → S##E## (dots to no dots)
find /mnt/media/tv -name "*S[0-9][0-9].E[0-9][0-9]*" | sed 's/\.E/E/'

# Fix files with just episode numbers (e.g., Thomas)
# Extract season from folder, prepend "Show (Year) - S##E## -" to filename
```

**Step 4: Handle Scene Dumps**
- Move to `/mnt/media/.quarantine/tv`
- Import via Sonarr manual import IF you want them

**Results:** 98.5% compliance in 30 minutes

### `/mnt/media/music` - Four-Pass Approach

**Pass 1: Catalog Existing Library (Safe)**
- Target: All current `/mnt/media/music` content
- Action: `beet import -A /mnt/media/music` (as-is import, no moves)
- Purpose: Get current state into Beets DB
- Validation: `beet stats` should show all albums

**Pass 2: Detect & Review Duplicates (Safe)**
- Action: `beet duplicates > /tmp/beets-dupes-$(date +%Y%m%d).txt`
- Manual Review: Decide which version to keep (higher bitrate, better tags)
- Mark for deletion: Move rejects to `/mnt/media/.quarantine/music`

**Pass 3: Re-Import for Organization (Medium Risk)**
- Action: `beet import -A /mnt/media/music` with move enabled
- Purpose: Apply Beets naming scheme
- Validation: Spot-check artist folders, verify multi-disc handling
- Rollback: Restore from Beets DB backup

**Pass 4: Import Loose Files (Medium Risk)**
- Target: Un-cataloged rips, `CD 01` folders
- Action: `beet import /mnt/media/music` (interactive mode)
- Review each match; use MusicBrainz lookups
- Quarantine: Poor matches → `/mnt/media/.quarantine/music`

### `/mnt/media/downloads*` & `/mnt/media/archive` - Drain Strategy

**Phase 1: Inventory & Prioritize**
```bash
# Get size breakdown
du -sh /mnt/media/downloads*/* /mnt/media/archive/* | sort -h

# Identify what's worth keeping
ls -lh /mnt/media/downloads/ | less
```

**Phase 2: Process High-Value Content**
- Target: Large, complete collections
- Action: Manual import via Radarr/Sonarr/Beets
- Check for duplicates BEFORE importing
- Use quarantine for "maybe" items

**Phase 3: Bulk Delete Low-Value**
- Target: Incomplete downloads, samples, low quality
- Action: After Phase 2, if folder still exists, likely not worth keeping
- Final review before `rm -rf`

---

## Implementation Plan

### PHASE 0: Preparation (1 hour)
1. ✓ Run pre-flight backup checklist
2. ✓ Verify disk space (min 20% free)
3. ✓ Create quarantine directories
4. ✓ Document baseline metrics
5. ✓ Test rename on 1 movie, 1 TV episode, 1 album

### PHASE 1: TV Shows (Lowest Risk First)
**Time Estimate**: 2-4 hours
**Why First**: Most standardized, Sonarr is most reliable

1. Configure Sonarr rename settings
2. **Pass 1**: Rename existing library (bulk)
3. Validate 20 random episodes
4. **Pass 2**: Manual import unpacked releases (10-50 at a time)
5. Review quarantine; research or delete
6. Final validation: `find /mnt/media/tv -type f -name "*.mkv" | wc -l`

**Checkpoint**: Compare file count before/after; should be same or higher

### PHASE 2: Movies (Medium Risk)
**Time Estimate**: 4-8 hours
**Why Second**: More complex than TV, but Radarr handles well

1. Configure Radarr rename settings + extras import
2. **Pass 1**: Organize existing library (bulk, ~1-2 hours)
3. Validate 20 random movies + check playback
4. **Pass 2**: Import scene dumps (batches of 25)
   - Review each batch for duplicates
   - Check quality (don't import worse versions)
5. **Pass 3**: Handle extras manually (case-by-case)
6. Review quarantine; keep only if rare/valuable
7. Final validation: `find /mnt/media/movies -type f -name "*.mkv" | wc -l`

**Checkpoint**: No missing movies; all extras preserved

### PHASE 3: Music (Highest Risk)
**Time Estimate**: 6-12 hours
**Why Last**: Most complex; Beets can be destructive

1. Configure Beets (`config.yaml`)
2. **Pass 1**: Catalog existing (`beet import -A` dry-run first!)
3. **Pass 2**: Generate duplicate report; manual review
   - Delete clear dupes (e.g., exact same album, lower bitrate)
4. **Pass 3**: Re-import with moves (batches of 50 albums)
5. **Pass 4**: Import loose files (interactive, one-by-one)
6. Review quarantine; use MusicBrainz Picard for tough matches
7. Final validation: `beet stats`, compare album count

**Checkpoint**: Album count matches or exceeds original; no data loss

### PHASE 4: Staging Areas (Ongoing)
**Time Estimate**: 2-4 hours
**Why Last**: Unknown content; most likely to be junk

1. Process `/mnt/media/downloads` (newest first)
2. Process `/mnt/media/downloads-old` (selective)
3. Process `/mnt/media/archive` (selective)
4. For each item:
   - Check if duplicate of existing library (skip)
   - If better quality, import and replace
   - If new, import
   - If unknown/poor quality, quarantine or delete
5. Delete empty folders
6. Final validation: Staging dirs empty or < 1GB

### PHASE 5: Guardrails & Monitoring
**Time Estimate**: 1-2 hours

1. Deploy validation script (cron nightly):
```bash
#!/usr/bin/env bash
# /usr/local/bin/media-validator.sh
find /mnt/media/movies -maxdepth 1 -type d ! -regex '.*/[^/]+ \([0-9]{4}\)' -exec echo "NON-COMPLIANT MOVIE: {}" \;
find /mnt/media/tv -maxdepth 2 -type d ! -regex '.*/Season [0-9]{2}' ! -path '*/Specials' -exec echo "NON-COMPLIANT TV: {}" \;
# Email or log results
```

2. Backup automation configs:
```bash
cp /var/lib/radarr/config.xml ~/backups/
cp /var/lib/sonarr/config.xml ~/backups/
cp /opt/beets/config.yaml ~/backups/
```

3. Update documentation (this file)
4. Schedule weekly Beets duplicate scans

---

## Validation & Rollback

### Per-Phase Validation
- **File counts**: Before/after must match (or be explicable)
- **Disk usage**: Should not significantly increase (moves, not copies)
- **Playback test**: Random sampling must play correctly
- **Database integrity**: Export library lists before/after; compare

### Rollback Procedures

**If Radarr/Sonarr rename fails:**
```bash
systemctl stop radarr sonarr
rm -rf /var/lib/radarr /var/lib/sonarr
cp -a /var/lib/radarr.backup.YYYYMMDD /var/lib/radarr
cp -a /var/lib/sonarr.backup.YYYYMMDD /var/lib/sonarr
systemctl start radarr sonarr
# Files may be in wrong location; re-scan libraries to update paths
```

**If Beets import corrupts:**
```bash
systemctl stop beets
cp /opt/beets/beets-library.db.backup.YYYYMMDD /opt/beets/beets-library.db
systemctl start beets
# Manually revert file moves if needed
```

**If disk space exhausted:**
1. Stop all automation
2. Delete quarantine contents
3. Remove duplicates from staging
4. Expand storage or move completed media to cold storage

### Success Criteria
- [ ] All files follow target naming conventions
- [ ] No duplicate titles (unless intentional - different editions)
- [ ] Staging areas empty or < 5GB
- [ ] All databases backed up
- [ ] Validation script running nightly
- [ ] Playback tests pass on random samples
- [ ] Documentation updated

---

## Maintenance Schedule

**Daily** (automated):
- Recyclarr sync
- Media validator script

**Weekly** (manual):
- Review quarantine folder; decide keep/delete/research
- `beet duplicates` scan
- Check logs for automation errors

**Monthly** (manual):
- Database backups
- Disk space review
- Update rename templates if needed

---

## Emergency Contacts & Resources

- **Radarr/Sonarr Wiki**: https://wiki.servarr.com/
- **Beets Docs**: https://beets.readthedocs.io/
- **TRaSH Guides**: https://trash-guides.info/ (for quality profiles/naming)
- **Local Backups**: `/var/lib/{radarr,sonarr,lidarr}.backup.*`, `/opt/beets/*.backup.*`

**Before starting any phase, ask**: "Can I roll this back if it fails?" If no, add more backups.
