# Prometheus Exporters - Quick Reference

## Current Status (2025-12-12)

✅ **7 of 10 targets operational**

### Working Exporters
| Service | Port | Job Name | Metrics |
|---------|------|----------|---------|
| Node Exporter | 9100 | node | CPU, RAM, disk, network |
| cAdvisor | 9120 | cadvisor | Container resources |
| Sonarr | 9707 | sonarr-exporter | TV shows (39 series) |
| Radarr | 9708 | radarr-exporter | Movies (292 films) |
| Lidarr | 9709 | lidarr-exporter | Music (45GB) |
| Prowlarr | 9710 | prowlarr-exporter | Indexers |
| Transcript API | 8000 | transcript-api-health | API health |

### Not Working
| Service | Port | Status | Reason |
|---------|------|--------|--------|
| Frigate | 9192 | ❌ Disabled | No Docker image available |
| Immich API | 8091 | ❌ Down | Metrics not exposed by v2.3.1 |
| Immich Workers | 8092 | ❌ Down | Metrics not exposed by v2.3.1 |

## Quick Commands

### Check All Targets
```bash
curl -s http://localhost:9090/api/v1/targets | \
  jq -r '.data.activeTargets[] | "\(.labels.job): \(.health)"'
```

### Test Exporters
```bash
# Quick health check
curl -s http://localhost:9707/metrics | head -5  # Sonarr
curl -s http://localhost:9708/metrics | head -5  # Radarr
curl -s http://localhost:9120/metrics | head -5  # cAdvisor
```

### Container Status
```bash
sudo podman ps --filter name="exportarr"
```

### Restart Exporters
```bash
sudo systemctl restart podman-exportarr-sonarr
sudo systemctl restart podman-exportarr-radarr
sudo systemctl restart podman-exportarr-lidarr
sudo systemctl restart podman-exportarr-prowlarr
```

## Configuration

### Enable/Disable
```nix
# profiles/monitoring.nix
hwc.server.monitoring.exportarr.enable = true;
hwc.server.monitoring.cadvisor.enable = true;
```

### Rebuild After Changes
```bash
sudo nixos-rebuild switch --flake .#hwc-server
```

## Architecture

```
Prometheus:9090
    ├─> node:9100 (system metrics)
    ├─> cadvisor:9120 (container metrics)
    ├─> sonarr-exporter:9707 -> Sonarr:8989/sonarr
    ├─> radarr-exporter:9708 -> Radarr:7878/radarr
    ├─> lidarr-exporter:9709 -> Lidarr:8686/lidarr
    └─> prowlarr-exporter:9710 -> Prowlarr:9696/prowlarr
```

## Troubleshooting

### Exporter Shows "down" in Prometheus
1. Check container is running: `sudo podman ps | grep exportarr`
2. Check logs: `sudo journalctl -u podman-exportarr-sonarr -n 50`
3. Test endpoint: `curl http://localhost:9707/metrics`
4. Verify API key: `sudo cat /run/exportarr/sonarr-env`

### Connection Refused Errors
- Ensure Arr app is running: `sudo podman ps | grep sonarr`
- Check URL base is correct: `/sonarr`, `/radarr`, etc.
- Verify port: `sudo ss -tlnp | grep 8989`

### Permission Denied on API Key
- Check secret exists: `sudo ls -la /run/agenix/sonarr-api-key`
- Verify service has secrets group: `systemctl show podman-exportarr-sonarr | grep SupplementaryGroups`
- Restart service: `sudo systemctl restart podman-exportarr-sonarr`

## See Also

- Full documentation: `docs/monitoring/prometheus-exporters.md`
- Grafana dashboards: http://grafana.hwc.local
- Prometheus UI: http://localhost:9090
