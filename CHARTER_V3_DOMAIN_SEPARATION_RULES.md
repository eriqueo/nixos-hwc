# Charter v3 Enhanced Domain Separation Rules
# Comprehensive Migration Methodology for Functional Completeness

**Created**: 2025-08-24  
**Purpose**: Ensure complete functionality migration with proper domain separation  
**Problem Solved**: Prevents scattered functionality from being missed or misplaced during Charter v3 migration

## 🎯 **Core Domain Principle**

**Every piece of functionality must live in its FUNCTIONAL DOMAIN, not its DISCOVERY LOCATION**

- ❌ **Wrong**: GPU toggle in `waybar.nix` (discovered in UI module)  
- ✅ **Right**: GPU toggle in `gpu.nix` (belongs in hardware domain)

---

## 📋 **Pre-Migration Functional Audit Process**

### **Step 1: Comprehensive Functionality Discovery**

Before any migration, audit EVERY file for cross-domain functionality:

```bash
# Search for domain-crossing patterns
rg -t nix "(writeScriptBin|systemd\.services|hardware\.)" --stats
rg -t nix -A5 -B5 "(gpu|nvidia|intel|audio|bluetooth|network)" 
rg -t nix -A3 "pkgs\.writeScript"
```

**Audit Questions for Each File:**
1. **What domain does this file claim to be?** (based on name/location)
2. **What functionality does it actually contain?** (scripts, services, hardware config)
3. **Does all functionality belong in this domain?** (domain purity check)
4. **What should be extracted to other domains?** (cross-domain violations)

### **Step 2: Functional Classification Matrix**

Every piece of functionality must be classified:

| **Functional Domain** | **Charter v3 Location** | **Indicators** | **Examples** |
|----------------------|-------------------------|----------------|-------------|
| **Hardware Management** | `modules/infrastructure/` | Device access, drivers, power management | GPU toggle, audio control, brightness |
| **System Services** | `modules/system/` | Core system functions, networking, security | SSH, firewall, user management |
| **Application Services** | `modules/services/` | Service orchestration, containers, daemons | Media stack, databases, APIs |
| **User Environment** | `modules/home/` | User-facing configs, UI, shell, desktop | Hyprland, waybar, shell aliases |
| **Machine-Specific** | `machines/*/` | Hardware-specific overrides ONLY | Bus IDs, device paths, hostnames |
| **Profile Orchestration** | `profiles/` | Service enablement, NO implementation | Toggle settings, imports |

### **Step 3: Cross-Domain Violation Detection**

**Automatic Detection Patterns:**

```bash
# Find hardware config in wrong domains
rg "nvidia|gpu|brightness|audio.*control" --type nix modules/home/
rg "writeScriptBin.*hardware|systemd.*hardware" modules/services/

# Find service logic in hardware modules  
rg "containers|podman|systemd\.services\." modules/infrastructure/

# Find UI logic in system modules
rg "waybar|hypr|desktop|rofi" modules/system/

# Find machine-specific logic in shared modules
rg "busId|hardware-configuration|hostName" modules/ --exclude machines/
```

**Manual Audit Checklist:**
- [ ] Are there any `writeScriptBin` in non-infrastructure modules that control hardware?
- [ ] Are there `systemd.services` in modules outside their functional domain?  
- [ ] Are there hardware controls (`nvidia-smi`, `brightnessctl`) in UI modules?
- [ ] Are there UI elements in hardware/system modules?
- [ ] Are there machine-specific values hardcoded in shared modules?

---

## 🏗️ **Domain Separation Rules**

### **Rule 1: Functional Purity**
**Every module must contain ONLY functionality from its domain**

```nix
# ✅ CORRECT - modules/infrastructure/gpu.nix
config.environment.systemPackages = [ gpu-toggle gpu-launch ];  # Hardware control scripts
config.hardware.nvidia = { ... };                              # Hardware configuration

# ❌ INCORRECT - modules/home/waybar.nix  
config.environment.systemPackages = [ gpu-toggle ];            # Hardware script in UI module
```

