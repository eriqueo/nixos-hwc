# Beets Music Library Management Guide

Comprehensive guide for using beets to organize, standardize, and maintain your music library on hwc-server.

## Quick Start

### Your Current Setup

**Beets Container:**
- Config: `/opt/downloads/beets/config.yaml`
- Database: `/opt/downloads/beets/beets-library.db`
- Music Library: `/mnt/media/music`

**Active Plugins:**
- `duplicates` - Find duplicate tracks
- `fetchart` - Download album artwork
- `embedart` - Embed artwork in files
- `scrub` - Clean metadata
- `replaygain` - Volume normalization
- `missing` - Find missing tracks
- `info` - Metadata information
- `chroma` - Acoustic fingerprinting

**Helper Script:** `workspace/utilities/beets-helper.sh`

## Using the Helper Script

The helper script automates common beets tasks:

```bash
# Analyze your library health
./workspace/utilities/beets-helper.sh analyze-library

# Find duplicates
./workspace/utilities/beets-helper.sh find-duplicates

# Interactive duplicate removal
./workspace/utilities/beets-helper.sh clean-duplicates

# Download missing album art
./workspace/utilities/beets-helper.sh fix-missing-art

# Standardize metadata
./workspace/utilities/beets-helper.sh normalize-tags

# Find incomplete albums
./workspace/utilities/beets-helper.sh find-missing-tracks

# Import new music
./workspace/utilities/beets-helper.sh import /mnt/hot/manual/music/
```

## Essential Beets Commands

### Library Querying

```bash
# List all music in library
beet ls

# List albums only
beet ls -a

# Search by artist
beet ls artist:'Radiohead'

# Search by album
beet ls album:'OK Computer'

# Search by year
beet ls year:2023

# Complex queries
beet ls artist:Ween year:2003..2010

# Show file paths
beet ls -p artist:Ween

# Show detailed info
beet info album:'Quebec'
```

### Duplicate Management

Your current config has the `duplicates` plugin configured with checksum verification (most accurate method).

```bash
# Find all duplicates
beet duplicates

# Find duplicates by checksum (most accurate)
beet duplicates -k

# Find duplicates of specific album
beet duplicates album:'Dark Side of the Moon'

# Show full file paths
beet duplicates -p

# Count duplicates
beet duplicates -c

# Find duplicates and copy to folder for review
beet duplicates -c /tmp/beets-review/
```

**Removing Duplicates:**

```bash
# Review before removing
beet duplicates -p | less

# Remove duplicates (interactive)
beet remove duplicate:true

# Remove duplicates and delete files
beet remove -d duplicate:true

# Remove specific duplicate
beet remove id:12345
```

**Advanced Duplicate Strategies:**

```bash
# Find duplicates by similar title/artist (fuzzy matching)
beet duplicates -t 80  # 80% similarity threshold

# Find duplicates in specific directory
beet duplicates path:/mnt/media/music/Ween/

# Export duplicate list for manual review
beet duplicates -f '$path' > /tmp/dupes.txt
```

### Album Art Management

```bash
# Fetch missing album art
beet fetchart

# Fetch art for specific album
beet fetchart album:'Quebec'

# Force re-fetch (overwrite existing)
beet fetchart -f

# Quiet mode (no prompts)
beet fetchart -q

# Embed artwork into files
beet embedart

# Embed for specific album
beet embedart album:'The Mollusk'

# Remove embedded art
beet embedart -r

# Clear album art and re-fetch
beet fetchart -f && beet embedart
```

### Metadata Standardization

```bash
# Scrub unnecessary metadata
beet scrub

# Scrub specific album
beet scrub album:'Quebec'

# Write tags from database to files
beet write

# Update database from file tags
beet update

# Re-import (re-match with MusicBrainz)
beet import -L /mnt/media/music/Ween/Quebec
```

### Finding Issues

```bash
# Find tracks without MusicBrainz ID
beet ls mb_trackid::

# Find albums without MusicBrainz ID
beet ls -a mb_albumid::

# Find tracks without album art
beet ls artpath::

# Find low bitrate MP3s
beet ls format:MP3 bitrate:..192000

# Find untagged files
beet ls artist:: album::

# Find missing tracks in albums
beet missing

# Find missing tracks for specific artist
beet missing artist:Ween
```

### Importing Music

```bash
# Import from directory (interactive)
beet import /mnt/hot/manual/music/

# Import single album
beet import /mnt/hot/manual/music/Ween\ -\ Quebec/

# Auto-import (skip prompts, use best match)
beet import -q /mnt/hot/manual/music/

# Import as-is (don't match, just organize)
beet import -A /mnt/hot/manual/music/

# Import without moving (copy instead)
beet import -C /mnt/hot/manual/music/

# Resume interrupted import
beet import -p /mnt/hot/manual/music/

# Import singles (non-album tracks)
beet import -s /mnt/hot/manual/music/singles/
```

