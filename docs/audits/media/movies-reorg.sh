#!/usr/bin/env bash
# movies-reorg.sh — dry-run-by-default rename/move plan for /mnt/media/movies.
#
# Companion to docs/audits/media/movies-audit.md (2026-06-24 audit).
#
# Standard: Title (Year)/Title (Year).<ext>, one movie per folder.
#
# Usage:
#   ./movies-reorg.sh                # dry run (default) — prints what it would do
#   DRY_RUN=0 ./movies-reorg.sh      # actually move/rename (REVIEW FIRST)
#
# This script is NEVER invoked automatically. Eric reviews the audit and runs
# it by hand. Order: structural fixes first (root sweep, splits, manual review
# flags), then the bulk rename of 124 inner files.

set -euo pipefail

ROOT="${ROOT:-/mnt/media/movies}"
DRY_RUN="${DRY_RUN:-1}"

if [[ ! -d "$ROOT" ]]; then
    echo "ERROR: $ROOT not found" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Action helpers — dry run prints, real run executes.
# ---------------------------------------------------------------------------

say() { printf '%s\n' "$*"; }

do_mv() {
    local src="$1" dst="$2"
    if [[ ! -e "$src" ]]; then
        say "SKIP (missing): $src"
        return 0
    fi
    if [[ -e "$dst" ]]; then
        say "SKIP (dst exists): $dst"
        return 0
    fi
    if [[ "$DRY_RUN" == "1" ]]; then
        say "DRY mv -- '$src' '$dst'"
    else
        mv -- "$src" "$dst"
        say "MOVED -- '$src' -> '$dst'"
    fi
}

do_rmdir() {
    local d="$1"
    if [[ ! -d "$d" ]]; then
        say "SKIP (missing dir): $d"
        return 0
    fi
    if [[ -n "$(ls -A "$d" 2>/dev/null)" ]]; then
        say "SKIP (non-empty dir): $d"
        return 0
    fi
    if [[ "$DRY_RUN" == "1" ]]; then
        say "DRY rmdir -- '$d'"
    else
        rmdir -- "$d"
        say "RMDIR -- '$d'"
    fi
}

flag() {
    say "MANUAL-REVIEW: $*"
}

say "=========================================================================="
say "movies-reorg.sh — DRY_RUN=$DRY_RUN, ROOT=$ROOT"
say "=========================================================================="

# ---------------------------------------------------------------------------
# 1. Library-root sweep — loose files that don't belong at the library root.
# ---------------------------------------------------------------------------
say
say "### 1. Library-root sweep (5 files) ###"
if [[ "$DRY_RUN" == "1" ]]; then
    say "DRY mkdir -p -- '$ROOT/_misc'"
else
    mkdir -p "$ROOT/_misc"
fi
for f in REORGANIZATION_LOG.md MediaInfo.txt Libraries.html normalize_movies.py strict_clean.sh; do
    do_mv "$ROOT/$f" "$ROOT/_misc/$f"
done

# ---------------------------------------------------------------------------
# 2. Structural fixes — multi-movie folder, missing year, wrong year, empty.
# ---------------------------------------------------------------------------
say
say "### 2. Structural fixes ###"

# 2a. Split "The Jungle Book/" — two videos, one for 1967, one unknown year.
flag "split '$ROOT/The Jungle Book/' into two folders: the 1967 NORDiC rip belongs in 'The Jungle Book (1967)'; the bare 'The Jungle Book.mkv' (283 MB) needs a year — manual identify before moving."
if [[ "$DRY_RUN" == "1" ]]; then
    say "DRY mkdir -p -- '$ROOT/The Jungle Book (1967)'"
else
    mkdir -p "$ROOT/The Jungle Book (1967)"
fi
do_mv "$ROOT/The Jungle Book/The.Jungle.Book.1967.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1-NoTrace.mkv" \
      "$ROOT/The Jungle Book (1967)/The Jungle Book (1967).mkv"
