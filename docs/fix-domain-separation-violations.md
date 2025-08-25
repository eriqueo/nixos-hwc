# Domain Separation Violations Fix Blueprint

**Problem**: Hardware control functionality scattered in UI modules  
**Charter Violations**: Domain boundaries, functional purity, single source of truth  
**Status**: Critical - Architecture integrity compromised

---

## **Root Cause Analysis**

### **Current Violations Detected**
```nix
# ❌ WRONG - modules/home/waybar.nix contains hardware scripts
networkStatus = pkgs.writeScriptBin "network-status" ''
  # Network hardware control logic
  SIGNAL=$(nmcli -f IN-USE,SIGNAL dev wifi...)
'';

batteryHealth = pkgs.writeScriptBin "battery-health" ''
  # Battery hardware access
  CAPACITY=$(cat "/sys/class/power_supply/BAT0/capacity")
'';

gpuMenu = pkgs.writeScriptBin "gpu-menu" ''
  # GPU hardware control
  nvidia-settings &
'';
```

### **Charter v3 Violations**

#### **Domain Boundary Violation** (Domain Rules §1)
- **Hardware scripts in UI domain**: Network, battery, GPU control in `waybar.nix`
- **Functional location ≠ Domain**: Found in home/ ≠ belongs in infrastructure/

#### **Single Source of Truth Violation** (Charter §4.2)  
- **Duplicate GPU functionality**: Both `infrastructure/gpu.nix` AND `home/waybar.nix` contain GPU logic
- **Scattered hardware control**: Each UI module reimplements hardware access

#### **Functional Purity Violation** (Domain Rules §1.1)
- **Mixed responsibilities**: UI module contains hardware device control

---

## **Fix Strategy**

### **Functional Domain Mapping** (Domain Rules §2)
| **Functionality** | **Current Location** | **Correct Domain** | **Target Location** |
|------------------|---------------------|-------------------|-------------------|
| GPU toggle/status | `home/waybar.nix` | Hardware Management | `infrastructure/gpu.nix` |
| Network status | `home/waybar.nix` | Hardware Management | `infrastructure/network.nix` |
| Battery monitoring | `home/waybar.nix` | Hardware Management | `infrastructure/power.nix` |
| System monitoring | `home/waybar.nix` | Hardware Management | `infrastructure/monitoring.nix` |

### **Clean Interface Design** (Charter §4.4)
```nix
# ✅ CORRECT - infrastructure/gpu.nix provides capability
options.hwc.infrastructure.gpu.controls = {
  toggle = mkEnableOption "GPU mode toggle";
  menu = mkEnableOption "GPU management menu"; 
};

config = mkIf cfg.controls.toggle {
  environment.systemPackages = [ gpu-toggle-script gpu-status-script ];
};

# ✅ CORRECT - home/waybar.nix consumes capability  
programs.waybar.settings.modules-right = [ "custom/gpu" ];
programs.waybar.settings."custom/gpu" = {
  exec = "gpu-status";        # References infrastructure-provided script
  on-click = "gpu-toggle";    # References infrastructure-provided script  
};
```

---

## **Implementation Steps**

### **Step 1: Extract Hardware Scripts to Infrastructure Domain**

#### **Create Infrastructure Modules**
- `modules/infrastructure/gpu.nix` - GPU control, monitoring, toggle
- `modules/infrastructure/network.nix` - Network status, management  
- `modules/infrastructure/power.nix` - Battery health, power management
- `modules/infrastructure/monitoring.nix` - System resource monitoring

#### **Script Extraction Pattern**
```nix
# Extract FROM: modules/home/waybar.nix
# Extract TO: modules/infrastructure/gpu.nix

gpuStatus = pkgs.writeScriptBin "gpu-status" ''
  # Hardware control logic moves to infrastructure domain
'';

config = mkIf cfg.enable {
  environment.systemPackages = [ gpuStatus gpuToggle ];  # System-level provision
};
```

### **Step 2: Convert Home Modules to Pure UI Configuration**

#### **Clean Waybar Module** (Domain Rules §4.3)
```nix
# ✅ AFTER - modules/home/waybar.nix contains ONLY UI config
programs.waybar = {
  settings."custom/gpu" = {
    format = "{}";
    exec = "gpu-status";           # Infrastructure-provided script
    on-click = "gpu-toggle";       # Infrastructure-provided script
    return-type = "json";
  };
};
```

### **Step 3: Update Profile Orchestration**
```nix
# profiles/workstation.nix - Enable infrastructure capabilities
hwc.infrastructure.gpu.controls.toggle = true;
hwc.infrastructure.network.monitoring = true;  
hwc.infrastructure.power.batteryHealth = true;

# UI modules automatically consume via environment.systemPackages
hwc.desktop.waybar.enable = true;
```

---

## **Charter Compliance Verification**

### **Domain Purity** (Domain Rules §1)
✅ **Infrastructure domain**: Contains only hardware management  
✅ **Home domain**: Contains only UI configuration  
✅ **No cross-domain implementation**: Each domain handles its responsibility

### **Single Source of Truth** (Charter §4.2)
✅ **GPU control**: Only in `infrastructure/gpu.nix`  
✅ **Network management**: Only in `infrastructure/network.nix`  
✅ **Battery monitoring**: Only in `infrastructure/power.nix`

### **Clean Interfaces** (Charter §4.4)
✅ **Infrastructure exposes**: Scripts via `environment.systemPackages`  
✅ **Home consumes**: Scripts via waybar configuration  
✅ **No implementation leakage**: UI doesn't know hardware details

### **Dependency Flow** (Charter §2.1)
```
profiles → infrastructure (enables hardware capabilities)
profiles → home (enables UI that consumes capabilities)  
```
✅ Proper left-to-right dependency flow maintained

---

## **Migration Execution Order**

### **Phase 1: Infrastructure Foundation**
1. Create new infrastructure modules with extracted functionality
2. Import infrastructure modules in `profiles/workstation.nix`
3. Enable infrastructure capabilities in profile

### **Phase 2: Home Module Cleanup**  
1. Remove hardware scripts from `waybar.nix`, `hyprland.nix`
2. Update modules to reference infrastructure-provided scripts
3. Test UI functionality with clean interfaces

### **Phase 3: Validation**
1. Verify no hardware logic remains in home domain
2. Confirm all functionality preserved through infrastructure domain
3. Validate Charter v3 compliance with domain audit

---

## **Expected Outcomes**

### **Domain Audit Results**
```bash
# No hardware control in home domain
rg "writeScriptBin.*gpu|nvidia-smi|brightnessctl" modules/home/ 
# Expected: No matches found

# Hardware control centralized in infrastructure  
rg "writeScriptBin" modules/infrastructure/
# Expected: All hardware scripts found here
```

### **Functional Verification**
- ✅ Waybar GPU toggle works (via infrastructure scripts)
- ✅ Network status displays (via infrastructure monitoring)  
- ✅ Battery health shows (via infrastructure power management)
- ✅ All original functionality preserved

---

**This fix restores Charter v3 domain separation by moving functionality to its correct functional domain, not its discovery location.**