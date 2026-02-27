# Prometheus Exporters - Implementation Guide

**Last Updated**: 2025-12-12
**Status**: ✅ Operational (7/10 targets active)

## Overview

This document describes the Prometheus exporters deployed in the hwc-server monitoring stack. These exporters collect metrics from various services and expose them in Prometheus format for visualization in Grafana.

## Active Exporters

### 1. Node Exporter (System Metrics)
- **Port**: 9100
- **Job Name**: `node`
- **Status**: ✅ UP
- **Module**: NixOS built-in (`services.prometheus.exporters.node`)
- **Metrics**: CPU, memory, disk, network, filesystem usage
- **Example Metrics**:
  - `node_cpu_seconds_total` - CPU time per core/mode
  - `node_memory_MemAvailable_bytes` - Available memory
  - `node_filesystem_avail_bytes` - Filesystem available space

### 2. cAdvisor (Container Metrics)
- **Port**: 9120
- **Job Name**: `cadvisor`
- **Status**: ✅ UP
- **Module**: `hwc.server.monitoring.cadvisor`
- **Location**: `domains/server/monitoring/cadvisor/`
- **Container**: `gcr.io/cadvisor/cadvisor:latest`
- **Metrics**: Per-container CPU, memory, network, filesystem usage
- **Example Metrics**:
  - `container_memory_usage_bytes` - Memory usage per container
  - `container_cpu_usage_seconds_total` - CPU usage per container
  - `container_network_receive_bytes_total` - Network RX bytes

**Configuration**:
```nix
hwc.server.monitoring.cadvisor = {
  enable = true;
  port = 9120;
};
```

### 3. Sonarr Exporter (TV Shows)
- **Port**: 9707
- **Job Name**: `sonarr-exporter`
- **Status**: ✅ UP
- **Module**: `hwc.server.monitoring.exportarr`
- **Location**: `domains/server/monitoring/exportarr/`
- **Container**: `ghcr.io/onedr0p/exportarr:latest`
- **URL**: `http://127.0.0.1:8989/sonarr`
- **Metrics**: Series count, episodes, queue, health
- **Example Metrics**:
  - `sonarr_series_total` - Total number of TV series
  - `sonarr_episode_total` - Total episodes monitored
  - `sonarr_queue_total` - Items in download queue

### 4. Radarr Exporter (Movies)
- **Port**: 9708
- **Job Name**: `radarr-exporter`
- **Status**: ✅ UP
- **Module**: `hwc.server.monitoring.exportarr`
- **URL**: `http://127.0.0.1:7878/radarr`
- **Metrics**: Movie count, queue, health, storage
- **Example Metrics**:
  - `radarr_movie_total` - Total number of movies
  - `radarr_movie_downloaded_total` - Downloaded movies
  - `radarr_queue_total` - Items in download queue

### 5. Lidarr Exporter (Music)
- **Port**: 9709
- **Job Name**: `lidarr-exporter`
- **Status**: ✅ UP
- **Module**: `hwc.server.monitoring.exportarr`
- **URL**: `http://127.0.0.1:8686/lidarr`
- **Metrics**: Artist count, albums, tracks, storage
- **Example Metrics**:
  - `lidarr_artist_total` - Total number of artists
  - `lidarr_artists_filesize_bytes` - Total storage used
  - `lidarr_queue_total` - Items in download queue

### 6. Prowlarr Exporter (Indexers)
- **Port**: 9710
- **Job Name**: `prowlarr-exporter`
- **Status**: ✅ UP
- **Module**: `hwc.server.monitoring.exportarr`
- **URL**: `http://127.0.0.1:9696/prowlarr`
- **Metrics**: Indexer status, queries, health
- **Example Metrics**:
  - `prowlarr_indexer_total` - Total number of indexers
  - `prowlarr_indexer_auth_queries_total` - Auth queries per indexer
  - `prowlarr_system_status` - System health

### 7. Transcript API Health
- **Port**: 8000
- **Job Name**: `transcript-api-health`
- **Status**: ✅ UP
- **Module**: `hwc.server.transcript-api`
- **Endpoint**: `/health`
- **Metrics**: API health status

## Exportarr Configuration

