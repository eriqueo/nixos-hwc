# Backup System Security & Production Readiness Guide

**CRITICAL**: This document addresses production-critical security requirements for the backup system.
Read this completely before deploying to production.

---

## ⚠️ Critical Security Checklist

Before using this backup system in production, you **MUST** address:

- [ ] **Encryption at rest** configured for all backup destinations
- [ ] **Database consistency** hooks enabled for all databases
- [ ] **Disaster recovery runbook** tested with full system restore
- [ ] **Key management** policy documented and tested
- [ ] **Cloud immutability** enabled for ransomware protection
- [ ] **Restore verification** scheduled and automated
- [ ] **Off-site backup** configured (cloud or physical)
- [ ] **RTO/RPO targets** defined and documented
- [ ] **Security audit** completed on backup scripts
- [ ] **Access controls** reviewed and minimized

---

## 1. Encryption At Rest (CRITICAL)

### Problem
Backups stored on external drives, NAS, or cloud without encryption expose sensitive data if stolen or compromised.

### Required Solution

#### Option A: LUKS Full-Disk Encryption (Recommended for External Drives)

```bash
# 1. Create LUKS encrypted partition
sudo cryptsetup luksFormat /dev/sdX1
# Enter strong passphrase (store in password manager)

# 2. Open encrypted volume
sudo cryptsetup luksOpen /dev/sdX1 backup_crypt

# 3. Format the encrypted volume
sudo mkfs.ext4 /dev/mapper/backup_crypt

# 4. Mount encrypted volume
sudo mkdir -p /mnt/backup
sudo mount /dev/mapper/backup_crypt /mnt/backup

# 5. Add to NixOS configuration for automatic unlocking
fileSystems."/mnt/backup" = {
  device = "/dev/mapper/backup_crypt";
  fsType = "ext4";
  options = [ "nofail" ];
};

# Unlock with keyfile (store keyfile in agenix secret)
boot.initrd.luks.devices.backup_crypt = {
  device = "/dev/disk/by-uuid/YOUR-UUID";
  keyFile = config.age.secrets.luks-backup-key.path;
  allowDiscards = true;
};
```

#### Option B: gocryptfs (File-Level Encryption)

```nix
# NixOS configuration
hwc.system.services.backup = {
  encryption.local = {
    enable = true;
    method = "gocryptfs";
  };
};
```

```bash
# Initialize encrypted directory
gocryptfs -init /mnt/backup-encrypted
# Mount encrypted filesystem
gocryptfs /mnt/backup-encrypted /mnt/backup
```

#### Option C: rclone crypt (For Cloud & NAS)

```nix
hwc.system.services.backup = {
  encryption.cloud = {
    enable = true;
    password.useSecret = true;
    password.secretName = "backup-encryption-password";
  };
};
```

```bash
# Configure rclone with encryption
rclone config create backup_encrypted crypt \
  remote=proton-drive:Backups \
  password=$(cat /run/agenix/backup-encryption-password) \
  password2=$(cat /run/agenix/backup-encryption-salt)
```

### Encryption Key Management

**CRITICAL**: Losing encryption keys means **permanent data loss**.

1. **Store keys securely**:
   - LUKS passphrases: In password manager (1Password, Bitwarden)
   - Keyfiles: In agenix secrets + offline backup
   - Recovery keys: Printed and stored in safe/vault

2. **Test key recovery**:
   ```bash
   # Verify you can unlock with recovery key
   sudo cryptsetup luksOpen --key-file=/path/to/backup-key /dev/sdX1 test
   sudo cryptsetup luksClose test
   ```

3. **Key rotation schedule**:
   - Rotate LUKS passphrase: Annually
   - Re-encrypt cloud backups: Every 2 years
   - Test key recovery: Quarterly

---

## 2. Database Consistency (CRITICAL)

### Problem
Backing up live databases without consistency measures results in corrupted, unrestorable backups.

### Required Solutions Per Database

#### PostgreSQL: Point-In-Time Recovery

```nix
hwc.system.services.backup = {
  database.postgres = {
    enable = true;
    pitr = true;  # Enable WAL archiving
  };
};
```

