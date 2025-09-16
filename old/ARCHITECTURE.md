# System Architecture

## Design Principles

### 1. Hierarchical Composition
```
lib → modules → profiles → machines
```

### 2. Module Structure
Every module follows this pattern:
```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.myservice;
in {
  options.hwc.services.myservice = {
    enable = lib.mkEnableOption "...";
    # Other options
  };
  
  config = lib.mkIf cfg.enable {
    # Implementation
  };
}
```

### 3. Path Management
All paths derive from `config.hwc.paths`:

- `hwc.paths.hot` - Fast storage
- `hwc.paths.media` - Media storage
- `hwc.paths.state` - Service state
- `hwc.paths.cache` - Cache data

### 4. Service Organization

- One service per file
- Internal feature flags for variants
- No hardcoded paths

## Layer Responsibilities

### Modules Layer (3-Bucket Architecture)

#### Infrastructure Domain
- **Hardware Bucket**: GPU drivers, device control, virtualization runtime
- **Mesh Bucket**: Container networking, service discovery, network topology  
- **Session Bucket**: [Reserved for future use]

#### System Domain
- Core OS functions, paths, networking, storage, user management
- Boot configuration, systemd services, firewall rules

#### Services Domain  
- Application orchestration, daemon management
- Business logic, media services, monitoring, AI services

#### Home Domain (Home Manager)
- User environment, desktop applications, shell configuration
- Waybar, terminal settings, development tools

### Profiles Layer

- Service composition and feature selection
- No implementation logic - pure configuration toggles
- Imports modules and sets `enable = true/false`

### Machines Layer

- Hardware-specific facts and profile selection
- Minimal overrides, ideally <50 lines
- No business logic, only hardware reality

## Naming Conventions

- Files: `kebab-case.nix`
- Options: `hwc.*` namespace
- Services: `hwc.services.*`
- Features: `enable*` pattern

## GPU Management

```nix
hwc.infrastructure.hardware.gpu.nvidia = {
  enable = true;
  containerRuntime = true;
};
```

## Storage Tiers

- Hot: SSD, databases, active data
- Media: HDD, media files, archives
- Backup: Redundant, snapshots

## Network Segmentation

- Management VLAN: Administration
- Media VLAN: Streaming services
- IoT VLAN: Cameras, sensors
- Guest VLAN: Isolated access
