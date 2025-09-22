# System Domain Reorganization - Migration Plan

## Overview

This document details the migration plan for the reorganized `modules/system/` structure, including what content changes each file needs and how to integrate with profiles/sys.nix.

## File Structure Changes Completed

### New Organization
```
modules/system/
├── index.nix                    # Auto-imports all subdirectories
├── core/                        # Essential system functions
│   ├── index.nix               # Auto-imports core modules
│   ├── paths.nix               # Moved from root (unchanged)
│   ├── secrets.nix             # Moved from root (unchanged)  
│   └── eric.nix                # User management (already consolidated)
├── packages/                   # System package definitions
│   ├── index.nix               # Auto-imports package modules
│   ├── base.nix                # Moved from base-packages.nix (unchanged)
│   ├── security.nix            # Moved from backup-packages.nix (unchanged)
│   └── server.nix              # Moved from server-packages.nix (unchanged)
├── services/                   # System service configuration
│   ├── index.nix               # Auto-imports service modules
│   ├── networking.nix          # Moved from root (unchanged)
│   ├── audio.nix               # Moved from root (unchanged)
│   └── sudo.nix                # Moved from security/ (unchanged)
└── storage/                    # Storage and filesystem
    ├── index.nix               # Auto-imports storage modules
    └── structure.nix           # Moved from filesystem.nix (unchanged)
```

### Files Deleted
- `desktop-packages.nix` - GUI packages need to move to modules/home/
- `media-packages.nix` - Duplicate packages, consolidate into existing files
- `users.bak` - Old backup file removed
- `security/` directory - Flattened sudo.nix into services/

## Required Content Changes

### 1. Package Deduplication Strategy

**Problem**: Massive duplication across package files:
- `htop`: base.nix, server.nix
- `curl/wget`: base.nix, security.nix, server.nix  
- `p7zip`: base.nix, security.nix, server.nix
- `rsync/ffmpeg/python3`: multiple files each

**Solution**: Create clear package categories:

#### packages/base.nix
**KEEP**: Core CLI tools needed everywhere
- shells (zsh), editors (vim, neovim, micro), utils (htop, tree, wget, curl)
- Essential development (git, gcc, make, nodejs, python3)
- Archive tools (unzip, zip, p7zip, rsync)

**REMOVE**: Language servers, advanced dev tools → packages/development.nix
**REMOVE**: GUI applications (kitty, thunar) → modules/home/apps/

#### packages/security.nix (backup-packages.nix)
**KEEP**: Backup-specific tools and scripts
- rclone, backup maintenance scripts, logrotate config
- Archive tools (gnutar, gzip) if backup-specific

**REMOVE**: General tools duplicated from base.nix (curl, wget, p7zip, rsync, findutils, coreutils)

#### packages/server.nix  
**KEEP**: Server administration tools
- Container management (docker-compose, podman-compose)
- Server monitoring (iotop, lsof, tcpdump, nmap)  
- Database clients (postgresql, redis)

**REMOVE**: GUI applications → modules/home/apps/
- file-roller, evince, feh, picard
**REMOVE**: Tools duplicated from base.nix (htop, rsync, unzip, p7zip, ffmpeg, python3)

### 2. Domain Violations to Fix

#### Move GUI Packages to modules/home/apps/

**From deleted desktop-packages.nix**:
```nix
# These need new modules/home/apps/ modules:
waybar → modules/home/apps/waybar/index.nix
wlogout → modules/home/apps/wlogout/index.nix  
swaynotificationcenter → modules/home/apps/swaync/index.nix
pavucontrol → modules/home/apps/pavucontrol/index.nix
pulsemixer → modules/home/apps/pulsemixer/index.nix
networkmanagerapplet → modules/home/apps/networkmanager/index.nix
btop → modules/home/apps/btop/index.nix
mission-center → modules/home/apps/mission-center/index.nix
baobab → modules/home/apps/baobab/index.nix
```

**From packages/server.nix**:
```nix
# These need modules/home/apps/ modules:
file-roller → modules/home/apps/file-roller/index.nix
evince → modules/home/apps/evince/index.nix  
feh → modules/home/apps/feh/index.nix
picard → modules/home/apps/picard/index.nix
```

**From packages/base.nix**:
```nix
# Move to modules/home/apps/:
kitty → modules/home/apps/kitty/index.nix (already exists)
thunar → modules/home/apps/thunar/index.nix (create)
```

**From services/networking.nix**:
```nix
# Remove from system packages, move to home:
networkmanagerapplet → modules/home/apps/networkmanager/index.nix
```

### 3. Service Configuration Adjustments

