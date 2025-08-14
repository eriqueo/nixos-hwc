# Day 3: First Service Migration (3-4 hours)

## Morning Session (2 hours)
### 9:00 AM - Validate Previous Work ✅

```bash
# Step 1: Ensure both repos still build
cd /etc/nixos
sudo nixos-rebuild build --flake .#hwc-server

cd /etc/nixos-next
sudo nixos-rebuild build --flake .#test-refactor

# Both should succeed before continuing
```

### 9:30 AM - Choose Simplest Service ✅

```bash
cd /etc/nixos-next

# Step 2: Let's migrate ntfy (simple, stateless service)
# First, understand the current config
cat /etc/nixos/hosts/server/modules/ntfy-server.yml
grep -r "ntfy" /etc/nixos/

# Step 3: Create new module
cat > modules/services/ntfy.nix << 'EOF'
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.ntfy;
  paths = config.hwc.paths;
in {
  options.hwc.services.ntfy = {
    enable = lib.mkEnableOption "ntfy notification service";
    
    port = lib.mkOption {
      type = lib.types.port;
      default = 8093;
      description = "Port for ntfy";
    };
    
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/ntfy";
      description = "Data directory";
    };
  };
  
  config = lib.mkIf cfg.enable {
    # Container configuration
    virtualisation.oci-containers.containers.ntfy = {
      image = "binwiederhier/ntfy:latest";
      ports = [ "${toString cfg.port}:80" ];
      volumes = [
        "${cfg.dataDir}:/var/cache/ntfy"
        "${cfg.dataDir}/etc:/etc/ntfy"
      ];
      environment = {
        TZ = "America/Denver";
      };
    };
    
    # Ensure directories exist
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root -"
      "d ${cfg.dataDir}/etc 0750 root root -"
    ];
    
    # Open firewall
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
EOF
```

### 10:30 AM - Create Service Test ✅

```bash
# Step 4: Create test for the service
cat > tests/ntfy-test.nix << 'EOF'
{ nixpkgs }:
let
  nixosTest = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      ../modules/system/paths.nix
      ../modules/services/ntfy.nix
      {
        hwc.services.ntfy.enable = true;
        
        # Minimal config for testing
        boot.loader.grub.device = "nodev";
        fileSystems."/" = {
          device = "none";
          fsType = "tmpfs";
        };
      }
    ];
  };
in
  nixosTest.config.system.build.toplevel
EOF

# Step 5: Test the module builds
nix-build tests/ntfy-test.nix --arg nixpkgs 'import <nixpkgs> {}'
```

## Afternoon Session (2 hours)

### 2:00 PM - Add Service to Machine ✅

```bash
cd /etc/nixos-next

# Step 6: Add service to test machine
cat > machines/test-refactor.nix << 'EOF'
{ config, lib, pkgs, ... }:
{
  imports = [
    /etc/nixos/hosts/server/hardware-configuration.nix
    ../modules/system/paths.nix
    ../modules/system/test.nix
    ../modules/services/ntfy.nix  # NEW!
  ];
  
  # Enable services
  hwc.test.enable = true;
  hwc.services.ntfy = {        # NEW!
    enable = true;
    port = 8093;
  };
  
  # Core config (unchanged from yesterday)
  networking.hostName = "test-refactor";
  networking.useDHCP = lib.mkDefault true;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  users.users.eric = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ];
  };
  
  # Container runtime (needed for ntfy)
  virtualisation.docker.enable = true;
  virtualisation.oci-containers.backend = "docker";
  
  services.openssh.enable = true;
  system.stateVersion = "24.05";
}
EOF

# Step 7: Build with service
sudo nixos-rebuild build --flake .#test-refactor
```

### 3:00 PM - Create Comparison Test ✅

```bash
# Step 8: Create validation script
cat > operations/validation/compare-services.sh << 'EOF'
#!/usr/bin/env bash

SERVICE="ntfy"

echo "=== Service Comparison: $SERVICE ==="

# Check old config
echo "Old config location: /etc/nixos/hosts/server/modules/"
ls -la /etc/nixos/hosts/server/modules/*ntfy* 2>/dev/null || echo "No ntfy in old"

# Check new config  
echo "New config location: /etc/nixos-next/modules/services/"
ls -la /etc/nixos-next/modules/services/ntfy.nix

# Compare outputs
echo ""
echo "Old build size:"
du -sh /etc/nixos/result 2>/dev/null || echo "No result link"

echo "New build size:"
du -sh /etc/nixos-next/result 2>/dev/null || echo "No result link"

echo ""
echo "✅ Service migrated (not activated, just configured)"
EOF
chmod +x operations/validation/compare-services.sh

# Step 9: Document the migration
cat > operations/MIGRATION_GUIDE.md << 'EOF'
# Service Migration Guide

## Migrated Services
1. ntfy - Day 3 - Simple container service

## Migration Process
1. Copy service from old location
2. Rewrite using hwc.services.* namespace
3. Use config.hwc.paths for all paths
4. Test module builds in isolation
5. Add to test machine
6. Validate build

## Next Services (by complexity)
- [ ] transcript-api (simple, no state)
- [ ] grafana (medium, has dashboards)
- [ ] jellyfin (complex, GPU + storage)
EOF

# Step 10: Commit progress
git add -A
git commit -m "Day 3: First service (ntfy) migrated"
```

## End of Day 3 Checklist

- [ ] First service module created
- [ ] Service builds in new structure
- [ ] Test machine includes service
- [ ] Documentation updated
- [ ] Old system still untouched

## Validation

```bash
# Final validation
cd /etc/nixos-next
./operations/validation/quick-check.sh
./operations/validation/compare-services.sh

# Check what was built
nix-store -q --tree ./result | head -20
```

## Weekend Homework (Optional)

If you want to continue:

1. Try migrating transcript-api (similar pattern)
2. Create a profile that groups services
3. Think about which services to migrate next week

**Day 3 Success**: One real service lives in the new structure!
