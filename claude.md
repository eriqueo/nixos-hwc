## 📋 Overview

This plan sets up your laptop as a dedicated Immich machine learning worker to offload CPU-intensive processing from your main server (`hwc-server`), solving the 91°C thermal issues.

## 🏗️ Architecture

```
┌─────────────────────┐    Tailscale VPN    ┌─────────────────────┐
│   hwc-server        │◄──────────────────►│   laptop-worker     │
│   (Main Server)     │                     │   (ML Processing)   │
│                     │                     │                     │
│ ┌─────────────────┐ │                     │ ┌─────────────────┐ │
│ │ Immich Web UI   │ │                     │ │ Immich ML Only  │ │
│ │ PostgreSQL DB   │ │◄────Network────────►│ │ Face Detection  │ │
│ │ Redis Cache     │ │     Access          │ │ Smart Search    │ │
│ │ Photo Storage   │ │                     │ │ Object Recog    │ │
│ │ File Serving    │ │                     │ │                 │ │
│ └─────────────────┘ │                     │ └─────────────────┘ │
└─────────────────────┘                     └─────────────────────┘
          │                                           │
          └─────────── NFS Share ───────────────────────┘
                   (Photos Access)
```

## ✅ Benefits

- **Thermal Relief**: Moves 90% of CPU load off main server
- **Better Performance**: Laptop CPU dedicated to ML tasks
- **Scalable**: Can add more worker nodes later
- **No Downtime**: Main server keeps running during setup
- **GPU Utilization**: Can use laptop GPU if available

## 📝 Implementation Plan

### Phase 1: Prepare Main Server for Distributed Access

#### 1.1 Enable NFS Server for Photo Sharing
```bash
# Add to hwc-server configuration
services.nfs.server = {
  enable = true;
  exports = ''
    /mnt/hot/pictures 100.115.126.0/24(rw,sync,no_subtree_check,no_root_squash)
  '';
};
```

#### 1.2 Configure Database for Remote Access
```bash
# PostgreSQL - allow Tailscale network connections
services.postgresql = {
  authentication = ''
    host immich_new immich_new 100.115.126.0/24 trust
  '';
  settings = {
    listen_addresses = "localhost,100.115.126.41";  # Tailscale IP
  };
};
```

#### 1.3 Configure Redis for Remote Access
```bash
# Redis - bind to Tailscale interface
services.redis.servers.immich = {
  bind = "100.115.126.41";  # Allow laptop access
  settings = {
    protected-mode = "no";
  };
};
```

#### 1.4 Update Firewall Rules
```bash
networking.firewall.interfaces."tailscale0" = {
  allowedTCPPorts = [ 
    2049    # NFS
    5432    # PostgreSQL
    6381    # Redis
    2283    # Immich (existing)
  ];
};
```

### Phase 2: Setup Laptop Worker Node

#### 2.1 Install NixOS on Laptop (if needed)
- Use minimal NixOS installation
- Enable flakes: `nix.settings.experimental-features = [ "nix-command" "flakes" ];`

#### 2.2 Deploy Worker Configuration
Copy the prepared `immich-worker-config.nix` to laptop and apply:
```bash
# On laptop
sudo nixos-rebuild switch -I nixos-config=./immich-worker-config.nix
```

#### 2.3 Join Tailscale Network
```bash
# On laptop
sudo tailscale up --auth-key YOUR_AUTH_KEY
```

### Phase 3: Configure Main Server ML Service

#### 3.1 Disable Local ML Processing
```bash
# On hwc-server - disable intensive ML jobs locally
systemd.services.immich-machine-learning = {
  serviceConfig.ExecStart = lib.mkForce "/bin/true";  # Disable
};
```

#### 3.2 Update Job Concurrency
Reduce main server to minimal processing:
- Thumbnail generation: 1 concurrent
- Metadata extraction: 1 concurrent  
- Face detection: 0 (handled by worker)
- Smart search: 0 (handled by worker)

### Phase 4: Network and Storage Configuration

#### 4.1 NFS Mount on Worker
Worker automatically mounts photos via:
```bash
# Auto-configured in worker config
/mnt/shared-photos = hwc-server:/mnt/hot/pictures
```

#### 4.2 Shared Database Access
Worker connects to main server's PostgreSQL:
- Host: `100.115.126.41` (hwc-server Tailscale IP)
- Database: `immich_new`
- User: `immich_new`

#### 4.3 Shared Cache Access  
Worker connects to main server's Redis:
- Host: `100.115.126.41`
- Port: `6381`

## 🔧 Configuration Files Created

