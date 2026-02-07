# NixOS HWC Quick Reference

**Last Updated**: 2026-01-08
**Charter Version**: v6.0

---

## Common Tasks (< 2 minutes each)

### Rebuild & Test
```bash
nix flake check                                    # Validate all configs
sudo nixos-rebuild test --flake .#hwc-laptop      # Test without activation
sudo nixos-rebuild switch --flake .#hwc-laptop    # Apply changes
```

### Add New Home App Module
```bash
mkdir -p domains/home/apps/myapp/parts
./workspace/nixos/add-home-app.sh myapp           # Scaffold structure
# Edit options.nix, index.nix following Charter
./workspace/nixos/charter-lint.sh domains/home/apps/myapp --fix
```

### Debug Service Failures
```bash
systemctl status <service>                         # Check service status
journalctl -u <service> -n 50 --no-pager          # View last 50 log lines
systemctl --user status <service>                  # For user services
./workspace/diagnostics/fix-service-permissions.sh <service>
```

### Secret Management
```bash
# Add new secret
./workspace/utilities/secret-manager.sh add domain/secret-name

# View secret
./workspace/utilities/secret-manager.sh lookup secret-name

# Edit secret
./workspace/utilities/secret-manager.sh edit secret-name
```

### Health Checks
```bash
./workspace/monitoring/service-health-summary.sh   # Quick health overview
./workspace/monitoring/health-check.sh             # System health (JSON)
./workspace/monitoring/gpu-monitor.sh              # GPU usage
systemd-analyze blame | head -20                   # Boot time analysis
```

---

## Common Issues & Fixes

### Issue: Service Won't Start
**Symptoms**: `systemctl status` shows "failed" or "inactive (dead)"

**Debug Steps**:
1. Check logs: `journalctl -u <service> -n 50`
2. Check permissions: `./workspace/diagnostics/fix-service-permissions.sh <service>`
3. Check dependencies: Review VALIDATION section in module's index.nix
4. Verify secrets: `ls -la /run/agenix/<secret-name>`

### Issue: Rebuild Hangs
**Symptoms**: `nixos-rebuild` stuck at "restarting sysinit-reactivation.target"

**Debug Steps**:
1. Check degraded services: `systemctl --failed`
2. Check user services: `systemctl --user --failed`
3. Review recent service changes in domains/home/
4. Check journal: `journalctl --since "5 minutes ago" -p err`

**Common Causes**:
- Service crash loops (check Restart= and RestartSec= settings)
- Missing dependencies (service starts before dependency available)
- Certificate/credential issues (services fail silently)

### Issue: Module Not Loading
**Symptoms**: Options not recognized, service not created

**Debug Steps**:
1. Verify module imported in profile: `rg "domains/path/to/module" profiles/`
2. Check options.nix namespace matches folder: `cat domains/.../options.nix`
3. Run charter lint: `./workspace/nixos/charter-lint.sh domains/...`
4. Validate flake: `nix flake check`

### Issue: Permission Denied
**Symptoms**: Service can't access files/secrets

**Debug Steps**:
1. Check service user: `systemctl show <service> | grep -E 'User=|Group='`
2. Check file permissions: `ls -la /path/to/file`
3. For secrets: Ensure service user in `secrets` group (`extraGroups = [ "secrets" ]`)
4. Run permission fix: `./workspace/diagnostics/fix-service-permissions.sh <service>`

---

## File Patterns

### Module Anatomy (Required)
```
domains/<domain>/<category>/<module>/
├── options.nix      # API definition (hwc.<domain>.<category>.<module>.*)
├── index.nix        # Implementation (OPTIONS → IMPLEMENTATION → VALIDATION)
├── sys.nix          # System-lane config (optional)
└── parts/           # Pure helper functions (optional)
    ├── config.nix
    ├── scripts.nix
    └── packages.nix
```

### index.nix Template
```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.domain.category.module;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Configuration here
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  config.assertions = lib.mkIf cfg.enable [
    {
      assertion = config.dependency.enable;
      message = "module requires dependency to be enabled";
    }
  ];
}
```

### options.nix Template
```nix
{ lib, ... }:
{
  options.hwc.domain.category.module = {
    enable = lib.mkEnableOption "Enable module description";

    # Additional options here
  };
}
```

---

## Decision Trees

### "Where Should This Go?"
- **User application** → `domains/home/apps/<name>/`
- **System service** → `domains/system/services/<name>/`
- **Container service** → `domains/server/containers/<name>/`
- **Native server app** → `domains/server/native/<name>/`
- **Hardware config** → `domains/infrastructure/hardware/<name>/`
- **Secret** → `domains/secrets/parts/<domain>/<name>.age`