#### services/networking.nix
**REMOVE**: GUI packages from environment.systemPackages
```nix
# Remove this:
networkmanagerapplet  # GUI for NetworkManager
```

#### services/audio.nix
**NO CHANGES**: Already clean system service configuration

#### services/sudo.nix  
**NO CHANGES**: Content is appropriate for system domain

### 4. Package File Header Updates

**ALL package files need option name changes**:

#### packages/base.nix
```nix
# Change from:
options.hwc.system.basePackages = {

# To:
options.hwc.system.packages.base = {
```

#### packages/security.nix  
```nix
# Change from:
options.hwc.system.backupPackages = {

# To:
options.hwc.system.packages.security = {
```

#### packages/server.nix
```nix  
# Change from:
options.hwc.system.serverPackages = {

# To:
options.hwc.system.packages.server = {
```

### 5. Profile Configuration Updates

#### profiles/base.nix
**CHANGE**: Option names to match new structure
```nix
# Change from:
hwc.system.basePackages.enable = true;

# To:
hwc.system.packages.base.enable = true;
```

#### profiles/workstation.nix
**ADD**: New GUI app configurations
```nix
# Add these configurations for moved GUI packages:
features.waybar.enable = true;
features.pavucontrol.enable = true;  
features.btop.enable = true;
features.thunar.enable = true;
# etc.
```

#### profiles/server.nix
**CHANGE**: Option name
```nix  
# Change from:
hwc.system.serverPackages.enable = true;

# To:
hwc.system.packages.server.enable = true;
```

## Integration with profiles/sys.nix

### Current profiles/sys.nix Analysis
The `profiles/sys.nix` appears to be a system-focused profile. To integrate the reorganized modules/system/, it should:

### Recommended profiles/sys.nix Structure
```nix
# profiles/sys.nix - Pure System Configuration Profile
{ lib, ... }:
{
  imports = [
    # Import entire organized system domain
    ../modules/system
    
    # Could also be selective:
    # ../modules/system/core        # Always needed
    # ../modules/system/services    # System services
    # ../modules/system/storage     # Filesystem structure
    # ../modules/system/packages    # System packages
  ];
  
  # Enable essential system components
  config = {
    hwc.system.packages.base.enable = true;
    hwc.networking.enable = true;
    hwc.infrastructure.filesystemStructure.enable = true;
    hwc.system.secrets.enable = true;
    hwc.system.users.enable = true;
    
    # Optional server-specific packages
    hwc.system.packages.server.enable = lib.mkDefault false;
    hwc.system.packages.security.enable = lib.mkDefault false;
  };
}
```

### Profile Hierarchy Recommendation
```
profiles/
├── sys.nix          # Pure system configuration (this plan)
├── base.nix         # Essential foundation (includes sys.nix)
├── workstation.nix  # Desktop environment (includes base.nix)
├── server.nix       # Server environment (includes base.nix)
└── ai.nix          # AI/ML services (extends base.nix)
```

## Migration Checklist

### Phase 1: Package Content Changes (HIGH PRIORITY)
- [ ] **packages/base.nix**: Remove GUI apps, remove language servers
- [ ] **packages/security.nix**: Remove duplicate CLI tools  
- [ ] **packages/server.nix**: Remove GUI apps, remove duplicate CLI tools
- [ ] **services/networking.nix**: Remove networkmanagerapplet

### Phase 2: Create Missing Home Apps (MEDIUM PRIORITY)  
- [ ] **modules/home/apps/waybar/** (if not exists)
- [ ] **modules/home/apps/pavucontrol/index.nix**
- [ ] **modules/home/apps/btop/index.nix**  
- [ ] **modules/home/apps/thunar/index.nix**
- [ ] **modules/home/apps/networkmanager/index.nix**
- [ ] **modules/home/apps/file-roller/index.nix**
- [ ] And others from domain violation list

### Phase 3: Update Option Names (LOW PRIORITY)
- [ ] Update all package option names to new hierarchy
- [ ] Update profile configurations to use new option names

### Phase 4: Test and Validate
- [ ] Build system successfully
- [ ] Verify all packages still available
- [ ] Confirm no functionality lost
- [ ] Update any remaining imports

## Success Criteria

1. **Zero package duplication** across system domain
2. **All GUI packages** moved to appropriate modules/home/apps/
3. **Clean domain separation** - system = CLI tools + services, home = GUI apps
4. **Functional equivalence** - no features lost in reorganization
5. **profiles/sys.nix integration** - clean system-only profile available

This reorganization creates a maintainable, Charter v7 compliant structure that eliminates duplication and respects domain boundaries.