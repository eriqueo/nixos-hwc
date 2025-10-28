# System Domain

## Purpose & Scope

The **System Domain** provides **core OS functionality** - the essential system services, configurations, and capabilities that form the foundation of the NixOS system. This domain owns daemons, manages system state, and provides the baseline functionality that other domains build upon.

**Key Principle**: If it's a fundamental OS capability or owns a system daemon → system domain. The system domain is the "operating system core" that everything else depends on.

## Domain Structure

```
domains/system/
├── index.nix                    # Domain aggregator
├── core/                        # Essential OS functionality  
│   ├── networking.nix          # Network configuration & DNS
│   ├── filesystem.nix          # Filesystems & mount management
│   └── users.nix              # User account management
├── services/                    # System-level services
│   ├── session.nix            # Login managers & session control
│   ├── behavior.nix           # Input/audio system behavior
│   └── samba.nix             # File sharing daemon
└── packages/                   # System package collections
    ├── base.nix              # Essential system tools
    ├── server.nix            # Server administration tools
    └── desktop.nix           # Desktop system packages
```

## Core Modules (`core/`)

### 🌐 Networking (`networking.nix`)
**Network configuration, DNS, and connectivity**

**Provides:**
- VLAN configuration and bridging
- Static routes and DNS settings
- Network optimization (TCP tuning, connection tracking)
- MTU configuration for interfaces

**Option Pattern:**
```nix
hwc.networking = {
  enable = true;
  vlans = {
    management = { id = 10; interface = "eth0"; };
    storage = { id = 20; interface = "eth0"; };
  };
  bridges = { br0 = { interfaces = [ "eth0" "eth1" ]; }; };
  staticRoutes = [
    { destination = "10.0.0.0/8"; gateway = "192.168.1.1"; }
  ];
  dnsServers = [ "1.1.1.1" "8.8.8.8" ];
  search = [ "local" "company.com" ];
  mtu = 1500;
};
```

**Data Flow:**
```
Machine declares network reality → Networking module configures interfaces
       ↓
VLAN/bridge setup → Network topology established
       ↓  
DNS configuration → Name resolution working
       ↓
Services → Can bind to interfaces and communicate
```

### 📁 Filesystem (`filesystem.nix`)  
**Filesystem setup and directory structure management**

**Provides:**
- Security directory structure (/etc/age/, /run/agenix/)
- Server storage hierarchy (hot/cold/media/backup)
- Business directory structure (AI, BI, analysis)
- Service configuration directories (*ARR stack)
- User PARA directory structure

**Option Pattern:**
```nix
hwc.infrastructure.filesystemStructure = {
  enable = true;
  securityDirectories.enable = true;    # /etc/age, /run/agenix
  serverStorage.enable = true;          # /mnt/hot, /mnt/cold, etc.
  businessDirectories.enable = true;    # /opt/ai, /opt/bi
  serviceDirectories.enable = true;     # /etc/radarr, /etc/sonarr
  userDirectories.enable = true;        # ~/Projects, ~/Areas, etc.
};
```

**Implementation:**
```nix
systemd.tmpfiles.rules = [
  "d /etc/age 0755 root root -"
  "d /run/agenix 0750 root root -"  
  "d /mnt/hot 0755 root users -"
  "d /opt/ai/models 0755 root users -"
  # etc...
];
```

### 👥 Users (`users.nix`)
**User account and authentication management**  

**Provides:**
- User account creation and configuration
- SSH key management (secrets + fallback)
- Group membership and permissions
- ZSH environment setup

**Option Pattern:**
```nix
hwc.system.users = {
  enable = true;
  user = {
    enable = true;
    name = "eric"; 
    useSecrets = true;  # Use agenix for password/SSH keys
    fallbackPassword = "emergency123";  # When secrets unavailable
    groups = {
      basic = true;     # wheel, networkmanager
      media = true;     # audio, video, input
      hardware = true;  # dialout, gpio, spi
    };
    ssh = {
      enable = true;
      useSecrets = true;
      fallbackKey = "ssh-rsa AAAAB3...";
    };
    environment.enableZsh = true;
  };
};
```

**Data Flow:**  
```
System boot → User accounts created
       ↓
Agenix → Passwords/SSH keys decrypted (if available)
       ↓
Infrastructure permissions → User added to hardware groups  
       ↓
User login → SSH keys, shell, environment ready
       ↓
Home Manager → User applications can access system resources
```

## Services Modules (`services/`)

### 🔐 Session (`session.nix`)
**Login managers and session control**