**What this does**:
- Creates `pg_basebackup` (crash-consistent base backup)
- Archives WAL (Write-Ahead Log) files for PITR
- Creates portable SQL dump for cross-version recovery

**Recovery procedure**:
```bash
# 1. Stop PostgreSQL
sudo systemctl stop postgresql

# 2. Move old PGDATA away
sudo mv /var/lib/postgresql /var/lib/postgresql.old

# 3. Extract base backup
sudo mkdir -p /var/lib/postgresql/data
cd /mnt/backup/latest/.database-backups/postgres-basebackup
sudo tar xzf base.tar.gz -C /var/lib/postgresql/data

# 4. Configure recovery
sudo cat > /var/lib/postgresql/data/recovery.conf << EOF
restore_command = 'cp /mnt/backup/latest/.database-backups/wal/%f %p'
recovery_target_time = '2025-01-17 14:00:00'
EOF

# 5. Start PostgreSQL (will replay WAL)
sudo systemctl start postgresql
```

**Test recovery**:
```bash
# Quarterly drill: Restore to test VM and verify data integrity
sudo backup-restore latest /.database-backups/postgres-dump.sql.gz /tmp/test-restore.sql.gz
gunzip /tmp/test-restore.sql.gz
psql -f /tmp/test-restore.sql testdb
```

#### MySQL/MariaDB: Consistent Dumps

```nix
hwc.system.services.backup = {
  database.mysql.enable = true;
};
```

Uses `mysqldump --single-transaction` for InnoDB consistency.

**Recovery**:
```bash
gunzip < /mnt/backup/latest/.database-backups/mysql-dump.sql.gz | mysql
```

#### Redis: BGSAVE Snapshots

```nix
hwc.system.services.backup = {
  database.redis.enable = true;
};
```

**Recovery**:
```bash
sudo systemctl stop redis
sudo cp /mnt/backup/latest/.database-backups/redis-dump.rdb /var/lib/redis/dump.rdb
sudo chown redis:redis /var/lib/redis/dump.rdb
sudo systemctl start redis
```

#### Docker Volumes: Container-Aware Backups

```nix
hwc.system.services.backup = {
  database.docker.enable = true;
};
```

**Recovery**:
```bash
docker volume create my-volume
docker run --rm \
  -v my-volume:/volume \
  -v /mnt/backup/latest/.database-backups:/backup \
  alpine tar xzf /backup/my-volume.tar.gz -C /volume
```

---

## 3. Cloud Immutability & Ransomware Protection (CRITICAL)

### Problem
`rclone sync` mirrors deletions - if source is compromised/encrypted by ransomware, the backup is too.

### Required Solutions

#### Option A: S3 Object Lock (AWS, Wasabi, Backblaze B2)

```nix
hwc.system.services.backup = {
  cloud = {
    provider = "s3";  # Use S3-compatible provider
    immutability = {
      enable = true;
      retentionDays = 90;  # Cannot delete for 90 days
      mode = "compliance";  # Even root cannot override
    };
  };
};
```

```bash
# Configure S3 bucket with object lock
rclone config create backup-s3 s3 \
  provider=AWS \
  access_key_id=... \
  secret_access_key=... \
  region=us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket my-backup-bucket \
  --versioning-configuration Status=Enabled

# Enable object lock
aws s3api put-object-lock-configuration \
  --bucket my-backup-bucket \
  --object-lock-configuration \
    '{"ObjectLockEnabled":"Enabled","Rule":{"DefaultRetention":{"Mode":"COMPLIANCE","Days":90}}}'
```

#### Option B: Proton Drive with Versioning

**WARNING**: Proton Drive does not natively support object lock. Use one of these mitigations:

1. **Separate immutable archive bucket**:
   ```bash
   # Weekly: Copy critical files to S3 Glacier with object lock
   rclone copy /mnt/backup/weekly s3-glacier:immutable-archive \
     --immutable --no-traverse
   ```

2. **Append-only cloud sync**:
   ```nix
   hwc.system.services.backup.cloud.syncMode = "copy";  # Never delete from cloud
   ```

