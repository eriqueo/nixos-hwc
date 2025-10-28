#!/bin/bash

# Music Library Duplicate Detection Script
# Run this in your music directory and paste the results back to Claude

MUSIC_DIR="/mnt/media/music"
echo "=== MUSIC LIBRARY DUPLICATE ANALYSIS ==="
echo "Analyzing: $MUSIC_DIR"
echo "Total artists: $(ls -1 "$MUSIC_DIR" | wc -l)"
echo ""

echo "=== 1. SIZE-BASED DUPLICATE DETECTION ==="
echo "Finding folders with identical sizes..."
find "$MUSIC_DIR" -mindepth 1 -maxdepth 1 -type d -exec du -sb {} \; | sort -n -k1,1 | awk '
{
    size = $1
    $1 = ""
    path = substr($0, 2)
    if (size == prev_size && size > 1000000) {
        if (!shown[prev_size]) {
            print "SIZE: " prev_size " bytes"
            print "  " prev_path
            shown[prev_size] = 1
        }
        print "  " path
    }
    prev_size = size
    prev_path = path
}'
echo ""

echo "=== 2. SUSPICIOUS NAME PATTERNS ==="
echo "Artists with similar names (case-insensitive)..."
ls -1 "$MUSIC_DIR" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | sort | uniq -c | sort -nr | awk '$1 > 1 {print "SIMILAR: " $1 " matches - " $2}'
echo ""

echo "=== 3. SPECIFIC DUPLICATE CANDIDATES ==="
for pattern in "giraffe" "looking" "ween" "brian" "beach" "various"; do
    echo "PATTERN: $pattern"
    find "$MUSIC_DIR" -mindepth 1 -maxdepth 1 -iname "*${pattern}*" -type d | while read dir; do
        if [ -d "$dir" ]; then
            name=$(basename "$dir")
            files=$(find "$dir" -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" -o -name "*.wav" 2>/dev/null | wc -l)
            size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            echo "  $name: $files files, $size"
        fi
    done
    echo ""
done

echo "=== 4. EMPTY OR SPARSE FOLDERS ==="
echo "Folders with 0-2 music files..."
find "$MUSIC_DIR" -mindepth 1 -maxdepth 1 -type d | while read dir; do
    if [ -d "$dir" ]; then
        name=$(basename "$dir")
        files=$(find "$dir" -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" -o -name "*.wav" 2>/dev/null | wc -l)
        if [ $files -le 2 ]; then
            size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            echo "  $name: $files files, $size"
        fi
    fi
done

echo ""
echo "=== 5. YEAR-PREFIXED FOLDERS ==="
echo "Folders starting with years that might be misplaced albums..."
ls -1 "$MUSIC_DIR" | grep "^[0-9][0-9][0-9][0-9]"

echo ""
echo "=== ANALYSIS COMPLETE ==="
echo "Review the output above for potential duplicates and issues."