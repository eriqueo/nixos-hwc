# NixOS Translator

A tool to convert NixOS configurations into distro-agnostic Universal IR that can be transformed into configurations for any Linux distribution (Arch, Ubuntu, Fedora, etc.).

## Concept

```
NixOS Config → Universal IR → [Arch | Ubuntu | Fedora | etc.]
              (YAML files)     (distro-specific configs)
```

## Features

- **Service Scanner**: Finds all enabled services (`.enable = true` patterns)
- **Package Extractor**: Extracts system and home packages
- **Container Scanner**: Finds OCI container definitions
- **Universal IR Generator**: Creates distro-agnostic YAML representation
- **Arch Backend**: Generates Arch-specific package lists and installation guides
- **Extensible**: Easy to add new distro backends (Ubuntu, Fedora, etc.)

## Architecture

### Scanners
- `service_scanner.py` - Extracts enabled services from NixOS configs
- `package_scanner.py` - Extracts package lists (system & home)
- `container_scanner.py` - Extracts container definitions

### Generators
- `universal_ir.py` - Creates Universal Intermediate Representation (YAML)
- `arch_backend.py` - Generates Arch Linux specific configs
- *Future*: `ubuntu_backend.py`, `fedora_backend.py`, etc.

## Usage

### Step 1: Export NixOS config to Universal IR

```bash
./nixos-translator.py export \
  --source /home/user/nixos-hwc \
  --output /tmp/translated \
  --verbose
```

**Output:**
```
/tmp/translated/universal-hwc/
├── services.yml      # Service definitions
├── packages.yml      # Package lists
├── containers.yml    # Container configs
└── README.md         # Documentation
```

### Step 2: Generate Arch Linux configs

```bash
./nixos-translator.py generate \
  --source /tmp/translated/universal-hwc \
  --target arch \
  --output /tmp/translated \
  --verbose
```

**Output:**
```
/tmp/translated/arch-hwc/
├── packages/
│   ├── pacman.txt              # Official packages
│   ├── aur.txt                 # AUR packages
│   └── install-packages.sh     # Installer script
├── systemd/
│   └── system/                 # Service units (TBD)
├── SERVICES.md                 # Service overview
└── README.md                   # Installation guide
```

## Universal IR Format

The Universal Intermediate Representation uses YAML to describe your system:

### services.yml
```yaml
metadata:
  generated_at: "2025-01-18T12:00:00"
  format_version: "1.0"

services:
  server:
    - name: jellyfin
      nixos_path: hwc.server.jellyfin.enable
      type: native
      port: 8096
      requires_gpu: true

  containers:
    - name: sonarr
      nixos_path: hwc.services.containers.sonarr.enable
      type: container
      port: 8989
```

### packages.yml
```yaml
metadata:
  generated_at: "2025-01-18T12:00:00"

packages:
  system:
    - nixos_name: git
      category: development
      mappings:
        arch: git
        ubuntu: git
        fedora: git

    - nixos_name: hyprland
      category: desktop
      mappings:
        arch: hyprland
        ubuntu: "hyprland (PPA)"
        fedora: "hyprland (COPR)"
```

### containers.yml
```yaml
metadata:
  note: "These can be directly translated to docker-compose.yml"

containers:
  - name: gluetun
    image: qmcgaw/gluetun
    ports: []
    source_file: domains/server/downloadarr/gluetun/index.nix

  - name: sonarr
    image: lscr.io/linuxserver/sonarr
    ports: ["8989:8989"]
    source_file: domains/server/containers/sonarr/index.nix
```

## Extending to Other Distros

To add a new distro backend (e.g., Ubuntu):

1. Create `generators/ubuntu_backend.py`
2. Implement `generate(universal_path, output_path)` method
3. Map package names (`nixos → apt packages`)
4. Generate distro-specific configs
5. Update `nixos-translator.py` to support `--target ubuntu`

## Limitations

This is a **proof-of-concept** translator. Current limitations:

1. **Simplified Nix parsing**: Uses regex, not full Nix AST evaluation
2. **Container details**: Basic extraction (image, ports), not full config
3. **No dotfiles**: Home-manager dotfiles need manual extraction
4. **No secrets**: Secret management needs manual setup (SOPS recommended)
5. **No system config**: Users, networking, firewall need manual configuration
6. **Service units**: Systemd units not auto-generated yet

## Future Improvements

- [ ] Full Nix AST parsing for accurate extraction
- [ ] Auto-generate systemd service units
- [ ] Extract home-manager dotfiles → GNU Stow structure
- [ ] Docker Compose generator from container definitions
- [ ] Ubuntu backend
- [ ] Fedora backend
- [ ] Secrets migration helper (agenix → SOPS)
- [ ] System configuration translation (users, networking, etc.)

## Dependencies

```bash
# Install PyYAML
pip install pyyaml
```

## Testing

Run the translator on your NixOS config:

```bash
# Export to universal format
./nixos-translator.py export \
  --source /home/user/nixos-hwc \
  --output ~/translated \
  --verbose

# Generate Arch configs
./nixos-translator.py generate \
  --source ~/translated/universal-hwc \
  --target arch \
  --output ~/translated \
  --verbose

# Review output
tree ~/translated
```

## License

Part of the nixos-hwc workspace utilities.