3. **Dual cloud strategy**:
   - Proton Drive: Daily sync (convenience)
   - Backblaze B2: Weekly immutable copy (protection)

#### Option C: Air-Gapped Backup

Most secure: Physical offline backup rotated monthly.

```bash
# Monthly: Create encrypted offline backup
sudo dd if=/dev/sdX of=/dev/sdY bs=4M status=progress
# Store drive offsite (safe deposit box)
```

---

## 4. Disaster Recovery Runbook (CRITICAL)

### RTO/RPO Targets

Define and document your requirements:

| System | RTO (Recovery Time) | RPO (Recovery Point) |
|--------|---------------------|---------------------|
| Laptop | 4 hours | 24 hours |
| Server | 2 hours | 6 hours |
| Databases | 30 minutes | 1 hour |

### Full System Recovery Procedure

#### Bare-Metal Recovery (Server)

**Pre-requisites**:
- NixOS installation media
- Backup drive accessible
- Encryption keys available

**Procedure** (test quarterly):

```bash
# 1. Boot NixOS installer
# 2. Partition disks (match original layout)
sudo parted /dev/sda -- mklabel gpt
sudo parted /dev/sda -- mkpart ESP fat32 1MiB 512MiB
sudo parted /dev/sda -- set 1 esp on
sudo parted /dev/sda -- mkpart primary 512MiB 100%

# 3. Setup LUKS if used
sudo cryptsetup luksFormat /dev/sda2
sudo cryptsetup luksOpen /dev/sda2 cryptroot

# 4. Format filesystems
sudo mkfs.fat -F 32 -n boot /dev/sda1
sudo mkfs.ext4 -L nixos /dev/mapper/cryptroot

# 5. Mount filesystems
sudo mount /dev/mapper/cryptroot /mnt
sudo mkdir -p /mnt/boot
sudo mount /dev/sda1 /mnt/boot

# 6. Mount backup drive
sudo mkdir /mnt-backup
sudo cryptsetup luksOpen /dev/sdX1 backup_crypt
sudo mount /dev/mapper/backup_crypt /mnt-backup

# 7. Restore configuration
sudo rsync -aAXHv /mnt-backup/latest/etc/nixos/ /mnt/etc/nixos/

# 8. Generate hardware config
sudo nixos-generate-config --root /mnt

# 9. Install NixOS
sudo nixos-install

# 10. Reboot into new system
sudo reboot

# 11. After boot, restore user data
sudo rsync -aAXHv --delete /mnt-backup/latest/home/ /home/

# 12. Restore databases (see section 2)

# 13. Verify services
sudo systemctl status postgresql
sudo systemctl status docker
```

**Estimated time**: 2-4 hours depending on data size.

#### Laptop Recovery

```bash
# 1-9: Same as server

# 10. After boot, restore from backup
sudo backup-restore latest /home /home
sudo backup-restore latest /etc/nixos /etc/nixos

# 11. Rebuild to apply configuration
sudo nixos-rebuild switch

# 12. Verify
backup-status
```

### Partial Recovery Scenarios

#### Single File Recovery
```bash
backup-restore latest /home/user/Documents/important.pdf /tmp/restored.pdf
```

#### Database-Only Recovery
```bash
# PostgreSQL
sudo backup-restore latest /.database-backups/postgres-dump.sql.gz /tmp/db.sql.gz
gunzip /tmp/db.sql.gz
sudo -u postgres psql < /tmp/db.sql

# MySQL
sudo backup-restore latest /.database-backups/mysql-dump.sql.gz /tmp/mysql.sql.gz
gunzip /tmp/mysql.sql.gz
mysql < /tmp/mysql.sql
```

#### Configuration-Only Recovery
```bash
sudo backup-restore latest /etc/nixos /etc/nixos
sudo nixos-rebuild switch
```

### Recovery Testing Schedule

| Test Type | Frequency | Last Tested | Next Test |
|-----------|-----------|-------------|-----------|
| Single file restore | Monthly | _________ | _________ |
| Database restore (to test VM) | Quarterly | _________ | _________ |
| Full laptop restore (to VM) | Semi-annually | _________ | _________ |
| Full server restore (to VM) | Annually | _________ | _________ |

