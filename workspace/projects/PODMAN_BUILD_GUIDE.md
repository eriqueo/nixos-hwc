# Podman Build & Deployment Guide

This project uses **Podman**, not Docker. Here's everything you need to know.

---

## Quick Start

```bash
# Build the image
./build-podman.sh

# Test locally
podman run -d \
  --name remodel-api \
  -p 8000:8000 \
  -e DATABASE_URL="postgresql://remodel:password@host.containers.internal/remodel" \
  --network=slirp4netns:allow_host_loopback=true \
  -v /var/lib/remodel-api/pdfs:/app/pdfs:Z \
  remodel-api:latest

# Check logs
podman logs -f remodel-api

# Test health
curl http://localhost:8000/health
```

---

## Building with Podman

### Automated Build (Recommended)

```bash
./build-podman.sh
```

This script:
1. Checks Podman is installed
2. Builds the image
3. Tests WeasyPrint dependencies
4. Shows deployment instructions

### Manual Build

```bash
podman build -t remodel-api:latest -f Dockerfile .
```

---

## Testing Locally with Podman

### Simple Test (No Database)

```bash
podman run --rm -p 8000:8000 remodel-api:latest
```

Visit `http://localhost:8000/docs` to see API documentation.

### Full Test (With Database)

```bash
# Start PostgreSQL
podman run -d \
  --name remodel-postgres \
  -e POSTGRES_DB=remodel \
  -e POSTGRES_USER=remodel \
  -e POSTGRES_PASSWORD=remodel \
  -p 5432:5432 \
  postgres:16

# Wait for DB to be ready
sleep 5

# Run migrations (from host)
psql -h localhost -U remodel -d remodel -f migrations/001_initial_schema.sql
psql -h localhost -U remodel -d remodel -f config/cost_rules_seed.sql

# Start API
podman run -d \
  --name remodel-api \
  -p 8000:8000 \
  -e DATABASE_URL="postgresql://remodel:remodel@host.containers.internal/remodel" \
  --network=slirp4netns:allow_host_loopback=true \
  remodel-api:latest

# Check logs
podman logs -f remodel-api

# Test
curl http://localhost:8000/health
```

### Cleanup

```bash
podman stop remodel-api remodel-postgres
podman rm remodel-api remodel-postgres
```

---

## Exporting for Server Deployment

### Export Image

```bash
podman save remodel-api:latest | gzip > remodel-api-latest.tar.gz
```

### Copy to Server

```bash
scp remodel-api-latest.tar.gz your-server:/tmp/
```

### Load on Server

```bash
ssh your-server
sudo podman load < /tmp/remodel-api-latest.tar.gz
```

---

## Podman vs Docker Differences

### Rootless by Default

Podman runs containers without root privileges:
```bash
# No sudo needed!
podman run ...
```

### No Daemon

Podman doesn't use a daemon:
```bash
# Docker
systemctl status docker

# Podman
# No daemon to manage!
```

### Systemd Integration

Podman integrates with systemd for container management:
```bash
# Generate systemd unit
podman generate systemd --new --name remodel-api > remodel-api.service

# Or use NixOS configuration (recommended)
```

### Networking

Different network modes:

**Docker:**
```bash
docker run --network bridge ...
```

**Podman (to access host PostgreSQL):**
```bash
podman run --network=slirp4netns:allow_host_loopback=true ...
```

### Volume Mounting

Podman uses SELinux labels:
```bash
# With SELinux relabeling
podman run -v /host/path:/container/path:Z ...

# Without (if SELinux disabled)
podman run -v /host/path:/container/path ...
```

---

## Debugging with Podman

### Check Running Containers

```bash
podman ps
podman ps -a  # Include stopped containers
```

### View Logs

```bash
# Follow logs
podman logs -f remodel-api

# Last 50 lines
podman logs --tail 50 remodel-api

# Since timestamp
podman logs --since 10m remodel-api
```

### Inspect Container

```bash
# Full details
podman inspect remodel-api

# Just IP address
podman inspect -f '{{.NetworkSettings.IPAddress}}' remodel-api

# Environment variables
podman inspect -f '{{.Config.Env}}' remodel-api
```

### Execute Commands in Container

```bash
# Interactive shell
podman exec -it remodel-api /bin/bash

# Single command
podman exec remodel-api python -c "import weasyprint; print(weasyprint.VERSION)"

# Check disk space
podman exec remodel-api df -h

# Test database connection
podman exec remodel-api python -c "
import asyncio, asyncpg
async def test():
    conn = await asyncpg.connect('postgresql://remodel:pass@host.containers.internal/remodel')
    print(await conn.fetchval('SELECT 1'))
asyncio.run(test())
"
```

### Stats & Resource Usage

