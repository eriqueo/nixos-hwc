#!/usr/bin/env bash
#
# CouchDB Old Database Cleanup Script
# Deletes old obsidian-* and yt-* databases after migration verification
#
# DANGER: This permanently deletes databases. Only run after verifying
# that all devices are successfully syncing to the new sync_* databases.
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load credentials
COUCHDB_USER=$(sudo cat /run/agenix/couchdb-admin-username)
COUCHDB_PASS=$(sudo cat /run/agenix/couchdb-admin-password)
COUCHDB_URL="http://127.0.0.1:5984"
AUTH="${COUCHDB_USER}:${COUCHDB_PASS}"

echo -e "${RED}======================================================================${NC}"
echo -e "${RED}⚠️  WARNING: DATABASE DELETION SCRIPT${NC}"
echo -e "${RED}======================================================================${NC}"
echo ""
echo -e "${YELLOW}This script will PERMANENTLY DELETE the following databases:${NC}"
echo ""

# Databases to delete
OLD_DBS=(
    "obsidian-hwc"
    "obsidian-nixos"
    "obsidian-personal"
    "obsidian-tech"
    "obsidian-templates"
    "obsidian-website"
    "obsidian-transcripts"
    "yt-transcript-vault"
    "yt-transcripts-vault"
)

# Check which databases exist and show them
for db in "${OLD_DBS[@]}"; do
    if curl -sf -u "$AUTH" "$COUCHDB_URL/$db" > /dev/null 2>&1; then
        count=$(curl -s -u "$AUTH" "$COUCHDB_URL/$db" | python3 -c "import sys, json; print(json.load(sys.stdin)['doc_count'])")
        echo -e "  ${RED}✗${NC} $db ($count documents)"
    fi
done

echo ""
echo -e "${YELLOW}Have you verified that:${NC}"
echo "  1. All devices are syncing to the new sync_* databases?"
echo "  2. No sync errors in Obsidian LiveSync on any device?"
echo "  3. All data is present in the new databases?"
echo "  4. At least 24-48 hours have passed since migration?"
echo ""
echo -e "${RED}This action CANNOT be undone!${NC}"
echo ""

read -p "Are you ABSOLUTELY SURE you want to delete these databases? (type 'DELETE' to confirm): " confirm

if [ "$confirm" != "DELETE" ]; then
    echo -e "${GREEN}Cancelled. No databases were deleted.${NC}"
    exit 0
fi

echo ""
echo -e "${RED}Deleting old databases...${NC}"
echo ""

for db in "${OLD_DBS[@]}"; do
    if curl -sf -u "$AUTH" "$COUCHDB_URL/$db" > /dev/null 2>&1; then
        echo -e "${YELLOW}Deleting: $db${NC}"
        curl -X DELETE -u "$AUTH" "$COUCHDB_URL/$db" -s | python3 -m json.tool
    fi
done

echo ""
echo -e "${GREEN}======================================================================${NC}"
echo -e "${GREEN}Cleanup Complete${NC}"
echo -e "${GREEN}======================================================================${NC}"
echo ""
echo "Remaining databases:"
curl -s -u "$AUTH" "$COUCHDB_URL/_all_dbs" | python3 -m json.tool
echo ""