### Modifying Library

```bash
# Modify album artist
beet modify album:'Quebec' albumartist='Ween'

# Fix year
beet modify album:'The Mollusk' year=1997

# Batch modifications
beet modify artist:'The Beatles' artist='Beatles'

# Move files after modification
beet move artist:'Beatles'

# Remove from library (keep files)
beet remove album:'Some Album'

# Remove from library and delete files
beet remove -d album:'Some Album'
```

### Statistics

```bash
# Library statistics
beet stats

# Extended stats
beet stats -e

# Stats for specific query
beet stats artist:Ween
```

## Advanced Plugin Usage

### Duplicates Plugin Deep Dive

Your config already has duplicates enabled. Here are advanced usage patterns:

**Configuration in `/opt/downloads/beets/config.yaml`:**
```yaml
duplicates:
  checksum: ffmpeg    # Use FFmpeg for audio fingerprinting
  copy: ""            # Copy duplicates to directory (disabled)
  move: ""            # Move duplicates to directory (disabled)
  keys: [mb_trackid, mb_albumid]  # Additional keys for matching
```

**Advanced Queries:**
```bash
# Find exact duplicates (same MusicBrainz ID)
beet duplicates -k mb_trackid

# Find near-duplicates (different versions)
beet duplicates -s 95  # 95% similarity

# Generate CSV report of duplicates
beet duplicates -f '$path|$artist|$album|$title' > dupes.csv

# Find duplicates and calculate disk space wasted
beet duplicates -f '$path' | while read f; do du -h "$f"; done | awk '{sum+=$1}END{print sum}'
```

**Batch Duplicate Removal Script:**
```bash
#!/bin/bash
# Keep highest quality duplicate, remove others

beet duplicates -p | sort | uniq | while read -r dup_group; do
  # Get all file paths in duplicate group
  files=$(beet ls -p "$dup_group")

  # Find highest bitrate
  best=$(echo "$files" | xargs -I {} sh -c 'echo $(beet info -f "$bitrate" "{}") {}' | sort -rn | head -1 | awk '{print $2}')

  # Remove all except best
  echo "$files" | grep -v "$best" | xargs -I {} beet remove -d path:{}
done
```

### Missing Tracks Plugin

```bash
# Find all incomplete albums
beet missing

# Find missing tracks with details
beet missing -f '$albumartist - $album: Missing track $track'

# Find missing for specific artist
beet missing artist:Ween

# Export missing track list
beet missing -f '$albumartist|$album|$track' > missing-tracks.csv
```

### Chroma Plugin (Acoustic Fingerprinting)

For matching files when metadata is wrong/missing:

```bash
# Submit fingerprints to AcousticBrainz
beet submit

# Generate fingerprints for matching
beet fingerprint

# Re-import using fingerprints
beet import -L --set "acoustid_id=<id>"
```

### ReplayGain Plugin

Normalize volume across tracks:

```bash
# Calculate ReplayGain for entire library
beet replaygain

# Calculate for specific album
beet replaygain album:'Quebec'

# Calculate for specific artist
beet replaygain artist:Ween

# Force recalculation
beet replaygain -f
```

## Recommended Additional Plugins

Your current setup is good, but here are useful plugins to consider adding:

### 1. **Edit Plugin** - Edit metadata in your text editor

**Add to config:**
```yaml
plugins: [...existing..., edit]
```

**Usage:**
```bash
# Edit album metadata
beet edit album:'Quebec'

# Edit all metadata for artist
beet edit artist:Ween
```

### 2. **Convert Plugin** - Transcode to different formats

**Add to config:**
```yaml
plugins: [...existing..., convert]

convert:
  auto: no
  dest: /mnt/media/music-converted
  format: opus
  formats:
    opus:
      command: ffmpeg -i $source -y -acodec libopus -ab 128k $dest
      extension: opus
```

**Usage:**
```bash
# Convert album to Opus
beet convert -a album:'Quebec'

# Convert to MP3 for portable device
beet convert -f mp3 artist:Ween
```

### 3. **LastGenre Plugin** - Fetch genre tags

**Add to config:**
```yaml
plugins: [...existing..., lastgenre]

lastgenre:
  auto: yes
  source: album
```

**Usage:**
```bash
# Fetch genres
beet lastgenre

# Fetch for specific album
beet lastgenre album:'Quebec'
```

### 4. **Lyrics Plugin** - Download lyrics

**Add to config:**
```yaml
plugins: [...existing..., lyrics]

lyrics:
  auto: yes
  sources: [google, genius, lyrics.com]
```

