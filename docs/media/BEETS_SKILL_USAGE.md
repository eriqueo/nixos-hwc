# Beets Music Organizer Skill - Usage Guide

The `beets-music-organizer` Claude skill is a specialized agent for comprehensive music library cleanup, deduplication, and optimization.

## Quick Start

### Basic Usage

Simply ask Claude to use the skill:

```
"Use the beets-music-organizer skill to clean up my music library"
```

Or be more specific:

```
"Use the beets-music-organizer skill to remove all duplicate tracks"
"Use the beets-music-organizer skill to import music from /mnt/hot/downloads/music"
"Use the beets-music-organizer skill to fix albums that aren't matching"
```

## What the Skill Does

### 1. Complete Library Cleanup (Recommended First Run)

When you ask for a complete cleanup, the skill will:

**Step 1: Initial Analysis**
- Runs comprehensive library health check
- Reports total tracks/albums/artists
- Counts duplicates, missing art, unmatched items
- Identifies quality issues

**Step 2: Database Integrity Check**
- Ensures database matches actual files
- Finds files not in database
- Offers to re-import if needed

**Step 3: Duplicate Removal**
- Presents 5 different strategies:
  - Interactive (safest, walks you through each)
  - Keep best quality (automated by bitrate/format)
  - Format preference (keep FLAC, remove MP3)
  - Path-based (remove from specific directory)
  - Date-based (keep newer imports)
- Recommends best strategy for your situation
- Executes with progress updates

**Step 4: Fix Missing Album Art**
- Fetches missing artwork
- Embeds into files
- Verifies completion

**Step 5: Metadata Standardization**
- Scrubs unnecessary tags
- Writes standardized tags
- Fixes common issues (artist names, formatting)

**Step 6: Match Unmatched Items**
- Re-imports items without MusicBrainz IDs
- Uses acoustic fingerprinting if needed
- Reports success rate

**Step 7: Find Incomplete Albums**
- Identifies albums with missing tracks
- Provides list for review
- Suggests actions

**Step 8: Handle Low-Quality Files**
- Finds low bitrate files
- Lists for review/re-download
- Provides recommendations

**Step 9: Verify & Report**
- Runs analysis again
- Shows before/after comparison
- Updates Navidrome
- Creates detailed log

### 2. Import New Downloads

For importing new music:

```
"Import the music from /mnt/hot/downloads/music/ using the beets skill"
```

The skill will:
- Check what's in downloads
- Clean up junk files
- Import with proper MusicBrainz matching
- Fetch and embed album art
- Check for duplicates introduced
- Update Navidrome

### 3. Deduplicate Specific Artist/Album

For targeted cleanup:

```
"Use the beets skill to remove duplicates for Ween"
"Use the beets skill to clean up The Simpsons Movie soundtrack"
```

The skill will:
- Analyze the specific artist/album
- Show all versions found
- Compare quality (format, bitrate, completeness)
- Recommend which to keep
- Remove unwanted versions

### 4. Fix Problematic Albums

For albums that won't match or have issues:

```
"Use the beets skill to fix the album that won't match MusicBrainz"
"Use the beets skill to merge split album directories"
```

The skill handles:
- Albums not matching MusicBrainz
- Albums split across multiple directories
- Compilation albums misidentified
- Multi-disc album issues

## Example Conversations

### Example 1: First-Time Complete Cleanup

**You:**
> "Use the beets-music-organizer skill to clean up my entire music library"

**Claude (using skill):**
> "I'll analyze your music library and create a cleanup plan. This will take a few minutes."
>
> Running analysis...
> - Total tracks: 15,432
> - Total albums: 1,234
> - Duplicates found: 487 groups (1,156 duplicate files)
> - Missing art: 89 albums
> - Unmatched: 234 items (15%)
> - Low quality: 67 files
>
> Recommended cleanup order:
> 1. Remove duplicates (will free ~8GB)
> 2. Fix missing album art (89 albums)
> 3. Match unmatched items (234 items)
> 4. Review low-quality files (67 files)
> 5. Standardize metadata
>
> Estimated time: 45-60 minutes
> Proceed?

