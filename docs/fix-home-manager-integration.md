# Home-Manager Integration Fix Blueprint

**Problem**: Home-manager not properly activated, waybar/hyprland configs not generated  
**Charter Violations**: Dependency hierarchy, circular module dependencies  
**Status**: Critical - Desktop environment non-functional

---

## **Root Cause Analysis**

### **Current Broken State**
```nix
# ❌ WRONG - modules/home/waybar.nix
config = lib.mkIf cfg.enable {
  home-manager.users.eric = {           # Module trying to define its own activation
    programs.waybar = { ... };
  };
};
```

### **Charter v3 Violations**
1. **Dependency Hierarchy Violation** (Charter §2.1): Individual modules attempting to define `home-manager.users.eric` 
2. **Circular Dependency**: Modules imported by home-manager trying to define home-manager configuration
3. **Single Source of Truth Violation** (Charter §4.2): Home-manager activation scattered across modules

---

## **Fix Strategy**

### **System-Level Activation** (Charter Compliant)
```nix
# ✅ CORRECT - profiles/workstation.nix
home-manager.users.eric = {
  imports = [
    ../modules/home/waybar.nix      # Import pure home modules
    ../modules/home/hyprland.nix
    ../modules/home/shell.nix
    # ... other home modules
  ];
  home.stateVersion = "24.05";
};
```

### **Pure Home Modules** (Domain Separation Compliant)
```nix
# ✅ CORRECT - modules/home/waybar.nix (after conversion)
config = lib.mkIf cfg.enable {
  programs.waybar = {               # Direct home-manager config
    enable = true;
    settings = { ... };
    style = "...";
  };
  
  home.packages = with pkgs; [      # Direct package installation
    pavucontrol
    # ... other waybar tools
  ];
};
```

---

## **Implementation Steps**

### **Step 1: Add System-Level Home-Manager Configuration**
**File**: `profiles/workstation.nix`
**Action**: Add home-manager.users.eric block with module imports
**Charter Reference**: §2.1 - Profiles orchestrate module activation

### **Step 2: Convert Home Modules to Pure Format**
**Files**: `modules/home/waybar.nix`, `modules/home/hyprland.nix`
**Action**: Remove `home-manager.users.eric` wrappers, use direct configuration
**Charter Reference**: §4.1 - Modules implement, profiles activate

### **Step 3: Validate Home-Manager Service**
**Action**: Ensure home-manager systemd service exists and runs
**Charter Reference**: §5.2 - Service dependencies properly configured

---

## **Charter Compliance Verification**

### **Dependency Flow** (Charter §2.1)
```
flake.nix → profiles/workstation.nix → modules/home/*.nix
```
✅ Left-to-right dependency flow maintained

### **Single Activation Point** (Charter §4.2)
✅ Only `profiles/workstation.nix` defines `home-manager.users.eric`
✅ Individual modules contain only implementation

### **Domain Purity** (Domain Rules §1)
✅ Home modules contain only user environment configuration
✅ No system-level concerns mixed in home modules

---

## **Expected Outcomes**

### **After Fix**
1. **Home-manager service active**: `systemctl --user status home-manager-eric.service`
2. **Waybar config generated**: `~/.config/waybar/config` exists
3. **Hyprland config generated**: `~/.config/hypr/hyprland.conf` exists
4. **Desktop environment functional**: waybar launches without errors

### **Validation Commands**
```bash
# Home-manager generation exists
ls -la /nix/var/nix/profiles/per-user/eric/home-manager*

# Configs generated
test -f ~/.config/waybar/config && echo "Waybar config exists"
test -f ~/.config/hypr/hyprland.conf && echo "Hyprland config exists"

# Service status
systemctl --user status home-manager-eric.service
```

---

**This fix restores Charter v3 compliance by establishing proper activation hierarchy and eliminating circular dependencies.**