flag "decide year for '$ROOT/The Jungle Book/The Jungle Book.mkv' before moving."

# 2b. Blade Runner 2049 — folder year is the in-universe year, not release year.
if [[ "$DRY_RUN" == "1" ]]; then
    say "DRY mv -- '$ROOT/Blade Runner (2049)' '$ROOT/Blade Runner 2049 (2017)'"
else
    mv -- "$ROOT/Blade Runner (2049)" "$ROOT/Blade Runner 2049 (2017)"
fi

# 2c. Empty folder.
flag "'$ROOT/Ice Age - Collision Course (2016)/' is empty — confirm intent (delete or refetch)."

# 2d. Nested subdirs at depth 2.
flag "'$ROOT/One Hundred and One Dalmatians (1961)/trailers/' — Radarr does not expect on-disk trailers; either delete or rename to '<folder>-trailer.mkv' (Plex extras convention)."
flag "'$ROOT/The Sword in the Stone (1963)/versions/' — looks like a duplicate copy; manual review (merge or delete)."

# ---------------------------------------------------------------------------
# 3. Inner-file renames — 124 single-video folders where filename != folder name.
#    Format below: folder<TAB>current-filename
# ---------------------------------------------------------------------------
say
say "### 3. Inner-file renames (124) ###"

rename_inner() {
    local folder="$1" current="$2"
    local ext="${current##*.}"
    local target="$folder.$ext"
    do_mv "$ROOT/$folder/$current" "$ROOT/$folder/$target"
}

# Generated 2026-06-24 from the audit; one entry = one inner-file rename.
# Folder<TAB>current filename.
while IFS=$'\t' read -r folder current; do
    [[ -z "$folder" ]] && continue
    rename_inner "$folder" "$current"