**Provides:**  
- Display manager configuration (GDM/SDDM/etc.)
- Session startup and management
- Sudo configuration and privilege escalation
- User session environment

**Option Pattern:**
```nix  
hwc.system.services.session = {
  enable = true;
  loginManager = {
    enable = true;
    defaultUser = "eric";
    defaultCommand = "Hyprland";
    autoLogin = true;
  };
  sudo = {
    enable = true;
    wheelNeedsPassword = false;  # Convenience vs security tradeoff
  };
};
```

### ⌨️ Behavior (`behavior.nix`)
**Input devices and audio system behavior**

**Provides:**
- Keyboard configuration and function key behavior
- Audio system setup (PipeWire/PulseAudio)
- Input device management
- System-wide input behavior

**Option Pattern:**
```nix
hwc.system.services.behavior = {
  enable = true;
  keyboard = {
    enable = true;
    universalFunctionKeys = true;  # F1-F12 work across all apps
    layout = "us";
  };
  audio = {
    enable = true;
    backend = "pipewire";  # or "pulseaudio"
    lowLatency = false;
  };
};
```

### 📂 Samba (`samba.nix`)
**File sharing daemon and SMB/CIFS services**

**Provides:**
- SMB file sharing with modern Windows compatibility
- User-defined share configuration
- Network printer sharing integration
- Guest access controls

**Option Pattern:**
```nix
hwc.services.samba = {
  enable = true;
  workgroup = "WORKGROUP";
  shares = {
    projects = {
      path = "/home/eric/Projects";
      browseable = true;
      readOnly = false;
      guestAccess = false;
    };
  };
  enableSketchupShare = true;  # Predefined VM share
};
```

## Package Modules (`packages/`)

### 📦 Base Packages (`base.nix`)
**Essential system tools and utilities**

**Provides:**
- Core command-line tools (grep, sed, awk, coreutils)
- System administration utilities
- Network debugging tools
- Text editors and development basics

**Option Pattern:**
```nix
hwc.system.basePackages = {
  enable = true;
  modernUnix = true;      # bat, exa, fd, ripgrep alternatives
  development = true;     # git, vim, basic dev tools
  networking = true;      # curl, wget, nmap, traceroute
};
```

### 🖥️ Server Packages (`server.nix`)  
**Server administration and monitoring tools**

**Provides:**
- Container management tools (podman, docker-compose)
- Monitoring utilities (htop, btop, iotop)
- Server debugging tools
- System analysis utilities

**Option Pattern:**
```nix
hwc.system.serverPackages = {
  enable = true;
  containers = true;      # podman, compose tools
  monitoring = true;      # system monitoring utilities
  debugging = true;       # network and system debugging
};
```

## System Domain Integration Patterns

### Foundational Layer
System domain provides the base that other domains build on:

```nix
# System provides user accounts
hwc.system.users.user.name = "eric";

# Infrastructure can reference the user  
config.infrastructure.permissions.username = config.hwc.system.users.user.name;

# Services can run as the user
systemd.services.user-service.serviceConfig.User = config.hwc.system.users.user.name;
```

### Service Dependencies
Other domains depend on system services:

```nix
# System provides networking
hwc.networking.enable = true;

# Services domain can bind to network
services.jellyfin.bind = "0.0.0.0:8096";  # Network available

# Infrastructure can configure firewall  
hwc.infrastructure.mesh.expose.jellyfin = { port = 8096; };
```

### Package Foundation
System packages provide tools for other domains:

```nix  
# System provides base tools
hwc.system.basePackages.enable = true;

# Services can use system commands in scripts
systemd.services.backup.script = ''
  ${pkgs.rsync}/bin/rsync ...  # rsync from base packages
'';

# Home Manager can assume basic tools exist
programs.git.enable = true;  # git from system base packages
```

## System Domain Validation

### Check User Setup
```bash
# Verify user account and groups
id $USER
groups $USER

# Check SSH access  
ssh-add -l
cat ~/.ssh/authorized_keys
```

### Check Network Configuration
```bash
# Verify networking
ip addr show
resolvectl status

# Test DNS resolution
dig google.com
```

### Check System Services
```bash
# Check login manager
systemctl status display-manager

# Check audio system
systemctl --user status pipewire
```

### Check Filesystem Structure
```bash
# Verify system directories  
ls -la /etc/age/
ls -la /run/agenix/
ls -la /mnt/

# Check user directories
ls -la ~/Projects ~/Areas ~/Resources ~/Archive
```

## Anti-Patterns

**❌ Don't put application services in system domain**:
```nix
# Wrong - application services belong in services domain
systemd.services.jellyfin = { ... };  # Services domain job
```