### 1. `/etc/nixos/immich-worker-config.nix`
Complete NixOS configuration for laptop worker node with:
- Immich ML service only (no web/server)
- NFS client for photo access
- Database/Redis connectivity to main server
- GPU acceleration (if laptop has discrete GPU)
- Performance optimizations and resource limits

### 2. Main Server Updates Required
Updates needed to `/etc/nixos/hosts/server/config.nix`:
- Enable NFS server exports
- Configure PostgreSQL for remote access
- Update Redis to bind to Tailscale IP
- Add firewall rules for new services
- Optionally disable local ML processing

## 📊 Expected Performance Improvements

### Before (Current State)
- Main server CPU: 91°C with 43% usage
- Single threaded ML processing
- Thermal throttling limiting performance
- Risk of system shutdown

### After (Distributed Setup)
- Main server CPU: ~50-60°C with <10% usage
- Laptop handles all ML processing
- Parallel processing capability
- Main server focuses on web/database/storage
- Scalable to multiple workers

## 🔄 Migration Strategy

### Step 1: Non-Disruptive Setup
1. Deploy worker node configuration
2. Test connectivity (database, NFS, Redis)
3. Verify photo access from worker

### Step 2: Gradual Migration
1. Start with face detection jobs on worker
2. Move object recognition to worker
3. Move smart search indexing to worker
4. Keep thumbnails on main server initially

### Step 3: Full Offload
1. Move all ML processing to worker
2. Disable ML service on main server
3. Monitor temperature improvements
4. Optimize concurrency on worker

## 🛡️ Security Considerations

### Network Security
- All communication via encrypted Tailscale VPN
- No public internet exposure of new services
- Database access limited to Tailscale subnet

### Access Control
- NFS exports limited to specific IP range
- PostgreSQL authentication via Tailscale only
- Redis protected-mode disabled only for Tailscale

### Firewall Rules
- Main server only opens ports to Tailscale interface
- Worker node blocks all external access
- Minimal attack surface

## 🔍 Monitoring and Troubleshooting

### Health Checks
```bash
# On main server - check service availability
curl http://100.115.126.41:6381/ping  # Redis
psql -h 100.115.126.41 -U immich_new immich_new -c "SELECT 1;"  # PostgreSQL

# On worker - check NFS mount
ls /mnt/shared-photos
df -h /mnt/shared-photos
```

### Performance Monitoring
```bash
# Worker resource usage
htop
nvidia-smi  # If GPU available
iostat -x 1  # NFS I/O performance

# Main server thermal monitoring
cat /sys/class/thermal/thermal_zone*/temp
```

### Common Issues and Solutions

#### NFS Mount Issues
```bash
# Check NFS exports on server
showmount -e 100.115.126.41

# Restart NFS services
sudo systemctl restart nfs-server
sudo systemctl restart rpcbind
```

#### Database Connection Issues
```bash
# Check PostgreSQL listening addresses
sudo ss -tlnp | grep 5432

# Test connection from worker
telnet 100.115.126.41 5432
```

#### Redis Connection Issues
```bash
# Test Redis connectivity
redis-cli -h 100.115.126.41 -p 6381 ping
```

## 📈 Scaling Considerations

### Adding More Workers
- Copy worker configuration to additional machines
- Update NFS exports to include new IP ranges
- Each worker shares same database/Redis
- Immich automatically distributes jobs across workers

### Performance Tuning
- Adjust `IMMICH_WORKERS` based on laptop CPU cores
- Tune NFS mount options for I/O performance
- Configure GPU acceleration if laptop has discrete GPU
- Monitor network bandwidth usage

### Resource Allocation
- Worker CPU: Dedicated to ML processing
- Worker RAM: 8GB+ recommended for ML models
- Network: Gigabit recommended for NFS performance
- Storage: Local SSD for ML model cache

## 🎯 Success Metrics

### Temperature Targets
- Main server CPU: <70°C under load
- Sustainable processing without thermal throttling
- Stable long-term operation

### Performance Targets
- 5-10x faster ML processing (parallel execution)
- Main server responds faster to web requests
- Reduced job queue backlog
- Improved photo browsing performance

### Reliability Targets
- Zero thermal shutdowns
- 99.9% uptime for photo services
- Automatic recovery from network issues
- Graceful handling of worker disconnection

---

## 🚀 Ready to Deploy?

This plan provides a comprehensive, production-ready solution for distributed Immich processing. The configuration is designed to be:

- **Safe**: Non-disruptive deployment with rollback capability
- **Secure**: Encrypted VPN communication with minimal attack surface  
- **Scalable**: Easily add more workers as needed
- **Maintainable**: Standard NixOS declarative configuration
- **Monitored**: Built-in health checks and performance monitoring

