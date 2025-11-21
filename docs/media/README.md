# Media Automation System

Comprehensive automation tools for organizing media files on the hwc-server media stack.

## Components

### 1. Claude Skill: `media-file-manager`
**Location:** `.claude/skills/media-file-manager/SKILL.md`

**Purpose:** AI-powered media organization with intelligent API integration

**Capabilities:**
- TMDb API integration for movie metadata
- TVDb API integration for TV show episodes
- MusicBrainz integration for music albums
- Intelligent filename parsing and cleaning
- Ambiguity resolution with user choices
- Multi-disc album consolidation
- Safe file operations with checksum verification

**Usage:**
```
# In Claude Code:
"Organize the movies in /mnt/hot/manual/movies/ using the media-file-manager skill"
"Analyze TV shows in /mnt/hot/downloads/usenet/tv/"
"What needs to be fixed in /mnt/hot/quarantine/?"
```

### 2. Shell Script: `media-organizer.sh`
**Location:** `workspace/utilities/media-organizer.sh`

**Purpose:** Standalone automation script for basic organization

**Capabilities:**
- Pattern-based file detection and organization
- Safe rsync-based moves with checksum verification
- Quarantine system for problematic files
- Dry-run mode for testing
- Detailed logging

**Usage:**
```bash
# Analyze files
./workspace/utilities/media-organizer.sh analyze /mnt/hot/manual/movies

# Dry run
./workspace/utilities/media-organizer.sh organize /mnt/hot/manual/movies --dry-run

# Execute
./workspace/utilities/media-organizer.sh organize /mnt/hot/manual/movies --execute
```

**Documentation:** `workspace/utilities/README-media-organizer.md`

### 3. Automation Rules
**Template:** `docs/media/AUTOMATION_RULES_TEMPLATE.md`
**Target:** `/mnt/media/AUTOMATION_RULES.md` (copy to server)

**Purpose:** Canonical rules for media organization

**Defines:**
- File naming conventions
- Directory structure standards
- API integration patterns
- Safety requirements
- Quality assurance checks

## System Overview

### Storage Architecture
```
/mnt/hot/  (SSD - 916GB)
├── downloads/          # Active downloads
├── processing/         # *arr temporary processing
├── quarantine/         # Problematic files
│   ├── movies/
│   ├── tv/
│   └── music/
└── manual/             # Manual import staging

/mnt/media/  (HDD - 7.3TB)
├── movies/             # Final movie library
├── tv/                 # Final TV library
└── music/              # Final music library
```

### Pipeline Flow
```
Download → /mnt/hot/downloads/ → *arr Processing →
→ /mnt/hot/processing/ → Verification →
→ /mnt/media/{movies,tv,music}/ → Jellyfin/Navidrome
```

### Service Integration
- **Sonarr** (port 8989): TV show automation
- **Radarr** (port 7878): Movie automation
- **Lidarr** (port 8686): Music automation
- **Jellyfin** (port 8096): Video streaming
- **Navidrome** (port 4533): Music streaming
- **Prometheus/Grafana**: Monitoring

## Quick Start

### First-Time Setup

1. **Copy automation rules to server:**
```bash
# On hwc-server:
cp ~/nixos-hwc/docs/media/AUTOMATION_RULES_TEMPLATE.md /mnt/media/AUTOMATION_RULES.md
```

2. **Test the script:**
```bash
# From nixos-hwc repo:
./workspace/utilities/media-organizer.sh analyze /mnt/hot/manual/movies
```

3. **Use Claude skill for advanced features:**
```
# In Claude Code:
"Use the media-file-manager skill to organize /mnt/hot/manual/movies/"
```

### Common Workflows

#### Organize New Movie Downloads
```bash
# 1. Check what's downloaded
ls -la /mnt/hot/downloads/usenet/movies/

# 2. Analyze
./workspace/utilities/media-organizer.sh analyze /mnt/hot/downloads/usenet/movies/

# 3. Organize with Claude (gets API metadata)
# In Claude:
"Organize movies in /mnt/hot/downloads/usenet/movies/"
```

#### Handle TV Show Season Pack
```
# In Claude:
"I have The Simpsons S26 in /mnt/hot/manual/tv/. Organize it with proper episode titles."

# Claude will:
1. Scan files for SXXEXX patterns
2. Lookup series on TVDb
3. Fetch episode titles
4. Create: /mnt/media/tv/The Simpsons (1989)/Season 26/
5. Rename: The Simpsons - S26E01 - Episode Title.mkv
```

