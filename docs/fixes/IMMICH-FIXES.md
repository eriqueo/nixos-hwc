# Immich Fixes

## Issue 1: Storage Path Configuration (SOLVED ✅)

**Issue:** Immich crash loop with error: `Failed to read /mnt/photos/library/library/.immich`

**Root Cause:** Configuration bug causing duplicate path segments. Both `UPLOAD_LOCATION` and `mediaLocation` were set to `/mnt/photos/library`, but Immich automatically appends `/library` to the base path, creating `/mnt/photos/library/library/.immich`.

**Fix Applied:** Changed both settings to use `cfg.storage.basePath` (`/mnt/photos`) instead of `cfg.storage.locations.library`.

**Status:** ✅ **FIXED** - Immich now running successfully on both server instances.

---

## Issue 2: Database Migration Errors

**Issue:** `relation "asset_metadata_audit" already exists`

**Cause:** Database schema out of sync with Immich's migration state, typically after version upgrades or interrupted migrations.

---

## Quick Fix (Recommended)

**On the server, run:**

```bash
cd /path/to/nixos-hwc
sudo ./scripts/fix-immich-database.sh 1
```

This will:
1. Check database state
2. Drop only the problematic `asset_metadata_audit` table
3. Preserve all your photo metadata, albums, and faces
4. Let Immich recreate the table on next startup

Then rebuild:
```bash
sudo nixos-rebuild switch --flake .#hwc-server
```

---

## All Fix Options

### Option 1: Drop Problematic Table (RECOMMENDED ✅)
```bash
sudo ./scripts/fix-immich-database.sh 1
```
- **Risk:** Very low
- **Data Loss:** None
- **Effect:** Removes only the conflicting table
- **Best for:** Standard migration errors

### Option 2: Reset Migration State
```bash
sudo ./scripts/fix-immich-database.sh 2
```
- **Risk:** Moderate
- **Data Loss:** None (but migrations may re-run)
- **Effect:** Clears migration history
- **Best for:** When Option 1 doesn't work

### Option 3: Recreate Database (DESTRUCTIVE ⚠️)
```bash
sudo ./scripts/fix-immich-database.sh 3
```
- **Risk:** VERY HIGH
- **Data Loss:** ALL metadata, albums, faces, memories
- **Effect:** Fresh start
- **Best for:** When nothing else works and you have backups

### Option 4: Diagnostic Check
```bash
sudo ./scripts/fix-immich-database.sh 4
# or
sudo ./scripts/fix-immich-database.sh check
```
- **Risk:** None
- **Data Loss:** None
- **Effect:** Shows database state without making changes

---

## Post-Fix Steps

1. **After running the fix:**
   ```bash
   sudo nixos-rebuild switch --flake /path/to/nixos-hwc#hwc-server
   ```

2. **Check Immich service:**
   ```bash
   sudo systemctl status immich-server.service
   sudo journalctl -u immich-server.service -n 50
   ```

3. **If successful:**
   - Visit Immich at `http://server-ip:2283`
   - All your photos should still be there
   - Albums, faces, and metadata preserved

4. **If still failing:**
   - Check logs: `sudo journalctl -u immich-server.service -f`
   - Try Option 2 (reset migrations)
   - Last resort: Option 3 (recreate database)

---

## Why This Happens

Immich uses TypeORM migrations to manage database schema. When you:
- Upgrade Immich versions
- Have an interrupted migration (power loss, crash)
- Switch between containerized and native Immich

The migration state table can become out of sync with the actual database schema, causing it to try creating tables that already exist.

---

## Prevention

To avoid this in the future:

1. **Check Immich logs before upgrading:**
   ```bash
   sudo journalctl -u immich-server.service -n 100
   ```

2. **Backup database before major upgrades:**
   ```bash
   sudo -u postgres pg_dump immich > /tmp/immich-backup-$(date +%Y%m%d).sql
   ```

3. **Use systematic upgrades:**
   - Don't skip multiple Immich versions at once
   - Read Immich release notes for breaking changes

---

## Technical Details

**Database Schema:**
- Database name: `immich`
- User: `immich`
- Config: `profiles/server.nix:311-325`

**Configuration:**
```nix
hwc.server.immich = {
  enable = true;
  database = {
    createDB = false;  # Using existing database
    name = "immich";
    user = "immich";
  };
};
```

**The problematic table:**
- `asset_metadata_audit` - Stores audit trail for photo metadata changes
- Used by Immich for tracking when metadata is modified
- Non-critical for basic Immich functionality
- Safe to drop and recreate

---

## Troubleshooting

**"Database 'immich' not found"**
- Change config to `createDB = true`
- Rebuild to let NixOS create the database

**"Permission denied"**
- Run script with sudo: `sudo ./scripts/fix-immich-database.sh`

**"Service won't start after fix"**
- Check logs: `sudo journalctl -u immich-server.service -xe`
- Verify storage directories exist
- Check GPU acceleration settings

**"All photos are gone"**
- Photo files are in `/mnt/photos` (not affected by database)
- Use Immich's external library feature to re-scan
- Or restore from backup: `sudo -u postgres psql immich < backup.sql`

---

## Related Files

- Fix script: `scripts/fix-immich-database.sh`
- Immich module: `domains/server/immich/index.nix`
- Server config: `machines/server/config.nix`
- Profile config: `profiles/server.nix:311-325`
