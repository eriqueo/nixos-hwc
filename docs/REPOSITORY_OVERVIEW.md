# NixOS HWC Repository - Comprehensive Overview

**Repository**: `/home/user/nixos-hwc`
**Platform**: NixOS (x86_64-linux)
**Current Branch**: `claude/agents-skills-workflows-01EEa8CKMsr8CZYTjyXe56Vn`
**Architecture Version**: Charter v6.0 (active implementation)

---

## 1. Overall Structure & Organization

### Philosophy
- **Domain-Separated Architecture**: Strict separation of concerns using domain boundaries
- **Declarative Everything**: All configuration, automation, and infrastructure declared as code
- **Reproducible & Maintainable**: Deterministic builds with clear ownership and patterns
- **Charter-Driven**: Architecture enforced through formal charter with automated linting
- **User-Centric**: Organization mirrors both system architecture and personal workflow (Filesystem Charter v2.0)

### Core Principle
The repository implements a sophisticated **domain-separated NixOS architecture** where:
1. Each domain handles a specific system interaction boundary
2. Modules organize around one logical concern per folder
3. Profiles serve as feature menus aggregating modules
4. Machines declare hardware facts and compose profiles
5. Namespace follows folder structure for debugging simplicity

### Build Flow
```
flake.nix (pins inputs)
  ↓
machines/<host>/config.nix (hardware facts + profile composition)
  ↓
profiles/system.nix, home.nix, server.nix (domain feature menus)
  ↓
domains/{system,home,infrastructure,server,secrets}/ (implementations)
  ↓
System rebuild + Home Manager activation
```

---

## 2. Main Directories & Their Purposes

### `/machines` - Host Configurations (2 machines)
**Purpose**: Hardware facts and profile composition for specific machines

```
machines/
├── laptop/
│   ├── config.nix          # Laptop-specific configuration & profile composition
│   ├── hardware.nix        # Hardware identification and boot settings
│   └── home.nix           # Home Manager user configuration
└── server/
    ├── config.nix         # Server-specific configuration & profile composition
    ├── hardware.nix       # Hardware identification and boot settings
    └── (home.nix via config)
```

**Machines**:
- **hwc-laptop**: Development machine with GPU, WinApps, desktop environment
- **hwc-server**: Production media/AI server with Quadro P1000, container services

### `/domains` - Implementation Domains (5 core domains)

#### `domains/system/` - NixOS Core
**Scope**: Operating system fundamentals (no Home Manager configs)
**Modules**:
- `core/` - Paths, networking, polkit, thermal management
- `services/` - Shell, hardware (audio/keyboard/bluetooth), session, backup, VPN
- `storage/` - Filesystem mounting and configuration
- `users/` - User account definitions (eric)
- `packages/` - System-level packages, development tools

**Key Options**: `hwc.system.*`, `hwc.networking.*`

#### `domains/home/` - User Environment (Home Manager)
**Scope**: Desktop environment, applications, shell configuration (no systemd services)
**Categories**:
- `apps/` - 27 applications including:
  - **Desktop**: Hyprland (WM), Waybar, Swaync (notifications)
  - **Terminals**: Kitty, Aerc (mail), Neomutt, Yazi (file manager)
  - **Browsers**: LibreWolf, Chromium
  - **Productivity**: Obsidian, OnlyOffice, N8N
  - **Security**: GPG, Proton Suite (Mail, Pass, Authenticator)
  - **Utilities**: Thunar, LocalSend, ipcalc, Wasistlos
- `core/` - Shell configuration (zsh, tmux, neovim)
- `environment/` - Environment variables, development tools
- `mail/` - Email configuration (Proton Bridge integration)
- `theme/` - Color palettes, theme adapters

**Key Options**: `hwc.home.apps.*`, `hwc.home.shell.*`

#### `domains/infrastructure/` - Hardware & Cross-Domain Orchestration
**Scope**: GPU, power management, virtualization, device integration
**Modules**:
- `hardware/` - GPU configuration (NVIDIA drivers, acceleration)
  - Laptop: NVIDIA RTX (PRIME with Intel iGPU)
  - Server: NVIDIA Quadro P1000 (legacy driver 580)