### **Rule 2: Single Source of Truth**
**Each functional capability has exactly ONE implementation location**

```nix
# ✅ CORRECT
modules/infrastructure/gpu.nix        # ONLY place with GPU hardware logic
modules/home/waybar.nix              # References GPU state, doesn't implement GPU logic

# ❌ INCORRECT - Multiple implementations
modules/infrastructure/gpu.nix        # GPU toggle implementation
modules/home/waybar.nix              # Duplicate GPU toggle implementation  
```

### **Rule 3: Dependency Direction Enforcement**
**Dependencies flow FROM profiles TO modules, never the reverse**

```nix
# ✅ CORRECT - Profile enables functionality
profiles/workstation.nix:
  hwc.infrastructure.gpu.powerManagement.smartToggle = true;

# ✅ CORRECT - Module provides functionality  
modules/infrastructure/gpu.nix:
  config = mkIf cfg.powerManagement.smartToggle { ... };

# ❌ INCORRECT - Module assumes enablement
modules/infrastructure/gpu.nix:
  config.hardware.nvidia = { enable = true; };  # No conditional
```

### **Rule 4: Interface Segregation**
**Modules expose clean interfaces, hide implementation details**

```nix
# ✅ CORRECT - Clean interface
options.hwc.infrastructure.gpu.powerManagement.smartToggle = mkEnableOption "GPU power management";

# ✅ CORRECT - Hidden implementation
config = mkIf cfg.powerManagement.smartToggle {
  environment.systemPackages = [ gpu-toggle-script ];  # Implementation hidden
};

# ❌ INCORRECT - Leaky abstraction  
options.hwc.infrastructure.gpu.toggleScript = mkOption { ... };  # Exposes implementation details
```

---

## 🔍 **Domain-Specific Migration Guidelines**

### **Infrastructure Domain (`modules/infrastructure/`)**
**Purpose**: Hardware management, device drivers, power control

**Should Contain:**
- Hardware device configuration (`hardware.nvidia`, `hardware.bluetooth`)
- Device control scripts (`gpu-toggle`, `brightness-control`, `audio-control`)
- Hardware monitoring services (`gpu-monitor`, `thermal-monitor`)
- Power management features (`tlp`, `powertop` integration)
- Device permissions and udev rules

**Should NOT Contain:**
- UI elements or desktop notifications (delegate to home modules)
- Application-specific logic (delegate to services modules)
- User preferences (delegate to home modules)

**Interface Pattern:**
```nix
options.hwc.infrastructure.{hardware}.{feature}.enable = mkEnableOption;
config.environment.systemPackages = mkIf cfg.enable [ control-scripts ];
```

### **System Domain (`modules/system/`)**
**Purpose**: Core system functions, networking, user management

**Should Contain:**
- Network configuration (`networking`, `firewall`, `ssh`)
- User account management (`users`, `groups`, `authentication`)
- Security configuration (`secrets`, `permissions`, `hardening`)
- Filesystem structure (`paths`, `mounts`, `directories`)
- Boot and kernel configuration

**Should NOT Contain:**
- Hardware-specific drivers (delegate to infrastructure)
- Application services (delegate to services)
- User interface configuration (delegate to home)

### **Services Domain (`modules/services/`)**
**Purpose**: Application orchestration, service management

**Should Contain:**
- Container orchestration (`podman`, `docker` containers)
- Database services (`postgresql`, `redis`, `mongodb`)
- Web services (`nginx`, `caddy`, `apis`)
- Media services (`jellyfin`, `*arr`, `downloaders`)
- Background daemons and their configuration

**Should NOT Contain:**
- Hardware drivers (delegate to infrastructure)
- User interface elements (delegate to home)
- Core system functions (delegate to system)

### **Home Domain (`modules/home/`)**
**Purpose**: User environment, UI, desktop configuration

