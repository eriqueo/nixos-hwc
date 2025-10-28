# Infrastructure Domain

## Purpose & Scope

The **Infrastructure Domain** provides integration glue between users, hardware, and services. It implements the "wiring layer" that connects different parts of the system without implementing core functionality itself.

**Key Principle**: If it owns a daemon → system/services domain. If it enforces policy → security domain. **If it wires users/services to hardware or to each other → infrastructure domain**.

## 3-Bucket Architecture

Infrastructure is organized into exactly **3 clean buckets** to eliminate sprawl:

### 🔧 Hardware Bucket (`hardware/`)
**User ↔ Hardware integration glue**
- **GPU acceleration**: Provides `hwc.infrastructure.hardware.gpu.*` for GPU detection, driver integration, container runtime support
- **Permissions**: User groups and hardware ACLs (`hwc.infrastructure.hardware.permissions.*`)
- **Peripherals**: Printer integration glue (`hwc.infrastructure.hardware.peripherals.*`)
- **Storage**: Storage device integration and mount helpers (`hwc.infrastructure.hardware.storage.*`)

### 🌐 Mesh Bucket (`mesh/`)
**Service ↔ Service and Service ↔ Network glue**
- **Container networking**: Inter-container communication, network overlays
- Future: Service mesh, load balancing, service discovery glue

### 👤 Session Bucket (`session/`)
**User-scoped helpers (non-WM-specific)**
- **Background services**: User environment setup, SSH key management
- **Shared commands**: CLI tools for cross-app integration (gpu-launch, etc.)
- **App system integration**: System-side helpers for HM apps (dbus, portals, dconf)

## Option Namespace Convention

All infrastructure options follow the pattern:
```nix
hwc.infrastructure.<bucket>.<module>.*
```

Examples:
- `hwc.infrastructure.hardware.gpu.enable = true;`
- `hwc.infrastructure.hardware.permissions.groups.media = true;`
- `hwc.infrastructure.session.chromium.enable = true;`
- `hwc.infrastructure.mesh.containerNetworking.enable = true;`

## Data Flow & Integration Points

### GPU Pipeline Example
```
Machine Config → hwc.infrastructure.hardware.gpu.type = "nvidia"
       ↓
GPU Module → Detects drivers, configures runtime
       ↓
Services → config.hwc.infrastructure.hardware.gpu.accel (consumed by ollama, jellyfin)
       ↓
User Apps → gpu-launch command available for HM keybinds
```

### App Integration Pipeline (Chromium Example)
```
profiles/hm.nix → features.chromium.enable = true (HM package)
       ↓
domains/home/apps/chromium/index.nix → home.packages = [ chromium ]
       ↓
profiles/workstation.nix → hwc.infrastructure.session.chromium.enable = true
       ↓
domains/home/apps/chromium/sys.nix → programs.dconf.enable, services.dbus.enable
       ↓
User Session → chromium binary available, system integration working
       ↓
gpu-launch chromium → Works via user PATH + GPU acceleration
```

## File Structure

```
domains/infrastructure/
├── index.nix                    # Domain aggregator (imports 3 buckets)
│
├── hardware/                    # Hardware integration bucket
│   ├── gpu.nix                 # GPU acceleration & driver integration
│   ├── permissions.nix         # User groups & hardware ACLs  
│   ├── peripherals.nix         # Printer/scanner integration glue
│   └── storage.nix             # Storage device integration
│
├── mesh/                       # Service networking bucket
│   └── container-networking.nix # Container network integration
│
└── session/                    # User session bucket
    ├── services.nix            # Background user services
    └── commands.nix            # Shared CLI commands (disabled by default)
```

## Import Pattern

Profiles should import the domain aggregator, not individual modules:

```nix
# ✅ Correct - Clean aggregation
imports = [ ../domains/infrastructure ];

# ❌ Wrong - Bypasses domain boundaries  
imports = [
  ../domains/infrastructure/hardware/gpu.nix
  ../domains/infrastructure/session/services.nix
];
```

## Validation Rules

1. **No daemon ownership**: Infrastructure modules configure but don't own systemd services
2. **No business logic**: Pure integration glue, no application-specific behavior  
3. **Stable interfaces**: Other domains should consume via stable option paths
4. **3-bucket limit**: All functionality must fit within hardware/mesh/session buckets
5. **Namespace consistency**: All options under `hwc.infrastructure.<bucket>.<module>.*`

## Common Usage Patterns

### Enable GPU acceleration for services
```nix
# Machine declares hardware reality
hwc.infrastructure.hardware.gpu = {
  enable = true;
  type = "nvidia";
  nvidia.containerRuntime = true;
};

# Services automatically consume via config.hwc.infrastructure.hardware.gpu.accel
```

### Add user to hardware groups
```nix
hwc.infrastructure.hardware.permissions = {
  enable = true;
  groups = {
    media = true;        # audio/video device access
    hardware = true;     # GPIO, sensors, etc.
    development = true;  # USB devices, debuggers
  };
};
```

### Enable system integration for HM app
```nix
# HM side: features.chromium.enable = true (in profiles/hm.nix)
# System side:
hwc.infrastructure.session.chromium.enable = true;  # dbus, dconf, portals
```

## Anti-Patterns to Avoid

- **❌ Hardware modules in home/**: Violates domain separation
- **❌ Service implementation**: Infrastructure provides glue, not services
- **❌ Complex business logic**: Keep modules simple and focused
- **❌ Cross-bucket dependencies**: Buckets should be independent
- **❌ Direct service configuration**: Use stable option interfaces

## Troubleshooting

**GPU not working in containers?**
- Check `hwc.infrastructure.hardware.gpu.nvidia.containerRuntime = true`
- Verify `config.hwc.infrastructure.hardware.gpu.accel` is set correctly

**User can't access hardware?** 
- Check `hwc.infrastructure.hardware.permissions.groups.*` settings
- Verify user is in the expected groups via `groups` command

**App missing system integration?**
- Check if `hwc.infrastructure.session.<app>.enable = true` is set
- Verify the app's `sys.nix` file is being imported via `profiles/sys.nix`

## Recent Changes & Evolution

### ✅ Workspace Integration (October 2024)
The infrastructure domain now supports the new workspace structure:
- **GPU-launch command**: Integrated with workspace productivity tools
- **Hardware permissions**: Support for workspace automation scripts
- **Cross-domain coordination**: Better integration between domains via workspace

### ✅ Container Orchestration Maturity
- **Container networking**: Advanced inter-container communication
- **GPU acceleration**: Seamless hardware acceleration for containerized services
- **Storage integration**: Coordinated storage access patterns

### ✅ Session Integration Expansion
- **App system integration**: Comprehensive support for Home Manager applications
- **Background services**: Enhanced user-scoped service coordination
- **CLI tools**: Expanded shared command ecosystem

## Future Roadmap

### Short-term (Next Quarter)
- **Enhanced GPU detection**: More robust hardware capability detection
- **Extended peripheral support**: Printer, scanner, and device automation
- **Advanced container networking**: Service mesh and load balancing capabilities

### Medium-term
- **Multi-machine coordination**: Infrastructure sharing across machines
- **Advanced storage integration**: Distributed storage and caching
- **Enhanced session management**: More sophisticated user environment coordination

---

**Domain Version**: v3.0 - Mature 3-bucket architecture with workspace integration
**Charter Compliance**: ✅ Full compliance with HWC Charter v6.0
**Last Updated**: October 2024 - Post workspace reorganization and container maturity

The infrastructure domain provides the essential "glue code" that makes the system cohesive without creating tight coupling between domains. Keep it focused on integration, not implementation.