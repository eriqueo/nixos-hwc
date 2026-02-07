# Infrastructure Domain

## Purpose & Scope

The **Infrastructure Domain** manages **hardware integration, storage orchestration, and cross-domain system coordination**. This domain sits between the OS core (system domain) and application services, providing hardware abstraction, storage management, virtualization infrastructure, and Windows application integration.

**Key Principle**: If it's about hardware capabilities, storage tiers, virtualization, or cross-platform integration → infrastructure domain.

## Domain Structure

```
domains/infrastructure/
├── index.nix                    # Domain aggregator
├── options.nix                  # Top-level infrastructure options (empty aggregator)
├── README.md                    # This file
├── hardware/                    # Hardware abstraction and GPU management
│   ├── index.nix
│   ├── options.nix
│   ├── parts/
│   │   ├── gpu.nix             # GPU drivers and configuration
│   │   └── peripherals.nix     # Printer and peripheral setup
│   └── README.md
├── storage/                     # Storage tier management
│   ├── index.nix
│   └── options.nix
├── virtualization/              # QEMU/KVM and container networking
│   ├── index.nix
│   └── options.nix
└── winapps/                     # Windows application integration via RDP
    ├── index.nix
    ├── options.nix
    ├── parts/
    │   ├── install-winapps.sh  # Installation automation
    │   ├── vm-manager.sh       # VM lifecycle management
    │   └── winapps-helper.sh   # Helper utilities
    └── WINAPPS-EXCEL-SETUP.md
```

## Subdomains Overview

### 1. Hardware (`hardware/`)
**GPU management, NVIDIA/Intel/AMD drivers, PRIME offload, printing**

**Namespace**: `hwc.infrastructure.hardware.*`

#### GPU Configuration (`hardware.gpu.*`)

Manages GPU drivers, hardware acceleration, and container GPU access:

**Option Pattern:**
```nix
hwc.infrastructure.hardware.gpu = {
  enable = true;
  type = "nvidia";  # "nvidia" | "intel" | "amd" | "none"

  # Derived acceleration target (auto-computed)
  # accel = "cuda";  # "cuda" | "rocm" | "intel" | "cpu" (read-only)

  # Power management (laptop GPUs)
  powerManagement = {
    enable = true;           # Enable power management helpers
    smartToggle = true;      # GPU mode switching scripts
    toggleNotifications = true;  # Show notifications on mode change
  };

  # NVIDIA-specific options
  nvidia = {
    enable = true;  # Auto-enabled when type = "nvidia"
    driver = "stable";  # "stable" | "beta" | "production"
    enableMonitoring = true;  # GPU utilization logging
    containerRuntime = true;  # NVIDIA container toolkit

    # Hybrid graphics (PRIME offload)
    prime = {
      enable = true;
      nvidiaBusId = "PCI:1:0:0";
      intelBusId = "PCI:0:2:0";
    };
  };

  # Intel GPU support
  intel.enable = true;  # Auto-enabled when type = "intel"

  # Auto-generated container flags (read-only)
  # containerOptions = [ "--device=/dev/nvidia0:..." ];
  # containerEnvironment = { NVIDIA_VISIBLE_DEVICES = "all"; };
};
```

**Key Features:**
- Automatic driver selection based on GPU type
- PRIME offload for hybrid graphics (laptop dGPU + iGPU)
- Container GPU passthrough (auto-generated device flags)
- Power management helpers with notifications
- GPU monitoring via nvidia-smi

**Container Integration:**
Services can use auto-generated GPU flags:
```nix
# In server container modules
extraOptions = config.hwc.infrastructure.hardware.gpu.containerOptions;
environment = config.hwc.infrastructure.hardware.gpu.containerEnvironment;
```

#### Peripherals (`hardware.peripherals.*`)

CUPS printing with auto-discovered network printers:

**Option Pattern:**
```nix
hwc.infrastructure.hardware.peripherals = {
  enable = true;
  drivers = [ pkgs.gutenprint pkgs.hplip pkgs.brlaser ];
  avahi = true;      # Network printer discovery
  guiTools = true;   # Install GUI printer management
};
```

---

### 2. Storage (`storage/`)
**Multi-tier storage management: hot (SSD), media (HDD), backup**

**Namespace**: `hwc.infrastructure.storage.*`

#### Hot Storage (`storage.hot.*`)

Fast SSD tier for active processing:

**Option Pattern:**
```nix
hwc.infrastructure.storage.hot = {
  enable = true;
  path = "/mnt/hot";  # Mount point
  device = "/dev/disk/by-uuid/YOUR-UUID";
  fsType = "ext4";
};
```

#### Media Storage (`storage.media.*`)

Bulk HDD tier for media libraries:

**Option Pattern:**
```nix
hwc.infrastructure.storage.media = {
  enable = true;
  path = "/mnt/media";
  directories = [  # Auto-create subdirectories
    "movies" "tv" "music" "books" "photos"
    "downloads" "incomplete" "blackhole"
  ];
};
```

#### Backup Storage (`storage.backup.*`)

Backup infrastructure with auto-mounting external drives:

**Option Pattern:**
```nix
hwc.infrastructure.storage.backup = {
  enable = true;
  path = "/mnt/backup";

  externalDrive = {
    autoMount = true;  # Auto-mount labeled drives
    label = "BACKUP";  # Expected filesystem label
    fsTypes = [ "ext4" "ntfs" "exfat" "vfat" ];
    mountOptions = [ "defaults" "noatime" "user" "exec" ];
    notificationUser = "eric";  # Notify on mount/unmount
  };
};
```

**Storage Integration with Paths:**
Storage paths integrate with `hwc.paths` system:
```nix
# Other domains reference via paths
config.hwc.paths.hot.root     # → /mnt/hot
config.hwc.paths.media.root   # → /mnt/media
config.hwc.paths.backup       # → /mnt/backup
```

---

### 3. Virtualization (`virtualization/`)
**QEMU/KVM, libvirtd, container networking**

**Namespace**: `hwc.infrastructure.virtualization.*`

#### VM Management

QEMU/KVM with libvirtd for Windows VMs:

**Option Pattern:**
```nix
hwc.infrastructure.virtualization = {
  enable = true;
  enableGpu = true;      # GPU passthrough support
  spiceSupport = true;   # SPICE USB redirection
  userGroups = [ "libvirtd" ];  # User permissions
};
```

#### Container Networking

Manages container network infrastructure:

**Option Pattern:**
```nix
hwc.infrastructure.virtualization.containerNetworking = {
  networks = {
    media = {
      subnet = "172.20.0.0/16";
      gateway = "172.20.0.1";
    };
  };
  defaultNetwork = "bridge";
  enableIpv6 = false;
};
```

**Features:**
- Libvirt VM management
- SPICE protocol for Windows VM interaction
- Container network definitions
- User permission management

---

### 4. WinApps (`winapps/`)
**Seamless Windows application integration via RDP**

**Namespace**: `hwc.infrastructure.winapps.*`

Runs Windows applications (Excel, Outlook) as native Linux apps via FreeRDP:

**Option Pattern:**
```nix
hwc.infrastructure.winapps = {
  enable = true;

  rdpSettings = {
    vmName = "RDPWindows";  # Libvirt domain name
    ip = "192.168.122.10";
    user = "youruser";
    scale = 100;  # Display scaling
    flags = "/cert-ignore /dynamic-resolution /audio-mode:1";
  };

  multiMonitor = true;   # Multi-monitor support
  debug = false;         # Debug logging
  autoStart = false;     # Auto-start VM on boot
  autoInstall = false;   # Auto-install WinApps
  monitorService = false;  # VM health monitoring
};
```

**Key Features:**
- Seamless Windows app integration (appears as native Linux windows)
- Multi-monitor support
- Dynamic resolution adjustment
- Automatic VM lifecycle management
- Helper scripts for installation and management

**Helper Scripts:**
- `install-winapps.sh` - Automated WinApps installation
- `vm-manager.sh` - VM start/stop/status management
- `winapps-helper.sh` - Utility functions

---

## Cross-Domain Integration

### GPU → Server Containers

Infrastructure provides GPU access to server containers:

```nix
# In infrastructure domain
hwc.infrastructure.hardware.gpu = {
  enable = true;
  type = "nvidia";
  nvidia.containerRuntime = true;
};

# In server container (e.g., Jellyfin)
systemd.services.podman-jellyfin.serviceConfig = {
  ExecStart = lib.concatStringsSep " " (
    baseCommand ++ config.hwc.infrastructure.hardware.gpu.containerOptions
  );
  Environment = lib.mapAttrsToList
    (n: v: "${n}=${v}")
    config.hwc.infrastructure.hardware.gpu.containerEnvironment;
};
```

### Storage → Server Services

Infrastructure storage paths used by server services:

```nix
# Infrastructure defines storage
hwc.infrastructure.storage.media.enable = true;

# Server services reference via hwc.paths
hwc.server.containers.jellyfin.mediaPath = config.hwc.paths.media.root;
hwc.server.containers.radarr.downloadPath = "${config.hwc.paths.media.root}/downloads";
```

### Virtualization → WinApps

Virtualization provides VM infrastructure for WinApps:

```nix
# Virtualization enables libvirtd
hwc.infrastructure.virtualization.enable = true;

# WinApps uses libvirt VMs
hwc.infrastructure.winapps.enable = true;
hwc.infrastructure.winapps.rdpSettings.vmName = "RDPWindows";  # Libvirt domain
```

---

## Validation & Health Checks

### GPU Validation
```bash
# Check GPU detection
lspci | grep -i vga

# NVIDIA-specific
nvidia-smi
systemctl status gpu-monitor  # If enableMonitoring = true

# Check container GPU access (in container)
ls -la /dev/nvidia*
```

### Storage Validation
```bash
# Check mounts
df -h | grep -E "hot|media|backup"
ls -la /mnt/

# Check media directories
ls -la /mnt/media/

# Test backup drive auto-mount
# Insert labeled external drive and check:
journalctl -u systemd-udevd -f
```

### Virtualization Validation
```bash
# Check libvirtd
systemctl status libvirtd
virsh list --all

# Check container networks
podman network ls
podman network inspect media
```