#### Fix Music Album Tags
```
# In Claude:
"Fix the album in /mnt/hot/manual/music/2003 - Quebec/"

# Claude will:
1. Read ID3 tags from tracks
2. Identify: Artist=Ween, Album=Quebec, Year=2003
3. Create: /mnt/media/music/Ween/Quebec (2003)/
4. Rename tracks: 01 - Track Title.flac
```

#### Review Quarantined Files
```
# In Claude:
"What's in the quarantine that needs my attention?"

# Claude will:
1. Scan /mnt/hot/quarantine/
2. Categorize by reason (ambiguous, missing-metadata, corrupted)
3. Present choices for ambiguous files
4. Suggest actions for each
```

## File Organization Standards

### Movies
```
/mnt/media/movies/Finding Nemo (2003)/Finding Nemo (2003).mkv
```
- Format: `Movie Title (YYYY)/Movie Title (YYYY).ext`
- Title case, clean of quality tags
- Year from TMDb API

### TV Shows
```
/mnt/media/tv/The Simpsons (1989)/Season 26/The Simpsons - S26E22 - Mathlete's Feat.mkv
```
- Format: `Series (YYYY)/Season XX/Series - SXXEXX - Episode Title.ext`
- Zero-padded season/episode
- Episode titles from TVDb API

### Music
```
/mnt/media/music/Ween/Quebec (2003)/01 - It's Gonna Be A Long Night.flac
```
- Format: `Artist/Album (YYYY)/XX - Track Title.ext`
- Zero-padded track numbers
- Metadata from ID3 tags or MusicBrainz

## Safety Features

### Checksum Verification
Every file move is verified:
```bash
1. Calculate SHA256 of source
2. rsync source → destination
3. Calculate SHA256 of destination
4. Compare checksums
5. Only delete source if match
```

### Quarantine System
Problem files isolated by category:
- **ambiguous**: Multiple possible matches
- **missing-metadata**: Need API lookup or user input
- **corrupted**: File integrity issues

### Logging
All operations logged to:
- `/var/log/media-automation/organize-YYYYMMDD-HHMMSS.log`
- Includes timestamps, paths, checksums, errors

## Monitoring Integration

### Prometheus Metrics
```promql
# Files processed
media_files_processed_total{type="movies",status="success"}

# Processing duration
media_processing_duration_seconds{type="movies"}

# Quarantine count
media_quarantine_files{type="movies"}
```

### Grafana Dashboard
- Processing success rate
- Files in quarantine alert
- Processing duration trends
- Storage usage tracking

## Troubleshooting

### "Missing year" for movies
→ Use Claude skill with TMDb API integration

### "No SXXEXX pattern" for TV
→ Use Claude skill to parse and lookup episode

### "Generic CD names" for music
→ Use Claude skill to read ID3 tags and organize

### "Storage >80%"
→ Clean up `/mnt/hot/processing/` and old downloads

### "Checksum mismatch"
→ File may be corrupted, check with `mediainfo`

## Advanced Features

### Automated Processing (Systemd Timer)

Add to NixOS config:
```nix
systemd.services.media-auto-organize = {
  description = "Automatically organize media files";
  serviceConfig = {
    Type = "oneshot";
    ExecStart = "${pkgs.bash}/bin/bash ${path-to-script} organize /mnt/hot/manual/movies --execute";
    User = "eric";
  };
};

systemd.timers.media-auto-organize = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "hourly";
    Persistent = true;
  };
};
```

### API Key Configuration

Store API keys in agenix secrets:
```nix
# domains/secrets/declarations/media-apis.nix
age.secrets.tmdb-api-key = {
  file = ../parts/media/tmdb-api-key.age;
  group = "secrets";
  mode = "0440";
};
```

Use in automation:
```bash
TMDB_API_KEY=$(cat /run/agenix/tmdb-api-key)
```

## Related Documentation

- **Skill Documentation**: `.claude/skills/media-file-manager/SKILL.md`
- **Script Documentation**: `workspace/utilities/README-media-organizer.md`
- **Automation Rules**: Copy `docs/media/AUTOMATION_RULES_TEMPLATE.md` → `/mnt/media/AUTOMATION_RULES.md`
- **Media Stack Overview**: Document your stack at `/mnt/media/MASTER_MEDIA_STACK_EXPLAINER.md`

## Support

For issues or improvements:
1. Check logs in `/var/log/media-automation/`
2. Review quarantine files in `/mnt/hot/quarantine/`
3. Use Claude skill for complex cases
4. Consult automation rules in `/mnt/media/AUTOMATION_RULES.md`

---

**Version:** 1.0.0
**Created:** 2025-11-21
**Last Updated:** 2025-11-21
**Maintainer:** Eric (hwc-server)