- `storage/` - Storage pool management, mounts, filesystem structure
- `virtualization/` - libvirt/QEMU, WinApps, VM management
- `winapps/` - Windows application integration via RDP

**Key Options**: `hwc.infrastructure.*`

#### `domains/server/` - Host-Provided Workloads
**Scope**: Services running on the machine for external access
**Modules**:
- **Container Services** (`containers/`):
  - Reverse proxy: Caddy
  - *Arr Stack*: Sonarr, Radarr, Lidarr, Prowlarr
  - Downloaders: qBittorrent, SABnzbd, SLSKD
  - Media processing: Tdarr, Beets
  - Discovery: JellySeerr, Organizr
  - Network: Gluetun (VPN container)
  - All ~20 containers managed via Podman

- **Native Services**:
  - **Media**: Jellyfin, Navidrome (music streaming)
  - **Photos**: Immich (photo/video management with ML)
  - **Monitoring**: Frigate (NVR - camera surveillance)
  - **Sync**: CouchDB (Obsidian LiveSync)

- **AI Services** (`ai/`):
  - Ollama (local LLM inference)
  - MCP server (Model Context Protocol for Claude)

- **Infrastructure**:
  - `networking/` - Network configuration, DNS, firewall
  - `storage/` - Container data paths, mount management
  - `backup/` - Backup automation (to Proton Drive)
  - `monitoring/` - Health checks, prometheus metrics
  - `business/` - Business application containers
  - `orchestration/` - Service coordination

**Key Options**: `hwc.server.*`

#### `domains/secrets/` - Encrypted Configuration
**Scope**: Sensitive data management via agenix
**Structure**:
- `declarations/` - Secret declarations (define which secrets exist)
- `parts/` - Encrypted `.age` files organized by domain:
  - `system/` - Emergency passwords, SSH keys
  - `infrastructure/` - VPN credentials, database passwords
  - `server/` - API keys (Sonarr, Radarr, etc.), admin credentials

**Security Model**:
- All secrets encrypted with age keys
- Stable API: `/run/agenix` for service access
- Permission model: `group = "secrets"; mode = "0440"`
- Service users must include `extraGroups = ["secrets"]`
- Fallback to hardcoded credentials if agenix unavailable

### `/profiles` - Domain Feature Menus (10 profiles)
**Purpose**: Aggregate domain modules as feature menus with BASE + OPTIONAL structure

```
profiles/
├── base.nix              # Foundation (paths, users, core services)
├── system.nix            # System services (shell, hardware, networking, backup)
├── home.nix              # Home Manager apps and environment
├── infrastructure.nix    # Hardware & virtualization
├── server.nix            # Server workloads (containers, media, AI)
├── security.nix          # Security hardening, emergency access
├── ai.nix                # AI services (Ollama, MCP)
├── media.nix             # Media services (Jellyfin, etc.)
├── business.nix          # Business tools & containers
└── monitoring.nix        # Monitoring infrastructure
```

**Structure Pattern**:
```nix
{
  # BASE SYSTEM - Required for boot/management
  imports = [ ../domains/system/index.nix ];
  
  # OPTIONAL FEATURES - Sensible defaults, machine-override
  hwc.system.services.shell.enable = true;
}
```

### `/workspace` - Declarative Automation
**Purpose**: Version-controlled scripts, utilities, and development projects

