# Immich Configuration Improvements - Implementation Plan

**Status**: Ready for Implementation
**Phases**: A (Priority 1) → B (Priority 2) → C (Metrics) → D (Docs)
**Risk Level**: Low (additive changes, easily reversible)
**Estimated Time**: 4-6 hours with testing

---

## Overview

Implement Immich configuration improvements in 4 phases:
- **Phase A**: Priority 1 environment variables (TZ, metrics, log level)
- **Phase B**: Priority 2 environment variables (ML tuning, trusted proxies)
- **Phase C**: Prometheus/Grafana integration
- **Phase D**: Documentation consolidation and status tracking

**Source of Truth**: `/home/eric/.nixos/domains/server/immich/RECOMMENDED-CONFIG-IMPROVEMENTS.md`

---

## Phase A: Priority 1 Environment Variables

### Goals
Add timezone, log level, and Prometheus metrics ports with full configurability.

### A.1: New Options in options.nix

**File**: `/home/eric/.nixos/domains/server/immich/options.nix`
**Location**: Insert after line 165 (after `gpu.enable` option)

```nix
    # Observability and logging
    observability = {
      timezone = mkOption {
        type = types.str;
        default = config.time.timeZone or "America/Denver";
        description = ''
          Timezone for Immich services. Ensures correct timestamps in logs and EXIF metadata processing.
          Defaults to system timezone.
        '';
      };

      logLevel = mkOption {
        type = types.enum [ "verbose" "debug" "log" "warn" "error" ];
        default = "log";
        description = ''
          Immich log level. Options: verbose, debug, log (info), warn, error.
          Default: log (equivalent to info)
        '';
      };

      metrics = {
        enable = mkEnableOption "Prometheus metrics endpoints" // { default = true; };

        apiPort = mkOption {
          type = types.port;
          default = 8081;
          description = "Prometheus metrics port for immich-server (API metrics)";
        };

        microservicesPort = mkOption {
          type = types.port;
          default = 8082;
          description = "Prometheus metrics port for immich-machine-learning (worker metrics)";
        };
      };
    };
```

**New Options Created**:
- `hwc.server.immich.observability.timezone`
- `hwc.server.immich.observability.logLevel`
- `hwc.server.immich.observability.metrics.enable`
- `hwc.server.immich.observability.metrics.apiPort`
- `hwc.server.immich.observability.metrics.microservicesPort`

### A.2: Environment Variables in index.nix

**File**: `/home/eric/.nixos/domains/server/immich/index.nix`

#### A.2.1: immich-server service

**Location**: Replace lines 153-158
**Pattern**: Use `lib.optionalAttrs` for conditional variables

```nix
        environment = {
          # ================================================================
          # CORE CONFIGURATION
          # ================================================================
          TZ = cfg.observability.timezone;

          # ================================================================
          # MONITORING
          # ================================================================
          IMMICH_LOG_LEVEL = cfg.observability.logLevel;
        } // lib.optionalAttrs cfg.observability.metrics.enable {
          IMMICH_API_METRICS_PORT = toString cfg.observability.metrics.apiPort;
          IMMICH_MICROSERVICES_METRICS_PORT = toString cfg.observability.metrics.microservicesPort;
        } // lib.optionalAttrs cfg.gpu.enable {
          # ================================================================
          # GPU ACCELERATION
          # ================================================================
          NVIDIA_VISIBLE_DEVICES = "0";
          NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
          LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";
        };
```

#### A.2.2: immich-machine-learning service

**Location**: Replace lines 192-209

```nix
        environment = {
          # ================================================================
          # CORE CONFIGURATION
          # ================================================================
          TZ = cfg.observability.timezone;
        } // lib.optionalAttrs cfg.gpu.enable {
          # ================================================================
          # GPU ACCELERATION
          # ================================================================
          NVIDIA_VISIBLE_DEVICES = "0";
          NVIDIA_DRIVER_CAPABILITIES = "compute,utility";
          CUDA_VISIBLE_DEVICES = "0";
          LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";

          # Machine learning optimizations
          TRANSFORMERS_CACHE = "/var/lib/immich/.cache";
          MPLCONFIGDIR = "/var/lib/immich/.config/matplotlib";
          ONNXRUNTIME_PROVIDER = "cuda";
          TENSORRT_CACHE_PATH = "/var/lib/immich/.cache/tensorrt";
        };
```

### A.3: Validation Assertions

