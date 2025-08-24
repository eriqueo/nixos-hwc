# Charter v3 Production Migration Plan
**Date**: 2025-08-21  
**Status**: In Progress  
**Current Phase**: Planning Complete, Ready for Execution

## Migration Strategy Overview

The goal is to systematically translate the entire production NixOS system from `/etc/nixos` into the Charter v3 compliant refactor at `nixos-hwc` without losing any functionality.

### Production System Analysis

**Current Production Structure** (`/etc/nixos`):
```
├── flake.nix                     # Flake with laptop/server configs
├── hosts/
│   ├── laptop/config.nix         # Direct imports, mixed patterns
│   └── server/config.nix         # Heavy service configuration
├── modules/
│   ├── users/eric.nix            # User configuration
│   ├── paths/default.nix         # Basic path management
│   ├── filesystem/              # Multi-file filesystem setup
│   └── [various service modules]
├── shared/
│   ├── secrets.nix              # SOPS configuration
│   ├── networking.nix           # Network setup
│   └── home-manager/            # Home manager configs
└── [40+ service-specific modules in hosts/server/modules/]
```

**Target Charter v3 Structure** (`nixos-hwc`):
```
├── flake.nix                    # Clean flake definition
├── lib/                         # Shared utilities
├── modules/
│   ├── system/                  # Core system modules
│   ├── infrastructure/          # Hardware and system services
│   ├── services/               # Application services by category
│   └── home/                   # User environment modules
├── profiles/                   # Machine type profiles
│   ├── base.nix                # Common configuration
│   ├── workstation.nix         # Desktop/laptop profile
│   ├── server.nix              # Server profile
│   └── [specialized profiles]
└── machines/                   # Individual machine configs
    ├── laptop/config.nix       # Minimal machine-specific config
    └── server/config.nix       # Minimal machine-specific config
```

## Migration Phases

### ✅ **Completed Work**
- **Comprehensive Path Management**: Created `modules/system/paths.nix` with complete production path structure
- **Filesystem Architecture**: Built `modules/system/filesystem.nix` with toggle-based directory creation
- **Charter v3 Foundation**: Established proper hierarchical composition and toggle architecture
- **Infrastructure Modules**: Created printing, virtualization, samba, login-manager modules
- **User Configuration**: Set up Charter v3 compliant user management

### ✅ **Phase 1: Core Infrastructure Migration**
**Status**: COMPLETED  
**Dependencies**: None

**✅ Completed Tasks:**  

#### ✅ 1.1 Security & Secrets Migration
- [x] **MIGRATED**: SOPS → agenix for simplified secrets management
  - **Created**: `modules/security/secrets.nix` with Charter v3 hwc.security options
  - **Created**: `secrets.nix` with age key configuration for all machines
  - **Created**: `AGENIX_MIGRATION_GUIDE.md` with step-by-step migration instructions
  - **Components**: All secret categories mapped (VPN, database, services, ARR stack)
  - **Status**: Infrastructure ready, user needs to migrate secret values

#### ✅ 1.2 User Management Migration  
- [x] **COMPLETED**: `/etc/nixos/modules/users/eric.nix` → `modules/home/eric.nix`
  - **Created**: Charter v3 user module with hwc.home options
  - **Features**: Toggle-based group management, secret integration, fallback configurations
  - **Components**: User definition, dynamic groups, SSH keys, environment variables
  - **Integration**: Full agenix secret support with fallback for migration period

#### ✅ 1.3 System Networking Migration
- [x] **COMPLETED**: `shared/networking.nix` → `modules/system/networking.nix`
  - **Created**: Charter v3 networking module with hwc.networking options
  - **Features**: SSH, Tailscale, NetworkManager, firewall with service-based port management
  - **Components**: Complete networking stack with toggle controls
  - **Integration**: Service port management ready for Phase 2 services

#### ✅ 1.4 Profile Integration and Updates
- [x] **UPDATED**: `profiles/base.nix` with Charter v3 modules
  - **Replaced**: Old networking/user config with hwc.* options
  - **Added**: Security and user modules with proper toggles
  - **Features**: Complete base system with secrets, networking, user management
- [x] **UPDATED**: `profiles/workstation.nix` for compatibility
  - **Removed**: Conflicting networking configuration (now in base)
  - **Added**: Workstation-specific extensions (X11 forwarding, virtualization)
  - **Maintained**: All desktop and development features
- [x] **CREATED**: `profiles/server.nix` for production migration
  - **Features**: All server secrets enabled, complete filesystem structure
  - **Performance**: Server-optimized settings and container configuration
  - **Integration**: Ready for Phase 2 service migration

### **Phase 2: Service Architecture Translation**
**Status**: Pending  
**Dependencies**: Phase 1 complete

#### 2.1 Media Stack Migration
- [ ] Consolidate all media services: `hosts/server/modules/media-*.nix` → `modules/services/media/`
  - **Source Files**: `media-containers.nix`, `media-core.nix`, `media-stack.nix`, `monitoring.nix`
  - **Target Structure**:
    ```
    modules/services/media/
    ├── arr-stack.nix           # Sonarr, Radarr, Lidarr, Prowlarr
    ├── downloaders.nix         # qBittorrent, SABnzbd, SLSKD
    ├── streaming.nix           # Jellyfin, Navidrome
    ├── photos.nix              # Immich
    ├── surveillance.nix        # Frigate, Home Assistant
    └── networking.nix          # VPN, reverse proxy
    ```
  - **Toggle Options**: `hwc.services.media.{arr,streaming,photos,surveillance}.enable`

