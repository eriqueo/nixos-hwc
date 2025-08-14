# Day 1: Foundation & Safety (2-3 hours total)

## Morning Session (1 hour)
### 9:00 AM - Safety Setup ✅

```bash
cd /etc/nixos

# Step 1: Commit current state
git status
git add -A
git commit -m "Pre-refactor snapshot: $(date +%Y-%m-%d)"

# Step 2: Create safety branches
git branch refactor-backup-$(date +%Y%m%d)
git checkout -b refactor-attempt-1

# Step 3: Document current generation
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -3 > generation-backup.txt

# Step 4: Test current builds
time sudo nixos-rebuild build --flake .#hwc-server
time sudo nixos-rebuild build --flake .#hwc-laptop
```

**CHECKPOINT**: Both builds should succeed. If not, STOP and fix.

### 10:00 AM - Create Parallel Structure ✅

```bash
# Step 5: Create new repository
sudo mkdir -p /etc/nixos-next
sudo chown -R $(whoami):users /etc/nixos-next
cd /etc/nixos-next
git init

# Step 6: Create directory structure
mkdir -p {modules,machines,lib,operations,tests}
mkdir -p modules/{system,services,infrastructure}
mkdir -p operations/{scripts,validation}

# Step 7: Create initial flake
cat > flake.nix << 'EOF'
{
  description = "Refactored NixOS Configuration";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.05";
  };
  
  outputs = { self, nixpkgs, nixpkgs-stable }: {
    nixosConfigurations = {
      # Machines will be added here
    };
  };
}
EOF

git add -A
git commit -m "Initial structure"
```

## Afternoon Session (1-2 hours)

### 2:00 PM - Create Tracking System ✅

```bash
cd /etc/nixos-next

# Step 8: Create migration tracking
cat > MIGRATION_LOG.md << 'EOF'
# Migration Log

## Day 1: $(date +%Y-%m-%d)
- [ ] Created backup: generation ___
- [ ] Created parallel structure at /etc/nixos-next
- [ ] Created base directories
- [ ] Initial flake created
- [ ] Test module created

## Status
- Old repo: /etc/nixos (untouched)
- New repo: /etc/nixos-next (empty)
- Can rollback: YES
EOF

# Step 9: Create validation script
cat > operations/validation/quick-check.sh << 'EOF'
#!/usr/bin/env bash
echo "=== Quick Validation ==="
echo "Old repo builds: $(cd /etc/nixos && nixos-rebuild build --flake .#hwc-server &>/dev/null && echo "✅" || echo "❌")"
echo "New repo exists: $([ -d /etc/nixos-next ] && echo "✅" || echo "❌")"
echo "Git status clean: $(cd /etc/nixos-next && git status --porcelain | wc -l | grep -q "^0$" && echo "✅" || echo "❌")"
EOF
chmod +x operations/validation/quick-check.sh
```

### 3:00 PM - First Test Module ✅

```bash
# Step 10: Create simplest possible module
cat > modules/system/test.nix << 'EOF'
{ config, lib, ... }:
{
  options.hwc.test = {
    enable = lib.mkEnableOption "Test module";
  };
  
  config = lib.mkIf config.hwc.test.enable {
    environment.etc."nixos-refactor-test.txt".text = "Working!";
  };
}
EOF

git add -A
git commit -m "Day 1 complete: Foundation established"
```

## End of Day 1 Checklist

- [ ] Old system still builds
- [ ] New structure created at /etc/nixos-next
- [ ] Git initialized in new structure
- [ ] Migration log started
- [ ] Test module created

## If Something Goes Wrong

```bash
# Just delete the new structure and start over tomorrow
sudo rm -rf /etc/nixos-next
cd /etc/nixos
git checkout main
```

**Day 1 Success Criteria**: New structure exists, old system untouched