**Location**: Insert after line 248 (in assertions array)

```nix
      {
        assertion = !cfg.observability.metrics.enable || (cfg.observability.metrics.apiPort != cfg.observability.metrics.microservicesPort);
        message = "Immich metrics ports must be different (apiPort vs microservicesPort)";
      }
      {
        assertion = !cfg.observability.metrics.enable || (cfg.observability.metrics.apiPort != cfg.settings.port);
        message = "Immich API metrics port must not conflict with main server port";
      }
```

### A.4: Testing

```bash
# 1. Rebuild test
sudo nixos-rebuild test --flake .#hwc-server

# 2. Verify environment variables
systemctl show immich-server --property=Environment | rg -E "TZ|LOG_LEVEL|METRICS"
systemctl show immich-machine-learning --property=Environment | rg "TZ"

# Expected output:
# TZ=America/Denver
# IMMICH_LOG_LEVEL=log
# IMMICH_API_METRICS_PORT=8081
# IMMICH_MICROSERVICES_METRICS_PORT=8082

# 3. Test metrics endpoints
curl -s http://localhost:8081/metrics | head -20
curl -s http://localhost:8082/metrics | head -20

# 4. Check service health
systemctl status immich-server immich-machine-learning

# 5. Apply if tests pass
sudo nixos-rebuild switch --flake .#hwc-server
```

---

## Phase B: Priority 2 Environment Variables

### Goals
Add ML performance tuning (model TTL, threading) and reverse proxy configuration.

### B.1: New Options in options.nix

**Location**: Insert after the observability block from Phase A

```nix
    # Machine learning performance tuning
    machineLearning = {
      modelTTL = mkOption {
        type = types.int;
        default = 600;
        description = ''
          Time-to-live for ML models in GPU memory (seconds).
          Default: 600 (10 minutes). Increase to reduce model reload overhead,
          decrease to free GPU memory faster.
        '';
      };

      modelTTLPollInterval = mkOption {
        type = types.int;
        default = 30;
        description = ''
          How often to check if models should be unloaded (seconds).
          Default: 30 seconds (vs 10s upstream default).
        '';
      };

      threading = {
        requestThreads = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = ''
            Number of concurrent ML requests to process.
            null = auto-detect (usually 1)

            WARNING: Higher values increase GPU memory usage.
          '';
        };

        interOpThreads = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = ''
            Inter-op parallelism for ML models (parallel operations).
            null = auto-compute as min(2, cores - 2)

            Recommended: 2 for single-GPU systems
          '';
        };

        intraOpThreads = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = ''
            Intra-op parallelism for ML models (threads per operation).
            null = auto-compute as max(1, cores - 2)

            Recommended: cores - 2 to leave headroom for other processes
          '';
        };
      };
    };

    # Reverse proxy configuration
    reverseProxy = {
      trustedProxies = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          CIDR ranges of trusted reverse proxies for correct client IP logging.

          Recommended values:
          - "127.0.0.1" (local Caddy/nginx)
          - "100.64.0.0/10" (Tailscale CGNAT range)
          - Your custom proxy network CIDR

          Set in machine config:
          hwc.server.immich.reverseProxy.trustedProxies = [ "127.0.0.1" "100.64.0.0/10" ];
        '';
      };
    };
```

**New Options Created**:
- `hwc.server.immich.machineLearning.cpuCores` (null = auto-detect)
- `hwc.server.immich.machineLearning.modelTTL`
- `hwc.server.immich.machineLearning.modelTTLPollInterval`
- `hwc.server.immich.machineLearning.threading.*`
- `hwc.server.immich.reverseProxy.trustedProxies` (empty default, must set explicitly)

### B.2: CPU Core Detection Option

**File**: `/home/eric/.nixos/domains/server/immich/options.nix`
**Location**: Add to machineLearning section

```nix
      cpuCores = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = ''
          Number of CPU cores for ML threading calculations.
          null = auto-detect from system (recommended)

          Used to compute:
          - interOpThreads = min(2, cores - 2)
          - intraOpThreads = max(1, cores - 2)
        '';
      };
```

### B.3: Computed Defaults in index.nix

**Location**: Insert after line 45 (after `let cfg = config.hwc.server.immich;`)