**Usage:**
```bash
# Fetch lyrics
beet lyrics

# Fetch for specific song
beet lyrics title:'Transdermal Celebration'
```

### 5. **Smart Playlist Plugin** - Auto-generate playlists

**Add to config:**
```yaml
plugins: [...existing..., smartplaylist]

smartplaylist:
  playlists:
    - name: 'recently_added.m3u'
      query: 'added:-30d..'
    - name: 'rock_2000s.m3u'
      query: 'genre:Rock year:2000..2009'
    - name: 'high_rated.m3u'
      query: 'rating:0.8..1.0'
```

**Usage:**
```bash
# Update playlists
beet splupdate
```

### 6. **BPM Plugin** - Detect tempo

**Add to config:**
```yaml
plugins: [...existing..., bpm]

bpm:
  auto: no
```

**Usage:**
```bash
# Calculate BPM
beet bpm

# Calculate for dance music
beet bpm genre:Electronic
```

### 7. **FromFilename Plugin** - Extract metadata from filenames

Useful when tags are completely missing:

**Usage:**
```bash
# Extract from filename pattern
beet fromfilename -f '%artist - %album - %track %title'
```

### 8. **MBSync Plugin** - Sync with MusicBrainz updates

```bash
# Update metadata from MusicBrainz
beet mbsync album:'Quebec'
```

## Workflow Recipes

### Recipe 1: Complete Library Cleanup

```bash
#!/bin/bash
# Complete library maintenance

echo "1. Finding and removing duplicates..."
beet duplicates -k > /tmp/dupes.txt
echo "Review /tmp/dupes.txt and run: beet remove <query>"

echo "2. Fetching missing album art..."
beet fetchart -q

echo "3. Embedding artwork..."
beet embedart -q

echo "4. Normalizing metadata..."
beet scrub

echo "5. Finding incomplete albums..."
beet missing > /tmp/missing.txt
echo "Review /tmp/missing.txt"

echo "6. Generating statistics..."
beet stats -e

echo "Done! Review /tmp/dupes.txt and /tmp/missing.txt"
```

### Recipe 2: Import New Music Properly

```bash
#!/bin/bash
# Import music with full processing

SOURCE="/mnt/hot/manual/music"

echo "Importing from $SOURCE..."
beet import -q "$SOURCE"

echo "Fetching album art..."
beet fetchart -q added:-1h..

echo "Embedding artwork..."
beet embedart -q added:-1h..

echo "Calculating ReplayGain..."
beet replaygain added:-1h..

echo "Done!"
```

### Recipe 3: Fix Low-Quality Files

```bash
#!/bin/bash
# Find and report low-quality files

echo "Low bitrate MP3s (<192kbps):"
beet ls -p format:MP3 bitrate:..192000 > /tmp/low-quality.txt
cat /tmp/low-quality.txt

echo ""
echo "Files saved to /tmp/low-quality.txt"
echo "Consider re-downloading in higher quality"
```

### Recipe 4: Standardize Artist Names

```bash
#!/bin/bash
# Fix common artist name inconsistencies

# Remove "The" prefix
beet modify -y 'artist::^The ' artist_sort='$artist' artist='${artist/The /}'

# Fix featuring variations
beet modify -y 'artist::(feat.|ft.)' artist='${artist/ feat.*/}' artist_credit='$artist'

# Standardize & vs and
beet modify -y 'artist::&' artist='${artist/&/and}'
```

### Recipe 5: Bulk Organize by Genre

```bash
#!/bin/bash
# Create genre-specific playlists

for genre in Rock Electronic Jazz Classical Hip-Hop; do
  beet ls -p genre:"$genre" > "/mnt/media/playlists/${genre}.m3u"
  echo "Created ${genre}.m3u"
done
```

## Useful Query Syntax

### Field Comparisons

```bash
# Exact match
beet ls artist:'Ween'

# Pattern match (case-insensitive)
beet ls artist:ween

# Regex match
beet ls artist::'^Wee'

# NOT operator
beet ls artist:'Ween' ^album:'Quebec'

# OR operator (multiple queries)
beet ls artist:Ween , artist:'Primus'

# Numeric ranges
beet ls year:2000..2010
beet ls bitrate:192000..

# Date ranges
beet ls added:-7d..
beet ls added:2024-01-01..

# Missing values
beet ls artist::
beet ls genre::
```

### Common Field Names

- `artist`, `albumartist` - Artist names
- `album` - Album title
- `title` - Track title
- `year` - Release year
- `genre` - Genre tag
- `format` - File format (MP3, FLAC, etc.)
- `bitrate` - Bitrate in bps
- `path` - File path
- `artpath` - Album art path
- `mb_trackid`, `mb_albumid` - MusicBrainz IDs
- `added` - Date added to library
- `rating` - Track rating (if set)

