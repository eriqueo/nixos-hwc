# Media Automation Rules & Patterns

**Target Location:** `/mnt/media/AUTOMATION_RULES.md` (copy this file there)

This document defines the canonical rules for automated media file organization on the hwc-server media stack. These rules are internalized by the Claude `media-file-manager` skill.

## Universal Rules

### File Safety
- **NEVER** delete source files until target verification complete
- **ALWAYS** use rsync for file operations: `rsync -av source/ dest/`
- **VERIFY** file integrity with checksums before removing originals
- **PRESERVE** original file timestamps and permissions

### Naming Conventions
- **NO** special characters in directory names: `? / \ : * " > < |`
- **STANDARDIZE** spaces vs underscores: prefer spaces for readability
- **CONSISTENT** year format: always `(YYYY)` with parentheses
- **CLEAN** release group tags: remove `[TGx]`, `[RARBG]`, etc.

### Directory Structure
- **MAXIMUM** 2 levels deep for organized content
- **DESCRIPTIVE** names that match *arr service expectations
- **AVOID** generic names like "CD 01", "Disc 2", "New Folder"

## Movies Automation Rules

### Target Structure
```
/mnt/media/movies/
├── Movie Title (Year)/
│   └── Movie Title (Year) [Quality-Source].ext
```

### Filename Patterns to Clean

#### Pattern 1: Root-level files
```
INPUT:  Finding Nemo.mkv
OUTPUT: Finding Nemo (2003)/Finding Nemo (2003).mkv
RULE:   Extract title → API lookup year → create directory
```

#### Pattern 2: Torrent directories with quality specs
```
INPUT:  Star.Wars.Episode.I.The.Phantom.Menace.1999.720p.DSNP.WEBRip.900MB.x264-GalaxyRG[TGx]/
OUTPUT: Star Wars Episode I - The Phantom Menace (1999)/
RULE:   Extract title and year → clean dots/underscores → remove quality tags
```

#### Pattern 3: Site-prefixed directories
```
INPUT:  www.UIndex.org - Citizen Kane 1941 1080p BluRay FLAC x264-CRiSC/
OUTPUT: Citizen Kane (1941)/
RULE:   Remove site prefix → extract title and year → clean release info
```

### Movie Title Cleaning Rules
1. **Replace dots with spaces**: `Star.Wars.Episode.I` → `Star Wars Episode I`
2. **Remove release groups**: `[TGx]`, `[RARBG]`, `-GalaxyRG`, etc.
3. **Remove quality specs**: `720p`, `1080p`, `BluRay`, `WEBRip`, `x264`, etc.
4. **Remove size info**: `900MB`, `1.5GB`, etc.
5. **Handle special characters**: `33.1.3` → `33⅓` (if appropriate)
6. **Preserve essential punctuation**: Keep hyphens in `Spider-Man`
7. **Title case consistency**: `The Matrix` not `THE MATRIX`

### Movie API Integration
- **Primary**: TMDb API for year lookup and validation
- **Fallback**: OMDB API for missing data
- **Cache**: Store API results locally to avoid repeat calls
- **Rate limiting**: Respect API limits (40 requests per 10 seconds for TMDb)

## TV Shows Automation Rules

### Target Structure
```
/mnt/media/tv/
├── Series Name (Year)/
│   ├── Season 01/
│   │   └── Series Name - S01E01 - Episode Title.ext
│   └── Season 02/
│       └── Series Name - S02E01 - Episode Title.ext
```

### Episode Pattern Extraction

#### Pattern 1: Standard SXXEXX format
```
INPUT:  South.Park.S02E01.1080p.BluRay.DD5.1.x264-W4NK3R/
OUTPUT: South Park (1997)/Season 02/South Park - S02E01 - Episode Title.mkv
RULE:   Extract series, season, episode → remove quality tags → API lookup title
```

#### Pattern 2: Torrent directory per episode
```
INPUT:  Band.of.Brothers.S01E01.Currahee.1080p.BluRay.x265-DH/
OUTPUT: Band of Brothers (2001)/Season 01/Band of Brothers - S01E01 - Currahee.mkv
RULE:   Extract all components → standardize naming → group by series
```

#### Pattern 3: Mixed episode files
```
INPUT:  It's Always Sunny in Philadelphia A Very Sunny Christmas (1080p Bluray x265 10bit BugsFunny).mkv
OUTPUT: It's Always Sunny in Philadelphia (2005)/Specials/It's Always Sunny in Philadelphia - S00E01 - A Very Sunny Christmas.mkv
RULE:   Manual review queue → identify season → standardize naming
```

