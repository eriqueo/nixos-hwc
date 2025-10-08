# Profile Refactor Guide: One Domain = One Profile

## Goal
Eliminate `base.nix` and `sys.nix`. Create one profile per domain with clear feature toggles. Each machine explicitly imports only the domain profiles it needs.

---

## Step 1: Create Profile Template

All domain profiles should follow this structure:

```nix
# profiles/<domain>.nix
#
# <DOMAIN> DOMAIN - Feature menu for <domain>-level capabilities
# Provides base <domain> requirements and optional <domain> features
{ lib, pkgs, ... }:

let
  # Helper to gather all sys.nix files from home apps (ONLY in system.nix)
  gatherSys = dir:
    let
      entries = builtins.readDir dir;
      sysFiles = lib.attrsets.mapAttrsToList
        (name: type:
          if type == "directory" && builtins.pathExists (dir + "/${name}/sys.nix")
          then dir + "/${name}/sys.nix"
          else null)
        entries;
    in
    builtins.filter (x: x != null) sysFiles;
in
{
  #==========================================================================
  # BASE <DOMAIN> - Critical for machine functionality
  #==========================================================================

  imports = [
    ../domains/<domain>/index.nix
    # Add gatherSys ONLY in system.nix: ] ++ (gatherSys ../domains/home/apps);
  ];

  # Essential functionality - machines with this domain enabled need these
  hwc.<domain>.essential.enable = true;

  #==========================================================================
  # OPTIONAL FEATURES - Sensible defaults, override per machine
  #==========================================================================

  # Group 1: <Category Name>
  hwc.<domain>.feature1.enable = false;
  hwc.<domain>.feature2.enable = false;

  # Group 2: <Category Name>
  hwc.<domain>.feature3.enable = false;
}
```

---

## Step 2: Break Down base.nix

**Current base.nix content (104 lines):**

### What STAYS in base.nix (NONE - it gets deleted):
- Nothing. base.nix will be deleted.

### What MOVES to system.nix:
```nix
# From base.nix lines 22-37:
time.timeZone = lib.mkDefault "America/Denver";
users.users.eric = {
  hashedPassword = "$y$j9T$mpCws7jy8SXAeH2rwkaGr.$lc1CQDwsoUxiv6s0PZqlKBmia1ffk4gs5jfyLW1Yg86";
};
nix = {
  settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    trusted-users = [ "eric" ];
  };
  gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
};

# From base.nix lines 40-46 (networking):
networking = {
  networkmanager.enable = true;
  firewall = {
    enable = true;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
  };
};

# From base.nix lines 54-58 (boot):
boot.loader.systemd-boot.enable = true;
boot.loader.efi.canTouchEfiVariables = true;

# From base.nix lines 60-66 (security):
security.polkit.enable = true;
security.sudo.wheelNeedsPassword = lib.mkDefault false;
```

### What MOVES to infrastructure.nix:
```nix
# Any hardware/storage settings currently in base.nix
# (Currently base.nix doesn't have these, they're in sys.nix)
```

---

## Step 3: Break Down sys.nix (120 lines)

**Current sys.nix is workstation-specific settings**

### What MOVES to system.nix:
```nix
# From sys.nix lines 37-44 (keyboard/audio behavior):
hwc.system.services.behavior = {
  enable = true;
  keyboard = {
    enable = true;
    universalFunctionKeys = true;
  };
  audio.enable = true;
};

# From sys.nix lines 47-51 (thermal):
hwc.system.core.thermal = {
  enable = true;
  powerManagement.enable = true;
  disableIncompatibleServices = true;
};

# From sys.nix lines 58-66 (login manager):
hwc.system.services.session.loginManager = {
  enable = true;
  defaultUser = "eric";
  defaultCommand = "Hyprland";
  autoLogin = true;
  showTime = true;
  greeterExtraArgs = [ "--remember" "--remember-user-session" ];
};

# From sys.nix lines 97-104 (security packages):
hwc.system.packages.security = {
  enable = true;
  protonDrive = {
    enable = true;
    useSecret = false;
  };
  monitoring.enable = true;
};

# From sys.nix lines 107-119 (user backup):
hwc.services.backup.user = {
  enable = true;
  externalDrive.enable = true;
  protonDrive = {
    enable = true;
    useSecret = false;
  };
  schedule = {
    enable = true;
    frequency = "daily";
  };
  notifications.enable = true;
};
```