```
workspace/
├── automation/           # System & media workflow automation
│   ├── media-orchestrator.py      # Event-driven media workflow coordinator
│   ├── qbt-finished.sh            # qBittorrent post-processing
│   ├── sab-finished.py            # SABnzbd post-processing
│   └── bible/                     # AI-powered content processing
│
├── infrastructure/       # Deployment & management scripts
│   ├── filesystem/                # File system automation
│   │   ├── add-home-app.sh       # Add new Home Manager app
│   │   └── update-headers.sh     # Update file headers
│   └── vault-sync-system.nix     # Obsidian vault sync
│
├── network/             # Network analysis & security tools
│   ├── quicknet.sh                # Fast network triage
│   ├── advnetcheck.sh             # Advanced diagnostics
│   ├── homewifi-audit.sh          # WiFi security audit
│   └── wifibrute.sh               # WiFi testing tools
│
├── productivity/        # Personal automation
│   ├── transcript-formatter/      # AI transcript processing
│   └── music_duplicate_detector.sh
│
├── utilities/           # NixOS development tools
│   ├── config-validation/         # Config analysis & migration
│   ├── lints/                     # Charter compliance linting
│   │   ├── charter-lint.sh       # Main compliance checker
│   │   ├── autofix.sh            # Auto-fix charter violations
│   │   └── analyze-namespace.sh  # Namespace validation
│   ├── templates/                 # Code scaffolding
│   └── scripts/                   # Utility scripts
│
└── projects/            # Development projects
    └── site-crawler/              # Web scraping infrastructure
```

### `/docs` - Project Documentation
**Purpose**: Cross-domain guides, migrations, architectural decisions

```
docs/
├── README.md                       # Documentation hub
├── DOCUMENTATION_STANDARDS.md      # Doc guidelines
├── architecture/                   # Architectural docs
│   ├── NATIVE_VS_CONTAINER_ANALYSIS.md
│   ├── PROFILE_REFACTOR_GUIDE.md
│   └── compliance-lint.md
├── migrations/                     # Migration guides (SOPS→agenix, etc.)
├── projects/                       # Active/completed projects
│   ├── NEW-SERVICES-IMPLEMENTATION.md
│   ├── server-modular-framework.md
│   └── server-container-scaffolding.md
├── applications/                   # Application-specific guides
│   └── n8n_plan.md
└── templates/                      # Documentation templates
```

### `/.claude` - Claude Code Configuration
- `README.md` - Claude Code setup instructions
- `MCP-SERVERS.md` - MCP (Model Context Protocol) server configuration
- `settings.local.json` - Local Claude Code settings
- `commands/` - Custom slash commands

### `/.github/workflows` - CI/CD
- `ci.yml` - GitHub Actions workflow
  - `nix flake check` for all systems
  - Build server and laptop configurations
  - Deadcode detection (deadnix)
  - Nix linting (statix)

---

## 3. NixOS Configurations Present

### Hosts
**Two complete NixOS configurations**:

#### hwc-laptop
- **Type**: Development/Desktop workstation
- **Hardware**: Intel CPU + NVIDIA RTX, 32GB RAM, NVMe SSD
- **GPU**: NVIDIA with PRIME (hybrid with Intel iGPU)
- **Boot**: systemd-boot, EFI
- **Key Profiles**: system, home, infrastructure, security
- **DE**: Hyprland (wayland WM)
- **Storage**: `/home/eric/03-tech/local-storage` for dev work
- **State Version**: 24.05

#### hwc-server
- **Type**: Production media/AI server
- **Hardware**: Intel/AMD CPU, NVIDIA Quadro P1000 (Pascal), 16GB+ RAM
- **GPU**: NVIDIA Quadro P1000 (legacy driver 580)
- **Boot**: systemd-boot, EFI
- **Hostname ID**: 8425e349 (for ZFS)
- **Key Profiles**: system, home (headless), server, security, ai
- **Storage**: 
  - `/mnt/hot` - SSD hot storage
  - `/mnt/media` - HDD media storage
  - `/opt/*` - Container data
- **Services**: 20+ containers, 3 native media services, AI services
- **Firewall**: Server-level (restrictive by default)
- **Network Wait**: Yes (all interfaces, 90s timeout)
- **State Version**: 24.05

### Modules Architecture

Every module follows strict anatomy:
```
domains/<domain>/<concern>/
├── options.nix       # MANDATORY - API definition
├── index.nix         # Aggregator - implements logic
├── sys.nix          # Optional - system-lane code (co-located)
└── parts/           # Optional - pure functions, helpers
    ├── scripts.nix
    ├── config.nix
    └── ...
```

**Namespace Rule**: 
`domains/home/apps/firefox/` → `hwc.home.apps.firefox.*`

