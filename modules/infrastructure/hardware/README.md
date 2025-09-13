# Infrastructure Hardware Bucket

## Purpose

The **Hardware Bucket** provides **user ↔ hardware integration glue**. These modules wire users to hardware capabilities without implementing the hardware drivers themselves (that's system domain) or the user applications themselves (that's home domain).

## Modules Overview

### 🎮 GPU (`gpu.nix`)
**GPU acceleration detection and integration**

**Provides:**
- GPU hardware detection and type classification
- Driver integration for NVIDIA/Intel/AMD
- Container runtime GPU passthrough  
- Acceleration signal for services (`config.hwc.infrastructure.hardware.gpu.accel`)

**Option Pattern:**
```nix
hwc.infrastructure.hardware.gpu = {
  enable = true;
  type = "nvidia" | "intel" | "amd" | "none";
  nvidia = {
    driver = "stable" | "beta" | "production";
    containerRuntime = true;      # Enable GPU in containers
    enableMonitoring = true;      # nvidia-smi logging
    prime = {                     # Hybrid laptop GPUs
      enable = true;
      nvidiaBusId = "PCI:1:0:0";
      intelBusId = "PCI:0:2:0";
    };
  };
  powerManagement.smartToggle = true;  # gpu-launch, gpu-toggle tools
};
```

**Data Flow:**
```
Machine Config → declares GPU type/settings
       ↓
GPU Module → detects drivers, configures runtime, sets accel signal
       ↓
Services (ollama, jellyfin) → consume accel signal for GPU usage
       ↓
User Commands → gpu-launch available for manual GPU usage
```

**Integration Points:**
- **Services consume**: `config.hwc.infrastructure.hardware.gpu.accel` ("cuda", "rocm", "intel", "cpu")
- **Container runtime**: Automatic GPU device passthrough when `containerRuntime = true`
- **User tools**: `gpu-launch`, `gpu-toggle` commands for manual control

### 🔐 Permissions (`permissions.nix`)
**User groups and hardware ACLs**

**Provides:**
- User membership in hardware access groups
- Tmpfiles rules for device permissions
- ACL management for hardware devices

**Option Pattern:**
```nix
hwc.infrastructure.hardware.permissions = {
  enable = true;
  groups = {
    basic = true;           # Basic system access
    media = true;           # audio, video, camera devices  
    hardware = true;        # GPIO, sensors, serial ports
    development = true;     # USB devices, debuggers, analyzers
    virtualization = true;  # KVM, libvirt, docker
  };
};
```

**Group Mappings:**
- `basic` → wheel, networkmanager
- `media` → audio, video, input, lp, scanner  
- `hardware` → dialout, gpio, spi, i2c
- `development` → plugdev, wireshark, docker
- `virtualization` → kvm, libvirtd, docker

**Data Flow:**
```
Profile enables → hwc.infrastructure.hardware.permissions.groups.media = true
       ↓
Permissions module → adds user to audio, video, input groups
       ↓
Tmpfiles rules → ensure /dev/video*, /dev/audio* have correct permissions
       ↓
User session → can access cameras, microphones, speakers
```

### 🖨️ Peripherals (`peripherals.nix`)
**Printer and scanner integration glue**

**Provides:**
- CUPS printing support with comprehensive drivers
- Scanner integration via SANE
- Network printer discovery
- GUI management tools integration

**Option Pattern:**
```nix
hwc.infrastructure.hardware.peripherals = {
  enable = true;
  drivers = [ pkgs.hplip pkgs.gutenprint pkgs.canon-cups-ufr2 ];  # Override defaults
  avahi = true;          # Network printer discovery
  scanning = true;       # Enable scanner support
};
```

**Data Flow:**
```
Peripheral enable → CUPS + driver packages installed
       ↓
Avahi discovery → finds network printers automatically  
       ↓
User permissions → user added to lp, scanner groups
       ↓
Desktop integration → printing dialogs work from apps
```

### 💾 Storage (`storage.nix`)
**Storage device integration and helpers**

**Provides:**
- External drive auto-mounting
- Backup destination management
- Storage directory structure
- User access to mounted devices