**ACTION REQUIRED**: Schedule and document first test in each category.

---

## 5. Key Management Lifecycle (CRITICAL)

### Keys to Manage

1. **LUKS encryption keys** (for encrypted backup drives)
2. **Age keys** (for agenix secrets)
3. **rclone passwords** (for cloud encryption)
4. **SSH keys** (for remote backups)
5. **GPG keys** (for backup signing)

### Key Storage Policy

| Key Type | Primary Storage | Backup Storage #1 | Backup Storage #2 |
|----------|----------------|-------------------|-------------------|
| LUKS passphrase | Password manager | Paper in safe | USB in safe deposit box |
| Age private key | `/root/.age/` | Encrypted USB | Paper backup (QR code) |
| rclone password | agenix secret | Password manager | Offline encrypted file |
| Root SSH key | `/root/.ssh/` | Encrypted backup | Hardware token |

### Key Backup Procedure

```bash
# 1. Export age key
sudo cat /etc/age/keys.txt > /tmp/age-master-key.txt

# 2. Encrypt with GPG
gpg --symmetric --cipher-algo AES256 /tmp/age-master-key.txt

# 3. Print QR code for offline storage
qrencode -t UTF8 < /tmp/age-master-key.txt

# 4. Store encrypted file on USB
cp /tmp/age-master-key.txt.gpg /media/usb/emergency-keys/

# 5. Test recovery
gpg --decrypt /media/usb/emergency-keys/age-master-key.txt.gpg
# Verify output matches original

# 6. Securely delete temp files
shred -u /tmp/age-master-key.txt*
```

### Key Rotation Schedule

| Key Type | Rotation Frequency | Last Rotated | Next Rotation |
|----------|-------------------|--------------|---------------|
| LUKS passphrase | Annually | _________ | _________ |
| Age keys | Every 2 years | _________ | _________ |
| rclone password | Annually | _________ | _________ |
| SSH keys | Every 2 years | _________ | _________ |

### Emergency Key Recovery

**Scenario**: Primary system destroyed, need to recover from backups.

1. Boot recovery environment (live USB)
2. Retrieve offline key backup from safe
3. Decrypt and import age key
4. Mount encrypted backup drive with LUKS key
5. Access backups

**Test this procedure annually.**

---

## 6. Access Control & Security Hardening

### Principle of Least Privilege

Current implementation runs backups as `root`. Consider:

```nix
# Create dedicated backup user
users.users.backup-runner = {
  isSystemUser = true;
  group = "backup";
  home = "/var/lib/backup";
};

# Grant only necessary permissions
security.sudo.extraRules = [{
  users = [ "backup-runner" ];
  commands = [
    { command = "${pkgs.rsync}/bin/rsync"; options = [ "NOPASSWD" ]; }
    { command = "${pkgs.rclone}/bin/rclone"; options = [ "NOPASSWD" ]; }
  ];
}];
```

### Audit Logging

```nix
# Log all backup operations
services.auditd.enable = true;
security.audit.rules = [
  "-w /mnt/backup -p wa -k backup_access"
  "-w /var/log/backup -p wa -k backup_logs"
];
```

### Network Segmentation

For NAS backups:
- Use dedicated VLAN for backup traffic
- Firewall rules: Allow only backup server → NAS
- Consider Tailscale for encrypted backup network

### Secret Rotation

```bash
# Rotate rclone password
new_password=$(openssl rand -base64 32)
echo "$new_password" | age -r $(cat /etc/age/public-key.txt) \
  > /etc/nixos/secrets/backup-encryption-password.age

# Update NixOS configuration
sudo nixos-rebuild switch

# Re-encrypt existing backups with new key
rclone sync --checksum backup-old: backup-new:
```

---

## 7. Compliance & Legal Considerations

### Data Retention

Configure retention to meet legal requirements:

```nix
hwc.system.services.backup.local = {
  keepDaily = 7;     # GDPR: 7 days for transactional data
  keepWeekly = 52;   # 1 year for business records
  keepMonthly = 84;  # 7 years for tax records (adjust per jurisdiction)
};
```

### Right to Deletion

