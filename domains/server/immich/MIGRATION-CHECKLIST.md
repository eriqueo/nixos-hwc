# Immich Storage Migration Checklist

Use this checklist when migrating to the new storage layout with organized templates.

## Pre-Migration

- [ ] **Read STORAGE-GUIDE.md** - Understand the new storage structure
- [ ] **Review current storage** - Check what data exists and where
  ```bash
  du -sh /mnt/photos/*
  df -h /mnt/photos
  ```

- [ ] **Verify backup destination has space** - Ensure enough space for full backup
  ```bash
  df -h /mnt/backup
  # Need: Current photos size + 20% buffer
  ```

- [ ] **Create full backup** (CRITICAL - DO NOT SKIP)
  ```bash
  # Backup photos
  sudo mkdir -p /mnt/backup/immich-pre-migration-$(date +%Y%m%d)
  sudo rsync -av --progress /mnt/photos/ /mnt/backup/immich-pre-migration-$(date +%Y%m%d)/

  # Backup database
  sudo -u postgres pg_dump immich | zstd > /mnt/backup/immich-db-pre-migration-$(date +%Y%m%d).sql.zst

  # Verify backups
  ls -lh /mnt/backup/immich-pre-migration-*/
  ls -lh /mnt/backup/immich-db-pre-migration-*.sql.zst
  ```

- [ ] **Document current configuration** - Save current settings
  ```bash
  # Save current NixOS config
  cp /etc/nixos/configuration.nix /tmp/config-backup-$(date +%Y%m%d).nix

  # Take screenshot of Immich storage template settings (if any)
  ```

- [ ] **Test backup restore** - Verify backups are valid (optional but recommended)
  ```bash
  # Test database restore to temporary database
  sudo -u postgres createdb immich_test
  zstdcat /mnt/backup/immich-db-pre-migration-*.sql.zst | sudo -u postgres psql -d immich_test
  sudo -u postgres dropdb immich_test
  ```

## Migration

- [ ] **Update NixOS configuration** - Apply new Immich module settings
  ```bash
  # Edit your server configuration
  # Add/update Immich storage settings
  # See example-config.nix for examples
  ```

- [ ] **Review changes before deploying**
  ```bash
  # Dry run to see what will change
  sudo nixos-rebuild dry-build
  ```

- [ ] **Deploy configuration**
  ```bash
  sudo nixos-rebuild switch
  ```

- [ ] **Verify new directories created**
  ```bash
  ls -la /mnt/photos/
  # Should see: library/, thumbs/, encoded-video/, profile/

  # Verify permissions
  ls -la /mnt/photos/ | grep immich
  # All should be owned by immich:immich with 750 permissions
  ```

- [ ] **Verify services started**
  ```bash
  systemctl status immich-server immich-machine-learning
  journalctl -u immich-server -u immich-machine-learning -n 50
  ```

- [ ] **Check database backup service**
  ```bash
  systemctl status postgresqlBackup-immich.service
  ls -la /var/backup/immich-db/
  ```

## Storage Template Configuration

- [ ] **Log in to Immich web UI**
  - URL: `https://hwc.ocelot-wahoo.ts.net:7443`
  - User: Admin account

- [ ] **Navigate to storage template settings**
  - Go to: `Administration → Settings → Storage Template`

- [ ] **Choose storage template** - See STORAGE-GUIDE.md for recommendations
  - Recommended: `{{y}}/{{MM}}/{{dd}}/{{filename}}`
  - Alternative: `{{y}}/{{MM}}/{{album}}/{{filename}}`

- [ ] **Test template** - Use the "Test" feature
  - Verify template produces expected structure
  - Check for errors or warnings

- [ ] **Save template**
  - Click "Save" to apply template to new uploads

- [ ] **Upload test photo** - Verify new structure
  ```bash
  # Upload a test photo via web UI or mobile app
  # Check location in /mnt/photos/library/
  ls -la /mnt/photos/library/2025/  # Verify organized by template
  ```

## Existing Data Migration (Optional)

**WARNING**: This step reorganizes all existing files. Only proceed if needed.

- [ ] **Review what will be migrated**
  ```bash
  # Count existing files
  find /mnt/photos -type f -name "*.jpg" -o -name "*.mp4" | wc -l

  # Estimate migration time (rough: 1000 files = ~5-10 minutes)
  ```

- [ ] **Run storage migration job** (via web UI)
  - Go to: `Administration → Jobs → Storage Migration Jobs`
  - Click "Run Job"
  - **DO NOT** close browser during migration

- [ ] **Monitor migration progress**
  ```bash
  # Watch logs
  journalctl -u immich-server -f

  # Monitor file changes
  watch -n 5 'find /mnt/photos/library -type f | wc -l'
  ```

- [ ] **Wait for completion** - Migration can take hours for large libraries
  - Check web UI for job completion status
  - Do not interrupt or restart services during migration

