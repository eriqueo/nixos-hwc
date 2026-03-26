#!/usr/bin/env bash
#
# CouchDB Database Migration Script
# Migrates obsidian-* databases to sync_* naming scheme
# Consolidates transcript databases into sync_transcripts
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load CouchDB credentials from agenix
COUCHDB_USER=$(sudo cat /run/agenix/couchdb-admin-username)
COUCHDB_PASS=$(sudo cat /run/agenix/couchdb-admin-password)
COUCHDB_URL="http://127.0.0.1:5984"
AUTH="${COUCHDB_USER}:${COUCHDB_PASS}"

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}CouchDB Database Migration${NC}"
echo -e "${BLUE}======================================================================${NC}"
echo ""

# Function to check if database exists
db_exists() {
    local db=$1
    if curl -sf -u "$AUTH" "$COUCHDB_URL/$db" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to get document count
get_doc_count() {
    local db=$1
    curl -s -u "$AUTH" "$COUCHDB_URL/$db" | python3 -c "import sys, json; print(json.load(sys.stdin)['doc_count'])"
}

# Function to create database
create_db() {
    local db=$1
    echo -e "${YELLOW}Creating database: $db${NC}"
    curl -X PUT -u "$AUTH" "$COUCHDB_URL/$db" -s | python3 -m json.tool
}

# Function to replicate database
replicate_db() {
    local source=$1
    local target=$2
    echo -e "${YELLOW}Replicating $source → $target${NC}"

    curl -X POST -u "$AUTH" "$COUCHDB_URL/_replicate" \
        -H "Content-Type: application/json" \
        -d "{
            \"source\": \"$source\",
            \"target\": \"$target\",
            \"create_target\": true
        }" -s | python3 -m json.tool

    # Verify replication
    local source_count=$(get_doc_count "$source")
    local target_count=$(get_doc_count "$target")

    if [ "$source_count" -eq "$target_count" ]; then
        echo -e "${GREEN}✓ Replication verified: $target_count documents${NC}"
    else
        echo -e "${RED}✗ Replication mismatch: source=$source_count, target=$target_count${NC}"
        return 1
    fi
}

# Migration mapping
declare -A MIGRATIONS=(
    ["obsidian-hwc"]="sync_hwc"
    ["obsidian-nixos"]="sync_nixos"
    ["obsidian-personal"]="sync_personal"
    ["obsidian-tech"]="sync_tech"
    ["obsidian-templates"]="sync_templates"
    ["obsidian-website"]="sync_website"
)

echo -e "${BLUE}Step 1: Migrate standard vaults (obsidian-* → sync_*)${NC}"
echo ""

for old_db in "${!MIGRATIONS[@]}"; do
    new_db="${MIGRATIONS[$old_db]}"

    if db_exists "$old_db"; then
        doc_count=$(get_doc_count "$old_db")
        echo -e "${BLUE}Migrating: $old_db → $new_db ($doc_count docs)${NC}"

        if db_exists "$new_db"; then
            echo -e "${YELLOW}  Database $new_db already exists, skipping creation${NC}"
        else
            replicate_db "$old_db" "$new_db"
        fi
    else
        echo -e "${YELLOW}  Database $old_db does not exist, skipping${NC}"
    fi
    echo ""
done

echo ""
echo -e "${BLUE}Step 2: Consolidate transcript databases → sync_transcripts${NC}"
echo ""

# Check which transcript databases exist
TRANSCRIPT_DBS=("obsidian-transcripts" "yt-transcript-vault" "yt-transcripts-vault")
TRANSCRIPT_TARGET="sync_transcripts"

# Find the database with the most documents (the authoritative source)
max_docs=0
source_db=""

for db in "${TRANSCRIPT_DBS[@]}"; do
    if db_exists "$db"; then
        count=$(get_doc_count "$db")
        echo -e "${BLUE}Found: $db with $count documents${NC}"

        if [ "$count" -gt "$max_docs" ]; then
            max_docs=$count
            source_db=$db
        fi
    fi
done

if [ -z "$source_db" ]; then
    echo -e "${RED}✗ No transcript databases found!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Using $source_db as authoritative source ($max_docs docs)${NC}"
echo ""

if db_exists "$TRANSCRIPT_TARGET"; then
    existing_count=$(get_doc_count "$TRANSCRIPT_TARGET")
    echo -e "${YELLOW}Target database $TRANSCRIPT_TARGET already exists with $existing_count docs${NC}"
    read -p "Overwrite? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Deleting existing $TRANSCRIPT_TARGET...${NC}"
        curl -X DELETE -u "$AUTH" "$COUCHDB_URL/$TRANSCRIPT_TARGET" -s
        replicate_db "$source_db" "$TRANSCRIPT_TARGET"
    else
        echo -e "${YELLOW}Skipping transcript database migration${NC}"
    fi
else
    replicate_db "$source_db" "$TRANSCRIPT_TARGET"
fi

echo ""
echo -e "${BLUE}======================================================================${NC}"
echo -e "${GREEN}Migration Summary${NC}"
echo -e "${BLUE}======================================================================${NC}"
echo ""

# List all sync_* databases
echo -e "${BLUE}New databases:${NC}"
for db in $(curl -s -u "$AUTH" "$COUCHDB_URL/_all_dbs" | python3 -c "import sys, json; print('\n'.join([d for d in json.load(sys.stdin) if d.startswith('sync_')]))"); do
    count=$(get_doc_count "$db")
    echo -e "  ${GREEN}✓${NC} $db: $count documents"
done

echo ""
echo -e "${YELLOW}======================================================================${NC}"
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "${YELLOW}======================================================================${NC}"
echo ""
echo "1. Update Obsidian LiveSync on ALL devices:"
echo "   - Open each vault in Obsidian"
echo "   - Go to Settings → Community Plugins → Self-hosted LiveSync"
echo "   - Update 'Remote database name' according to:"
echo ""
printf "     %-25s → %s\n" "obsidian-hwc" "sync_hwc"
printf "     %-25s → %s\n" "obsidian-nixos" "sync_nixos"
printf "     %-25s → %s\n" "obsidian-personal" "sync_personal"
printf "     %-25s → %s\n" "obsidian-tech" "sync_tech"
printf "     %-25s → %s\n" "obsidian-templates" "sync_templates"
printf "     %-25s → %s\n" "obsidian-website" "sync_website"
printf "     %-25s → %s\n" "obsidian-transcripts" "sync_transcripts"
echo ""
echo "2. Update NixOS configuration:"
echo "   - Edit domains/server/networking/parts/transcript-api.nix"
echo "   - Change COUCHDB_DATABASE from 'yt-transcripts-vault' to 'sync_transcripts'"
echo "   - Run: sudo nixos-rebuild switch --flake .#hwc-server"
echo ""
echo "3. Verify all devices are syncing correctly"
echo ""
echo "4. After verification (24-48 hours), delete old databases:"
echo "   bash scripts/couchdb-cleanup-old-databases.sh"
echo ""
echo -e "${BLUE}======================================================================${NC}"