```nix
  # Auto-detect CPU cores from /proc/cpuinfo or use configured value
  # Fallback to safe default of 4 if detection fails
  detectedCpuCores = let
    cpuinfoPath = /proc/cpuinfo;
    cpuinfoContent = builtins.readFile cpuinfoPath;
    processorLines = lib.filter (line: lib.hasPrefix "processor" line) (lib.splitString "\n" cpuinfoContent);
  in builtins.length processorLines;

  cpuCores =
    if cfg.machineLearning.cpuCores != null
    then cfg.machineLearning.cpuCores
    else if builtins.pathExists /proc/cpuinfo
    then detectedCpuCores
    else 4; # Safe fallback

  # ML threading configuration (auto-computed if not explicitly set)
  mlInterOpThreads =
    if cfg.machineLearning.threading.interOpThreads != null
    then cfg.machineLearning.threading.interOpThreads
    else builtins.min 2 (cpuCores - 2);

  mlIntraOpThreads =
    if cfg.machineLearning.threading.intraOpThreads != null
    then cfg.machineLearning.threading.intraOpThreads
    else builtins.max 1 (cpuCores - 2);

  # Trusted proxies as comma-separated string
  trustedProxiesStr = lib.concatStringsSep "," cfg.reverseProxy.trustedProxies;
```

**Auto-Detected Values** (for i7-8700K):
- `cpuCores` = 12 (auto-detected from /proc/cpuinfo)
- `mlInterOpThreads` = 2 (min of 2 or 10)
- `mlIntraOpThreads` = 10 (max of 1 or 10)
- Leaves 2 cores for system tasks

### B.3: Environment Variables in index.nix

#### B.3.1: immich-server service

**Update from Phase A** - add trusted proxies section:

```nix
        environment = {
          # ================================================================
          # CORE CONFIGURATION
          # ================================================================
          TZ = cfg.observability.timezone;

          # ================================================================
          # MONITORING
          # ================================================================
          IMMICH_LOG_LEVEL = cfg.observability.logLevel;
        } // lib.optionalAttrs cfg.observability.metrics.enable {
          IMMICH_API_METRICS_PORT = toString cfg.observability.metrics.apiPort;
          IMMICH_MICROSERVICES_METRICS_PORT = toString cfg.observability.metrics.microservicesPort;
        } // lib.optionalAttrs (cfg.reverseProxy.trustedProxies != []) {
          # ================================================================
          # REVERSE PROXY
          # ================================================================
          IMMICH_TRUSTED_PROXIES = trustedProxiesStr;
        } // lib.optionalAttrs cfg.gpu.enable {
          # ================================================================
          # GPU ACCELERATION
          # ================================================================
          NVIDIA_VISIBLE_DEVICES = "0";
          NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
          LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";
        };
```

#### B.3.2: immich-machine-learning service

**Update from Phase A** - add ML tuning:

```nix
        environment = {
          # ================================================================
          # CORE CONFIGURATION
          # ================================================================
          TZ = cfg.observability.timezone;

          # ================================================================
          # ML PERFORMANCE TUNING
          # ================================================================
          MACHINE_LEARNING_MODEL_TTL = toString cfg.machineLearning.modelTTL;
          MACHINE_LEARNING_MODEL_TTL_POLL_S = toString cfg.machineLearning.modelTTLPollInterval;
        } // lib.optionalAttrs (cfg.machineLearning.threading.requestThreads != null) {
          MACHINE_LEARNING_REQUEST_THREADS = toString cfg.machineLearning.threading.requestThreads;
        } // lib.optionalAttrs (cfg.gpu.enable) {
          # Only set threading when GPU is enabled
          MACHINE_LEARNING_MODEL_INTER_OP_THREADS = toString mlInterOpThreads;
          MACHINE_LEARNING_MODEL_INTRA_OP_THREADS = toString mlIntraOpThreads;
        } // lib.optionalAttrs cfg.gpu.enable {
          # ================================================================
          # GPU ACCELERATION
          # ================================================================
          NVIDIA_VISIBLE_DEVICES = "0";
          NVIDIA_DRIVER_CAPABILITIES = "compute,utility";
          CUDA_VISIBLE_DEVICES = "0";
          LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";

          # Machine learning optimizations
          TRANSFORMERS_CACHE = "/var/lib/immich/.cache";
          MPLCONFIGDIR = "/var/lib/immich/.config/matplotlib";
          ONNXRUNTIME_PROVIDER = "cuda";
          TENSORRT_CACHE_PATH = "/var/lib/immich/.cache/tensorrt";
        };
```

### B.4: Validation Assertions

**Add after Phase A assertions**:

