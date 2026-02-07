# Data Retention & Lifecycle Management Policy

**Source**: Extracted from Charter v8.0 Section 23
**Status**: Active Policy
**Owner**: Eric
**Last Updated**: 2026-01-10

## Policy Statement

All data retention policies **MUST** be declared in NixOS configuration with automated enforcement. Manual cleanup scripts and ad-hoc retention policies are prohibited.

---

## Core Principles

1. **Declarative-First**: Retention policies defined in configuration, never ad-hoc
2. **Fail-Safe**: Automated enforcement even if primary application fails
3. **Predictable**: Time-based and size-based limits clearly documented
4. **Observable**: All cleanup operations logged to systemd journal
5. **Reproducible**: Version-controlled policies deployable to any machine

---

## Data Classification System

All data stores must be classified into one of four categories:

| Category | Retention | Backup | Examples | Enforcement |
|----------|-----------|--------|----------|-------------|
| **CRITICAL** | Indefinite | ✅ Weekly | Photos, configs, business data, documents | Manual review only |
| **REPLACEABLE** | Indefinite | ❌ No | Movies, TV shows, music, books | No automatic deletion |
| **AUTO-MANAGED** | 7-30 days | ❌ No | Surveillance, logs, download buffers | Automated cleanup |
| **EPHEMERAL** | <7 days | ❌ No | Cache, temp files, processing buffers | Automated cleanup |

### Classification Guidelines

**CRITICAL** - Data that cannot be recovered if lost:
- Personal photos and videos
- Configuration files (dotfiles, NixOS config)
- Business data (receipts, documents, databases)
- User-created content
- Private keys and credentials

**REPLACEABLE** - Data that can be re-downloaded or regenerated:
- Movies, TV shows (from streaming/download)
- Music (from streaming services or CD rips)
- Books and audiobooks (from library or store)
- Software packages (from nixpkgs or upstream)

**AUTO-MANAGED** - Data with time-based relevance:
- Surveillance footage (relevant for 7-30 days)
- Application logs (debug history window)
- Download buffers (temporary processing)
- Metrics and monitoring data

**EPHEMERAL** - Data with no retention value:
- System cache (`/var/cache`)
- Temporary files (`/tmp`, `/var/tmp`)
- Processing buffers (video transcoding temp)
- Build artifacts

---

## Retention Policy Structure

Every data store with retention requirements MUST define both primary and fail-safe enforcement.

### Pattern: Primary + Fail-Safe

```nix
{
  # PRIMARY ENFORCEMENT (application-level)
  # The application's native retention mechanism
  retention = {
    days = 7;        # or weeks/months
    mode = "time";   # or "size" or "count"
  };

  # FAIL-SAFE ENFORCEMENT (systemd timer)
  # Catches what the application missed
  systemd.timers.<service>-cleanup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";  # Avoid thundering herd
    };
  };

  systemd.services.<service>-cleanup = {
    script = ''
      # Cleanup script with proper error handling
      find /path/to/data -type f -mtime +7 -delete
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "eric";
      Group = "users";
    };
  };
}
```

---

## Retention Schedules by Data Type

### Surveillance Footage (AUTO-MANAGED)

**Primary**: Application config (Frigate built-in retention)
**Fail-Safe**: systemd timer enforcement

```yaml
# domains/server/frigate/config/config.yml
record:
  retain:
    days: 7  # Keep recordings for 7 days
  events:
    retain:
      default: 30  # Keep motion events for 30 days
```

```nix
# machines/server/config.nix
systemd.timers.frigate-cleanup = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "daily";
    Persistent = true;
  };
};

systemd.services.frigate-cleanup = {
  script = ''
    # Fail-safe: delete recordings older than 7 days
    ${pkgs.findutils}/bin/find ${config.hwc.paths.media.surveillance}/frigate \
      -type f -mtime +7 -delete

    # Fail-safe: delete events older than 30 days
    ${pkgs.findutils}/bin/find ${config.hwc.paths.media.surveillance}/frigate/clips \
      -type f -mtime +30 -delete
  '';
  serviceConfig = {
    Type = "oneshot";
    User = "eric";
    Group = "users";
  };
};
```

### Application Logs (AUTO-MANAGED)

**Retention**: 30 days
**Method**: systemd journal native rotation

```nix
services.journald.extraConfig = ''
  MaxRetentionSec=30d
  SystemMaxUse=1G
'';
```

### Download Buffers (EPHEMERAL)

**Retention**: 7 days
**Method**: Centralized cleanup service

```nix
# domains/server/native/storage/options.nix
hwc.services.storage.cleanup = {
  enable = true;
  retentionDays = 7;
  paths = [
    "${config.hwc.paths.hot.root}/processing/sonarr-temp"
    "${config.hwc.paths.hot.root}/processing/radarr-temp"
    "${config.hwc.paths.hot.root}/processing/lidarr-temp"
    "${config.hwc.paths.hot.downloads.root}/incomplete"
    "/var/tmp/hwc"
    "/var/cache/hwc"
  ];
};
```

### System Cache (EPHEMERAL)