**Should Contain:**
- Desktop environment (`hyprland`, `waybar`, `rofi`)
- Shell configuration (`zsh`, `bash`, `aliases`)
- User applications (`firefox`, `terminal`, `editor`)
- User-specific settings and preferences
- Dotfiles and configuration files

**Should NOT Contain:**
- Hardware control logic (delegate to infrastructure)
- System services (delegate to services)
- Core system configuration (delegate to system)

**Interface Pattern:**
```nix
options.hwc.home.{category}.{feature}.enable = mkEnableOption;
config.programs.{application} = mkIf cfg.enable { ... };
```

---

## 🚨 **Common Anti-Patterns to Avoid**

### **Anti-Pattern 1: Hardware Logic in UI Modules**
```nix
# ❌ BAD - waybar.nix contains GPU hardware control
waybar.nix:
  gpuToggle = writeScriptBin "gpu-toggle" { nvidia-smi ... };

# ✅ GOOD - waybar references, gpu.nix implements  
waybar.nix:
  programs.waybar.settings.modules-right = [ "gpu-status" ];
gpu.nix:
  environment.systemPackages = [ gpu-toggle ];
```

### **Anti-Pattern 2: Service Logic in Hardware Modules**
```nix
# ❌ BAD - gpu.nix contains application service
gpu.nix:
  virtualisation.oci-containers.containers.ollama = { ... };

# ✅ GOOD - gpu.nix provides capability, ai.nix uses it
gpu.nix:
  options.hwc.gpu.containerOptions = [ "--device=/dev/nvidia0" ];
ai.nix:
  extraOptions = cfg.gpu.containerOptions;
```

### **Anti-Pattern 3: Hardcoded Machine Values in Shared Modules**
```nix
# ❌ BAD - Hardcoded in shared module
networking.nix:
  networking.hostName = "hwc-laptop";  # Machine-specific

# ✅ GOOD - Configurable with machine override
networking.nix:
  options.hwc.networking.hostName = mkOption { ... };
machines/laptop/config.nix:
  hwc.networking.hostName = "hwc-laptop";
```

---

## 📝 **Enhanced Migration Checklist**

### **Pre-Migration Analysis**
- [ ] **Functional Discovery**: List ALL functionality in current system
- [ ] **Domain Classification**: Assign each function to correct Charter v3 domain
- [ ] **Cross-Domain Detection**: Identify scattered/misplaced functionality
- [ ] **Dependency Mapping**: Document what depends on what
- [ ] **Interface Design**: Plan clean APIs between domains

### **Migration Execution**
- [ ] **Domain Purity**: Ensure each module contains only its domain's functionality
- [ ] **Single Source**: Each capability implemented in exactly one place
- [ ] **Clean Interfaces**: Modules expose options, hide implementation
- [ ] **Proper Dependencies**: Profiles enable, modules implement
- [ ] **Test Coverage**: Verify all functionality works after migration

### **Post-Migration Validation**
- [ ] **Cross-Domain Audit**: No hardware logic in UI modules
- [ ] **Functional Completeness**: All original functionality preserved
- [ ] **Interface Consistency**: All modules follow Charter v3 patterns
- [ ] **Documentation**: Domain rules clearly documented
- [ ] **Maintainability**: Future changes have clear domain homes

---

## 🎯 **Success Metrics**

### **Technical Metrics**
- **Domain Purity**: 0% cross-domain violations detected by audit scripts
- **Functional Completeness**: 100% of original functionality preserved
- **Interface Consistency**: All modules follow Charter v3 option patterns
- **Maintainability**: New functionality has obvious domain placement

### **Process Metrics**
- **Discovery Coverage**: Migration catches 100% of scattered functionality
- **Effort Efficiency**: Minimal post-migration cleanup required
- **Knowledge Transfer**: Domain rules are clear enough for others to follow
- **Future-Proofing**: System scales without domain violations

---

**This enhanced methodology ensures complete, properly-architected Charter v3 migrations with zero functional gaps.**