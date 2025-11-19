#!/usr/bin/env bash
# fix-immich-database.sh
# Fixes Immich database migration issues
#
# Usage: sudo ./scripts/fix-immich-database.sh [option]
# Options:
#   1 - Drop problematic table only (safe, preserves data)
#   2 - Reset migrations table (moderate risk)
#   3 - Recreate entire database (DESTRUCTIVE - all data lost)
#   4 - Check database state (diagnostic only)

set -euo pipefail

DB_NAME="immich"
DB_USER="immich"
PROBLEMATIC_TABLE="asset_metadata_audit"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Immich Database Fix Tool ===${NC}\n"

# Check if we're root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Function to run SQL as postgres user
run_sql() {
    sudo -u postgres psql -d "$DB_NAME" -c "$1"
}

# Function to check database state
check_database() {
    echo -e "${GREEN}Checking database state...${NC}"

    # Check if database exists
    if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        echo -e "${GREEN}✓ Database '$DB_NAME' exists${NC}"
    else
        echo -e "${RED}✗ Database '$DB_NAME' not found${NC}"
        echo "  You may need to set createDB = true in your config"
        exit 1
    fi

    # Check if problematic table exists
    if sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name='$PROBLEMATIC_TABLE');" | grep -q t; then
        echo -e "${YELLOW}⚠ Table '$PROBLEMATIC_TABLE' exists (this is causing the error)${NC}"
    else
        echo -e "${GREEN}✓ Table '$PROBLEMATIC_TABLE' does not exist${NC}"
    fi

    # Check migrations table
    if sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name='migrations');" | grep -q t; then
        echo -e "${GREEN}✓ Migrations table exists${NC}"
        MIGRATION_COUNT=$(sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM migrations;")
        echo "  Applied migrations: $MIGRATION_COUNT"
    else
        echo -e "${YELLOW}⚠ Migrations table not found${NC}"
    fi

    # List all tables
    echo -e "\n${GREEN}All tables in database:${NC}"
    sudo -u postgres psql -d "$DB_NAME" -c "\dt" | grep "public" || echo "  No tables found"
}

# Option 1: Drop problematic table only
fix_drop_table() {
    echo -e "${YELLOW}Option 1: Dropping '$PROBLEMATIC_TABLE' table${NC}"
    echo "This will remove only the problematic table and let Immich recreate it."
    echo -e "${YELLOW}This is the SAFEST option - other data will be preserved.${NC}\n"

    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted"
        exit 1
    fi

    echo "Dropping table..."
    run_sql "DROP TABLE IF EXISTS $PROBLEMATIC_TABLE CASCADE;"
    echo -e "${GREEN}✓ Table dropped${NC}"
    echo -e "\nNow rebuild with: sudo nixos-rebuild switch --flake .#hwc-server"
}

# Option 2: Reset migrations table
fix_reset_migrations() {
    echo -e "${YELLOW}Option 2: Resetting migrations table${NC}"
    echo "This will clear the migration history, forcing Immich to re-check schema."
    echo -e "${YELLOW}MODERATE RISK: May cause Immich to re-run migrations${NC}\n"

    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted"
        exit 1
    fi

    echo "Resetting migrations..."
    run_sql "TRUNCATE TABLE migrations;"
    echo -e "${GREEN}✓ Migrations table cleared${NC}"
    echo -e "\nNow rebuild with: sudo nixos-rebuild switch --flake .#hwc-server"
}

# Option 3: Recreate entire database
fix_recreate_database() {
    echo -e "${RED}Option 3: Recreate entire database${NC}"
    echo -e "${RED}WARNING: This will DELETE ALL IMMICH DATA${NC}"
    echo "  - All photos metadata will be lost"
    echo "  - Albums, faces, memories will be deleted"
    echo "  - Photo files on disk will NOT be deleted"
    echo "  - You will need to re-upload/scan photos"
    echo
    echo -e "${RED}THIS IS DESTRUCTIVE AND CANNOT BE UNDONE${NC}\n"

    read -p "Are you ABSOLUTELY SURE? Type 'DELETE ALL DATA' to continue: " -r
    echo
    if [[ $REPLY != "DELETE ALL DATA" ]]; then
        echo "Aborted (correct choice!)"
        exit 1
    fi

    echo "Stopping Immich services..."
    systemctl stop immich-server.service || true
    systemctl stop immich-machine-learning.service || true

    echo "Dropping database..."
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS $DB_NAME;"

    echo "Recreating database..."
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"

    echo -e "${GREEN}✓ Database recreated${NC}"
    echo -e "\nNow rebuild with: sudo nixos-rebuild switch --flake .#hwc-server"
    echo "Then re-scan your photo library in Immich settings"
}

# Main menu
case "${1:-menu}" in
    1)
        check_database
        echo
        fix_drop_table
        ;;
    2)
        check_database
        echo
        fix_reset_migrations
        ;;
    3)
        check_database
        echo
        fix_recreate_database
        ;;
    4|check)
        check_database
        ;;
    menu|*)
        check_database
        echo
        echo -e "${GREEN}Select a fix option:${NC}"
        echo "  1) Drop '$PROBLEMATIC_TABLE' table only (RECOMMENDED - safe)"
        echo "  2) Reset migrations table (moderate risk)"
        echo "  3) Recreate entire database (DESTRUCTIVE)"
        echo "  4) Check database state only (no changes)"
        echo
        echo "Usage: sudo ./scripts/fix-immich-database.sh [1|2|3|4]"
        ;;
esac