**Retention**: Boot-based (cleared on reboot)
**Method**: tmpfs mount

```nix
boot.tmpOnTmpfs = true;  # /tmp cleared on boot
```

---

## Backup Source Selection

**Rule**: Only back up CRITICAL data. Exclude REPLACEABLE and AUTO-MANAGED data.

### Backup Configuration Pattern

```nix
hwc.system.services.backup.local = {
  enable = true;

  sources = [
    # CRITICAL - User data
    "/home/eric"

    # CRITICAL - Photos (irreplaceable)
    "${config.hwc.paths.photos}"

    # CRITICAL - Configuration
    "/etc/nixos"

    # CRITICAL - Business data
    "${config.hwc.paths.business.root}/data"
  ];

  excludePatterns = [
    # REPLACEABLE - Media
    "*/movies/*"
    "*/tv/*"
    "*/music/*"
    "*/books/*"

    # AUTO-MANAGED - Surveillance
    "*/surveillance/*"

    # EPHEMERAL - Cache and temp
    "*/.cache/*"
    "*/tmp/*"
    "*/processing/*"

    # System managed
    "*/.nix-*"
    "*/.local/share/Trash/*"
  ];

  schedule = "daily";
  retention = {
    daily = 7;
    weekly = 4;
    monthly = 6;
  };
};
```

---

## Anti-Patterns

### ❌ Manual Cleanup Scripts Outside NixOS Config

**DON'T DO THIS**:
```bash
# Ad-hoc cron job (not declarative, not version-controlled)
crontab -e
0 0 * * * find /data -mtime +30 -delete
```

**DO THIS INSTEAD**:
```nix
# Declarative systemd timer in machines/server/config.nix
systemd.timers.data-cleanup = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "daily";
    Persistent = true;
  };
};

systemd.services.data-cleanup = {
  script = ''
    ${pkgs.findutils}/bin/find /data -type f -mtime +30 -delete
  '';
  serviceConfig.Type = "oneshot";
};
```

### ❌ Backing Up Replaceable Media

**DON'T DO THIS**:
```nix
# Wasting 3TB+ on replaceable movies/TV
sources = [
  "/mnt/media/movies"  # Can re-download
  "/mnt/media/tv"      # Can re-download
];
```

**DO THIS INSTEAD**:
```nix
# Only irreplaceable photos
sources = [ "/mnt/media/pictures" ];

excludePatterns = [
  "*/movies/*"  # Explicitly exclude
  "*/tv/*"      # Explicitly exclude
];
```

### ❌ No Fail-Safe for Application Retention

**DON'T DO THIS**:
```yaml
# config.yml - only application retention, no fail-safe
record:
  retain:
    days: 7
# What if the application fails to clean up?
```

**DO THIS INSTEAD**:
```yaml
# config.yml - primary retention
record:
  retain:
    days: 7
```

```nix
# machines/server/config.nix - fail-safe
systemd.timers.app-cleanup = {
  # Catches what the application missed
  ...
};
```

---

## Monitoring & Verification

All retention policies MUST have verification commands documented.

### Check Oldest Files

Verify retention policy is working:

```bash
# Check oldest surveillance footage (should be ~7 days old)
find /mnt/media/surveillance/frigate -type f -printf '%T+ %p\n' | sort | head -1

# Check oldest logs (should be ~30 days old)
journalctl --since "31 days ago" | head -1
```

### Verify Timer Status

Check that cleanup timers are active:

```bash
# List all cleanup timers
systemctl list-timers | grep cleanup

# Check specific timer status
systemctl status frigate-cleanup.timer
systemctl status storage-cleanup.timer

# View cleanup service logs
journalctl -u frigate-cleanup.service -n 20
journalctl -u storage-cleanup.service -n 20
```

### Disk Usage Monitoring

Monitor storage growth to catch retention failures:

```bash
# Check storage usage trends
du -sh /mnt/media/surveillance
du -sh /mnt/hot/processing

# Alert if surveillance exceeds expected size
# Expected: ~7 days * ~10GB/day = ~70GB
# Alert if >100GB (retention failure)
```

---

## Implementation Checklist

When adding new data stores, ensure:

- [ ] Data is classified (CRITICAL/REPLACEABLE/AUTO-MANAGED/EPHEMERAL)
- [ ] Retention policy is defined in NixOS config
- [ ] Primary enforcement exists (application-level)
- [ ] Fail-safe enforcement exists (systemd timer)
- [ ] Backup policy reflects classification
- [ ] Verification commands are documented
- [ ] Monitoring alerts are configured (if AUTO-MANAGED)

---

## Related Documentation

- **Charter v9.0**: Domain Architecture Overview
- **domains/server/README.md**: Server workload patterns
- **docs/infrastructure/retention-and-cleanup.md**: Detailed implementation guide
- **domains/infrastructure/storage/**: Storage infrastructure implementation

---

## Policy Change Log

- **2026-01-10**: Extracted from Charter v8.0 as standalone policy
- **2025-12-04**: Added to Charter v8.0 as Section 23
- **2025-11-**: Initial retention policy implementation

