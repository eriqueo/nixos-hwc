# NixOS Configuration

## Structure
This repository contains a modular NixOS configuration using flakes.

### Directory Layout
- `modules/` - Reusable NixOS modules
- `profiles/` - Composable configuration profiles
- `machines/` - Machine-specific configurations
- `operations/` - Operational scripts and tools
- `tests/` - Testing framework
- `secrets/` - Encrypted secrets (SOPS)

## Quick Start

### Build Configuration
```bash
sudo nixos-rebuild build --flake .#hwc-server
```

### Apply Configuration
```bash
sudo nixos-rebuild switch --flake .#hwc-server
```

### Run Tests
```bash
./operations/validation/validate-all.sh
```

## Machines
- `hwc-server` - Main server (media, monitoring, AI)
- `hwc-laptop` - Personal laptop

## Profiles
- `base` - Common configuration
- `media` - Media services (Jellyfin, ARR stack)
- `monitoring` - Prometheus & Grafana
- `ai` - AI/ML services
- `security` - Security hardening

## Management

### Update System
```bash
nix flake update
sudo nixos-rebuild switch --flake .#$(hostname)
```

### Add New Service
1. Create module in `modules/services/`
2. Add to appropriate profile
3. Test with `nixos-rebuild build`
4. Deploy with `nixos-rebuild switch`

## Documentation
- [Architecture](docs/ARCHITECTURE.md)
- [Security Guide](docs/SECURITY_GUIDE.md)
- [Service Catalog](docs/SERVICE_CATALOG.md)