### Custom Module Count
- **System modules**: 10+ (core, users, services, packages)
- **Home modules**: 27+ applications (desktop, terminals, productivity, security)
- **Infrastructure modules**: 4 (hardware, storage, virtualization, winapps)
- **Server modules**: 20+ (containers + 10+ native services)
- **Secrets modules**: 20+ encrypted secrets across all domains

### Package Management
- **Unstable nixpkgs**: Primary, experimental features enabled
- **Stable nixpkgs** (24.05): Referenced for specific packages
- **nixvirt**: Virtualization infrastructure
- **home-manager**: Integrated as NixOS module
- **agenix**: Secrets management

---

## 4. Services & Applications Configured

### Desktop Environment (Laptop)
- **WM**: Hyprland (wayland, modern compositor)
- **Status Bar**: Waybar (with custom GPU monitoring)
- **Notifications**: SwayNC (desktop notifications)
- **Terminal**: Kitty (GPU-accelerated)
- **Shell**: Zsh + tmux + neovim
- **File Manager**: Yazi (TUI) + Thunar (GUI)

### Applications
**Browsers**:
- LibreWolf (privacy-focused Firefox fork)
- Chromium (Ungoogled builds)

**Productivity**:
- Obsidian (note-taking with Proton Bridge sync)
- OnlyOffice (office suite)
- N8N (workflow automation platform)

**Email & Communication**:
- Proton Mail (GUI + Proton Bridge integration)
- ProtonPass (password manager)
- Proton Authenticator (2FA)
- Neomutt (CLI mail client)
- Aerc (modern CLI mail)
- Thunderbird/Betterbird (email clients)

**Security & Development**:
- GPG (encryption, signing)
- Gemini CLI (Google AI integration)
- Google Cloud SDK
- OpenCode (IDE)

**Utilities**:
- LocalSend (LAN file sharing)
- Wasistlos (file recovery)
- Bottles (Windows app compatibility)
- ipcalc (IP calculator)

### Server Services

#### Container Stack (~20 containers)
**Reverse Proxy**:
- Caddy (reverse proxy, automatic HTTPS)

**Media Management** (*Arr stack):
- Sonarr (TV show management)
- Radarr (Movie management)
- Lidarr (Music library management)
- Prowlarr (Indexer management/search)
- JellySeerr (Request management)

**Downloaders**:
- qBittorrent (torrent)
- SABnzbd (Usenet)
- SLSKD (Soulseek - music)

**Media Processing**:
- Tdarr (transcoding automation)
- Beets (music metadata management)

**Organization**:
- Organizr (dashboard)

**Network**:
- Gluetun (VPN container)

**Data**:
- PostgreSQL (databases)

#### Native Services
- **Jellyfin** (8096) - Media streaming to LAN devices (Roku, etc.)
- **Navidrome** (4533) - Music streaming server
- **Immich** (2283) - Photo/video management with ML tagging
- **Frigate** (5000) - NVR for camera surveillance
- **CouchDB** (5984) - Obsidian LiveSync backend

#### AI Services
- **Ollama** - Local LLM inference
  - Models: qwen2.5-coder:3b, phi3:3.8b
  - Optimized for Quadro P1000 4GB VRAM
- **MCP Server** - Model Context Protocol for Claude
  - Filesystem MCP for `~/.nixos`
  - HTTP proxy on localhost:6001
  - Reverse proxy via Caddy at `/mcp-nixos`

#### System Services
- **Backup** - Rclone to Proton Drive
- **VPN** - ProtonVPN CLI integration
- **Monitoring** - Prometheus + Grafana
- **Logging** - Systemd journal management
- **Networking** - NetworkManager + Tailscale

---

## 5. Custom Modules & Specialized Configurations

### Architectural Patterns

#### 1. **Domain Separation**
- Strict boundaries between system/home/infrastructure/server/secrets
- One interaction boundary per domain
- Prevents circular dependencies
- Enables parallel maintenance

#### 2. **Profile System**
- BASE: Required for boot/management
- OPTIONAL: Sensible defaults, machine-override
- Example: `profiles/system.nix` imports domain implementations, machines choose which profiles to include

#### 3. **Options-First Architecture**
- All options defined in `options.nix`
- Implementation in `index.nix`
- Validation in `# VALIDATION` section
- Enables declarative configuration