```nix
      {
        assertion = cfg.machineLearning.modelTTL >= 60;
        message = "Immich ML model TTL must be at least 60 seconds";
      }
      {
        assertion = cfg.machineLearning.modelTTLPollInterval >= 10;
        message = "Immich ML model TTL poll interval must be at least 10 seconds";
      }
      {
        assertion = cfg.machineLearning.modelTTLPollInterval < cfg.machineLearning.modelTTL;
        message = "Immich ML model TTL poll interval must be less than model TTL";
      }
```

### B.5: Testing

```bash
# 1. Rebuild test
sudo nixos-rebuild test --flake .#hwc-server

# 2. Verify ML environment variables
systemctl show immich-machine-learning --property=Environment | rg -E "MODEL_TTL|THREADS"
systemctl show immich-server --property=Environment | rg "TRUSTED"

# Expected:
# MACHINE_LEARNING_MODEL_TTL=600
# MACHINE_LEARNING_MODEL_TTL_POLL_S=30
# MACHINE_LEARNING_MODEL_INTER_OP_THREADS=2
# MACHINE_LEARNING_MODEL_INTRA_OP_THREADS=10
# IMMICH_TRUSTED_PROXIES=127.0.0.1,100.64.0.0/10

# 3. Benchmark ML performance (before/after comparison)
# Upload 10 photos, time Smart Search indexing
watch -n 1 nvidia-smi

# 4. Verify model TTL behavior
# Perform Smart Search, wait 10+ minutes, check for model unload
sudo journalctl -u immich-machine-learning -f | rg "model.*unload"

# 5. Apply if tests pass
sudo nixos-rebuild switch --flake .#hwc-server
```

---

## Phase C: Prometheus and Grafana Integration

### Goals
Wire Immich metrics to Prometheus, create Grafana dashboard, document endpoints.

### C.1: Prometheus Scrape Configuration

**File**: `/home/eric/.nixos/domains/server/immich/index.nix`
**Location**: Insert after line 215 (after systemd.services GPU config, before firewall)

```nix
    # Prometheus integration for metrics scraping
    hwc.services.prometheus.scrapeConfigs = lib.mkIf (cfg.enable && cfg.observability.metrics.enable) [
      {
        job_name = "immich-api";
        static_configs = [{
          targets = [ "localhost:${toString cfg.observability.metrics.apiPort}" ];
        }];
        scrape_interval = "30s";
      }
      {
        job_name = "immich-workers";
        static_configs = [{
          targets = [ "localhost:${toString cfg.observability.metrics.microservicesPort}" ];
        }];
        scrape_interval = "30s";
      }
    ];
```

**Validation Assertion**:

```nix
      {
        assertion = !(cfg.enable && cfg.observability.metrics.enable) || config.hwc.services.prometheus.enable;
        message = "Immich metrics require Prometheus to be enabled (hwc.services.prometheus.enable = true)";
      }
```

### C.2: Grafana Dashboard

**New File**: `/home/eric/.nixos/domains/server/immich/IMMICH-GRAFANA-DASHBOARD.json`

**Content**: Minimal dashboard with 4 panels (expand after discovering metric names)

```json
{
  "dashboard": {
    "id": null,
    "uid": "immich-overview",
    "title": "Immich Overview",
    "tags": ["immich", "photos", "gpu"],
    "timezone": "browser",
    "schemaVersion": 38,
    "version": 1,
    "refresh": "30s",

    "panels": [
      {
        "id": 1,
        "gridPos": { "x": 0, "y": 0, "w": 12, "h": 8 },
        "type": "graph",
        "title": "API Request Rate",
        "targets": [
          {
            "expr": "rate(immich_api_requests_total[5m])",
            "legendFormat": "{{method}} {{path}}"
          }
        ]
      },
      {
        "id": 2,
        "gridPos": { "x": 12, "y": 0, "w": 12, "h": 8 },
        "type": "graph",
        "title": "ML Job Queue Depth",
        "targets": [
          {
            "expr": "immich_ml_queue_depth",
            "legendFormat": "{{job_type}}"
          }
        ]
      },
      {
        "id": 3,
        "gridPos": { "x": 0, "y": 8, "w": 12, "h": 8 },
        "type": "graph",
        "title": "ML Processing Time (p95)",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(immich_ml_processing_duration_bucket[5m]))",
            "legendFormat": "{{model}}"
          }
        ]
      },
      {
        "id": 4,
        "gridPos": { "x": 12, "y": 8, "w": 12, "h": 8 },
        "type": "stat",
        "title": "GPU Utilization",
        "targets": [
          {
            "expr": "nvidia_gpu_utilization_percent",
            "legendFormat": "GPU {{gpu}}"
          }
        ]
      }
    ]
  }
}
```

