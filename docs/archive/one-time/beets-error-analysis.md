   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   BEETS MUSIC LIBRARY ERROR ANALYSIS
   Generated: $(date)
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   📊 LIBRARY STATISTICS
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Total Tracks:    6,780
   Total Albums:    472
   Total Artists:   174
   Album Artists:   54
   Total Size:      94.5 GiB
   Total Time:      2.8 weeks

   Format Distribution:
     - FLAC: 2,492 (37%)
     - AAC:  2,509 (37%)
     - MP3:  1,746 (26%)
     - AIFF: 31 (<1%)
     - WAVE: 2 (<1%)

   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   🚨 CRITICAL ERRORS FOUND
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   1. DATABASE CORRUPTION - ORPHANED ENTRIES
      Severity: CRITICAL
      Count: 108+ database entries for non-existent files

      Details:
      - 15 files in /music/__/ (malformed artist/album paths)
      - 93 files in /music/_/ (incomplete metadata paths)
      - Multiple files in "Compilations/Romeo and Juliet Soundtrack"
      - Multiple files in "_/Murmurs of Earth"
      - Multiple files in "_/Satisfied Mind"
      - Multiple files in "Compilations/The Roots of John Fahey"
      - Multiple Giraffes? Giraffes! tracks with .1 suffixes
      - Multiple Brian Eno tracks missing

      Impact: Database out of sync with filesystem, causes errors on every operation

      Example Orphaned Paths:
      - /music/__/00.mp3 through 00.14.mp3
      - /music/_/[265]/00.mp3 through 00.14.mp3
      - /music/_/[272]/00.mp3 through 00.14.mp3
      - /music/_/[368]/00.aiff through 00.30.aiff
      - /music/Giraffes_ Giraffes!/Death Breath/01 Pulse Lick.1.m4a
      - /music/Giraffes_ Giraffes!/Live in Toronto/*.1.mp3

   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   2. MASSIVE DUPLICATE PROBLEM
      Severity: CRITICAL
      Impact: Wasting ~10-20GB of storage, causing confusion

      Confirmed Duplicates:

      A. Giraffes? Giraffes! - Memory Lame (4 versions!):
         - /music/Giraffes_ Giraffes!/Memory Lame [166]/ (FLAC)
         - /music/Giraffes_ Giraffes!/Memory Lame/ (FLAC)
         - /music/Giraffes_ Giraffes!/Memory Lame [album]/ (M4A)
         - /music/Giraffes_ Giraffes!/Memory Lame [275]/ (FLAC)

      B. Giraffes? Giraffes! - SUPERBASS (2 versions)

      C. Giraffes? Giraffes! - Live in Toronto (3 path variations):
         - Giraffes_ Giraffes!/Live in Toronto/
         - GIRAFFES_ GIRAFFES!/Live In Toronto/
         - GIRAFFES_ GIRAFFES!/Live In Toronto [247]/

      D. Brian Eno - 77 Million (6 versions):
         - Brian Eno/77 Million/
         - Brian Eno/77 Million [402]/
         - (4 more variations)

      E. Brian Eno - Multiple Albums Duplicated:
         - "Lightness" Music For The Marble Palace (3 copies)
         - Ambient 4: On Land (2 copies)
         - Before and After Science (2 copies)

      Full duplicate count: Still calculating (background process)

   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   3. COMPLETE ABSENCE OF METADATA MATCHING
      Severity: CRITICAL
      Count: 6,780 tracks (100% OF LIBRARY!)

      Details:
      - Zero tracks have MusicBrainz IDs
      - Library has never been matched against MusicBrainz
      - Missing accurate metadata, album relationships, artist info

      Impact:
      - Cannot leverage beets' powerful matching features
      - Duplicate detection less accurate
      - Missing canonical data for organization
      - Integration with music services limited

   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   4. MISSING ALBUM ARTWORK
      Severity: HIGH
      Count: 472 albums (100% OF LIBRARY!)

      Details:
      - No albums have embedded or cached artwork
      - Artwork never fetched during import

      Sample Albums Missing Art:
      - All Ane Brun albums (23+)
      - All Arthur Russell albums
      - All Courtney Barnett albums
      - All Beach Boys albums
      - All Bibio albums
      - All Brian Eno albums (many)
      - All Giraffes? Giraffes! albums
      - Plus ~450 more

   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   5. LOW-QUALITY AUDIO FILES
      Severity: MEDIUM
      Count: 415 MP3 files under 192kbps

      Impact: Suboptimal listening quality, should consider re-acquiring

   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   6. INCOMPLETE ALBUMS
      Severity: MEDIUM
      Count: 100+ albums with missing tracks

      Sample Incomplete Albums:
      - All Ane Brun albums (23+ albums)
      - Arthur Russell albums (multiple)
      - Many others not shown

      Impact: Incomplete listening experience

   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   📋 RECOMMENDED CLEANUP PLAN
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   PHASE 1: DATABASE REPAIR (CRITICAL - DO FIRST)
      Estimated Time: 10-15 minutes
      Risk: Low (just cleaning database)

      1. Remove orphaned database entries
      2. Update database from actual files
      3. Verify database integrity

      Commands:
      beet update    # Sync DB with filesystem

      Expected Result: Clean database, no more "file not found" errors

   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   PHASE 2: DUPLICATE REMOVAL (CRITICAL)
      Estimated Time: 45-60 minutes
      Risk: Medium (file deletion)
      Storage Freed: ~10-20 GB

      Strategy: Keep highest quality, remove others
      - FLAC > M4A/AAC > MP3
      - Higher bitrate > lower bitrate
      - Most complete > partial

      Focus Areas:
      1. Giraffes? Giraffes! albums (4 versions → 1)
      2. Brian Eno albums (many duplicates)
      3. Systematic duplicate scan for rest of library

      Commands:
      beet duplicates -k                    # Find all by checksum
      ./workspace/utilities/beets-helper.sh clean-duplicates  # Interactive

   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   PHASE 3: MUSICBRAINZ MATCHING (HIGH PRIORITY)
      Estimated Time: 2-3 hours (automated)
      Risk: Low

      Re-import entire library with MusicBrainz matching:

      Commands:
      beet import -L /mnt/media/music/

      Benefits:
      - Accurate metadata
      - Better duplicate detection
      - Artist/album relationships
      - Integration with music services

      Expected Result: 6,780 tracks → 90%+ matched

   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   PHASE 4: ALBUM ARTWORK (HIGH PRIORITY)
      Estimated Time: 30-45 minutes
      Risk: Very Low

      Fetch and embed artwork for all 472 albums:

      Commands:
      beet fetchart -q
      beet embedart -q

      Expected Result: 472 albums → 450+ with artwork (95%+)

   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   PHASE 5: ADDRESS INCOMPLETE ALBUMS (OPTIONAL)
      Estimated Time: Variable
      Risk: N/A

      Review incomplete albums:
      - Decide if intentional (singles, EPs) or missing tracks
      - Re-download missing tracks where desired
      - Or accept as-is

   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   PHASE 6: QUALITY UPGRADE (OPTIONAL)
      Estimated Time: Variable
      Risk: N/A

      Review 415 low-bitrate MP3s:
      - Identify which are worth upgrading
      - Re-download in FLAC or higher quality
      - Replace low-quality versions

   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   📊 ESTIMATED TOTAL CLEANUP TIME
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Phases 1-4 (Critical): ~4-5 hours (mostly automated)
   Phases 5-6 (Optional): Variable based on goals

   Benefits After Cleanup:
   ✅ Clean, error-free database
   ✅ 10-20 GB storage freed
   ✅ Complete metadata from MusicBrainz
   ✅ Album artwork for all albums
   ✅ Better organization and searchability
   ✅ Integration with streaming services (Navidrome, etc.)

   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   NEXT STEPS
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   Ready to proceed? I recommend starting with Phase 1 (database repair) immediately,
   as it's low-risk and will eliminate errors on every operation.

   Would you like me to:
   1. Start Phase 1 (Database Repair) now
   2. Skip to Phase 2 (Duplicate Removal)
   3. Execute all phases automatically
   4. Manual step-by-step guidance