#### 4. **Namespace Mapping**
- Folder path → option namespace
- `domains/home/apps/firefox/` → `hwc.home.apps.firefox.*`
- Aids debugging and discovering options

#### 5. **Co-located sys.nix Pattern**
- Home modules can have `sys.nix` for system-lane code
- Keeps related code together while respecting lanes
- Example: `domains/home/apps/kitty/sys.nix` for system packages

#### 6. **Secrets API**
- Stable interface at `/run/agenix`
- All services use same permission model
- Fallback to hardcoded credentials if unavailable
- Age key management for encryption

### Specialized Configurations

#### Laptop GPU Management
- NVIDIA PRIME hybrid graphics
- Automatic switching between dGPU and iGPU
- Smart power management (TLP, thermald)

#### Server GPU Acceleration
- NVIDIA Quadro P1000 (legacy driver 580)
- ONNX-based Frigate detection (no TensorRT)
- FP16 disabled for Pascal compatibility
- GPU memory limits (4GB VRAM)

#### WinApps Integration
- RDP to Windows VM
- Multi-monitor support
- Excel/Office app bridging

#### Container Networking
- Podman with custom networks
- Network boundaries prevent external device access
- Lesson learned: Native services preferred for LAN devices

#### Email Integration
- Proton Bridge as system service
- CLI wrapper for easy access
- Integration with Neomutt, Aerc, Thunderbird

#### Theme System
- Color palettes in `domains/home/theme/palettes/*.nix`
- Adapters transform to app-specific configs
- No hardcoded colors in app configs

#### Media Orchestration
- Event-driven automation (file watchers)
- Post-processing hooks (qBittorrent, SABnzbd)
- API integration with *Arr services
- Prometheus metric export

#### Monitoring Stack
- Prometheus for metrics
- Grafana for visualization
- Health checks for services
- Watchdog for Frigate

---

## 6. Deployment & Build Structure

### Flake Architecture
```nix
inputs:
  - nixpkgs (nixos-unstable)
  - nixpkgs-stable (24.05)
  - nixvirt (virtualization)
  - home-manager
  - agenix (secrets)
  - legacy-config (reference during migration)

outputs:
  - nixosConfigurations.hwc-laptop
  - nixosConfigurations.hwc-server
```

### Build Commands
```bash
# Build (evaluate, download, no switch)
sudo nixos-rebuild build --flake .#hwc-laptop

# Test (boots into new config, reverts on reboot)
sudo nixos-rebuild test --flake .#hwc-laptop

# Switch (activate permanently)
sudo nixos-rebuild switch --flake .#hwc-laptop

# Flake validation
nix flake check --all-systems
```

### State Versions
- Both machines: 24.05 (NixOS 24.05 LTS-equivalent behavior)
- Ensures forward compatibility with future nixpkgs updates

### Home Manager Integration
- Configured as NixOS module (not separate flake)
- Imports via `machines/<host>/home.nix`
- Activates during `nixos-rebuild switch`
- Per-machine configuration (laptop has GUI, server is headless)

### Secrets Deployment
1. Age key generated: `sudo age-keygen -y /etc/age/keys.txt`
2. Secret encrypted: `echo "value" | age -r <pubkey> > domains/secrets/parts/domain/name.age`
3. Committed to git
4. Decrypted at build time via agenix
5. Available at `/run/agenix` with secure permissions

---

## 7. Workflows, Secrets Management & Automation

### CI/CD Pipeline (.github/workflows/ci.yml)

**Runs on**: Pull requests, pushes to main

**Jobs**:

1. **nix-checks**
   - `nix flake check --all-systems`
   - Build hwc-server.config.system.build.toplevel
   - Build hwc-laptop.config.system.build.toplevel

2. **code-quality**
   - deadnix (dead code detection)
   - statix (Nix linter)

**Status**: Simple but effective validation

### Secrets Management (Agenix)

**Encrypted Secrets** (20+ files):

System domain:
- `emergency-password.age` - Fallback password
- `user-initial-password.age` - Initial user password
- `user-ssh-public-key.age` - SSH key

