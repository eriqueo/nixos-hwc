# Media File Organizer

Automated media file organization tool for the nixos-hwc media server, following the automation rules defined in the `media-file-manager` Claude skill.

## Overview

This tool helps organize media files from `/mnt/hot` to `/mnt/media` with:

- ✅ **Safety-first**: Checksums verify every move, sources kept until verified
- ✅ **Smart detection**: Auto-identifies movies, TV shows, and music
- ✅ **Naming cleanup**: Removes quality tags, release groups, normalizes spacing
- ✅ **Structure enforcement**: Creates *arr-compatible directory layouts
- ✅ **Quarantine system**: Problem files isolated for manual review

## Installation

The script is located at: `workspace/utilities/media-organizer.sh`

Dependencies (available in NixOS):
```bash
nix-shell -p rsync coreutils jq curl mediainfo
```

## Usage

### 1. Analyze Files First

Always start by analyzing to see what will be done:

```bash
./workspace/utilities/media-organizer.sh analyze /mnt/hot/manual/movies
```

**Output:**
```
ℹ Analyzing directory: /mnt/hot/manual/movies
  ✅ Movie ready: Finding Nemo (2003).mkv
  ⚠️  Movie needs API: Star Wars Episode I The Phantom Menace.mkv (missing year)
  ✅ Movie ready: Citizen Kane (1941).mkv

ℹ Analysis complete:
  Total files:      3
  Ready to process: 2
  Need API lookup:  1
  Need review:      0
```

### 2. Dry Run (Test Without Changes)

Test the organization without actually moving files:

```bash
./workspace/utilities/media-organizer.sh organize /mnt/hot/manual/movies --dry-run
```

**Output:**
```
ℹ DRY RUN MODE - No files will be modified
ℹ Would move: Finding Nemo (2003).mkv → /mnt/media/movies/Finding Nemo (2003)/Finding Nemo (2003).mkv
⚠️  Missing year - needs API lookup: Star Wars Episode I The Phantom Menace.mkv
```

### 3. Execute (Actually Move Files)

When satisfied with the plan, execute:

```bash
./workspace/utilities/media-organizer.sh organize /mnt/hot/manual/movies --execute
```

**Confirmation Required:**
```
⚠️  EXECUTE MODE - Files will be moved!
Are you sure? (yes/no): yes
```

## Target Structures

### Movies
```
/mnt/media/movies/
├── Finding Nemo (2003)/
│   └── Finding Nemo (2003).mkv
├── Star Wars Episode I - The Phantom Menace (1999)/
│   └── Star Wars Episode I - The Phantom Menace (1999).mkv
└── Citizen Kane (1941)/
    └── Citizen Kane (1941).mkv
```

### TV Shows
```
/mnt/media/tv/
├── The Simpsons (1989)/
│   ├── Season 01/
│   │   ├── The Simpsons - S01E01 - Episode Title.mkv
│   │   └── The Simpsons - S01E02 - Episode Title.mkv
│   └── Season 02/
│       └── The Simpsons - S02E01 - Episode Title.mkv
```

### Music
```
/mnt/media/music/
├── Ween/
│   ├── Quebec (2003)/
│   │   ├── 01 - It's Gonna Be A Long Night.flac
│   │   └── 02 - Zoloft.flac
│   └── The Mollusk (1997)/
```

## Quarantine System

Files that can't be automatically organized go to `/mnt/hot/quarantine/`:

```
/mnt/hot/quarantine/
├── movies/
│   ├── ambiguous/          # Multiple possible matches
│   ├── missing-metadata/   # No year found, needs API lookup
│   └── corrupted/          # File integrity issues
├── tv/
│   ├── ambiguous/
│   ├── missing-metadata/   # No SXXEXX pattern or series name unclear
│   └── corrupted/
└── music/
    ├── ambiguous/
    ├── missing-metadata/   # Missing artist/album tags
    └── corrupted/
```

## Common Scenarios

### Scenario 1: Bulk Movie Organization

**Input:** Mixed torrent downloads in `/mnt/hot/downloads/usenet/movies/`

```bash
# 1. Analyze
./workspace/utilities/media-organizer.sh analyze /mnt/hot/downloads/usenet/movies/

# 2. Review output, check quarantine reasons

# 3. Organize ready files
./workspace/utilities/media-organizer.sh organize /mnt/hot/downloads/usenet/movies/ --execute

# 4. Check quarantine for manual review
ls -la /mnt/hot/quarantine/movies/missing-metadata/
```