## Post-Migration Verification

- [ ] **Verify all photos visible** - Check web UI
  - Browse timeline
  - Search for specific photos
  - Check albums

- [ ] **Test upload** - Upload new photos
  - Verify new photos use template structure
  - Check file location matches template

- [ ] **Test search** - Verify ML features working
  - Search by object/person
  - Check facial recognition
  - Test CLIP semantic search

- [ ] **Test mobile app** - Verify sync working
  - Log in on mobile
  - Enable backup
  - Upload test photo

- [ ] **Verify backup integration**
  ```bash
  # Check backup sources include new paths
  # In /etc/nixos or machine config:
  # hwc.system.services.backup.local.sources should include:
  #   - /mnt/photos
  #   - /var/backup/immich-db

  # Test backup (dry-run if supported)
  sudo systemctl start backup-local.service
  journalctl -u backup-local.service -f
  ```

- [ ] **Check database backup**
  ```bash
  # Verify daily backups are running
  ls -lh /var/backup/immich-db/

  # Check latest backup
  systemctl status postgresqlBackup-immich.service
  ```

- [ ] **Verify GPU acceleration** - Check performance
  ```bash
  # Monitor GPU during photo processing
  nvidia-smi -l 1

  # Check Immich logs for GPU usage
  journalctl -u immich-machine-learning -n 100 | grep -i cuda
  ```

- [ ] **Check disk usage** - Monitor space
  ```bash
  df -h /mnt/photos
  du -sh /mnt/photos/*
  ```

## Cleanup

- [ ] **Keep migration backup for 30 days** - Safety period
  ```bash
  # Set reminder to clean up after 30 days:
  echo "Migration backup at /mnt/backup/immich-pre-migration-*" > /tmp/cleanup-reminder.txt
  echo "Safe to delete after: $(date -d '+30 days' +%Y-%m-%d)" >> /tmp/cleanup-reminder.txt
  ```

- [ ] **Monitor for issues** - Watch for 1-2 weeks
  - Check logs daily: `journalctl -u immich-server -u immich-machine-learning --since today`
  - Monitor disk space: `df -h /mnt/photos`
  - Verify backups running: `systemctl status postgresqlBackup-immich.service`

- [ ] **Document any issues** - Note problems and solutions
  - Create issues in repository if needed
  - Update STORAGE-GUIDE.md with troubleshooting tips

- [ ] **Remove old backup** (after 30 days of stable operation)
  ```bash
  # Only after verifying everything works perfectly for 30 days
  # sudo rm -rf /mnt/backup/immich-pre-migration-*
  # sudo rm /mnt/backup/immich-db-pre-migration-*.sql.zst
  ```

## Rollback Plan (If Migration Fails)

If something goes wrong during migration:

1. **Stop Immich services**
   ```bash
   sudo systemctl stop immich-server immich-machine-learning
   ```

2. **Restore from backup**
   ```bash
   # Restore photos
   sudo rsync -av /mnt/backup/immich-pre-migration-*/ /mnt/photos/

   # Restore database
   sudo -u postgres dropdb immich
   sudo -u postgres createdb immich -O immich
   zstdcat /mnt/backup/immich-db-pre-migration-*.sql.zst | sudo -u postgres psql -d immich
   ```

3. **Revert NixOS configuration**
   ```bash
   # Restore old configuration
   sudo cp /tmp/config-backup-*.nix /etc/nixos/configuration.nix
   sudo nixos-rebuild switch
   ```

4. **Restart services**
   ```bash
   sudo systemctl start immich-server immich-machine-learning
   ```

5. **Verify restoration**
   - Check web UI
   - Verify all photos visible
   - Test upload

## Success Criteria

Migration is successful when:

- [x] All photos visible in web UI
- [x] Search and ML features working
- [x] New uploads use template structure
- [x] Mobile app syncing correctly
- [x] Backups running automatically
- [x] No errors in logs
- [x] GPU acceleration working
- [x] Database backups completing

## Support

If you encounter issues:

1. Check `STORAGE-GUIDE.md` troubleshooting section
2. Review Immich logs: `journalctl -u immich-server -u immich-machine-learning -n 200`
3. Check NixOS logs: `journalctl -xe`
4. Verify configuration: `nixos-option hwc.server.immich`
5. Consult Immich docs: https://docs.immich.app/

## Timeline Estimate

| Task | Estimated Time |
|------|----------------|
| Pre-migration backup | 30 min - 2 hours (depends on data size) |
| Configuration update | 15-30 minutes |
| Storage template setup | 10 minutes |
| Storage migration job | 1-8 hours (depends on library size) |
| Verification | 30 minutes |
| **Total** | **2-12 hours** |

**Recommendation**: Plan migration during a weekend or low-usage period.