Infrastructure domain:
- Database credentials (user, password, name)
- VPN credentials (username, password)
- Camera credentials (Frigate RTSP)

Server domain:
- API keys (Sonarr, Radarr, Lidarr)
- Service credentials (CouchDB admin, SLSKD)
- NTFY user credentials

**Access Model**:
- All secrets: `group = "secrets"; mode = "0440"`
- Service users: `extraGroups = ["secrets"]`
- Runtime access: `/run/agenix`

**Emergency Access**:
- Hardcoded fallback password: `il0wwlm?`
- Automatic detection of agenix failure
- System warns when using fallback

### Automation Scripts

#### Media Orchestrator
- Event-driven coordination
- Watches `/mnt/hot/events` for completion
- Triggers Sonarr/Radarr/Lidarr rescans
- Prometheus metrics
- Deployed to `/opt/downloads/scripts/`

#### Post-Processing Hooks
- qBittorrent: `qbt-finished.sh` → event JSON
- SABnzbd: `sab-finished.py` → event JSON
- Both trigger media orchestrator

#### Backup Automation
- Rclone to Proton Drive
- Systemd timer-based
- Configurable schedule

#### Transcript Processing
- AI-powered transcript formatting (Ollama)
- Obsidian vault integration
- Desktop GUI prompts
- Automatic file monitoring

#### Network Tools
- Network diagnostics (quicknet, netcheck, advnetcheck)
- WiFi security auditing (homewifi-audit, wifibrute)
- Hardware overview
- Tool availability scanning

#### Code Quality Tools
**Charter Linting**:
- `workspace/utilities/lints/charter-lint.sh`
- Enforces domain boundaries
- Validates namespace compliance
- Checks options definitions
- Detects hardcoded paths
- Validates validation sections

**Autofix**:
- `workspace/utilities/lints/autofix.sh`
- Auto-corrects simple violations

### Environment Variables (XDG Integration)

Filesystem Charter mapped to system:
```
XDG_DOWNLOAD_DIR      → ~/000_inbox/downloads/
XDG_DOCUMENTS_DIR     → ~/100_hwc/110_documents/
XDG_PICTURES_DIR      → ~/500_media/pictures/
XDG_MUSIC_DIR         → ~/500_media/music/
XDG_VIDEOS_DIR        → ~/500_media/videos/
```

Configured in `domains/system/core/paths.nix`

### Workspace Automation

**Declarative Deployment**:
- Scripts stored in `workspace/`
- Deployed via systemd services during rebuild
- Automatic permission management
- Version-controlled and reproducible

**Integration Points**:
- Media services consume post-processing scripts
- Orchestration deploys automation
- Home Manager enables productivity tools
- Secrets domain provides API keys

---

## Architecture Quality & Compliance

### Charter Compliance (v6.0)

**Phases**:
- Phase 1 (Domain separation): ✅ Complete
- Phase 2 (Domain/Profile architecture): 🔄 In progress
- Phase 3 (Namespace alignment): ⏳ Pending
- Phase 4 (Validation & optimization): ⏳ Pending

**Validation**:
- Automated charter-lint tool
- Checks all hard blockers
- Detects common anti-patterns
- Part of CI pipeline

**Key Rules**:
- ✅ No HM in system domain
- ✅ No systemd services in home domain
- ✅ Options always in options.nix
- ✅ Validation sections present
- ✅ Namespace matches folder structure
- ✅ All modules have one concern

### Known Lessons Learned

1. **Jellyfin Container Isolation** (2025-10-31)
   - Containerized services isolated from LAN devices
   - Solution: Use native NixOS service for media servers
   - Container networks create routing barriers
   - Reference implementation in `/etc/nixos` vs HWC pattern

2. **Secrets Failover**
   - Agenix can fail at runtime
   - System has hardcoded fallback credentials
   - Automatic detection and warning
   - No manual intervention needed

3. **GPU Memory Optimization**
   - Quadro P1000 has 4GB VRAM
   - Ollama models carefully selected
   - FP16 disabled for Pascal support
   - TensorRT not available on amd64

---