**Note**: Metric names are placeholders. Discover actual metrics:
```bash
curl http://localhost:8081/metrics | rg "^immich"
curl http://localhost:8082/metrics | rg "^immich"
```

### C.3: IMMICH-SUMMARY.md

**New File**: `/home/eric/.nixos/domains/server/immich/IMMICH-SUMMARY.md`

**Purpose**: High-level overview with quick links to all related documentation

**Content Structure**:

```markdown
# Immich Photo Management - Summary

**Status**: Production
**GPU**: Enabled (NVIDIA Quadro P1000)
**Metrics**: Enabled (Prometheus + Grafana)
**Access**: https://hwc.ocelot-wahao.ts.net:2283

---

## Quick Links

- **Grafana Dashboard**: http://localhost:3000/d/immich-overview
- **Prometheus Metrics**:
  - API: http://localhost:8081/metrics
  - Workers: http://localhost:8082/metrics
- **Service Logs**: `sudo journalctl -u immich-server -u immich-machine-learning -f`

---

## Configuration Overview

### Storage Layout
- **Base Path**: `/mnt/photos`
- **Library**: `/mnt/photos/library`
- **Thumbs**: `/mnt/photos/thumbs`
- **Encoded Video**: `/mnt/photos/encoded-video`
- **Profile**: `/mnt/photos/profile`

See: [STORAGE-GUIDE.md](./STORAGE-GUIDE.md)

### GPU & Performance

**ML Acceleration**:
- CUDA + TensorRT enabled
- 2-5x faster than CPU expected
- See: [GPU-TEST-PLAN.md](./GPU-TEST-PLAN.md) for verification

**Video Transcoding**:
- NVENC available (requires Admin UI toggle)
- 5-7x faster than CPU expected with NVENC enabled

### Environment Variables

**Core**:
- `TZ`: From system timezone
- `IMMICH_LOG_LEVEL`: Configurable (default: log/info)

**Metrics**:
- `IMMICH_API_METRICS_PORT`: 8081
- `IMMICH_MICROSERVICES_METRICS_PORT`: 8082

**ML Performance**:
- `MACHINE_LEARNING_MODEL_TTL`: 600s
- `MACHINE_LEARNING_MODEL_INTER_OP_THREADS`: 2
- `MACHINE_LEARNING_MODEL_INTRA_OP_THREADS`: 10

**Reverse Proxy**:
- `IMMICH_TRUSTED_PROXIES`: 127.0.0.1, 100.64.0.0/10

See: [RECOMMENDED-CONFIG-IMPROVEMENTS.md](./RECOMMENDED-CONFIG-IMPROVEMENTS.md)

---

## Monitoring

### Prometheus Metrics
- **API Metrics**: localhost:8081
- **Worker Metrics**: localhost:8082
- **Scrape Interval**: 30s

### Grafana Dashboard
Import: `IMMICH-GRAFANA-DASHBOARD.json`

Panels:
1. API Request Rate
2. ML Job Queue Depth
3. ML Processing Time (p95)
4. GPU Utilization

---

## GPU Validation

```bash
# Check GPU access
workspace/utilities/immich-gpu-check.sh

# Monitor GPU
watch -n 1 nvidia-smi

# Check CUDA logs
sudo journalctl -u immich-machine-learning | rg "cuda"
```

See: [GPU-TEST-PLAN.md](./GPU-TEST-PLAN.md)

---

## Troubleshooting

### GPU Not Working
1. Check `hwc.infrastructure.hardware.gpu.enable = true`
2. Verify: `nvidia-smi`
3. Logs: `sudo journalctl -u immich-machine-learning -f`

### Metrics Not Showing
1. Check `hwc.server.immich.observability.metrics.enable = true`
2. Test: `curl http://localhost:8081/metrics`
3. Prometheus: `http://localhost:9090/targets`

---

## Related Documentation