The Exportarr module creates **separate containers** for each Arr application to enable independent monitoring and restarts.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Prometheus (localhost:9090)                                │
└───────────────┬─────────────────────────────────────────────┘
                │ scrapes metrics every 60s
                │
        ┌───────┴────────┬────────┬────────┬────────┐
        │                │        │        │        │
┌───────▼──────┐ ┌───────▼──────┐ ┌──────▼──────┐ ┌──────▼──────┐
│ exportarr-   │ │ exportarr-   │ │ exportarr-  │ │ exportarr-  │
│ sonarr:9707  │ │ radarr:9708  │ │ lidarr:9709 │ │ prowlarr:   │
│              │ │              │ │             │ │ 9710        │
└───────┬──────┘ └───────┬──────┘ └──────┬──────┘ └──────┬──────┘
        │                │               │               │
        │ reads API key from /run/exportarr/{app}-env   │
        │                │               │               │
┌───────▼──────┐ ┌───────▼──────┐ ┌──────▼──────┐ ┌──────▼──────┐
│ Sonarr       │ │ Radarr       │ │ Lidarr      │ │ Prowlarr    │
│ :8989/sonarr │ │ :7878/radarr │ │ :8686/lidarr│ │ :9696/      │
│              │ │              │ │             │ │ prowlarr    │
└──────────────┘ └──────────────┘ └─────────────┘ └─────────────┘
```

### Key Implementation Details

1. **Host Networking**: Containers use `--network=host` to access Arr apps on 127.0.0.1
2. **Unique Ports**: Each exporter gets its own port (9707-9710)
3. **URL Bases**: All Arr apps use URL base paths (e.g., `/sonarr`, `/radarr`)
4. **Secret Management**: API keys stored in agenix, converted to environment files at runtime
5. **Environment File Pattern**:
   ```bash
   # Created by systemd preStart
   /run/exportarr/sonarr-env  # contains: API_KEY=<value>
   /run/exportarr/radarr-env
   /run/exportarr/lidarr-env
   /run/exportarr/prowlarr-env
   ```

### NixOS Configuration

```nix
# profiles/monitoring.nix
hwc.server.monitoring.exportarr = {
  enable = true;
  port = 9707;  # Base port, each app gets +1
  apps = [ "sonarr" "radarr" "lidarr" "prowlarr" ];
};
```

### Secret Requirements

Each Arr app requires an API key stored in agenix:
- `/run/agenix/sonarr-api-key`
- `/run/agenix/radarr-api-key`
- `/run/agenix/lidarr-api-key`
- `/run/agenix/prowlarr-api-key`

The systemd service `preStart` converts these to environment files:
```bash
echo "API_KEY=$(cat /run/agenix/sonarr-api-key)" > /run/exportarr/sonarr-env
```

## Inactive Exporters

### Frigate Exporter (NVR Metrics)
- **Port**: 9192 (configured but not running)
- **Status**: ❌ DISABLED
- **Reason**: No accessible Docker images found
- **Attempted Images**:
  - `docker.io/rhysbailey/frigate-exporter:latest` - Access denied
  - `ghcr.io/blakeblackshear/frigate-prometheus-exporter:latest` - Not found
- **Resolution**: Needs custom exporter or official image release

**Configuration** (disabled in profiles/monitoring.nix):
```nix
# hwc.server.frigate.exporter.enable = lib.mkDefault true;  # Commented out
```

### Immich Metrics (Photo Library)
- **Ports**: 8091 (API), 8092 (Workers)
- **Status**: ❌ DOWN
- **Reason**: Immich v2.3.1 doesn't expose Prometheus metrics despite environment variables
- **Environment Variables Set**:
  - `IMMICH_API_METRICS_PORT=8091`
  - `IMMICH_MICROSERVICES_METRICS_PORT=8092`
- **Resolution Options**:
  1. Enable metrics in Immich web UI (Admin → Settings → Server Settings)
  2. Add `IMMICH_METRICS_ENABLED=true` environment variable (if supported)
  3. Upgrade to newer Immich version with full metrics support
  4. Leave disabled (current approach)

**Current Configuration**:
```nix
# profiles/server.nix
hwc.server.immich.observability.metrics = {
  enable = true;
  apiPort = 8091;
  microservicesPort = 8092;
};
```

## Testing Exporters

### Check All Targets
```bash
curl -s http://localhost:9090/api/v1/targets | \
  jq -r '.data.activeTargets[] | "\(.labels.job): \(.health)"' | sort