done <<'EOF'
A Bug's Life (1998)	A.Bugs.Life.1998.1080p.WEBRip.DD+7.1.x264-playHD.mkv
A Charlie Brown Christmas (1965)	A.Charlie.Brown.Christmas.1965.BluRay.1080p.DD.5.1.x264-hallowed.mkv
Airplane! (1980)	Airplane.1980.1080p.AMZN.WEB-DL.DDP5.1.H.264-BLOOM.mkv
Airplane II - The Sequel (1982)	Airplane.II.The.Sequel.1982.1080p.AMZN.WEB-DL.DDP2.0.H.264-BLOOM.mkv
Aladdin (1992)	Aladdin.1992.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1.Atmos-NoTrace.mkv
Aladdin and the King of Thieves (1996)	Aladdin.And.The.King.Of.Thieves.1996.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1-NoTrace.mkv
Alice in Wonderland (1951)	Alice.in.Wonderland.1951.1080p.BluRay.DD+5.1.x264-playHD.mkv
A Minecraft Movie (2025)	Un.Film.Minecraft.2025.iTA-ENG.WEB-DL.1080p.x264-CYBER.mkv
Atlantis - The Lost Empire (2001)	Atlantis.The.Lost.Empire.2001.NORDiC.ENG.1080p.DSNP.WEB-DL.H.264-NORViNE.mkv
Back to the Future (1985)	Back.to.the.Future.1985.1080p.MGMP.WEB-DL.DDP.5.1.H.264-PiRaTeS.mkv
Balto (1995)	Balto (1995) Bluray-1080p Proper.mkv
Bambi (1942)	Bambi 1942 1080p BluRay x264 DuaL-TURKO.mkv
Bambi II (2006)	Bambi.II.2006.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1-NoTrace.mkv
Beauty and the Beast (1991)	Beauty and the Beast 1991 1080p DSNP WEB-DL DDP5 1 Atmos H 264-BLOOM.mkv
Big Hero 6 (2014)	Big.Hero.6.2014.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1.Atmos-NoTrace.mkv
Blade Runner (1982)	Blade.Runner.1982.WEBRip.1080p.x264.EAC3.ITA.ENG.SUB.ITA.ENG-Lullozzo.mkv
Blade Runner (2049)	Blade.Runner.2049.2017.BluRay.1080p.DDP.Atmos.5.1.x264-hallowed.mkv
Blow-Up (1966)	Blow-Up.1966.1080p.BluRay.X264-AOS.mkv
Bugs Bunny's 3rd Movie - 1001 Rabbit Tales (1982)	Bugs.Bunnys.3rd.Movie.1001.Rabbit.Tales.1982.1080p.AMZN.WEB-DL.H264-SiGMA.mp4
Cars (2006)	Cars 2006 BluRay 1080p DDP 5 1 x264-hallowed.mkv
Cinderella (1950)	Cinderella.1950.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1-NoTrace.mkv
Cinderella II - Dreams Come True (2002)	Cinderella.II.Dreams.Come.True.2002.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1-NoTrace.mkv
Cinderella III - A Twist in Time (2007)	Cinderella.III.A.Twist.In.Time.2007.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1-NoTrace.mkv
Despicable Me (2010)	Despicable.Me.2010.1080p.PCOK.WEB-DL.DDP.5.1.H.264-OnlyWeb.mkv
Despicable Me 2 (2013)	Despicable.Me.2.2013.1080p.PCOK.WEB-DL.DDP.5.1.H.264-OnlyWeb.mkv
Despicable Me 3 (2017)	Despicable.Me.3.2017.1080p.PCOK.WEB-DL.DDP.5.1.H.264-OnlyWeb.mkv
Despicable Me 4 (2024)	Cattivissimo.Me.4.2024.iTA-ENG.Bluray.1080p.x264-CYBER.mkv
Donald in Mathmagic Land (1959)	Donald.in.Mathmagic.Land.1959.480p.DVDRip.AC3.x265.10bit-MarkII.mkv
Dr Strangelove or How I Learned to Stop Worrying and Love the Bomb (1964)	Dr.Strangelove.1964.1080p.BluRay.x264-CiNEFiLE.mkv
Duck Soup (1933)	01193.m2ts
Dune (2021)	Dune.2021.1080p.BluRay.DDP.7.1.x264-SPHD.mkv
Dune - Part Two (2024)	Dune.Parte.Due.2024.iTA-ENG.Bluray.1080p.x264-CYBER.mkv
FernGully - The Last Rainforest (1992)	FernGully.The.Last.Rainforest.1992.1080p.YT.WEB-DL.DDP.5.1.H.264-PiRaTeS.mkv
Forrest Gump (1994)	Forrest.Gump.1994.REPACK.1080p.MGMP.WEB-DL.DDP.5.1.H.264-PiRaTeS.mkv
Friendship (2025)	Friendship.2024.iTA-ENG.Bluray.1080p.x264-CYBER.mkv
Frosty the Snowman (1969)	Frosty the Snowman (1969) Bluray-1080p Proper.mkv
Gary Gulman - Born on 3rd Base (2023)	Gary.Gulman.Born.On.3rd.Base.2023.1080p.WEB.h264-EDITH.mkv
Gary Gulman - In This Economy! (2012)	Gary.Gulman.In.This.Economy.2012.1080p.AMZN.WEBRip.DD2.0.x264-QOQ.mkv
Gary Gulman - It's About Time (2016)	Gary.Gulman.Its.About.Time.2016.1080p.Netflix.WEB-DL.DD5.1.x264.mkv
Gary Gulman - The Great Depresh (2019)	Gary.Gulman.The.Great.Depresh.2019.1080p.AMZN.WEB-DL.DDP2.0.H....mkv
Glengarry Glen Ross (1992)	Glengarry Glen Ross (1992) Bluray-1080p.mkv
Harvey (1950)	Harvey.1950.BluRay.1080p.DTS-HD.MA.2.0.x264-HDH.mkv
Heat Lightning (1934)	heat.lightning.1934.1080p.hdtv.x264-regret.mkv
Here Comes Peter Cottontail (1971)	Here.Comes.Peter.Cottontail.1971.1080i.BluRay.REMUX.AVC.FLAC.2.0-EPSiLON.mkv
Horton Hatches the Egg (1942)	Horton Hatches the Egg (1942) WEBDL-1080p.mkv
How the Grinch Stole Christmas! (1966)	How the Grinch Stole Christmas! (1966) Bluray-1080p.mkv
How to Train Your Dragon (2010)	How.to.Train.Your.Dragon.2010.1080p.MAX.WEB-DL.DDP.5.1.H.264-OnlyWeb.mkv
How to Train Your Dragon (2025)	Dragon.Trainer.2025.iTA-ENG.PROPER.Bluray.1080p.x264-CYBER.mkv
How to Train Your Dragon 2 (2014)	How.to.Train.Your.Dragon.2.2014.1080p.BluRay.DTS-ES.x264-NTb.mkv
Idiocracy (2006)	Idiocracy.2006.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1-NoTrace.mkv
Incredibles 2 (2018)	Incredibles.2.2018.1080p.BluRay.DD.7.1.x264-playHD.mkv
I Never Sang for My Father (1970)	I.Never.Sang.for.My.Father.1970.1080p.AMZN.WEB-DL.DDP2.0.x264-ABM.mkv
It's the Easter Beagle, Charlie Brown (1974)	Its.The.Easter.Beagle.Charlie.Brown.1974.2160p.WEB-DL.AAC.5.1.SDR.x265.10bit-MarkII-xpost.mkv
It's the Great Pumpkin, Charlie Brown (1966)	It's the Great Pumpkin, Charlie Brown (1966) Bluray-1080p.mkv
It Was a Short Summer, Charlie Brown (1969)	It Was a Short Summer, Charlie Brown (1969) WEBDL-1080p.mkv
John Wick - Chapter 4 (2023)	John.Wick.4.2023.iTA-ENG.PROPER.Bluray.1080p.x264-CYBER.mkv
Lady and the Tramp (1955)	Lady and the Tramp 1955 1080p BluRay DDP 7 1 x264-j3rico.mkv
Lilo & Stitch (2002)	Lilo.and.Stitch.2002.1080p.DSNP.WEB-DL.DDP.5.1.H.264-SPWEB.mkv
Madagascar 3 - Europe's Most Wanted (2012)	Madagascar.3.Europes.Most.Wanted.2012.1080p.HMAX.WEB-DL.DD.5.1.H.264-SPWEB.mkv
Mary Poppins (1964)	Mary Poppins (1964) Bluray-1080p Proper.mkv
Me and My Pal (1933)	Me and My Pal (1933) Bluray-1080p.mkv
Moana 2 (2024)	Oceania.2.2024.iTA-ENG.PROPER.Bluray.1080p.x264-CYBER.mkv
Mulan (1998)	Mulan.1998.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1.Atmos-NoTrace.mkv
Mulan II (2004)	Mulan.II.2004.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1-NoTrace.mkv
My Father's Dragon (2022)	My.Fathers.Dragon.2022.PROPER.1080p.WEBRip.x264.mp4
My Man Godfrey (1936)	My.Man.Godfrey.1936.1080p.BluRay.REMUX.AVC.FLAC.1.0-EPSiLON.mkv
Mystery Science Theater 3000 - The Movie (1996)	Mystery Science Theater 3000 - The Movie (1996) Bluray-1080p.mkv
National Lampoon's European Vacation (1985)	National Lampoon's European Vacation (1985) Remux-1080p.mkv
National Lampoon's Vacation (1983)	National Lampoon's Vacation (1983) Bluray-1080p Proper.mkv
Notorious (1946)	Notorious (1946) Bluray-1080p.mkv
Oliver & Company (1988)	Oliver.And.Company.1988.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1-NoTrace.mkv
One Hundred and One Dalmatians (1961)	One.Hundred.And.One.Dalmatians.1961.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1-NoTrace.mkv
Peace on Earth (1939)	Peace.on.Earth.1939.1080p.BluRay.H264.AAC.mp4
Peter Pan (1953)	Peter.Pan.1953.1080p.4gtv.WEB-DL.x264.3Audio.AAC-PTerWEB.mkv
Pinocchio (1940)	Pinocchio 1940 1080p BluRay x264 DuaL-TURKO.mkv
Planes - Fire & Rescue (2014)	Planes.Fire.and.Rescue.2014.1080p.BluRay.DTS.x264-VietHD.mkv
Pocahontas (1995)	Pocahontas.1995.Disney.Classics.Timeless.Collection.1080p.BluRay.x264-OPUSLAW.mkv
Ponyo (2008)	Ponyo (2008) WEBDL-1080p.mkv
Pooh's Heffalump Movie (2005)	Poohs.Heffalump.Movie.2005.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1-NoTrace.mkv
Pulp Fiction (1994)	Pulp Fiction 1994 1080p PCOK WEB-DL DDP 5 1 H 264-PiRaTeS.mkv
Ratatouille (2007)	Ratatouille.2007.720p.BluRay.RoDubbed.DD.5.1.x264-SPHD.mkv
Shrek (2001)	Shrek.2001.1080p.HULU.WEB-DL.DDP.5.1.H.264-PiRaTeS.mkv
Shrek 2 (2004)	Shrek.2.2004.1080p.HULU.WEB-DL.DDP.5.1.H.264-PiRaTeS.mkv
Shrek The Third (2007)	Shrek.the.Third.2007.1080p.HULU.WEB-DL.DDP.5.1.H.264-PiRaTeS.mkv
Sleeping Beauty (1959)	Sleeping.Beauty.1959.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1-NoTrace.mkv
Snow Dogs (2002)	00045.m2ts
Snow White and the Seven Dwarfs (1937)	Snow White and the Seven Dwarfs 1937 1080p BluRay x264 DuaL-TURKO.mkv
Song of the Sea (2014)	Song of the Sea 2014 Upscaled BluRay 2160p HDR10 HEVC DTS-HD MA 5.1 x265-E.mkv
Sons of the Desert (1933)	Sons of the Desert (1933) Bluray-1080p.mkv
Spinal Tap II - The End Continues (2025)	Spinal Tap II - The End Continues (2025) WEBDL-2160p.mkv
Star Wars - Episode I - The Phantom Menace (1999)	Star Wars Episode I - The Phantom Menace (1999).mkv
Star Wars - The Last Jedi (2017)	Star.Wars.Episode.VIII.The.Last.Jedi.2017.BluRay.1080p.DD.5.1.x264-BHDStudio.mp4
The 39 Steps (1935)	The 39 Steps (1935) Bluray-1080p.mkv
The 39 Steps (1959)	The 39 Steps (1959) Bluray-1080p.mkv
The Emperor's New Groove (2000)	The Emperors New Groove 2000 1080p BluRay x264 DuaL-TURKO.mkv
The Godfather Part II (1974)	The.Godfather.Part.II.1974.1080p.BluRay.x264-ADHD.mkv
The Godfather Part III (1990)	The.Godfather.Part.III.1990.1080p.BluRay.DD5.1.x264-CtrlHD.mkv
The Great Mouse Detective (1986)	The Great Mouse Detective.mkv
The Grinch (2018)	The Grinch (2018) WEBDL-2160p.mkv
The Grinch Grinches the Cat in the Hat (1982)	The Grinch Grinches the Cat in the Hat (1982) WEBDL-1080p.mkv
The Hunchback of Notre Dame (1996)	The.Hunchback.Of.Notre.Dame.1996.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1-NoTrace.mkv
The Killing (1956)	The Killing (1956) Bluray-1080p.mkv
The Lego Movie 2 - The Second Part (2019)	The.Lego.Movie.2.The.Second.Part.2019.1080p.BluRay.DD.7.1.x264-Geek-WhiteRev.mkv
The Lion King (1994)	The.Lion.King.1994.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1.Atmos-NoTrace.mkv
The Little Mermaid (1989)	The.Little.Mermaid.1989.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1.Atmos-NoTrace.mkv
The Looney, Looney, Looney Bugs Bunny Movie (1981)	The.Looney.Looney.Looney.Bugs.Bunny.Movie.1981.1080p.AMZN.WEBRip.DDP2.0.x264-SiGMA.mkv
The Maltese Falcon (1941)	The.Maltese.Falcon.1941.1080p.BluRay.DD5.1.x264-CtrlHD.mkv
The Naked Gun 33 1 3 The Final Insult (1994)	Naked Gun 33 1 3 The Final Insult (1994).mkv
The Night of the Hunter (1955)	The Night of the Hunter (1955) Bluray-1080p Proper.mkv
The Rescuers Down Under (1990)	The Rescuers Down Under (1990) Bluray-1080p.mkv
The Return of Jafar (1994)	The.Return.Of.Jafar.1994.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1-NoTrace.mkv
The Secret Life of Pets (2016)	Pets-Vita.da.animali.2016.WEBRip.1080p.x264.EAC3.ITA.ENG.SUB.ITA.ENG-Lullozzo.mkv
The Secret Life of Pets 2 (2019)	Pets.2-Vita.da.animali.2019.WEBRip.1080p.x264.EAC3.ITA.ENG.SUB.ITA.ENG-Lullozzo.mkv
The Secret of Kells (2009)	The.Secret.of.Kells.2009.1080o.Blu-ray.Remux.AVC.DTS-HD.MA.5.1-HDT.mkv
The Secret of NIMH (1982)	The.Secret.of.Nimh.1982.1080p.AMZN.WEB-DL.DDPA.2.0.H.264-SPWEB.mkv
The Secret World of Arrietty (2010)	The Secret World of Arrietty (2010) Bluray-1080p.mkv
The Super Mario Galaxy Movie (2026)	The Super Mario Galaxy Movie 2026 1080p iT WEB-DL DDP5 1 Atmos H 264-BYNDR.mkv
The Sword in the Stone (1963)	The.Sword.in.the.Stone.1963.1080p.DSNP.WEB-DL.MULTI.DDP.5.1.H.264-OldT.mkv
To Have and Have Not (1945)	To.Have.and.Have.Not.1944.1080p.BluRay.REMUX.AVC.FLAC.2.0-EPSiLON.mkv
Treasure Planet (2002)	Treasure.Planet.2002.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1-NoTrace.mkv
Wallace and Gromit - A Close Shave (1995)	A Close Shave (1996).mkv
Wallace and Gromit - A Matter of Loaf and Death (2008)	A Matter of Loaf and Death (2008).mkv
Wallace and Gromit - Vengeance Most Fowl (2024)	Wallace.and.Gromit.Vengeance.Most.Fowl.2024.1080p.NF.WEB-DL.DDPA.5.1.x264-SPWEB.mkv
Winnie the Pooh - A Very Merry Pooh Year (2002)	00883.m2ts
EOF

# Notes for the manual reviewer:
# - "Blade Runner (2049)" entry above is intentional: the inner-file rename runs
#   AGAINST the original folder name. If you take the structural fix in §2b
#   first, re-generate the inner-file rename for the new folder name
#   "Blade Runner 2049 (2017)".
# - Several entries are language mismatches (Cattivissimo/Oceania/Dragon Trainer
#   etc.). Renaming to the folder basename is correct for Plex/Radarr matching;
#   the underlying audio language is unchanged.
# - "To Have and Have Not (1945)" inner file says "1944" — folder year may be
#   wrong; verify against TMDB before running.

say
say "=========================================================================="
say "Done. DRY_RUN=$DRY_RUN. Re-run with DRY_RUN=0 to execute."
say "=========================================================================="