**You:**
> "Yes, proceed"

**Claude:**
> "Starting duplicate removal..."
>
> Found 487 duplicate groups. I recommend Strategy 2 (keep best quality).
> This will:
> - Keep highest bitrate versions
> - Prefer FLAC over lossy formats
> - Remove ~1,156 files (~8GB)
>
> Confirm?

**You:**
> "Confirm"

**Claude:**
> "Executing..."
> Progress: 100/487 groups processed...
> Progress: 200/487 groups processed...
> ...
> Complete! Removed 1,143 duplicate files, freed 7.8GB.
>
> Next step: Fix missing album art?

*[Process continues through all steps]*

**Final Report:**
> "Cleanup complete! Here's what changed:"
>
> Before → After:
> - Total tracks: 15,432 → 14,289 (-1,143 duplicates)
> - Duplicates: 487 groups → 3 groups (99% reduction)
> - Missing art: 89 → 0 albums
> - Unmatched: 234 → 12 items (95% improvement)
> - Disk usage: 127GB → 119GB (-8GB freed)
>
> Remaining issues:
> - 12 albums couldn't auto-match (queued for manual review)
> - 3 duplicate groups need manual decision (ambiguous quality)
>
> Navidrome library refreshed. All changes logged to /tmp/cleanup-20251121.log.

### Example 2: Import New Downloads

**You:**
> "Use the beets skill to import music from /mnt/hot/downloads/music/"

**Claude:**
> "Checking downloads directory..."
>
> Found 3 albums (47 tracks):
> - Ween - Quebec (14 tracks, FLAC)
> - Primus - Sailing the Seas of Cheese (13 tracks, MP3 320kbps)
> - Various Artists - Compilation (20 tracks, MP3 VBR)
>
> Will import with MusicBrainz matching. Proceed?

**You:**
> "Yes"

**Claude:**
> "Importing..."
>
> ✅ Ween - Quebec: Matched (confidence: 0.95)
> ✅ Primus - Sailing the Seas of Cheese: Matched (confidence: 0.98)
> ⚠️  Various Artists - Compilation: Multiple matches, needs choice
>
> For "Compilation", found 3 possible matches:
> 1. Now That's What I Call Music! Vol. 45 (2000)
> 2. 90s Hits Collection (1999)
> 3. Import as-is (no match)
>
> Which option?

### Example 3: Targeted Duplicate Removal

**You:**
> "Use the beets skill to find and remove duplicate Radiohead albums"

**Claude:**
> "Analyzing Radiohead in library..."
>
> Found duplicates:
>
> OK Computer:
> - Version 1: FLAC, 1997, 320-340 kbps, complete (12 tracks)
> - Version 2: MP3, 1997, 192 kbps, complete (12 tracks)
> - Version 3: FLAC, 2017, Remastered, complete (12 tracks)
>
> Kid A:
> - Version 1: MP3, 2000, 256 kbps, complete (10 tracks)
> - Version 2: FLAC, 2000, complete (10 tracks)
>
> Recommendations:
> - OK Computer: Keep Version 3 (2017 Remaster FLAC), remove v1 & v2
> - Kid A: Keep Version 2 (FLAC), remove v1
>
> This will free ~850MB. Proceed?

## When to Use the Skill

### ✅ Use the skill for:

- **Complete library cleanup** - First time or periodic deep clean
- **Duplicate removal** - Multiple strategies, safe and automated
- **Importing new downloads** - With proper matching and metadata
- **Fixing problematic albums** - Albums that won't match or have issues
- **Bulk operations** - Standardizing metadata across many albums
- **Library health checks** - Comprehensive analysis and reporting

### ⚠️ Use helper script instead for:

- **Quick duplicate check** - Just want to see what duplicates exist
- **Quick art fetch** - Just need to download missing art
- **Analysis only** - Just want a health report