### WinApps Validation
```bash
# Check VM status
virsh list --all | grep RDPWindows

# Test WinApps installation
~/.local/bin/winapps check

# Check RDP connectivity
xfreerdp /v:192.168.122.10 /u:youruser
```

---

## Common Configuration Patterns

### Laptop with NVIDIA dGPU
```nix
hwc.infrastructure = {
  hardware.gpu = {
    enable = true;
    type = "nvidia";
    powerManagement.enable = true;
    powerManagement.smartToggle = true;
    nvidia = {
      driver = "stable";
      prime.enable = true;
      prime.nvidiaBusId = "PCI:1:0:0";  # Find with: lspci | grep -i vga
      prime.intelBusId = "PCI:0:2:0";
    };
  };
};
```

### Server with Media Storage
```nix
hwc.infrastructure.storage = {
  hot.enable = true;
  hot.device = "/dev/disk/by-uuid/YOUR-SSD-UUID";

  media.enable = true;
  media.path = "/mnt/media";
  media.directories = [ "movies" "tv" "music" "books" "photos" ];

  backup.enable = true;
  backup.externalDrive.autoMount = true;
};
```

### Windows App Integration
```nix
hwc.infrastructure = {
  virtualization = {
    enable = true;
    spiceSupport = true;
  };

  winapps = {
    enable = true;
    rdpSettings = {
      vmName = "RDPWindows";
      ip = "192.168.122.10";
      user = "eric";
    };
    multiMonitor = true;
    autoStart = false;
  };
};
```

---

## Troubleshooting

### GPU Issues

**Problem**: NVIDIA driver not loading
```bash
# Check kernel modules
lsmod | grep nvidia

# Check driver installation
nix-store -q --references /run/current-system | grep nvidia

# Verify busID detection
lspci | grep -i vga
```

**Problem**: Container can't access GPU
```bash
# Verify container runtime
podman info | grep nvidia

# Check device nodes
ls -la /dev/nvidia*

# Test in container
podman run --rm \
  --device=/dev/nvidia0 \
  --device=/dev/nvidiactl \
  nvidia/cuda:11.0-base \
  nvidia-smi
```

### Storage Issues

**Problem**: Mount point not available
```bash
# Check fstab generation
cat /etc/fstab | grep -E "hot|media"

# Manual mount test
sudo mount /mnt/hot
df -h | grep hot
```

**Problem**: External backup drive not auto-mounting
```bash
# Check drive label
lsblk -f | grep BACKUP

# Watch udev events
journalctl -u systemd-udevd -f

# Manual mount
sudo mount -L BACKUP /mnt/backup
```

### WinApps Issues

**Problem**: VM won't start
```bash
# Check VM status
virsh list --all
virsh start RDPWindows

# Check for errors
virsh dumpxml RDPWindows | less
journalctl -u libvirtd
```

**Problem**: RDP connection fails
```bash
# Test connectivity
ping 192.168.122.10

# Verify VM IP (in VM console)
ipconfig

# Test RDP manually
xfreerdp /v:192.168.122.10 /u:youruser
```

---

## Anti-Patterns

**❌ Don't put application logic in infrastructure**:
```nix
# Wrong - this is server domain's job
hwc.infrastructure.services.jellyfin = { ... };
```

**❌ Don't manage filesystem structure here**:
```nix
# Wrong - filesystem structure is system domain
systemd.tmpfiles.rules = [ "d /opt/ai ..." ];
```

**❌ Don't configure network services**:
```nix
# Wrong - network services are system/server domain
services.nginx = { ... };
```

**✅ Do provide hardware abstraction**:
```nix
# Correct - GPU drivers and hardware access
hwc.infrastructure.hardware.gpu.type = "nvidia";
```

**✅ Do manage storage orchestration**:
```nix
# Correct - storage tier management
hwc.infrastructure.storage.hot.enable = true;
```

**✅ Do provide cross-domain integration**:
```nix
# Correct - GPU flags for any domain to use
config.hwc.infrastructure.hardware.gpu.containerOptions
```

---

## Recent Changes & Evolution

### ✅ WinApps Integration (2024)
- Full Windows application integration via RDP
- Automatic VM lifecycle management
- Multi-monitor support with dynamic resolution
- Helper scripts for installation and troubleshooting

### ✅ Storage Tier Maturity (2024)
- Multi-tier storage architecture (hot/media/backup)
- External backup drive auto-mounting
- Integration with hwc.paths system
- Automatic directory structure creation

### ✅ GPU Container Integration (2024)
- Auto-generated container device flags
- NVIDIA container runtime support
- GPU monitoring and utilization logging
- Power management for laptop GPUs

---

**Domain Version**: v4.0 - Hardware abstraction with cross-domain integration
**Charter Compliance**: ✅ Full compliance with HWC Charter v6.0+
**Last Updated**: January 2025 - Accurate documentation matching implementation
**Architecture**: 4 subdomains (hardware, storage, virtualization, winapps)

The infrastructure domain provides the **hardware and orchestration layer** between OS core and application services, enabling GPU acceleration, multi-tier storage, virtualization, and cross-platform integration.