**❌ Don't put user applications in system packages**:
```nix  
# Wrong - user apps belong in home domain
environment.systemPackages = [ pkgs.chromium ];  # Home domain job
```

**❌ Don't implement hardware drivers**:
```nix
# Wrong - hardware integration belongs in infrastructure  
hardware.nvidia.enable = true;  # Infrastructure domain job
```

**✅ Do provide foundational OS capabilities**:
```nix
# Correct - core system functionality
users.users.eric = { ... };
networking.networkmanager.enable = true;
systemd.services.sshd.enable = true;
```

**✅ Do own system daemons**:
```nix
# Correct - fundamental system services
services.openssh = { ... };
services.networkmanager = { ... };
systemd.services.display-manager = { ... };
```

**✅ Do provide stable interfaces for other domains**:
```nix
# Correct - other domains can reference system state
options.hwc.system.users.user.name = lib.mkOption { ... };
config.hwc.paths.user.home = "/home/${config.hwc.system.users.user.name}";
```

## Recent Changes & Evolution

### ✅ Audit Log Management (October 2024)
Critical fix to prevent disk space issues:
- **Log rotation configuration**: Added proper auditd.conf with 100MB files, 5 file rotation
- **Space thresholds**: 2GB/1GB warning levels with syslog actions
- **Emergency fix**: Resolved 282GB audit.log that consumed 97% disk space
- **Prevention**: Automated log management prevents future disk crises

### ✅ Workspace Foundation (October 2024)
System domain now provides foundation for workspace integration:
- **Directory structure**: Proper hierarchy for workspace automation
- **User permissions**: Enhanced group management for workspace scripts
- **Service integration**: Foundation for workspace script deployment

### ✅ Filesystem Structure Maturity
- **Security directories**: Proper /etc/age/ and /run/agenix/ structure
- **Server storage**: Enhanced hot/cold/media directory organization
- **User PARA structure**: Projects/Areas/Resources/Archive organization
- **Service directories**: Comprehensive service configuration paths

## Validation & Health Checks

### Critical System Health
```bash
# Check disk usage (prevent audit log crisis)
df -h /
sudo du -sh /var/log/audit/

# Verify audit rotation is working
sudo ls -lah /var/log/audit/
```

### User Account Validation
```bash
# Verify user setup
id $USER
groups $USER

# Check SSH configuration
ssh-add -l
cat ~/.ssh/authorized_keys
```

### Network and Services
```bash
# Network status
ip addr show
resolvectl status

# Critical services
systemctl status display-manager
systemctl status sshd
systemctl --user status pipewire
```

## Troubleshooting Common Issues

### Disk Space Crisis
**Symptoms**: System becomes unresponsive, can't write files
**Cause**: Audit logs growing without rotation
**Solution**:
```bash
# Emergency: Truncate large audit log
sudo truncate -s 0 /var/log/audit/audit.log

# Permanent: Verify rotation config
sudo cat /etc/audit/auditd.conf | grep -E "(max_log_file|num_logs)"
```

### User Authentication Issues
**Symptoms**: Can't login, SSH keys not working
**Cause**: Agenix secrets not decrypted or fallback not working
**Solution**:
```bash
# Check agenix status
sudo ls -la /run/agenix/

# Verify fallback password works
sudo passwd eric

# Check SSH key deployment
sudo cat /etc/age/keys.txt
```

### Network Connectivity Problems
**Symptoms**: No internet, DNS not resolving
**Cause**: Network configuration or DNS issues
**Solution**:
```bash
# Check network manager
systemctl status NetworkManager

# Test DNS
dig @1.1.1.1 google.com
resolvectl flush-caches
```

## Future Roadmap

### Short-term (Next Quarter)
- **Enhanced audit management**: More sophisticated log analysis and alerting
- **Advanced filesystem structure**: Better service directory organization
- **Improved user management**: More granular permission controls

### Medium-term
- **System monitoring integration**: Proactive health monitoring
- **Advanced networking**: Better VLAN and bridge management
- **Enhanced security**: More comprehensive security hardening

---

**Domain Version**: v3.0 - Foundational OS with workspace integration and audit management
**Charter Compliance**: ✅ Full compliance with HWC Charter v6.0
**Last Updated**: October 2024 - Post audit crisis resolution and workspace foundation

The system domain forms the **foundational layer** of the NixOS configuration, providing the essential OS services and capabilities that all other domains depend on. It focuses on **core system functionality** while maintaining clean interfaces for integration with higher-level domains.