Implement secure deletion when required:

```bash
# Securely delete specific user data from backups
find /mnt/backup -name "*user-email@domain.com*" -exec shred -u {} \;

# Or delete entire user directory
find /mnt/backup -type d -name "user-email@domain.com" -exec rm -rf {} \;
```

### Encryption Compliance

- **HIPAA**: LUKS with FIPS-validated crypto
- **PCI-DSS**: AES-256 encryption for cardholder data
- **GDPR**: Encryption + key management documentation

---

## 8. Monitoring & Alerting

### Health Check Escalation

```nix
hwc.system.services.backup.monitoring = {
  enable = true;
  alerts = {
    email = "admin@example.com";
    webhook = "https://hooks.slack.com/services/...";
    escalationAfterHours = 24;
  };
};
```

### Metrics to Monitor

1. **Backup success rate** (should be >99%)
2. **Backup duration** (alert if >2x normal)
3. **Backup size growth** (detect data bloat)
4. **Available storage** (alert at 80% full)
5. **Restore test success** (quarterly drills)

### Prometheus Integration

```nix
# Export backup metrics
services.prometheus.exporters.node = {
  enable = true;
  enabledCollectors = [ "textfile" ];
};

# Backup script writes metrics
cat > /var/lib/prometheus/node-exporter/backup.prom << EOF
backup_success{job="local"} 1
backup_duration_seconds{job="local"} 3600
backup_size_bytes{job="local"} 96636764160
EOF
```

---

## 9. Threat Model & Mitigations

| Threat | Likelihood | Impact | Mitigation |
|--------|-----------|--------|------------|
| Ransomware | High | Critical | Immutable cloud backups, offline backups |
| Drive failure | Medium | High | RAID on NAS, multiple backup copies |
| Theft/fire | Low | Critical | Offsite backups, encryption |
| Accidental deletion | High | Medium | Versioning, 30-day retention |
| Insider threat | Low | High | Audit logging, principle of least privilege |
| Supply chain | Low | High | Verify checksums, reproducible builds (NixOS) |

---

## 10. Action Items Before Production

**YOU MUST COMPLETE THIS CHECKLIST**:

### Immediate (Before First Backup)
- [ ] Enable LUKS encryption on backup drive
- [ ] Configure database consistency hooks
- [ ] Create offline key backup
- [ ] Test single file restore

### Within 1 Week
- [ ] Configure cloud immutability
- [ ] Document RTO/RPO targets
- [ ] Schedule quarterly restore drills
- [ ] Setup monitoring alerts

### Within 1 Month
- [ ] Perform full system restore test to VM
- [ ] Document disaster recovery procedure
- [ ] Implement audit logging
- [ ] Create key rotation schedule

### Ongoing
- [ ] Quarterly: Test database restore
- [ ] Quarterly: Verify offline key backups
- [ ] Semi-annually: Full system restore drill
- [ ] Annually: Security audit
- [ ] Annually: Update disaster recovery runbook

---

## 11. Support & Escalation

### When Backups Fail

1. Check logs: `sudo journalctl -u backup.service -n 100`
2. Check disk space: `df -h /mnt/backup`
3. Verify mount: `mountpoint /mnt/backup`
4. Run health check: `backup-status`
5. Manual backup: `sudo backup-now`

### Emergency Recovery Contact

Document your emergency contacts:

- Primary admin: __________________
- Secondary admin: __________________
- Key custodian: __________________
- Vendor support: __________________

### External Resources

- NixOS backup best practices: https://nixos.wiki/wiki/Backup
- PostgreSQL PITR: https://www.postgresql.org/docs/current/continuous-archiving.html
- rclone encryption: https://rclone.org/crypt/
- LUKS documentation: https://gitlab.com/cryptsetup/cryptsetup

---

## Conclusion

This backup system is **not production-ready** until you address all items in this document.
A backup system is only as good as its tested recovery procedures.

**Next steps**:
1. Review this document with your team
2. Create implementation plan
3. Test recovery procedures
4. Document your specific RTO/RPO requirements
5. Schedule regular drills

**Remember**: Backups are insurance - test them before you need them.