### Scenario 2: TV Season Pack

**Input:** `The.Simpsons.S26.720p.BluRay.x264/` with 22 episodes

```bash
# Note: TV shows need API integration for episode titles
# Current script will quarantine TV files for manual processing
# Use the Claude skill "media-file-manager" for full TV automation

# 1. Analyze
./workspace/utilities/media-organizer.sh analyze /mnt/hot/manual/tv/

# 2. Files will be quarantined with note to use API
# 3. Use Claude to fetch episode metadata and organize
```

### Scenario 3: Music Album Cleanup

**Input:** `2003 - Quebec/` with track files

```bash
# 1. Analyze
./workspace/utilities/media-organizer.sh analyze /mnt/hot/manual/music/

# 2. Script reads ID3 tags to determine artist
# 3. Creates proper structure: Ween/Quebec (2003)/
```

## Integration with Claude Skill

For advanced features (API lookups, metadata fetching), use the Claude `media-file-manager` skill:

```
# In Claude Code chat:
"Organize the movies in /mnt/hot/manual/movies/ using the media-file-manager skill"
```

**The skill provides:**
- TMDb API integration for movie year/title lookup
- TVDb API integration for episode titles
- MusicBrainz integration for album metadata
- Intelligent handling of edge cases
- Multi-disc album consolidation
- Ambiguity resolution (presents choices)

## Monitoring & Logs

**Logs:** `/var/log/media-automation/organize-YYYYMMDD-HHMMSS.log`

**Contents:**
- Timestamp for each operation
- Source and destination paths
- Checksum verification results
- Error messages and reasons

**View recent log:**
```bash
tail -f /var/log/media-automation/organize-*.log | tail -1
```

## Safety Features

### Checksums
Every move is verified with SHA256:
```bash
# Source checksum calculated
sha256sum source.mkv

# File moved with rsync
rsync -av source.mkv dest.mkv

# Destination verified
sha256sum dest.mkv

# Only deleted if checksums match
```

### Rollback
If verification fails:
1. Destination file deleted
2. Source file preserved
3. Error logged
4. User notified

### Atomic Operations
All operations are atomic:
- Move completes fully or not at all
- No partial/corrupted states
- Source always preserved on failure

## Troubleshooting

### "Missing dependencies"
```bash
# Install required tools
nix-shell -p rsync coreutils jq curl mediainfo

# Or add to system packages in NixOS config
environment.systemPackages = with pkgs; [
  rsync
  coreutils
  jq
  curl
  mediainfo
];
```

### "Storage >80%"
Clean up old files first:
```bash
# Check usage
df -h /mnt/hot
df -h /mnt/media

# Clean up processed files
rm -rf /mnt/hot/processing/*/
```

### "Checksum mismatch"
File may be corrupted:
```bash
# Check file integrity
mediainfo /path/to/file.mkv

# If corrupted, move to quarantine/corrupted/
# Re-download original
```

### "Permission denied"
Fix ownership:
```bash
# Set proper ownership (user:group 1000:1000)
sudo chown -R 1000:1000 /mnt/hot/manual/
sudo chown -R 1000:1000 /mnt/media/
```

## Next Steps

1. **Test in dry-run mode first** - Always!
2. **Review quarantine files** - Manual attention needed
3. **Use Claude skill for API integration** - For complete automation
4. **Monitor Jellyfin/Navidrome** - Ensure services pick up new files
5. **Set up systemd timer** - For automatic processing (see below)

### Automated Processing (Systemd Timer)

Create a systemd service and timer for automatic organization:

```nix
# In your NixOS config
systemd.services.media-auto-organize = {
  description = "Automatically organize media files";
  serviceConfig = {
    Type = "oneshot";
    ExecStart = "${pkgs.bash}/bin/bash /home/user/nixos-hwc/workspace/utilities/media-organizer.sh organize /mnt/hot/manual/movies --execute";
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

## Related Documentation

- **Automation Rules**: `/mnt/media/AUTOMATION_RULES.md` (define your rules)
- **Media Stack Guide**: `/mnt/media/MASTER_MEDIA_STACK_EXPLAINER.md` (system overview)
- **Claude Skill**: `.claude/skills/media-file-manager/SKILL.md` (full automation)

---

**Last Updated:** 2025-11-21
**Version:** 1.0.0
**Maintainer:** Eric (with Claude assistance)