```bash
# Quick operations with helper script
./workspace/utilities/beets-helper.sh find-duplicates
./workspace/utilities/beets-helper.sh analyze-library
./workspace/utilities/beets-helper.sh fix-missing-art
```

### 🔧 Use beets commands directly for:

- **Simple queries** - Looking up specific tracks/albums
- **Quick modifications** - Changing one or two fields
- **Testing** - Trying out commands before bulk operations

```bash
# Direct beets commands
beet ls artist:Ween
beet modify album:'Quebec' year=2003
beet fetchart album:'The Mollusk'
```

## Best Practices

### Before Starting Major Cleanup

1. **Backup database:**
   ```bash
   cp /opt/downloads/beets/beets-library.db /opt/downloads/beets/beets-library.db.backup
   ```

2. **Run analysis first:**
   ```
   "Use the beets skill to analyze my library"
   ```

3. **Review the plan** before confirming execution

4. **Stop Lidarr** if running (prevents conflicts):
   ```bash
   sudo systemctl stop podman-lidarr
   ```

### During Cleanup

1. **Trust the skill's recommendations** - It knows your setup
2. **Review ambiguous cases** - Skill will ask when uncertain
3. **Watch progress** - Skill provides updates during long operations
4. **Don't interrupt** - Let each step complete

### After Cleanup

1. **Review the report** - Check what changed
2. **Handle remaining issues** - Skill lists items needing attention
3. **Update Navidrome** - Skill does this automatically
4. **Restart Lidarr** if stopped:
   ```bash
   sudo systemctl start podman-lidarr
   ```

## Skill Features

### Internalized Knowledge

The skill knows:
- Your exact beets container configuration
- All your enabled plugins and their settings
- Your path format preferences
- Your import settings and thresholds
- Your music directory locations
- Your helper script commands
- Integration with Navidrome and Lidarr
- Common problems and solutions

### Safety Features

- **Database backups** before major operations
- **Dry-run simulation** for complex operations
- **Confirmation prompts** for destructive actions
- **Progress tracking** with ability to resume
- **Error recovery** with rollback capability
- **Detailed logging** of all operations

### Duplicate Removal Strategies

1. **Interactive** - Safest, walks through each group
2. **Keep Best Quality** - Automated by bitrate/format
3. **Format Preference** - Keep FLAC, remove lossy
4. **Path-Based** - Remove from specific directory
5. **Date-Based** - Keep newer imports

The skill recommends the best strategy based on your library analysis.

### Integration

- **Navidrome**: Refreshes library after changes
- **Lidarr**: Coordinates to prevent conflicts
- **SoulSeek (SLSKD)**: Imports rare albums
- **Helper Script**: Uses for quick operations
- **Monitoring**: Exports metrics (if configured)

## Troubleshooting

### Skill not finding issues

Make sure you're using the skill:
```
"Use the beets-music-organizer skill to..."
```

Not just:
```
"Find duplicates"  # This won't use the skill
```

### Skill taking too long

For large libraries (>10,000 tracks), some operations take time:
- Checksum-based duplicate detection: ~5-10 minutes
- Re-importing entire library: ~30-60 minutes
- Album art fetching: ~2-5 minutes per 100 albums

The skill provides progress updates.

### Want more control

Use the helper script for individual operations:
```bash
./workspace/utilities/beets-helper.sh clean-duplicates
```

Or use beets commands directly for fine-grained control.

## Related Documentation

- **Skill Code**: `.claude/skills/beets-music-organizer/SKILL.md`
- **Full Beets Guide**: `docs/media/BEETS_GUIDE.md`
- **Quick Reference**: `docs/media/BEETS_QUICK_REFERENCE.md`
- **Helper Script**: `workspace/utilities/beets-helper.sh`
- **Media System Overview**: `docs/media/README.md`

---

**When in doubt, just ask the skill:**

```
"What can the beets-music-organizer skill do?"
"What's the best way to remove duplicates?"
"How do I import new music properly?"
```

The skill will guide you through the process step-by-step!