### What MOVES to infrastructure.nix:
```nix
# From sys.nix lines 31-34 (GPU):
hwc.infrastructure.hardware.gpu = {
  enable = true;
  type = "nvidia";
};

# From sys.nix lines 69-94 (peripherals, permissions, storage):
hwc.infrastructure = {
  hardware = {
    peripherals = {
      enable = true;
      avahi = true;
    };
    permissions = {
      enable = true;
      groups = {
        media = true;
        development = true;
        virtualization = true;
        hardware = true;
      };
    };
    storage = {
      backup = {
        enable = true;
        externalDrive.autoMount = true;
      };
    };
  };
  session.services.enable = true;
};
```

### What MOVES to server.nix:
```nix
# From sys.nix lines 22-24:
imports = [
  ../domains/server/backup
];
```

---

## Step 4: Update system.nix

**File:** `profiles/system.nix`

### Current state (59 lines):
- Has gatherSys function ✓
- Has imports with gatherSys ✓
- Has some toggles but incomplete

### Actions needed:

1. **Keep the gatherSys function and imports** (lines 7-32)
2. **Add BASE SYSTEM section** with content from base.nix:
   - time.timeZone
   - users.users.eric.hashedPassword
   - nix settings (flakes, gc, trusted users)
   - networking (networkmanager, firewall)
   - boot.loader settings
   - security.polkit, security.sudo

3. **Expand OPTIONAL FEATURES section** with content from sys.nix:
   ```nix
   #==========================================================================
   # OPTIONAL FEATURES - Sensible defaults, override per machine
   #==========================================================================

   # System Services
   hwc.system.services.behavior.enable = false;
   hwc.system.services.session.loginManager.enable = false;

   # Thermal & Power
   hwc.system.core.thermal.enable = false;

   # Packages & Tools
   hwc.system.packages.development.enable = false;
   hwc.system.packages.media.enable = false;
   hwc.system.packages.security.enable = false;

   # Backup Services
   hwc.services.backup.user.enable = false;

   # Networking
   hwc.networking.level = "basic";  # basic, advanced, server
   hwc.system.services.vpn.enable = false;
   ```

---

## Step 5: Update infrastructure.nix

**File:** `profiles/infrastructure.nix`

### Current state (34 lines):
- Has basic structure
- Missing workstation hardware settings

### Actions needed:

1. **Keep imports** (line 11)
2. **Add BASE INFRASTRUCTURE section**:
   ```nix
   # Essential infrastructure - every machine needs these
   hwc.infrastructure.filesystemStructure.enable = true;
   hwc.infrastructure.filesystemStructure.userDirectories.enable = true;
   ```

3. **Expand OPTIONAL FEATURES** with content from sys.nix:
   ```nix
   #==========================================================================
   # OPTIONAL FEATURES - Sensible defaults, override per machine
   #==========================================================================

   # Hardware - GPU
   hwc.infrastructure.hardware.gpu.enable = false;
   hwc.infrastructure.hardware.gpu.type = "intel";  # intel, nvidia, amd

   # Hardware - Peripherals & Permissions
   hwc.infrastructure.hardware.peripherals.enable = false;
   hwc.infrastructure.hardware.peripherals.avahi = false;
   hwc.infrastructure.hardware.permissions.enable = false;

   # Hardware - Virtualization
   hwc.infrastructure.hardware.virtualization.enable = false;

   # Storage - Tiers
   hwc.infrastructure.hardware.storage.hot.enable = false;
   hwc.infrastructure.hardware.storage.media.enable = false;
   hwc.infrastructure.hardware.storage.backup.enable = false;

   # Session Services
   hwc.infrastructure.session.services.enable = false;
   ```

---

## Step 6: Rename security.nix to secrets.nix

**File:** `profiles/security.nix` → `profiles/secrets.nix`