#### 2.2 Business Services Migration
- [ ] Migrate business modules → `modules/services/business/`
  - **Source Files**: `business-services.nix`, `business-api.nix`, `business-monitoring.nix`
  - **Target Structure**:
    ```
    modules/services/business/
    ├── database.nix            # PostgreSQL with SOPS integration
    ├── api.nix                 # FastAPI business intelligence
    ├── monitoring.nix          # Business-specific monitoring
    └── backup.nix              # Automated backups
    ```
  - **Toggle Options**: `hwc.services.business.{database,api,monitoring}.enable`

#### 2.3 AI/ML Services Migration
- [ ] Consolidate AI modules → `modules/services/ai/`
  - **Source Files**: `ai-services.nix`, `ai-documentation.nix`, `ollama configuration`
  - **Target Structure**:
    ```
    modules/services/ai/
    ├── ollama.nix              # GPU-accelerated Ollama
    ├── documentation.nix       # AI documentation system
    └── models.nix              # Model management
    ```
  - **Toggle Options**: `hwc.services.ai.{ollama,documentation}.enable`

#### 2.4 Infrastructure Services Migration
- [ ] Move infrastructure services → `modules/infrastructure/`
  - **Source Files**: `gpu-acceleration.nix`, `hot-storage.nix`, `monitoring.nix`
  - **Target Structure**:
    ```
    modules/infrastructure/
    ├── gpu.nix                 # NVIDIA GPU acceleration (already exists)
    ├── storage.nix             # Hot/cold storage management
    ├── monitoring.nix          # System monitoring stack
    └── backup.nix              # System backup services
    ```

### **Phase 3: Host-Specific Configuration**
**Status**: Pending  
**Dependencies**: Phase 2 complete

#### 3.1 Profile Creation
- [ ] Create `profiles/server.nix` for server-specific configuration
  - Enable: filesystem.serverStorage, services.media, services.business, services.ai
  - Hardware: GPU acceleration, storage mounts
  - Networking: VPN, reverse proxy, firewall rules

#### 3.2 Machine Configuration Cleanup
- [ ] Simplify `machines/server/config.nix`
  - Remove direct module imports
  - Keep only machine-specific hardware configuration
  - Use profile composition: `imports = [ ../../profiles/server.nix ];`

#### 3.3 Home Manager Migration
- [ ] Migrate `/etc/nixos/shared/home-manager/` to Charter v3 home modules
  - **Source Files**: `core-cli.nix`, `development.nix`, `productivity.nix`, `zsh.nix`
  - **Target**: Integrate into existing `modules/home/` structure
  - **Toggle Integration**: Use existing hwc.home options

### **Phase 4: Validation & Testing**
**Status**: Pending  
**Dependencies**: Phase 3 complete

#### 4.1 Build Verification
- [ ] Test `nixos-rebuild build` for both laptop and server configurations
- [ ] Verify no missing dependencies or circular imports
- [ ] Validate all paths resolve correctly

#### 4.2 Service Testing
- [ ] Verify all containers start correctly
- [ ] Test media pipeline functionality
- [ ] Validate business services connectivity
- [ ] Check AI services GPU acceleration

#### 4.3 Data Integrity
- [ ] Verify all existing data directories are accessible
- [ ] Test configuration persistence across reboots
- [ ] Validate secrets integration works correctly

## Migration Execution Notes

### Critical Success Factors
1. **Path Consistency**: Ensure all hardcoded paths are replaced with `config.hwc.paths.*` references
2. **Toggle Architecture**: Every service must be controlled by hwc.* options
3. **Hierarchical Composition**: Maintain lib → modules → profiles → machines structure
4. **Service Dependencies**: Preserve container dependencies and networking
5. **Hardware Integration**: Keep GPU acceleration and storage mounting functional

### Risk Mitigation
1. **Incremental Testing**: Build and test each phase before proceeding
2. **Configuration Backup**: Maintain working production system during migration
3. **Rollback Plan**: Keep production flake.nix as fallback
4. **Service Validation**: Test each service category independently

## Current Status

**✅ Phase 1 COMPLETED** (2025-08-21):
- **SOPS → Agenix Migration**: Complete infrastructure, user needs to migrate secret values
- **User Management**: Full Charter v3 user module with toggle-based configuration
- **Networking**: Complete networking stack with service-aware firewall
- **Profile Updates**: Base, workstation, and server profiles ready
- **Flake Migration**: Updated from sops-nix to agenix

**🔄 USER ACTION REQUIRED**:
1. **Migrate Secret Values**: Follow `AGENIX_MIGRATION_GUIDE.md` to convert SOPS secrets to agenix
2. **Test Base System**: Build laptop/server configs to verify Phase 1 works

**Ready to Execute**: Phase 2.1 - Media Stack Migration (after secret migration)

**Next Steps**: 
1. User migrates secrets using agenix CLI
2. Test incremental builds of Phase 1 infrastructure
3. Execute Phase 2 service architecture translation
4. Continue updating this document with progress

---
*This document will be updated as migration progresses to track completion status and any modifications to the plan.*