### Query Examples by Use Case

**Find all FLAC files:**
```bash
beet ls format:FLAC
```

**Find albums from the 90s:**
```bash
beet ls -a year:1990..1999
```

**Find albums added this month:**
```bash
beet ls -a added:-30d..
```

**Find compilations:**
```bash
beet ls -a comp:true
```

**Find singles (not part of albums):**
```bash
beet ls singleton:true
```

**Find specific audio format:**
```bash
beet ls format:FLAC samplerate:96000
```

## External Resources

### Official Documentation
- **Beets Docs**: https://beets.readthedocs.io/
- **Plugin Reference**: https://beets.readthedocs.io/en/stable/plugins/index.html
- **Query Syntax**: https://beets.readthedocs.io/en/stable/reference/query.html

### Community Scripts
- **Awesome Beets**: https://github.com/tidalwave/awesome-beets
- **Beets Scripts Collection**: https://github.com/geigerzaehler/beets-scripts
- **Community Plugins**: https://github.com/beetbox/beets/wiki/Plugins

### Related Tools
- **MusicBrainz Picard**: GUI for tagging (https://picard.musicbrainz.org/)
- **AcousticBrainz**: Acoustic analysis (https://acousticbrainz.org/)
- **Last.fm**: Genre and metadata (https://www.last.fm/)

### Useful GitHub Issues/Discussions
- **Duplicate Strategies**: https://github.com/beetbox/beets/issues/2563
- **Performance Tips**: https://github.com/beetbox/beets/issues/1891
- **Best Practices**: https://github.com/beetbox/beets/discussions

## Troubleshooting

### Issue: "Database is locked"

```bash
# Check for other beets processes
ps aux | grep beet

# Kill hung processes
pkill -9 beet

# Or restart the container
sudo systemctl restart podman-beets
```

### Issue: "No matches found" during import

```bash
# Try with relaxed matching
beet import -t

# Or import as-is and match later
beet import -A
beet import -L /mnt/media/music/Album/
```

### Issue: Duplicates not found

```bash
# Force checksum calculation
beet duplicates -k -f

# Check plugin is enabled
beet config | grep duplicates
```

### Issue: Album art not downloading

```bash
# Check fetchart sources
beet config | grep fetchart

# Force fetch with verbose output
beet fetchart -f -v

# Try different source
beet fetchart -f -s coverart
```

### Issue: Slow performance

```bash
# Check database size
ls -lh /opt/downloads/beets/beets-library.db

# Vacuum database
sqlite3 /opt/downloads/beets/beets-library.db "VACUUM;"

# Re-index
beet import -L /mnt/media/music/
```

## Integration with Media Stack

### Navidrome Integration

Beets organizes music perfectly for Navidrome:

```bash
# After importing/organizing with beets
curl -X POST http://localhost:4533/api/scan

# Or restart Navidrome to pick up changes
sudo systemctl restart podman-navidrome
```

### Automation with Systemd Timer

Create automated library maintenance:

```bash
# Create systemd service
sudo tee /etc/systemd/system/beets-maintenance.service <<'EOF'
[Unit]
Description=Beets Library Maintenance
After=network.target

[Service]
Type=oneshot
User=eric
ExecStart=/home/eric/nixos-hwc/workspace/utilities/beets-helper.sh analyze-library
ExecStart=/usr/bin/beet fetchart -q
ExecStart=/usr/bin/beet embedart -q
StandardOutput=journal

[Install]
WantedBy=multi-user.target
EOF

# Create timer
sudo tee /etc/systemd/system/beets-maintenance.timer <<'EOF'
[Unit]
Description=Run beets maintenance weekly

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable --now beets-maintenance.timer
```

## Best Practices

1. **Always backup before bulk operations**
   ```bash
   cp /opt/downloads/beets/beets-library.db /opt/downloads/beets/beets-library.db.backup
   ```

2. **Use queries to test modifications**
   ```bash
   # Test first
   beet ls artist:'Beatles'
   # Then modify
   beet modify artist:'Beatles' artist='The Beatles'
   ```

3. **Import in batches**
   - Import albums one at a time for better control
   - Use `-q` only when you trust the source

4. **Regular maintenance schedule**
   - Weekly: Check for duplicates
   - Monthly: Fetch missing art
   - Quarterly: Full library analysis

5. **Version control your config**
   - Keep `/opt/downloads/beets/config.yaml` in git
   - Track changes over time

---

**Last Updated:** 2025-11-21
**Version:** 1.0.0
**Maintainer:** Eric (hwc-server)