### Actions:
1. Rename file: `mv profiles/security.nix profiles/secrets.nix`
2. Update header comment to say "SECRETS DOMAIN"
3. Keep all existing content (it's already correct)

---

## Step 7: Update Machine Configs

### Laptop (machines/laptop/config.nix):

**OLD imports:**
```nix
imports = [
  ./hardware.nix
  ../../scripts/vault-sync-system.nix
  ../../profiles/base.nix      # DELETE
  ../../profiles/security.nix  # RENAME
  ../../profiles/ai.nix
  ../../profiles/home.nix
  ../../profiles/sys.nix       # DELETE
];
```

**NEW imports:**
```nix
imports = [
  ./hardware.nix
  ../../scripts/vault-sync-system.nix
  ../../profiles/system.nix         # NEW (contains base + sys content)
  ../../profiles/infrastructure.nix # NEW (contains sys hardware content)
  ../../profiles/secrets.nix        # RENAMED from security
  ../../profiles/home.nix
  ../../profiles/ai.nix
  # Optional: ../../profiles/server.nix (only if backup services needed)
];
```

### Server (machines/server/config.nix):

**OLD imports:**
```nix
imports = [
  ./hardware.nix
  ../../profiles/base.nix      # DELETE
  ../../profiles/server.nix
  ../../profiles/security.nix  # RENAME
  ../../profiles/ai.nix
];
```

**NEW imports:**
```nix
imports = [
  ./hardware.nix
  ../../profiles/system.nix         # NEW
  ../../profiles/infrastructure.nix # NEW
  ../../profiles/secrets.nix        # RENAMED
  ../../profiles/server.nix
  ../../profiles/ai.nix
];
```

---

## Step 8: Testing & Validation

### After completing all changes:

1. **Test build (don't switch yet):**
   ```bash
   sudo nixos-rebuild build --flake .#hwc-laptop
   ```

2. **Check for errors** - common issues:
   - Missing imports
   - Duplicate option definitions
   - Options defined but module not imported

3. **If build succeeds, switch:**
   ```bash
   sudo nixos-rebuild switch --flake .#hwc-laptop
   ```

4. **Verify functionality:**
   ```bash
   # Check scripts are available
   which hyprland-monitor-toggle
   which hyprland-workspace-overview
   which hyprland-system-health-checker

   # Check services are running
   systemctl --user status waybar

   # Test keybindings
   # SUPER+SHIFT+H should run health checker
   # SUPER+TAB should show workspace overview
   ```

---

## Step 9: Cleanup

After successful switch:

1. **Delete old files:**
   ```bash
   git rm profiles/base.nix
   git rm profiles/sys.nix
   ```

2. **Commit changes:**
   ```bash
   git add profiles/system.nix profiles/infrastructure.nix profiles/secrets.nix
   git add machines/laptop/config.nix machines/server/config.nix
   git add domains/home/apps/hyprland/parts/scripts.nix
   git add domains/home/apps/hyprland/sys.nix
   git commit -m "refactor: One profile per domain - eliminate base.nix and sys.nix

   - Move base.nix essentials to system.nix BASE section
   - Move sys.nix workstation settings to system.nix and infrastructure.nix
   - Rename security.nix to secrets.nix for clarity
   - Add gatherSys to system.nix to import all domains/home/apps/*/sys.nix
   - Create hyprland helper scripts in domains/home/apps/hyprland/parts/scripts.nix
   - Update machine configs to import domain profiles explicitly

   Result: Clean domain separation, no base layer, explicit dependencies"
   ```

---

## Troubleshooting

### If neomutt error appears:
```
error: The option `features' does not exist
```

**Fix:** Check `domains/home/apps/neomutt/sys.nix` - it likely has a syntax error or is trying to set an option that doesn't exist in the system context.

### If scripts still don't appear:
1. Check that `system.nix` has the gatherSys function
2. Verify `domains/home/apps/hyprland/sys.nix` exists and imports `./parts/scripts.nix`
3. Ensure machine imports `system.nix`

### If duplicate option errors:
- Check that base.nix settings aren't also in system.nix
- Ensure sys.nix content was moved, not copied

---

## Summary Checklist

- [ ] Create backup: `git stash` or commit current state
- [ ] Update system.nix with base.nix + sys.nix content + gatherSys
- [ ] Update infrastructure.nix with sys.nix hardware content
- [ ] Rename security.nix to secrets.nix
- [ ] Update laptop/config.nix imports
- [ ] Update server/config.nix imports
- [ ] Delete base.nix and sys.nix
- [ ] Test build
- [ ] Test switch
- [ ] Verify scripts work
- [ ] Commit changes

---

**Estimated Time:** 30-45 minutes

**Complexity:** Medium - mostly copy/paste with careful organization

**Risk:** Low - can easily revert via git if issues arise