## Specialized Agents & Skills Recommendations

Based on the repository structure, these specialized agents would be most useful:

### 🎯 **Recommended Agents**

1. **`nixos-hwc-architect`**
   - Domain boundary design and enforcement
   - New module creation and scaffolding
   - Profile composition planning
   - Architecture review and refactoring
   - Secrets management workflows
   - Cross-domain optimization

2. **`nixos-hwc-troubleshooter`**
   - Build failure debugging
   - Module conflicts and type errors
   - systemd service issues
   - Secret decryption/encryption problems
   - Performance optimization
   - Runtime error diagnosis

3. **Charter Linter Agent** (if possible)
   - Automated compliance checking
   - Namespace validation
   - Anti-pattern detection
   - Auto-fix recommendations

### 📚 **Specialized Skills for This Repo**

1. **Module Scaffolding** - Generate new modules following charter patterns
2. **Container Configuration** - Podman container setup and networking
3. **Secrets Management** - Age encryption/decryption workflows
4. **Media Service Configuration** - *Arr stack, Jellyfin, Immich setup
5. **Build Optimization** - Flake composition, reproducibility
6. **Documentation Generation** - Auto-generate docs from module structure
7. **Migration Assistance** - Migrate between architectures (container ↔ native)
8. **Monitoring Setup** - Prometheus, Grafana, health checks
9. **Email System Configuration** - Proton Bridge, Neomutt, Aerc integration
10. **Theme System Management** - Color palette and adapter management

---

## Key Statistics

| Aspect | Count |
|--------|-------|
| **Machines** | 2 (laptop, server) |
| **Domains** | 5 (system, home, infrastructure, server, secrets) |
| **Profiles** | 10+ (system, home, server, etc.) |
| **Home Applications** | 27+ (browsers, terminals, productivity, security) |
| **Server Containers** | 20+ (*Arr stack, downloaders, media) |
| **Server Native Services** | 5+ (Jellyfin, Navidrome, Immich, Frigate, CouchDB) |
| **System Modules** | 10+ (core, services, users, packages) |
| **Encrypted Secrets** | 20+ encrypted .age files |
| **Automation Scripts** | 15+ (media, network, productivity) |
| **Documentation Files** | 15+ guides and charters |
| **Lines of Nix Code** | 3000+ (excluding containers/configs) |
| **CI Jobs** | 2 (nix-checks, code-quality) |

---

## Getting Started with This Repository

### For Architecture Work
1. Read `/charter.md` (complete architecture)
2. Review `/FILESYSTEM-CHARTER.md` (home organization)
3. Study domain READMEs (`domains/*/README.md`)
4. Use `nixos-hwc-architect` agent

### For Troubleshooting
1. Check error logs carefully
2. Understand the build flow
3. Validate domain boundaries
4. Check secrets access
5. Use `nixos-hwc-troubleshooter` agent

### For New Features
1. Determine which domain owns the concern
2. Create module with `options.nix` + `index.nix`
3. Follow namespace pattern
4. Add to appropriate profile
5. Test with `nix flake check`
6. Rebuild and test on machine

### For Secrets
1. Get age public key: `sudo age-keygen -y /etc/age/keys.txt`
2. Encrypt: `echo "value" | age -r <pubkey> > domains/secrets/parts/domain/name.age`
3. Commit and rebuild
4. Access at `/run/agenix`

---

## Critical Files to Understand

1. **`flake.nix`** - Input pinning and system definitions
2. **`CHARTER.md`** - Architecture rules (MUST READ)
3. **`FILESYSTEM-CHARTER.md`** - Home directory organization
4. **`machines/*/config.nix`** - Machine composition
5. **`profiles/system.nix`** - System features menu
6. **`domains/*/README.md`** - Domain-specific documentation
7. **`workspace/utilities/lints/charter-lint.sh`** - Compliance checker
8. **`meta/CLAUDE.md`** - Working instructions for AI

---

**Document Generated**: 2025-11-18
**Repository Branch**: claude/agents-skills-workflows-01EEa8CKMsr8CZYTjyXe56Vn
**Charter Version**: v6.0
**Archive Version**: v2.0
