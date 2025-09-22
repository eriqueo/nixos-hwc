# Infrastructure Session Bucket

## Purpose

The **Session Bucket** provides **user-scoped helpers and system integration** for user applications. These modules handle the system-side setup needed for user session functionality without implementing the user applications themselves.

**Key Principle**: Session bucket provides the "system plumbing" that user applications need to function properly - dbus services, portal integration, CLI tools, and environment setup.

## Modules Overview

### 🔧 Services (`services.nix`)
**Background user services and environment setup**

**Provides:**
- SSH key setup and management
- User environment initialization
- Home Manager integration services
- Secret synchronization for user session

**Option Pattern:**
```nix
hwc.infrastructure.session.services = {
  enable = true;
  username = "eric";    # defaults to config.hwc.system.users.user.name
};
```

**Implementation Details:**
```nix
# SSH key setup service
systemd.services."setup-ssh-keys-${username}" = {
  description = "Setup SSH authorized keys for ${username}";
  wantedBy = [ "multi-user.target" ];
  after = [ "agenix.service" ];
  # Handles both secrets and fallback SSH keys
};
```

**Data Flow:**
```
System Boot → agenix decrypts secrets → SSH setup service runs
       ↓
User SSH keys → copied to ~/.ssh/authorized_keys with correct permissions
       ↓  
User Login → SSH access works, environment properly initialized
       ↓
Home Manager → can access secrets for user application configuration
```

### 🛠️ Commands (`commands.nix`)
**Shared CLI commands for cross-app integration**

**Provides:**
- GPU launch helper for cross-application GPU usage
- Shared utilities that both system and HM apps can use
- Command wrappers for complex system integration

**Option Pattern:**
```nix
hwc.infrastructure.session.commands = {
  enable = true;
  gpuLaunch = true;    # Enable gpu-launch command
};
```

**Current Status:**
- Placeholder implementation for future gpu-launch improvements
- Designed to provide system-wide commands that HM apps can reference
- Commands are available in system PATH for use in keybinds, scripts

**Future Implementation:**
```nix
# Example: gpu-launch wrapper with better detection
environment.systemPackages = lib.optionals cfg.gpuLaunch [
  (pkgs.writeShellScriptBin "gpu-launch" ''
    # Advanced GPU detection and offloading logic
    # Integrates with hardware.gpu module for optimal performance
  '')
];
```

### 🌐 App System Integration

The session bucket also provides **system integration for Home Manager applications** through `sys.nix` files that get imported via `profiles/sys.nix` gatherSys pattern.

#### Chromium Integration (`domains/home/apps/chromium/sys.nix`)
**System-side browser support**

**Provides:**
- D-Bus services for portal integration
- dconf configuration support  
- System-level browser integration

**Option Pattern:**
```nix
hwc.infrastructure.session.chromium = {
  enable = true;  # System integration only, no packages
};
```

**Implementation:**
```nix
config = lib.mkIf cfg.enable {
  # System-side helpers for Chromium (no packages - HM handles those)  
  programs.dconf.enable = lib.mkDefault true;      # Browser settings storage
  services.dbus.enable = lib.mkDefault true;       # Portal communication
  # No environment.systemPackages - HM provides the chromium binary
  # gpu-launch will find it via user PATH when running as user
};
```

**Data Flow:**
```
profiles/hm.nix → features.chromium.enable = true (HM package)
       ↓
HM chromium/index.nix → home.packages = [ pkgs.chromium ]
       ↓  
profiles/workstation.nix → hwc.infrastructure.session.chromium.enable = true
       ↓
chromium/sys.nix → programs.dconf.enable, services.dbus.enable
       ↓
User session → chromium binary available + system integration working
       ↓
gpu-launch chromium → Works via user PATH + GPU acceleration
```

## Session Bucket Integration Patterns

### HM + System Integration Pattern
**The proper way to integrate user applications:**

1. **Home Manager Side** (`domains/home/apps/<app>/index.nix`):
   - Provides `features.<app>.enable` option
   - Installs user packages: `home.packages = [ pkgs.<app> ]`
   - Handles user configuration files