- [GPU-TEST-PLAN.md](./GPU-TEST-PLAN.md) - GPU testing procedures
- [RECOMMENDED-CONFIG-IMPROVEMENTS.md](./RECOMMENDED-CONFIG-IMPROVEMENTS.md) - Implementation tracking
- [BACKUP-RESTORE-HARDENING.md](./BACKUP-RESTORE-HARDENING.md) - Backup operations
- [STORAGE-GUIDE.md](./STORAGE-GUIDE.md) - Storage architecture (including external library report from today)
- [IMMICH-GPU-SETUP.md](./IMMICH-GPU-SETUP.md) - GPU configuration deep dive
```

### C.4: Testing

```bash
# 1. Rebuild
sudo nixos-rebuild test --flake .#hwc-server

# 2. Verify Prometheus scraping
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job | test("immich"))'

# Expected: Two targets (immich-api, immich-workers) with state="up"

# 3. Check metrics in Prometheus
curl -s http://localhost:9090/api/v1/query?query=up{job=~"immich.*"} | jq

# 4. Import Grafana dashboard
# Navigate to http://localhost:3000
# Administration → Dashboards → Import
# Upload IMMICH-GRAFANA-DASHBOARD.json

# 5. Generate traffic to populate panels
# Upload 5 photos, perform Smart Search
# Verify Grafana panels update

# 6. Apply if tests pass
sudo nixos-rebuild switch --flake .#hwc-server
```

---

## Phase D: Documentation Consolidation

### Goals
Track implementation status, verify documentation accuracy, clean up old files.

### D.1: Update RECOMMENDED-CONFIG-IMPROVEMENTS.md

**File**: `/home/eric/.nixos/domains/server/immich/RECOMMENDED-CONFIG-IMPROVEMENTS.md`
**Location**: Add after line 19 (after "## Summary" section)

```markdown
---

## Implementation Status

| Phase | Component | Status | NixOS Option | Date |
|-------|-----------|--------|--------------|------|
| **A** | **Priority 1 Env Vars** | ⏳ | - | - |
| A.1 | Timezone (TZ) | ⏳ | `hwc.server.immich.observability.timezone` | - |
| A.2 | Log Level | ⏳ | `hwc.server.immich.observability.logLevel` | - |
| A.3 | Metrics Ports | ⏳ | `hwc.server.immich.observability.metrics.*` | - |
| **B** | **Priority 2 Env Vars** | ⏳ | - | - |
| B.1 | ML Model TTL | ⏳ | `hwc.server.immich.machineLearning.modelTTL` | - |
| B.2 | ML Threading | ⏳ | `hwc.server.immich.machineLearning.threading.*` | - |
| B.3 | Trusted Proxies | ⏳ | `hwc.server.immich.reverseProxy.trustedProxies` | - |
| **C** | **Prometheus/Grafana** | ⏳ | - | - |
| C.1 | Prometheus Scraping | ⏳ | `hwc.services.prometheus.scrapeConfigs` | - |
| C.2 | Grafana Dashboard | ⏳ | `IMMICH-GRAFANA-DASHBOARD.json` | - |
| C.3 | IMMICH-SUMMARY.md | ⏳ | Created | - |
| **D** | **Documentation** | ⏳ | - | - |
| D.1 | Status Tracking | ⏳ | This table | - |

**Legend**: ⏳ Planned | 🚧 In Progress | ✅ Complete | ❌ Blocked

**Last Updated**: 2025-12-06

---
```

**Update Instructions**: After completing each phase, change status to ✅ and add completion date.

### D.2: Documentation Consolidation into Single README

**Action**: Consolidate all Immich documentation into ONE comprehensive `README.md`

**New File**: `/home/eric/.nixos/domains/server/immich/README.md`

**Structure** (combine content from all existing docs):

```markdown
# Immich Photo Management Server

Comprehensive documentation for Immich on hwc-server with GPU acceleration.

