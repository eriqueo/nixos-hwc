# Immich Photo Management Server

**Version**: Native NixOS Service with GPU Acceleration
**Last Updated**: 2025-12-06
**Status**: ✅ Production
**GPU**: NVIDIA Quadro P1000 (CUDA + TensorRT)

---

## Table of Contents

1. [Quick Start & Summary](#1-quick-start--summary)
2. [Configuration Reference](#2-configuration-reference)
3. [GPU Acceleration](#3-gpu-acceleration)
4. [Storage Architecture](#4-storage-architecture)
5. [Backup & Restore](#5-backup--restore)
6. [Monitoring & Metrics](#6-monitoring--metrics)
7. [Implementation Status](#7-implementation-status)
8. [Testing & Validation](#8-testing--validation)
9. [Troubleshooting](#9-troubleshooting)
10. [Migration & Deployment](#10-migration--deployment)

---

## 1. Quick Start & Summary

### Access

- **Primary**: https://hwc.ocelot-wahoo.ts.net:2283 (Tailscale HTTPS)
- **Local**: http://192.168.1.13:2283

### Service Status

```bash
# Check services
systemctl status immich-server immich-machine-learning

# View logs
sudo journalctl -u immich-server -u immich-machine-learning -f

# GPU utilization
watch -n 1 nvidia-smi
```

### Quick Stats

**Performance (with GPU)**:
- Smart Search indexing: **2-5x faster** than CPU
- Facial recognition: **2-5x faster** than CPU
- Video transcoding: **5-7x faster** than CPU (NVENC)

**Storage Layout**:
```
/mnt/photos/
├── library/          # Primary uploads (organized by storage template)
├── thumbs/           # Thumbnail cache
├── encoded-video/    # Transcoded videos
└── profile/          # User profile pictures
```

---

## 2. Configuration Reference

### NixOS Options

All Immich configuration is managed through `hwc.server.immich.*` options:

```nix
# profiles/server.nix or machines/server/config.nix
hwc.server.immich = {
  enable = true;

  # Basic settings
  settings = {
    host = "0.0.0.0";
    port = 2283;
    mediaLocation = "/mnt/photos";
  };

  # Advanced storage layout (enabled by default)
  storage = {
    enable = true;
    basePath = "/mnt/photos";
    locations = {
      library = "/mnt/photos/library";
      thumbs = "/mnt/photos/thumbs";
      encodedVideo = "/mnt/photos/encoded-video";
      profile = "/mnt/photos/profile";
    };
  };

  # GPU acceleration
  gpu.enable = true;  # Requires hwc.infrastructure.hardware.gpu.enable = true

  # Observability (Phase A)
  observability = {
    timezone = "America/Denver";  # Or use config.time.timeZone
    logLevel = "log";  # verbose | debug | log | warn | error
    metrics = {
      enable = true;
      apiPort = 8091;              # Prometheus metrics for API
      microservicesPort = 8092;    # Prometheus metrics for ML workers
    };
  };

  # Machine learning performance tuning (Phase B)
  machineLearning = {
    cpuCores = null;  # null = auto-detect from /proc/cpuinfo
    modelTTL = 600;   # Keep models in GPU memory for 10 minutes
    modelTTLPollInterval = 30;  # Check every 30 seconds
    threading = {
      requestThreads = null;   # null = 1 (conservative default)
      interOpThreads = null;   # null = auto-compute as min(2, cores - 2)
      intraOpThreads = null;   # null = auto-compute as max(1, cores - 2)
    };
  };

  # Reverse proxy configuration (Phase B)
  reverseProxy = {
    trustedProxies = [];  # Empty default - set in machine config
    # Example: [ "127.0.0.1" "100.64.0.0/10" ]  # Caddy + Tailscale
  };

  # Database
  database = {
    createDB = false;  # Use existing database
    name = "immich";
    user = "immich";
  };

  # Redis caching
  redis.enable = true;

  # Backup integration
  backup = {
    enable = true;
    includeDatabase = true;
    databaseBackupPath = "/var/backup/immich-db";
    schedule = "daily";  # or "hourly"
  };
};
```

### Environment Variables Set

**immich-server**:
```bash
TZ=America/Denver
IMMICH_LOG_LEVEL=log
IMMICH_API_METRICS_PORT=8091
IMMICH_MICROSERVICES_METRICS_PORT=8092
IMMICH_TRUSTED_PROXIES=<from reverseProxy.trustedProxies>
NVIDIA_VISIBLE_DEVICES=0
NVIDIA_DRIVER_CAPABILITIES=compute,video,utility
```

**immich-machine-learning**:
```bash
TZ=America/Denver
MACHINE_LEARNING_MODEL_TTL=600
MACHINE_LEARNING_MODEL_TTL_POLL_S=30
MACHINE_LEARNING_REQUEST_THREADS=1
MACHINE_LEARNING_MODEL_INTER_OP_THREADS=2
MACHINE_LEARNING_MODEL_INTRA_OP_THREADS=2
NVIDIA_VISIBLE_DEVICES=0
ONNXRUNTIME_PROVIDER=cuda
CUDA_VISIBLE_DEVICES=0
TRANSFORMERS_CACHE=/var/lib/immich/.cache
TENSORRT_CACHE_PATH=/var/lib/immich/.cache/tensorrt
```

---

## 3. GPU Acceleration

### Hardware

- **GPU**: NVIDIA Quadro P1000
- **VRAM**: 4GB GDDR5
- **CUDA Cores**: 640
- **Driver**: Latest stable (via hwc.infrastructure.hardware.gpu)

### What Gets Accelerated

**Machine Learning** (CUDA + ONNX Runtime):
- Smart Search (CLIP embeddings)
- Facial Recognition
- Object Detection
- **Expected speedup**: 2-5x vs CPU

**Video Transcoding** (NVENC/NVDEC):
- H.264 encoding/decoding
- H.265 encoding/decoding
- **Expected speedup**: 5-7x vs CPU

**Thumbnail Generation** (GPU-assisted):
- Image resizing
- **Expected speedup**: 1.5-3x vs CPU

### Configuration

GPU acceleration is configured through:

1. **Infrastructure domain** (hardware-level):
```nix
hwc.infrastructure.hardware.gpu = {
  enable = true;
  type = "nvidia";
  nvidia = {
    driver = "stable";
    containerRuntime = true;  # For nvidia-container-toolkit
    enableMonitoring = true;
  };
};
```

2. **Immich module** (service-level):
```nix
hwc.server.immich.gpu.enable = true;
```

### SystemD Service Configuration

**Critical components**:
- Device access: `/dev/nvidia*`, `/dev/dri/*`
- Service dependencies: `nvidia-container-toolkit-cdi-generator.service`
- Memory locking: `LimitMEMLOCK=infinity` (prevents GPU memory thrashing)
- Process priority: `Nice=-10` for ML service (responsive AI features)

### Validation

```bash
# 1. Verify CUDA is available
nvidia-smi

# 2. Check Immich ML service has GPU access
systemctl show immich-machine-learning | rg "NVIDIA|CUDA"

# Expected:
# NVIDIA_VISIBLE_DEVICES=0
# CUDA_VISIBLE_DEVICES=0
# ONNXRUNTIME_PROVIDER=cuda

# 3. Watch GPU utilization during ML operations
# Upload photos and perform Smart Search, should see GPU activity
watch -n 1 nvidia-smi

# 4. Check TensorRT cache (should populate over time)
ls -lh /var/lib/immich/.cache/tensorrt/
```

---

## 4. Storage Architecture

### Layout

```
/mnt/photos/ (base path)
├── library/              # Primary photo/video uploads
│   ├── 2025/
│   │   ├── 01/
│   │   │   ├── 01/       # Organized by storage template
│   │   │   └── 02/
│   │   └── 02/
│   └── .immich           # Mount verification marker
├── thumbs/               # Thumbnail cache (regeneratable)
│   └── .immich
├── encoded-video/        # Transcoded videos (regeneratable)
│   └── .immich
└── profile/              # User profile pictures
    └── .immich
```

### Storage Templates

**Configured via Web UI** (Administration → Settings → Storage Template):

**Recommended**: `{{y}}/{{MM}}/{{dd}}/{{filename}}`
- Organizes by: Year/Month/Day/Filename
- Good for: Single-user, chronological browsing

**Alternatives**:
- Multi-user: `{{y}}/{{MM}}/{{album}}/{{filename}}`
- Camera-based: `{{y}}/{{MM}}/{{assetId}}/{{filename}}`
- Simple monthly: `{{y}}/{{MM}}/{{filename}}`

**Important**: Storage templates only affect NEW uploads. Use the migration job in the web UI to reorganize existing files.

### External Library

Immich can scan existing photo directories without moving files:

1. Navigate to: **Administration → External Libraries**
2. Add library path (e.g., `/mnt/media/pictures`)
3. Configure scan settings
4. Trigger initial scan

**NixOS Configuration**:
```nix
hwc.server.immich = {
  # ... other config

  # Grant ML service read-only access to external library
  # (configured in index.nix:197)
};
```

### Backup Strategy

**What to backup**:
- ✅ `/mnt/photos/library` - CRITICAL (original photos/videos)
- ✅ `/mnt/photos/profile` - Important (user profiles)
- ✅ Database dumps - CRITICAL (metadata, albums, face data)
- ⚠️ `/mnt/photos/thumbs` - Optional (regeneratable from originals)
- ⚠️ `/mnt/photos/encoded-video` - Optional (regeneratable from originals)

**Automated backups** (via NixOS):
```nix
hwc.server.immich.backup = {
  enable = true;
  includeDatabase = true;
  databaseBackupPath = "/var/backup/immich-db";
  schedule = "daily";  # PostgreSQL dumps
};
```

---

## 5. Backup & Restore

### Database Backups

**Automated** (via `hwc.server.immich.backup.enable = true`):
- Location: `/var/backup/immich-db/immich.sql.zst`
- Schedule: Daily at 02:00 (configurable)
- Compression: zstd
- Managed by: `services.postgresqlBackup`

**Manual backup**:
```bash
# Dump database
sudo -u postgres pg_dump immich | zstd > immich-$(date +%Y%m%d).sql.zst

# Verify backup
zstd -dc immich-20251206.sql.zst | head -20
```

### Media Backups

**Option 1: rsync** (recommended for local backups):
```bash
# Dry run first
rsync -avun --progress /mnt/photos/library/ /mnt/backup/immich-library/

# Actual backup
rsync -av --progress /mnt/photos/library/ /mnt/backup/immich-library/
```

**Option 2: rclone** (recommended for cloud backups):
```bash
# Example: Proton Drive
rclone sync /mnt/photos/library/ proton:immich-library \
  --progress \
  --transfers 4 \
  --checkers 8
```

### Restore Procedures

**Database restore**:
```bash
# 1. Stop Immich services
sudo systemctl stop immich-server immich-machine-learning

# 2. Drop and recreate database
sudo -u postgres psql <<EOF
DROP DATABASE immich;
CREATE DATABASE immich;
GRANT ALL PRIVILEGES ON DATABASE immich TO immich;
EOF

# 3. Restore from backup
zstd -dc immich-backup.sql.zst | sudo -u postgres psql immich

# 4. Restart services
sudo systemctl start immich-server immich-machine-learning
```

**Media restore**:
```bash
# Restore library
rsync -av /mnt/backup/immich-library/ /mnt/photos/library/

# Fix permissions (running as eric user)
sudo chown -R eric:users /mnt/photos/library/

# Verify .immich markers exist
ls -la /mnt/photos/library/.immich
```

### Disaster Recovery Checklist

- [ ] Database backup exists and is recent
- [ ] Media files backed up (library + profile)
- [ ] Backup integrity verified (test restore on non-prod)
- [ ] Recovery time objective documented
- [ ] Recovery point objective acceptable

---

## 6. Monitoring & Metrics

### Prometheus Integration

**Configuration** (Phase C implementation):
```nix
# Automatically added by Immich module when metrics enabled
hwc.services.prometheus.scrapeConfigs = [
  {
    job_name = "immich-api";
    static_configs = [{ targets = [ "localhost:8091" ]; }];
    scrape_interval = "30s";
  }
  {
    job_name = "immich-workers";
    static_configs = [{ targets = [ "localhost:8092" ]; }];
    scrape_interval = "30s";
  }
];
```

**Metrics Endpoints**:
- API metrics: http://localhost:8091/metrics
- Worker metrics: http://localhost:8092/metrics

**Note**: Metrics exposure requires Immich v1.108+ or may need additional configuration. Endpoints are configured but may not be active yet.

### Grafana Dashboard

**Access**: http://localhost:3000

**Planned Panels**:
1. API Request Rate
2. ML Job Queue Depth
3. ML Processing Time (p95)
4. GPU Utilization

**Import**:
1. Navigate to: Administration → Dashboards → Import
2. Upload: `IMMICH-GRAFANA-DASHBOARD.json` (if created)
3. Select Prometheus datasource

### Key Metrics to Monitor

**Performance**:
- Smart Search indexing rate
- Face detection processing time
- Video transcoding queue depth
- GPU memory utilization

**Health**:
- Service uptime
- Database connection pool
- Redis connection status
- Storage capacity

**Alerts** (recommended):
- Storage >85% full
- ML queue depth >100 jobs
- Service down >5 minutes
- GPU temperature >80°C

---

## 7. Implementation Status

### Phase Completion Tracking

| Phase | Component | Status | NixOS Option | Completed |
|-------|-----------|--------|--------------|-----------|
| **A** | **Priority 1 Environment Variables** | ✅ | - | 2025-12-06 |
| A.1 | Timezone (TZ) | ✅ | `observability.timezone` | 2025-12-06 |
| A.2 | Log Level | ✅ | `observability.logLevel` | 2025-12-06 |
| A.3 | Metrics Ports | ✅ | `observability.metrics.*` | 2025-12-06 |
| **B** | **Priority 2 Environment Variables** | ✅ | - | 2025-12-06 |
| B.1 | CPU Auto-Detection | ✅ | `machineLearning.cpuCores` | 2025-12-06 |
| B.2 | ML Model TTL | ✅ | `machineLearning.modelTTL` | 2025-12-06 |
| B.3 | ML Threading | ✅ | `machineLearning.threading.*` | 2025-12-06 |
| B.4 | Trusted Proxies | ✅ | `reverseProxy.trustedProxies` | 2025-12-06 |
| **C** | **Prometheus/Grafana Integration** | ✅ | - | 2025-12-06 |
| C.1 | Prometheus Scraping | ✅ | Auto-configured | 2025-12-06 |
| C.2 | Metrics Port Fix | ✅ | 8091-8092 (avoid 8081 conflict) | 2025-12-06 |
| C.3 | Documentation Note | ✅ | Metrics require Immich v1.108+ | 2025-12-06 |
| **D** | **Documentation Consolidation** | ✅ | - | 2025-12-06 |
| D.1 | Single README.md | ✅ | This file | 2025-12-06 |

**Legend**: ⏳ Planned | 🚧 In Progress | ✅ Complete | ❌ Blocked

### Configuration Improvements Summary

**Implemented**:
- ✅ Explicit timezone configuration (TZ environment variable)
- ✅ Configurable log levels via NixOS options
- ✅ Prometheus metrics endpoints configured (ports 8091-8092)
- ✅ CPU core auto-detection from /proc/cpuinfo
- ✅ ML model TTL tuning (10 min default, keeps models in GPU memory)
- ✅ ML threading auto-computed from detected cores
- ✅ Dynamic trusted proxy configuration (empty default, set in machine config)
- ✅ Prometheus scrape targets auto-configured when metrics enabled

**Benefits**:
- Better observability (structured logging, metrics)
- Improved ML performance (longer model retention, optimized threading)
- Flexible proxy configuration (supports Caddy, Tailscale, custom setups)
- Future-ready for Grafana dashboards

---

## 8. Testing & Validation

### GPU Validation

**Quick Test**:
```bash
# 1. Upload 10 photos via web UI
# 2. Perform Smart Search (e.g., "person", "sunset")
# 3. Monitor GPU usage
watch -n 1 nvidia-smi

# Expected:
# - GPU utilization: 20-80% during ML operations
# - GPU memory: 1-2GB used
# - Process: .gunicorn-wrapp (immich-machine-learning)
```

**Comprehensive Test Plan**:

**Phase 1: Upload & Indexing**
```bash
# 1. Upload 50 diverse photos (faces, landscapes, objects)
# 2. Monitor ML processing
sudo journalctl -u immich-machine-learning -f | rg "Smart Search|Facial"

# 3. Verify GPU acceleration
nvidia-smi dmon -s pucvmt -c 60
# Should see active GPU memory and compute usage
```

**Phase 2: Smart Search**
```bash
# 1. Test various queries:
#    - "person" (face detection)
#    - "sunset" (scene classification)
#    - "car" (object detection)
# 2. Note response times (should be <1s with GPU)
# 3. Compare to CPU baseline (disable GPU: gpu.enable = false)
```

**Phase 3: Video Transcoding**
```bash
# 1. Upload large video (>1GB, 4K preferred)
# 2. Monitor NVENC usage:
nvidia-smi dmon -s u -c 60
# Encoder utilization should spike

# 3. Check encoded output quality
ls -lh /mnt/photos/encoded-video/
```

**Phase 4: Model TTL Verification**
```bash
# 1. Perform Smart Search
# 2. Wait 10+ minutes (modelTTL = 600s)
# 3. Check logs for model unload
sudo journalctl -u immich-machine-learning | rg -i "unload"

# 4. Perform another search, note latency
# Should be ~2s (model reload) vs <200ms (cached)
```

### Performance Benchmarks

**Expected Results** (with GPU vs CPU):
- Smart Search indexing: 10 photos in ~5s (GPU) vs ~20s (CPU)
- Face detection: 100 faces in ~30s (GPU) vs ~120s (CPU)
- Video transcode (4K→1080p): 10min video in ~3min (GPU) vs ~20min (CPU)

---

## 9. Troubleshooting

### Services Not Starting

**Check service status**:
```bash
systemctl status immich-server immich-machine-learning
```

**Common issues**:

1. **Database permission errors** (`permission denied for schema vectors`):
```bash
# Symptom: Logs show "PostgresError: permission denied for schema vectors"
# Cause: Service runs as eric user but PostgreSQL user not configured

# Fix: Module should auto-configure on rebuild, but if manual fix needed:
sudo -u postgres psql -d immich <<EOF
GRANT USAGE ON SCHEMA vectors TO eric;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA vectors TO eric;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA vectors TO eric;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA vectors TO eric;
EOF

# Then rebuild to make it declarative:
sudo nixos-rebuild switch --flake .#hwc-server
```

**Note**: This issue occurs when Immich service runs as `eric` system user and connects to PostgreSQL via Unix socket peer authentication. The module automatically ensures the `eric` PostgreSQL user exists with proper permissions on every rebuild.

2. **Marker file permission errors** (`EACCES: permission denied, open '/mnt/photos/*/​.immich'`):
```bash
# Symptom: Logs show "Failed to read: <UPLOAD_LOCATION>/encoded-video/.immich"
# Cause: Storage base directory (/mnt/photos) not owned by eric or lacks traversal permissions

# Check current ownership
sudo ls -ld /mnt/photos
# Should show: drwxr-xr-x ... eric users ...

# Fix: Module should auto-configure on rebuild using tmpfiles.d, but if manual fix needed:
sudo chown eric:users /mnt/photos
sudo chmod 755 /mnt/photos

# Verify access
cat /mnt/photos/library/.immich  # Should succeed
```

**Note**: Immich verifies storage mounts by reading `.immich` marker files in each storage subdirectory. The service runs as `eric:users`, so all parent directories in the path must have execute permission for the eric user. The module uses `systemd.tmpfiles.d` to declaratively set `/mnt/photos` ownership to `eric:users` with `755` permissions on every boot.

3. **PostgreSQL not ready**:
```bash
# Check database service
systemctl status postgresql

# Test connection
sudo -u postgres psql -c "\l" | rg immich
```

3. **Redis not available**:
```bash
# Check Redis service
systemctl status redis-immich

# Test socket
ls -l /run/redis-immich/redis.sock
```

4. **GPU not accessible**:
```bash
# Verify nvidia-container-toolkit
systemctl status nvidia-container-toolkit-cdi-generator

# Check device access
ls -l /dev/nvidia*

# Verify user in groups
groups eric | rg "video\|render"
```

### GPU Not Being Used

**Diagnosis**:
```bash
# 1. Check ONNX Runtime provider
systemctl show immich-machine-learning | rg ONNXRUNTIME_PROVIDER
# Should be: ONNXRUNTIME_PROVIDER=cuda

# 2. Verify CUDA visible
systemctl show immich-machine-learning | rg CUDA_VISIBLE_DEVICES
# Should be: CUDA_VISIBLE_DEVICES=0

# 3. Check ML logs for CUDA errors
sudo journalctl -u immich-machine-learning -n 100 | rg -i "cuda|gpu|error"
```

**Fix**:
```bash
# Ensure GPU acceleration enabled
# In configuration.nix or profiles/server.nix:
hwc.infrastructure.hardware.gpu.enable = true;
hwc.server.immich.gpu.enable = true;

# Rebuild
sudo nixos-rebuild switch --flake .#hwc-server
```

### Slow Performance

**ML operations slow**:
```bash
# 1. Check model TTL (should be 600s)
systemctl show immich-machine-learning | rg MODEL_TTL

# 2. Verify threading
systemctl show immich-machine-learning | rg "INTER_OP\|INTRA_OP"

# 3. Increase model TTL if needed
# In configuration.nix:
hwc.server.immich.machineLearning.modelTTL = 900;  # 15 minutes
```

**Database slow**:
```bash
# Check PostgreSQL performance
sudo -u postgres psql immich <<EOF
SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;
EOF

# Vacuum and analyze
sudo -u postgres psql immich -c "VACUUM ANALYZE;"
```

### Storage Issues

**Out of space**:
```bash
# Check usage
df -h /mnt/photos

# Find largest directories
du -h --max-depth=2 /mnt/photos | sort -hr | head -10

# Clean regeneratable caches (if desperate)
sudo systemctl stop immich-server immich-machine-learning
sudo rm -rf /mnt/photos/thumbs/*
sudo rm -rf /mnt/photos/encoded-video/*
sudo systemctl start immich-server immich-machine-learning
# Immich will regenerate on demand
```

**Missing .immich markers**:
```bash
# Recreate mount verification markers
for dir in library thumbs encoded-video profile; do
  sudo touch /mnt/photos/$dir/.immich
  sudo chown eric:users /mnt/photos/$dir/.immich
done
```

### Metrics Not Exposing

**Check if ports are listening**:
```bash
sudo ss -tlnp | rg "809[12]"
```

**Verify environment variables set**:
```bash
systemctl show immich-server | rg "METRICS_PORT"
```

**Note**: Metrics exposure may require Immich v1.108+ or additional configuration. Current implementation has Prometheus scraping configured, but endpoints may not be active yet.

---

## 10. Migration & Deployment

### Initial Deployment

1. **Enable in NixOS configuration**:
```nix
# profiles/server.nix or machines/server/config.nix
hwc.server.immich = {
  enable = true;
  gpu.enable = true;
  # ... other options from Section 2
};
```

2. **Create PostgreSQL database** (if not auto-created):
```bash
sudo -u postgres psql <<EOF
CREATE DATABASE immich;
CREATE USER immich WITH PASSWORD 'securepassword';
GRANT ALL PRIVILEGES ON DATABASE immich TO immich;
ALTER DATABASE immich OWNER TO immich;
EOF
```

**Note on Permission Simplification**: The Immich service runs as the `eric` system user (single-user system pattern). The NixOS module automatically:
- Creates an `eric` PostgreSQL user with superuser privileges (for extension management and migrations)
- Grants full access to the immich database and schemas (public, vectors)
- Sets `/mnt/photos` ownership to `eric:users` with `755` permissions for storage access

This happens declaratively on every rebuild via `services.postgresql.ensureUsers`, `postgresql.postStart` hooks, and `systemd.tmpfiles.d` rules.

3. **Build and deploy**:
```bash
sudo nixos-rebuild switch --flake .#hwc-server
```

4. **Initial setup via web UI**:
- Navigate to http://localhost:2283
- Create admin account
- Configure storage template (Administration → Settings)
- Set up external libraries (if needed)

### Upgrading Immich

**NixOS updates automatically manage Immich version**:
```bash
# Update flake inputs
nix flake update

# Rebuild
sudo nixos-rebuild switch --flake .#hwc-server

# Verify new version
curl -s http://localhost:2283/api/server-info/version
```

### Migrating from Docker/Podman

**Prerequisites**:
- Existing Docker Immich instance
- Database dump
- Media files accessible

**Migration steps**:

1. **Backup existing installation**:
```bash
# Docker/Podman database dump
docker exec -t immich_postgres pg_dumpall -c -U postgres > immich_backup.sql

# Media backup
rsync -av /path/to/docker/upload/ /mnt/photos/library/
```

2. **Configure NixOS Immich** (as above)

3. **Import database**:
```bash
sudo -u postgres psql < immich_backup.sql
```

4. **Verify permissions**:
```bash
sudo chown -R eric:users /mnt/photos/
```

5. **Start services and verify**:
```bash
sudo systemctl start immich-server immich-machine-learning
systemctl status immich-server
```

### Trusted Proxy Configuration

**Set in machine config**:
```nix
# machines/server/config.nix
hwc.server.immich.reverseProxy.trustedProxies = [
  "127.0.0.1"        # Local Caddy
  "100.64.0.0/10"    # Tailscale CGNAT range
];
```

**Verification**:
```bash
systemctl show immich-server | rg TRUSTED_PROXIES
# Should show: IMMICH_TRUSTED_PROXIES=127.0.0.1,100.64.0.0/10
```

---

## Additional Resources

### Official Documentation
- [Immich Docs](https://docs.immich.app/)
- [Environment Variables Reference](https://docs.immich.app/install/environment-variables)
- [Storage Templates](https://docs.immich.app/docs/administration/storage-template)

### NixOS Resources
- `domains/server/immich/index.nix` - Implementation
- `domains/server/immich/options.nix` - All configuration options
- Charter v7.0 - Architecture rules

### Support
- GitHub Issues: https://github.com/immich-app/immich/issues
- Discord: https://discord.gg/immich

---

**Generated**: 2025-12-06
**Maintainer**: eric
**Repository**: /home/eric/.nixos
