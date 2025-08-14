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

### Modules Layer
- Service definitions
- System configuration
- Resource management
- No machine-specific config

### Profiles Layer
- Service composition
- Feature selection
- No implementation logic
- Pure configuration

### Machines Layer
- Hardware configuration
- Profile selection
- Minimal overrides
- <50 lines ideal

## Naming Conventions
- Files: `kebab-case.nix`
- Options: `hwc.*` namespace
- Services: `hwc.services.*`
- Features: `enable*` pattern

## GPU Management
```nix
hwc.gpu.nvidia = {
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