**Option Pattern:**
```nix
hwc.infrastructure.hardware.storage = {
  backup = {
    enable = true;
    externalDrive.autoMount = true;    # Auto-mount backup drives
  };
  media = {
    enable = true;
    directories = [ "movies" "tv" "music" "downloads" ];
  };
  hot.enable = true;      # SSD storage management
};
```

**Data Flow:**
```
Storage config → creates directory structure under hwc.paths.*
       ↓
External drives → auto-mount to /mnt/backup, /mnt/media
       ↓
User permissions → user can read/write mounted storage
       ↓
Services → consume storage paths for media, backups
```

## Hardware Bucket Integration Patterns

### Machine Hardware Declaration
Machines declare hardware reality, infrastructure wires it up:

```nix
# machines/laptop/config.nix
hwc.infrastructure.hardware.gpu = {
  enable = true;
  type = "nvidia";                    # Declares what hardware exists
  nvidia.prime.enable = true;         # Laptop-specific hybrid setup
};

hwc.infrastructure.hardware.permissions.groups = {
  media = true;                       # User needs camera/audio access
  development = true;                 # User needs USB device access
};
```

### Service Hardware Consumption  
Services automatically detect and use hardware capabilities:

```nix
# modules/services/ai/ollama.nix
config = {
  virtualisation.oci-containers.containers.ollama = {
    # GPU acceleration automatically applied based on:
    extraOptions = config.hwc.infrastructure.hardware.gpu.containerOptions;
    environment = config.hwc.infrastructure.hardware.gpu.containerEnvironment;
  };
};
```

### Cross-Hardware Integration
Hardware modules coordinate without tight coupling:

```nix
# GPU module provides acceleration, storage provides paths
hwc.infrastructure.hardware.gpu.enable = true;
hwc.infrastructure.hardware.storage.media.enable = true;

# Service consumes both
services.jellyfin = {
  enable = true;
  # Gets GPU accel from hardware.gpu + media paths from hardware.storage
};
```

## Validation & Troubleshooting

### GPU Issues
**Symptom**: Services not using GPU acceleration
```bash
# Check GPU detection
nix eval .#nixosConfigurations.hwc-laptop.config.hwc.infrastructure.hardware.gpu.accel

# Should output: "cuda", "rocm", "intel", or "cpu"
# If "cpu", check GPU type and driver configuration
```

**Symptom**: `gpu-launch` command missing
```bash
# Check if power management tools enabled
nix eval .#nixosConfigurations.hwc-laptop.config.hwc.infrastructure.hardware.gpu.powerManagement.smartToggle
```

### Permissions Issues  
**Symptom**: User can't access camera/microphone
```bash
# Check user groups
groups $USER | grep -E "(video|audio|input)"

# Check if permissions module enabled
nix eval .#nixosConfigurations.hwc-laptop.config.hwc.infrastructure.hardware.permissions.enable
```

### Storage Issues
**Symptom**: External drives not auto-mounting
```bash
# Check systemd mount units
systemctl status 'mnt-*.mount'

# Check storage configuration
nix eval .#nixosConfigurations.hwc-laptop.config.hwc.infrastructure.hardware.storage
```

## Anti-Patterns

**❌ Don't implement device drivers**: That's system domain responsibility
```nix
# Wrong - implementing driver logic in infrastructure
config.boot.kernelModules = [ "nvidia" ];  # System domain job
```

**❌ Don't create user applications**: That's home domain responsibility  
```nix  
# Wrong - installing user apps in infrastructure
environment.systemPackages = [ pkgs.gimp ];  # Home domain job
```

**❌ Don't implement service daemons**: That's services domain responsibility
```nix
# Wrong - running services in infrastructure  
systemd.services.custom-gpu-daemon = { ... };  # Services domain job
```

**✅ Do provide integration glue**:
```nix
# Correct - wiring users to hardware capabilities
users.users.${username}.extraGroups = hardwareGroups;
systemd.tmpfiles.rules = devicePermissionRules;
environment.variables.GPU_ACCELERATION = gpuAccelType;
```

---

The hardware bucket focuses purely on **integration between users and hardware**, leaving the heavy lifting to the appropriate domains while ensuring everything works together seamlessly.