### Series Name Standardization
1. **Remove dots**: `South.Park` → `South Park`
2. **Preserve articles**: Keep "The" in "The Simpsons"
3. **Year format**: Always `(YYYY)` from series start year
4. **Special characters**: Handle `&` vs `and` consistently
5. **Subtitle handling**: "Series: Subtitle" → "Series - Subtitle"

### Season/Episode Logic
- **Season extraction**: From SXXEXX pattern or directory structure
- **Episode numbering**: Zero-padded (S01E01, not S1E1)
- **Special episodes**: Use S00EXX for specials/extras
- **Multi-part episodes**: Use S01E01-E02 format
- **Missing episodes**: Flag for manual review

### TV API Integration
- **Primary**: TVDb API for episode metadata
- **Fallback**: TMDb API for series information
- **Episode titles**: Fetch from API when missing from filename
- **Season validation**: Cross-reference episode counts

## Music Automation Rules

### Target Structure
```
/mnt/media/music/
├── Artist Name/
│   ├── Album Name (Year)/
│   │   ├── 01 - Track Title.ext
│   │   └── 02 - Track Title.ext
│   └── Album Name 2 (Year)/
```

### Album Pattern Transformations

#### Pattern 1: Year-first albums
```
INPUT:  2003 - Quebec/
OUTPUT: Ween/Quebec (2003)/
RULE:   Extract year and album → metadata lookup artist → create structure
```

#### Pattern 2: Generic disc names
```
INPUT:  CD 01/ (with track files)
OUTPUT: Artist Name/Album Name (Year)/
RULE:   Analyze track metadata → extract artist/album → rename directory
```

#### Pattern 3: Multi-disc albums
```
INPUT:  Disc 1/, Disc 2/, Disc 3/
OUTPUT: Artist Name/Album Name (Year)/
RULE:   Detect disc set → consolidate → renumber tracks (1-01, 1-02, 2-01, 2-02)
```

### Artist Name Standardization
1. **Remove "The" prefix**: "The Beatles" → "Beatles" (configurable)
2. **Handle collaborations**: "Artist A & Artist B" → "Artist A"
3. **Sort characters**: "AC/DC" → "AC-DC" for filesystem compatibility
4. **Various Artists**: Use "Various Artists" for compilations
5. **Featuring**: "Artist feat. Guest" → "Artist"

### Album Name Cleaning
1. **Remove brackets**: `[Remastered]`, `[Deluxe Edition]` → separate field
2. **Year format**: Always `(YYYY)` from release year
3. **Special editions**: "Album (Year) [Deluxe]" format
4. **Reissues**: Use original release year, not reissue year
5. **Compilations**: "Greatest Hits (Year)" format

### Track Numbering
1. **Zero-padded**: 01, 02, 03... (not 1, 2, 3)
2. **Multi-disc**: 1-01, 1-02, 2-01, 2-02...
3. **Track titles**: "01 - Track Title.ext" format
4. **Special characters**: Remove filesystem-incompatible characters
5. **Durations**: Don't include in filename

### Music Metadata Strategy
- **Primary**: Audio file tags (ID3v2, FLAC, M4A)
- **Secondary**: MusicBrainz API for validation
- **Fallback**: Directory structure analysis
- **Quality**: Preserve original audio quality and format

## Error Handling & Manual Review

### Automatic Retry Scenarios
- **Network timeouts**: Retry API calls with exponential backoff
- **File locks**: Wait and retry file operations
- **Temporary failures**: Disk space, permissions, etc.

### Manual Review Queue
- **Ambiguous titles**: Multiple possible matches
- **Missing metadata**: API lookups return no results
- **Conflicting information**: File tags vs API data mismatch
- **Special cases**: Bootlegs, rare releases, foreign content

### Recovery Procedures
1. **Failed moves**: Rollback to previous state
2. **Corrupted files**: Restore from backup
3. **API quota exceeded**: Pause and resume processing
4. **Disk space issues**: Clean up temporary files

## Quality Assurance Checks

### Pre-processing Validation
- [ ] Source file integrity check
- [ ] Sufficient disk space available
- [ ] No file locks or access issues
- [ ] Backup verification

### Post-processing Validation
- [ ] Target structure compliance
- [ ] File integrity verification
- [ ] No orphaned files
- [ ] Service integration test

### Ongoing Monitoring
- [ ] Processing speed metrics
- [ ] Error rate tracking
- [ ] API usage monitoring
- [ ] Storage space trends

---

*Rules Version: 1.0*
*Created: 2025-11-21*
*Last Updated: 2025-11-21*
*Maintained By: Eric (hwc-server)*

**Usage:** Copy this file to `/mnt/media/AUTOMATION_RULES.md` on hwc-server for Claude skill to reference.
