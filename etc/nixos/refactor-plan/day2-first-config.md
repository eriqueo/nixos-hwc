# Day 2: First Working Configuration (2-3 hours)

## Morning Session (1.5 hours)
### 9:00 AM - Review & Validate Day 1 ✅

```bash
# Step 1: Validate yesterday's work
cd /etc/nixos
git status  # Should be clean
sudo nixos-rebuild build --flake .#hwc-server  # Should still work

cd /etc/nixos-next
./operations/validation/quick-check.sh

# Step 2: Update migration log
echo "## Day 2: $(date +%Y-%m-%d)" >> MIGRATION_LOG.md
```

### 9:30 AM - Create Core Paths Module ✅

```bash
cd /etc/nixos-next

# Step 3: Create paths module (critical for everything else)
cat > modules/system/paths.nix << 'EOF'
{ lib, config, ... }:
{
  options.hwc.paths = {
    root = lib.mkOption {
      type = lib.types.path;
      default = "/";
      description = "System root";
    };
    
    hot = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/hot";
      description = "Hot storage";
    };
    
    media = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/media";
      description = "Media storage";
    };
    
    state = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/hwc";
      description = "Service state";
    };
  };
  
  config = {
    # Ensure directories exist
    systemd.tmpfiles.rules = [
      "d ${config.hwc.paths.state} 0755 root root -"
    ];
  };
}
EOF
```

### 10:00 AM - Create Minimal Machine Config ✅

```bash
# Step 4: Create test machine that can actually build
cat > machines/test-refactor.nix << 'EOF'
{ config, lib, pkgs, ... }:
{
  imports = [
    # Import hardware from existing config
    /etc/nixos/hosts/server/hardware-configuration.nix
    
    # Import our modules
    ../modules/system/paths.nix
    ../modules/system/test.nix
  ];
  
  # Enable test module
  hwc.test.enable = true;
  
  # Minimal required config
  networking.hostName = "test-refactor";
  networking.useDHCP = lib.mkDefault true;
  
  # Boot loader (copy from your current)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  # Add your user
  users.users.eric = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
  };
  
  # Basic services
  services.openssh.enable = true;
  
  system.stateVersion = "24.05";
}
EOF

# Step 5: Update flake to recognize the machine
cat > flake.nix << 'EOF'
{
  description = "Refactored NixOS Configuration";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  
  outputs = { self, nixpkgs }: {
    nixosConfigurations = {
      test-refactor = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./machines/test-refactor.nix ];
      };
    };
  };
}
EOF
```

## Afternoon Session (1.5 hours)

### 2:00 PM - Test First Build ✅

```bash
cd /etc/nixos-next

# Step 6: Attempt first build (WILL LIKELY FAIL - THAT'S OK!)
sudo nixos-rebuild build --flake .#test-refactor 2>&1 | tee build-attempt-1.log

# Step 7: Fix common issues
# If missing options, add:
echo "{ config, lib, pkgs, ... }: {}" > modules/system/compat.nix
# Then add to imports in machines/test-refactor.nix

# Step 8: Keep trying until it builds
sudo nixos-rebuild build --flake .#test-refactor

# SUCCESS MESSAGE SHOULD APPEAR
```

### 3:00 PM - Create Migration Bridge ✅

```bash
# Step 9: Create bridge to reference old config
cat > lib/migration-helper.nix << 'EOF'
{ lib }:
{
  # Helper to import from old config
  importLegacy = path: 
    import (/etc/nixos + "/${path}");
  
  # Helper to track migration status  
  migrationStatus = service: status:
    lib.trace "Migration: ${service} is ${status}" true;
}
EOF

# Step 10: Document success
cat >> MIGRATION_LOG.md << 'EOF'
- [ ] Created paths module
- [ ] Created test machine config
- [ ] First successful build
- [ ] Migration bridge created

Build Output: $(readlink result)
EOF

git add -A
git commit -m "Day 2: First successful build"
```

## End of Day 2 Checklist

- [ ] New config builds successfully
- [ ] Paths module created
- [ ] Test machine defined
- [ ] Old system still untouched
- [ ] Can build: `sudo nixos-rebuild build --flake /etc/nixos-next#test-refactor`

## Troubleshooting Commands

```bash
# See what's failing
sudo nixos-rebuild build --flake .#test-refactor --show-trace

# Check syntax
nix flake check

# See what would be built
nix eval .#nixosConfigurations.test-refactor.config.system.build.toplevel
```

**Day 2 Success**: New structure can build a minimal system