```bash
# Real-time stats
podman stats remodel-api

# Check disk usage
podman system df

# Image size
podman images remodel-api
```

---

## NixOS Integration

### Using Podman in NixOS

NixOS configuration handles Podman automatically:

```nix
virtualisation.oci-containers = {
  backend = "podman";  # Use Podman, not Docker
  containers.remodel-api = {
    image = "remodel-api:latest";
    autoStart = true;
    # ... rest of config
  };
};
```

### Loading Images

```bash
# After building locally and copying to server:
sudo podman load < /tmp/remodel-api-latest.tar.gz

# Verify
sudo podman images | grep remodel-api
```

### Systemd Service

NixOS creates systemd services automatically:

```bash
# Status
systemctl status podman-remodel-api.service

# Logs
journalctl -u podman-remodel-api -f

# Restart
systemctl restart podman-remodel-api
```

---

## Common Issues & Solutions

### Issue: "Cannot connect to database"

```bash
# Check network mode
podman run --network=slirp4netns:allow_host_loopback=true ...

# Test connectivity
podman exec remodel-api ping host.containers.internal
```

### Issue: "PDF directory not writable"

```bash
# Check volume mount
podman run -v /var/lib/remodel-api/pdfs:/app/pdfs:Z ...
#                                                   ^^^ SELinux label

# Create directory first
sudo mkdir -p /var/lib/remodel-api/pdfs
sudo chmod 777 /var/lib/remodel-api/pdfs
```

### Issue: "WeasyPrint import error"

```bash
# Test in container
podman run --rm remodel-api:latest python -c "import weasyprint; print('OK')"

# If fails, rebuild with fixed Dockerfile
./build-podman.sh
```

### Issue: "Port already in use"

```bash
# Find what's using port 8000
sudo ss -tulpn | grep 8000

# Use different port
podman run -p 8001:8000 ...
```

---

## Production Deployment

### Recommended Setup

```bash
# 1. Create directories
sudo mkdir -p /var/lib/remodel-api/pdfs
sudo chmod 755 /var/lib/remodel-api

# 2. Load image
sudo podman load < remodel-api-latest.tar.gz

# 3. NixOS configuration will:
#    - Create systemd service
#    - Mount volumes
#    - Set up networking
#    - Configure auto-restart

# 4. Rebuild NixOS
sudo nixos-rebuild switch

# 5. Check status
systemctl status podman-remodel-api
journalctl -u podman-remodel-api -n 50
```

### Health Monitoring

```bash
# Add to monitoring script
curl -f http://localhost:8001/health || alert

# Or use Podman health check
podman inspect --format='{{.State.Health.Status}}' remodel-api
```

---

## Performance Tuning

### Resource Limits

```bash
# Limit memory
podman run --memory=1g remodel-api:latest

# Limit CPUs
podman run --cpus=2 remodel-api:latest

# Both
podman run --memory=1g --cpus=2 remodel-api:latest
```

### In NixOS Config

```nix
virtualisation.oci-containers.containers.remodel-api = {
  extraOptions = [
    "--memory=1g"
    "--cpus=2"
  ];
};
```

---

## Build Optimization

### Reduce Image Size

Already optimized with multi-stage build:
- Builder stage: ~1GB
- Final image: ~300MB

### Faster Builds

```bash
# Use build cache
podman build --layers -t remodel-api:latest .

# Parallel builds
podman build --jobs 4 -t remodel-api:latest .
```

---

## Troubleshooting Checklist

When deployment fails:

- [ ] Image built successfully: `podman images | grep remodel-api`
- [ ] WeasyPrint works: `podman run --rm remodel-api:latest python -c "import weasyprint"`
- [ ] Container starts: `podman run --rm remodel-api:latest`
- [ ] Health check passes: `curl http://localhost:8000/health`
- [ ] Database connects: Check logs for "✓ Database connection pool ready"
- [ ] PDF directory writable: Check logs for "✓ PDF directory ready"
- [ ] Logs show no ❌ errors: `podman logs remodel-api | grep ❌`

---

## Quick Reference

### Build
```bash
./build-podman.sh
```

### Run
```bash
podman run -d --name remodel-api -p 8000:8000 \
  -e DATABASE_URL="..." \
  --network=slirp4netns:allow_host_loopback=true \
  -v /var/lib/remodel-api/pdfs:/app/pdfs:Z \
  remodel-api:latest
```

### Debug
```bash
podman logs -f remodel-api
podman exec -it remodel-api /bin/bash
```

### Export
```bash
podman save remodel-api:latest | gzip > remodel-api.tar.gz
```

### Deploy
```bash
scp remodel-api.tar.gz server:/tmp/
ssh server 'sudo podman load < /tmp/remodel-api.tar.gz'
```

---

**For full deployment instructions, see DEPLOYMENT_QUICK_START.md**