2. **System Side** (`domains/home/apps/<app>/sys.nix`):  
   - Provides `hwc.infrastructure.session.<app>.enable` option
   - Enables required system services (dbus, dconf, portals)
   - NO user packages - that's HM's job

3. **Profile Coordination**:
   - `profiles/hm.nix`: Sets `features.<app>.enable = true`
   - `profiles/workstation.nix`: Sets `hwc.infrastructure.session.<app>.enable = true`  
   - `profiles/sys.nix`: Auto-imports `<app>/sys.nix` via gatherSys

### gatherSys Auto-Import Pattern
Session bucket leverages the `profiles/sys.nix` gatherSys function:

```nix
# profiles/sys.nix automatically finds and imports:
# - domains/home/apps/*/sys.nix  
# - domains/services/*/sys.nix
# - domains/infrastructure/*/sys.nix

gatherSys = dirPath: 
  # Finds all sys.nix files in subdirectories
  lib.filter builtins.pathExists (map (n: dirPath + "/${n}/sys.nix") subdirs);
```

This means session integration modules are **automatically imported** without manual profile maintenance.

### Cross-App Integration  
Session bucket enables apps to work together:

```nix
# GPU hardware detection (hardware bucket)
hwc.infrastructure.hardware.gpu.type = "nvidia";

# Session command integration (session bucket)  
hwc.infrastructure.session.commands.gpuLaunch = true;

# App system integration (session bucket)
hwc.infrastructure.session.chromium.enable = true;

# Result: Hyprland keybind can use gpu-launch chromium
bind = SUPER, B, exec, gpu-launch chromium
```

## Adding New App Integration

To add system integration for a new Home Manager app:

### 1. Create sys.nix file
```bash
mkdir -p domains/home/apps/myapp/
```

```nix
# domains/home/apps/myapp/sys.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.infrastructure.session.myapp;
in {
  options.hwc.infrastructure.session.myapp = {
    enable = lib.mkEnableOption "MyApp system integration";
  };
  
  config = lib.mkIf cfg.enable {
    # System services needed by MyApp
    services.dbus.enable = lib.mkDefault true;
    # NO packages - HM handles those
  };
}
```

### 2. Enable in profile
```nix
# profiles/workstation.nix  
hwc.infrastructure.session.myapp.enable = true;
```

### 3. Verify auto-import
The gatherSys function will automatically find and import the sys.nix file.

## Validation & Troubleshooting

### Check gatherSys Import
```bash
# Verify sys.nix files are being found
sudo nixos-rebuild build --show-trace 2>&1 | grep "gatherSys"
```

### Check App System Integration  
```bash
# Verify app system integration is enabled
nix eval .#nixosConfigurations.hwc-laptop.config.hwc.infrastructure.session

# Check specific app
nix eval .#nixosConfigurations.hwc-laptop.config.hwc.infrastructure.session.chromium.enable
```

### Check User Session Services
```bash  
# SSH key setup
systemctl status setup-ssh-keys-eric

# D-Bus session
systemctl --user status dbus
```

## Anti-Patterns

**❌ Don't install user packages in session bucket**:
```nix
# Wrong - packages belong in HM
environment.systemPackages = [ pkgs.chromium ];
```

**❌ Don't implement application logic**:
```nix
# Wrong - app config belongs in HM  
programs.chromium.extensions = [ ... ];
```  

**❌ Don't hardcode app imports**:
```nix
# Wrong - defeats gatherSys auto-import
imports = [ ../domains/home/apps/chromium/sys.nix ];
```

**✅ Do provide system integration**:
```nix
# Correct - system services needed by apps
services.dbus.enable = true;
programs.dconf.enable = true;
xdg.portal.enable = true;
```

**✅ Do enable proper namespacing**:
```nix
# Correct - follows session bucket namespace
hwc.infrastructure.session.<app>.enable = true;
```

**✅ Do separate concerns cleanly**:
```nix
# HM: User packages and config
home.packages = [ pkgs.chromium ];

# System: Integration services  
services.dbus.enable = true;
```

---

The session bucket provides essential **system plumbing for user applications**, ensuring proper integration between the user session and system services while maintaining clean separation of concerns.