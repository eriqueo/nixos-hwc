# Beets Quick Reference Card

Essential beets commands for daily use. Full guide: `docs/media/BEETS_GUIDE.md`

## Helper Script (Recommended)

```bash
# Comprehensive analysis
./workspace/utilities/beets-helper.sh analyze-library

# Find duplicates
./workspace/utilities/beets-helper.sh find-duplicates

# Interactive cleanup
./workspace/utilities/beets-helper.sh clean-duplicates

# Fix album art
./workspace/utilities/beets-helper.sh fix-missing-art

# Import new music
./workspace/utilities/beets-helper.sh import /mnt/hot/manual/music/
```

## Top 10 Most Useful Commands

### 1. Find Duplicates
```bash
beet duplicates           # Find all duplicates
beet duplicates -k        # By checksum (most accurate)
beet duplicates -p        # Show full paths
```

### 2. Import Music
```bash
beet import /path/to/music/          # Interactive import
beet import -q /path/to/music/       # Quiet (auto-select best)
beet import -A /path/to/music/       # As-is (no matching)
```

### 3. Fix Album Art
```bash
beet fetchart             # Download missing art
beet fetchart -f          # Force re-fetch all
beet embedart             # Embed art into files
```

### 4. Search Library
```bash
beet ls artist:Ween                  # By artist
beet ls album:'Quebec'               # By album
beet ls year:2003                    # By year
beet ls -p artist:Ween album:Quebec  # Show paths
```

### 5. Find Problems
```bash
beet ls artpath::         # Missing album art
beet ls mb_albumid::      # Unmatched albums
beet missing              # Missing tracks in albums
beet duplicates           # Duplicate tracks
```

### 6. Statistics
```bash
beet stats                # Basic stats
beet stats -e             # Extended stats
```

### 7. Clean Metadata
```bash
beet scrub                # Remove unnecessary tags
beet write                # Write tags to files
beet update               # Update DB from files
```

### 8. Modify Metadata
```bash
beet modify album:'Title' artist='Correct Name'
beet modify year:2023 year=2024
beet move artist:'Beatles'  # Move files after modifying
```

### 9. Remove Items
```bash
beet remove album:'Album Name'       # Remove from DB
beet remove -d album:'Album Name'    # Remove + delete files
```

### 10. Get Info
```bash
beet info album:'Quebec'             # Detailed info
beet ls -f '$artist - $album'        # Custom format
```

## Common Queries

```bash
# Recently added (last 7 days)
beet ls added:-7d..

# Year range
beet ls year:2000..2010

# Low bitrate MP3s
beet ls format:MP3 bitrate:..192000

# FLAC files only
beet ls format:FLAC

# Missing genre
beet ls genre::

# Albums only
beet ls -a artist:Ween

# Specific path
beet ls path:/mnt/media/music/Ween/
```

## Duplicate Removal Workflow

```bash
# 1. Find duplicates
beet duplicates -k > /tmp/dupes.txt

# 2. Review
less /tmp/dupes.txt

# 3. Remove interactively
beet remove duplicate:true

# Or use helper script
./workspace/utilities/beets-helper.sh clean-duplicates
```

## Import Workflow

```bash
# 1. Put new music in staging
cp -r ~/Downloads/New\ Album/ /mnt/hot/manual/music/

# 2. Import with beets
beet import /mnt/hot/manual/music/

# 3. Fetch art and embed
beet fetchart -q added:-1h..
beet embedart -q added:-1h..

# 4. Scan Navidrome
curl -X POST http://localhost:4533/api/scan
```

## Maintenance Checklist

### Weekly
- [ ] `beet duplicates -k` - Check for duplicates
- [ ] `beet fetchart` - Download missing art

### Monthly
- [ ] `./workspace/utilities/beets-helper.sh analyze-library` - Full analysis
- [ ] `beet missing` - Check incomplete albums
- [ ] `beet scrub` - Clean metadata
- [ ] Backup database: `cp /opt/downloads/beets/beets-library.db{,.backup}`

### Quarterly
- [ ] `beet stats -e` - Review library growth
- [ ] `beet ls mb_albumid::` - Re-match unmatched albums
- [ ] Check for low-quality files

## Useful Aliases

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# Beets shortcuts
alias bl='beet ls'
alias bla='beet ls -a'
alias blp='beet ls -p'
alias bi='beet import'
alias bd='beet duplicates -k'
alias bf='beet fetchart && beet embedart'
alias bs='beet stats -e'
alias bh='~/nixos-hwc/workspace/utilities/beets-helper.sh'
```

## Quick Fixes

### "No matches found during import"
```bash
beet import -A /path/  # Import as-is, match later
beet import -L /path/  # Re-import to match
```

### "Database is locked"
```bash
pkill beet
sudo systemctl restart podman-beets
```

### "Album art not downloading"
```bash
beet fetchart -f -v    # Force with verbose output
```

### "Too many duplicates found"
```bash
# Keep highest quality
beet duplicates -k | while read dup; do
  beet ls -f '$bitrate $path' "$dup" | sort -rn | tail -n +2 | awk '{print $2}' | xargs -I {} beet remove -d path:{}
done
```

## Field Reference

Common fields for queries and formatting:

- `$artist`, `$albumartist` - Artists
- `$album` - Album title
- `$title` - Track title
- `$year` - Year
- `$genre` - Genre
- `$format` - Format (MP3, FLAC, etc.)
- `$bitrate` - Bitrate
- `$path` - File path
- `$mb_trackid` - MusicBrainz track ID
- `$added` - Date added
- `$track` - Track number

## Query Operators

- `:` - Contains (case-insensitive)
- `::` - Regex match
- `..` - Range (numeric or date)
- `,` - OR operator
- `^` - NOT operator

## Resources

- **Full Guide**: `docs/media/BEETS_GUIDE.md`
- **Helper Script**: `workspace/utilities/beets-helper.sh`
- **Config**: `/opt/downloads/beets/config.yaml`
- **Database**: `/opt/downloads/beets/beets-library.db`
- **Official Docs**: https://beets.readthedocs.io/

---

**Print this and keep it handy!** 📋