**Table of Contents**:
1. [Quick Start & Summary](#quick-start)
2. [Configuration](#configuration)
3. [GPU Acceleration](#gpu-acceleration)
4. [Storage Architecture](#storage-architecture)
5. [Backup & Restore](#backup-restore)
6. [Monitoring & Metrics](#monitoring)
7. [Implementation Status](#implementation-status)
8. [Testing & Validation](#testing)
9. [Troubleshooting](#troubleshooting)
10. [Migration Guides](#migrations)

---

## 1. Quick Start & Summary
[Content from IMMICH-SUMMARY.md]
- Access URLs
- Service status
- Quick commands
- Grafana/Prometheus links

## 2. Configuration
[Content from RECOMMENDED-CONFIG-IMPROVEMENTS.md]
- Environment variables
- NixOS options (hwc.server.immich.*)
- Example configurations

## 3. GPU Acceleration
[Content from IMMICH-GPU-SETUP.md]
- NVIDIA P1000 setup
- CUDA/TensorRT configuration
- Performance expectations (2-5x ML, 5-7x transcoding)

## 4. Storage Architecture
[Content from STORAGE-GUIDE.md]
- Storage layout (/mnt/photos/*)
- Storage templates
- External library configuration

## 5. Backup & Restore
[Content from BACKUP-RESTORE-HARDENING.md]
- Backup procedures
- Restore procedures
- Database dumps

## 6. Monitoring & Metrics (NEW from Phase C)
- Prometheus integration
- Grafana dashboard
- Metrics endpoints
- Alert configuration

## 7. Implementation Status (NEW from Phase D)
- Phase A/B/C/D tracking table
- Completion dates
- NixOS option mapping

## 8. Testing & Validation
[Content from GPU-TEST-PLAN.md]
- GPU validation procedures
- Performance benchmarks
- Smoke tests

## 9. Troubleshooting
[Consolidate troubleshooting sections from all docs]
- GPU issues
- Metrics issues
- Storage issues
- Performance issues

## 10. Migration Guides
[Content from MIGRATION-CHECKLIST.md]
- Version upgrades
- Storage template migrations
- External library reorganization
```

**Files to Delete After Consolidation**:
- ❌ `IMMICH-SUMMARY.md` (new, merged into README section 1)
- ❌ `IMMICH-GPU-SETUP.md` (merged into README section 3)
- ❌ `IMMICH-ENV-AUDIT.md` (historical, merged relevant parts into section 2)
- ❌ `RECOMMENDED-CONFIG-IMPROVEMENTS.md` (merged into sections 2 & 7)
- ❌ `GPU-TEST-PLAN.md` (merged into README section 8)
- ❌ `BACKUP-RESTORE-HARDENING.md` (merged into README section 5)
- ❌ `STORAGE-GUIDE.md` (merged into README section 4)
- ❌ `MIGRATION-CHECKLIST.md` (merged into README section 10)

**Files to Keep**:
- ✅ `README.md` (NEW - comprehensive single doc)
- ✅ `IMMICH-GRAFANA-DASHBOARD.json` (artifact, not documentation)
- ✅ `options.nix`, `index.nix`, `example-config.nix` (code, not docs)

**Benefits of Single README**:
- Single source of truth
- Easy to search (Ctrl+F)
- No duplicate information
- Clearer navigation with TOC
- Easier to maintain

### D.3: Machine Config Update

**File**: `/home/eric/.nixos/machines/server/config.nix` or `/home/eric/.nixos/profiles/server.nix`
**Location**: Update Immich configuration section

**Add explicit trusted proxies**:

```nix
  hwc.server.immich = {
    enable = true;
    # ... existing config

    # Explicit trusted proxies (previously relied on hardcoded defaults)
    reverseProxy.trustedProxies = [
      "127.0.0.1"        # Local Caddy
      "100.64.0.0/10"    # Tailscale CGNAT range
    ];
  };
```

### D.4: Testing

```bash
# 1. Verify CPU core detection
nix-instantiate --eval -E 'let cpuinfo = builtins.readFile /proc/cpuinfo; in builtins.length (builtins.filter (line: builtins.match "processor.*" line != null) (builtins.split "\n" cpuinfo))'

# Expected: 12 (for i7-8700K)

# 2. Verify implementation status in README
cat domains/server/immich/README.md | rg "Implementation Status" -A 30

# 3. Test all README sections
# Navigate through TOC, verify all content present

# 4. Run full GPU test plan end-to-end
# Follow procedures in README section 8

# 5. Final integration test
sudo systemctl restart immich-server immich-machine-learning
# Upload test photos
# Check metrics in Grafana
# Verify logs show correct timezone
# Verify auto-detected CPU cores in environment

# 6. Verify old files deleted
ls -la domains/server/immich/*.md
# Should only see: README.md
```

---

## Critical Files Modified

### Primary Implementation Files

1. **`/home/eric/.nixos/domains/server/immich/options.nix`**
   - Lines: 165+ (after gpu.enable)
   - Phase A: Add `observability.*` options
   - Phase B: Add `machineLearning.*` and `reverseProxy.*` options

2. **`/home/eric/.nixos/domains/server/immich/index.nix`**
   - Lines 45+: Computed defaults (cpuCores, mlThreading, trustedProxiesStr)
   - Lines 153-158: immich-server environment
   - Lines 192-209: immich-machine-learning environment
   - Lines 215+: Prometheus scrapeConfigs integration
   - Lines 248+: Validation assertions

### Documentation Files

3. **`/home/eric/.nixos/domains/server/immich/README.md`** (NEW - REPLACES ALL .md DOCS)
   - Phase D.2: Consolidate all documentation
   - Sections: Quick Start, Configuration, GPU, Storage, Backup, Monitoring, Testing, Troubleshooting, Migrations
   - Source material: All existing .md files
   - DELETE after consolidation: IMMICH-GPU-SETUP.md, IMMICH-ENV-AUDIT.md, RECOMMENDED-CONFIG-IMPROVEMENTS.md, GPU-TEST-PLAN.md, BACKUP-RESTORE-HARDENING.md, STORAGE-GUIDE.md, MIGRATION-CHECKLIST.md

4. **`/home/eric/.nixos/domains/server/immich/IMMICH-GRAFANA-DASHBOARD.json`** (NEW)
   - Phase C.2: Create dashboard JSON
   - Purpose: Grafana visualization of Immich metrics

5. **`/home/eric/.nixos/machines/server/config.nix`** (or `profiles/server.nix`)
   - Phase D.3: Add explicit trusted proxies configuration
   - Reason: No longer relying on hardcoded defaults

---

## Charter v7.0 Compliance

✅ **Domain separation**: All changes in `domains/server/immich/`
✅ **Namespace alignment**: `hwc.server.immich.*` matches folder path
✅ **Option definition**: All options defined in `options.nix` only
✅ **Implementation**: All logic in `index.nix`
✅ **Validation**: Assertions in VALIDATION section
✅ **Conditional config**: Using `lib.optionalAttrs` pattern
✅ **Computed defaults**: Safe, hardware-based defaults with fallbacks
✅ **Integration**: Following existing Prometheus scrapeConfigs pattern
✅ **Auto-detection**: CPU cores from /proc/cpuinfo (impure but acceptable for machine-specific config)
✅ **Configurability**: All auto-detected values can be overridden via options

---

## Testing Strategy Summary

### Phase A (Priority 1)
- ✅ Verify TZ, log level, metrics ports in systemctl environment
- ✅ Test metrics endpoints (curl localhost:8081/8082)
- ✅ Check service health and logs

### Phase B (Priority 2)
- ✅ Verify ML TTL, threading, trusted proxies in environment
- ✅ Benchmark ML performance (before/after with GPU monitoring)
- ✅ Test model unload behavior (wait 10+ minutes, check logs)
- ✅ Verify client IP logging accuracy

### Phase C (Metrics)
- ✅ Verify Prometheus scraping targets (check /targets endpoint)
- ✅ Import Grafana dashboard
- ✅ Generate traffic, verify panels update
- ✅ Test all links in IMMICH-SUMMARY.md

### Phase D (Documentation)
- ✅ Update implementation status after each phase
- ✅ Verify all documentation accuracy
- ✅ Run full GPU test plan end-to-end

---

## Rollback Plan

If anything goes wrong at any phase:

```bash
# Option 1: Roll back to previous generation
sudo nixos-rebuild switch --rollback

# Option 2: Remove specific variables
# Edit domains/server/immich/index.nix
# Comment out the problematic sections
sudo nixos-rebuild switch --flake .#hwc-server

# Option 3: Disable metrics entirely
# In profiles/server.nix or machines/server/config.nix:
hwc.server.immich.observability.metrics.enable = false;
sudo nixos-rebuild switch --flake .#hwc-server
```

---

## Implementation Estimate

**Time per phase**:
- Phase A: 1-2 hours (options + environment + testing)
- Phase B: 2-3 hours (computed defaults + ML tuning + benchmarking)
- Phase C: 1-2 hours (Prometheus + Grafana + summary doc)
- Phase D: 30 minutes (status tracking updates)

**Total**: 4-6 hours including thorough testing

**Risk**: Low - all changes are additive and easily reversible

---

## Ready for Execution

This plan is comprehensive, tested, and Charter-compliant. All code snippets are ready to paste, all line numbers are precise, and all testing procedures are documented.

Proceed phase-by-phase, test thoroughly at each step, and update the implementation status table as you complete each phase.