```

### Test Individual Exporters
```bash
# Node Exporter
curl -s http://localhost:9100/metrics | rg "^node_cpu"

# cAdvisor
curl -s http://localhost:9120/metrics | rg "^container_memory"

# Sonarr
curl -s http://localhost:9707/metrics | rg "^sonarr_series"

# Radarr
curl -s http://localhost:9708/metrics | rg "^radarr_movie"

# Lidarr
curl -s http://localhost:9709/metrics | rg "^lidarr_artist"

# Prowlarr
curl -s http://localhost:9710/metrics | rg "^prowlarr_indexer"
```

### Check Container Status
```bash
sudo podman ps --filter name="exportarr" --format "{{.Names}}\t{{.Status}}"
```

### View Exporter Logs
```bash
sudo journalctl -u podman-exportarr-sonarr.service -n 50
sudo journalctl -u podman-exportarr-radarr.service -n 50
sudo journalctl -u podman-exportarr-lidarr.service -n 50
sudo journalctl -u podman-exportarr-prowlarr.service -n 50
```

## Grafana Dashboards

These exporters provide data for the following Grafana dashboards:

1. **System Health** (node-exporter metrics)
   - CPU, memory, disk, network usage
   - Filesystem capacity and I/O

2. **Container Metrics** (cAdvisor metrics)
   - Per-container resource usage
   - Container lifecycle events

3. **Media Services** (Exportarr metrics)
   - Library statistics (movies, TV shows, music)
   - Download queue status
   - Service health monitoring
   - Storage usage trends

## Troubleshooting

### Exporter Container Won't Start
```bash
# Check logs
sudo journalctl -u podman-exportarr-sonarr.service -n 100

# Verify secret file exists
sudo ls -la /run/agenix/sonarr-api-key

# Verify environment file was created
sudo cat /run/exportarr/sonarr-env

# Restart service
sudo systemctl restart podman-exportarr-sonarr.service
```

### Metrics Showing Errors
Common issues:
- **Connection refused**: Arr app not running or wrong port
- **Permission denied**: API key file not readable
- **307 Redirect**: Wrong URL base (missing `/sonarr`, `/radarr`, etc.)

```bash
# Test Arr app accessibility
curl -I http://localhost:8989/sonarr

# Verify API key works
curl -H "X-Api-Key: $(sudo cat /run/agenix/sonarr-api-key)" \
  http://localhost:8989/sonarr/api/v3/system/status
```

### Prometheus Not Scraping
```bash
# Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health == "down")'

# Verify scrape config
sudo systemctl cat prometheus | rg -A 10 "scrape_configs"

# Reload Prometheus
sudo systemctl reload prometheus
```

## Module Locations

```
domains/server/monitoring/
├── index.nix              # Domain aggregator
├── prometheus/            # Prometheus server
├── grafana/              # Grafana dashboards
├── alertmanager/         # Alert routing
├── cadvisor/             # Container metrics exporter
│   ├── options.nix
│   └── index.nix
└── exportarr/            # Arr apps exporter
    ├── options.nix
    └── index.nix

domains/server/frigate/exporter/  # Frigate exporter (disabled)
    ├── options.nix
    └── index.nix
```

## Charter Compliance

All exporters follow Charter v6.0 patterns:

✅ **OPTIONS/IMPLEMENTATION/VALIDATION sections**
✅ **Namespace alignment** (`hwc.server.monitoring.*`)
✅ **Dependency assertions** (Prometheus required)
✅ **Secret management** via agenix
✅ **Domain boundaries** (monitoring domain)
✅ **No hardcoded values** (configurable ports)

## Success Metrics

- **7/10 targets UP** (70% operational)
- **All critical services monitored** (system, containers, media apps)
- **Zero manual configuration** (fully declarative)
- **Automatic secret management** (agenix integration)
- **Production-ready** (proper error handling, logging)

## Future Improvements

1. **Enable Frigate metrics** when official exporter image is available
2. **Enable Immich metrics** via web UI or version upgrade
3. **Add custom dashboards** for Exportarr metrics
4. **Set up alerting rules** for service health
5. **Add blackbox exporter** for endpoint monitoring
6. **Consider SNMP exporter** for network device monitoring