### "Which Tool Should I Use?"
- **Charter compliance** → `./workspace/nixos/charter-lint.sh`
- **Secret management** → `./workspace/utilities/secret-manager.sh`
- **Health monitoring** → `./workspace/monitoring/service-health-summary.sh`
- **Service permissions** → `./workspace/diagnostics/fix-service-permissions.sh`
- **Module scaffolding** → `./workspace/nixos/add-home-app.sh`

### "How Do I Debug This?"
- **Build failures** → `nix flake check --show-trace`
- **Service failures** → `journalctl -u <service> -n 100`
- **Permission issues** → `./workspace/diagnostics/fix-service-permissions.sh`
- **Network issues** → `./workspace/diagnostics/network/`
- **GPU issues** → `./workspace/diagnostics/check-gpu-acceleration.sh`

---

## Namespace Mapping Reference

**Folder Path** → **Option Namespace**

```
domains/home/apps/firefox/           → hwc.home.apps.firefox.*
domains/system/core/networking/      → hwc.system.core.networking.*
domains/server/containers/caddy/     → hwc.server.containers.caddy.*
domains/infrastructure/hardware/gpu/ → hwc.infrastructure.hardware.gpu.*
domains/secrets/                     → hwc.secrets.*
```

---

## Essential Commands by Task

### Daily Development
```bash
# Check what changed
git status
git diff

# Validate changes
nix flake check
./workspace/nixos/charter-lint.sh domains/<changed-domain>

# Test without activating
sudo nixos-rebuild test --flake .#hwc-laptop

# Apply changes
sudo nixos-rebuild switch --flake .#hwc-laptop
```

### Troubleshooting
```bash
# System overview
./workspace/monitoring/service-health-summary.sh

# Failed services
systemctl --failed
systemctl --user --failed

# Recent errors
journalctl --since "10 minutes ago" -p err --no-pager

# Service details
systemctl status <service>
journalctl -u <service> -n 100 --no-pager

# Container logs
podman logs <container>
```

### Maintenance
```bash
# Update dependencies
nix flake update
git diff flake.lock  # Review changes
nix flake check

# Garbage collection
nix-collect-garbage -d
sudo nix-collect-garbage -d

# Check disk usage
df -h
du -sh /nix/store

# Optimize store
nix-store --optimize
```

---

## Secret Management Quick Reference

### Permission Model
All secrets use: `group = "secrets"; mode = "0440"`
Service users need: `extraGroups = [ "secrets" ]`

### Common Operations
```bash
# Get public key
sudo age-keygen -y /etc/age/keys.txt

# Encrypt new secret
echo "secret-value" | age -r <pubkey> > domains/secrets/parts/domain/name.age

# Decrypt to verify
sudo age -d -i /etc/age/keys.txt domains/secrets/parts/domain/name.age

# Use secret-manager helper
./workspace/utilities/secret-manager.sh add domain/secret-name
./workspace/utilities/secret-manager.sh lookup secret-name
```

---

## Performance Tips

### Fast Rebuilds
- Use `nixos-rebuild test` for iteration (no bootloader update)
- Run `nix flake check` before rebuilding (catches errors faster)
- Keep services from crash-looping (adds 30-60s to rebuilds)

### Build Optimization
- Use `--show-trace` only when debugging (slower evaluation)
- Leverage `cachix` for binary caches (if configured)
- Run `nix-store --optimize` periodically (deduplicates files)

### Health Monitoring
- Run `./workspace/monitoring/service-health-summary.sh` after rebuilds
- Check `systemctl --failed` before troubleshooting
- Use `systemd-analyze blame` to identify slow boot services

---

## Links to Full Documentation

- **Architecture**: `CHARTER.md` - Domain boundaries and module anatomy
- **AI Guide**: `CLAUDE.md` - Comprehensive guide for AI assistants
- **Filesystem**: `FILESYSTEM_CHARTER.md` - Home directory organization
- **Standards**: `docs/standards/HWC_STANDARDS.md` - Coding standards
- **Permissions**: `docs/troubleshooting/permissions.md` - Permission troubleshooting
- **Agent Guidelines**: `AGENTS.md` - Repository best practices

---

## Quick Diagnostic Commands

```bash
# Everything at once
./workspace/monitoring/service-health-summary.sh

# Individual checks
systemctl list-units --type=service --state=failed   # Failed system services
systemctl --user list-units --type=service --state=failed  # Failed user services
podman ps -a --filter "status=exited"                # Stopped containers
journalctl -b -p err --no-pager | tail -20           # Boot errors
df -h                                                  # Disk space
```

---

**For emergencies**: See `docs/troubleshooting/` directory
**For new contributors**: Start with `CHARTER.md` and `CLAUDE.md`
