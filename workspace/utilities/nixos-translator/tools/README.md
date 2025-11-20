## Migration Tools for NixOS → Any Distro

**Complete toolkit for migrating from NixOS to other Linux distributions while preserving your entire system configuration.**

These tools address the critical gaps in the basic nixos-translator:
1. ✅ Accurate config extraction (using `nix eval` instead of regex)
2. ✅ Secrets migration (agenix → SOPS)
3. ✅ Dotfiles extraction (home-manager → GNU Stow)
4. ✅ GPU setup automation (NVIDIA/AMD/Intel)
5. ✅ Volume/path initialization
6. ✅ Validation suite (pre/post checks)

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────┐
│           NixOS Machine (SOURCE)                     │
│                                                      │
│  ┌──────────────────┐   ┌─────────────────┐        │
│  │ nix-evaluator.py │   │ migrate-secrets │        │
│  │ (evaluate config)│   │  (decrypt age)  │        │
│  └────────┬─────────┘   └────────┬────────┘        │
│           │                      │                  │
│           ▼                      ▼                  │
│  containers-evaluated.json   secrets-export/       │
│                                                      │
│  ┌──────────────────────────────────────┐          │
│  │ extract-dotfiles.sh                   │          │
│  │ (copy home-manager configs)           │          │
│  └─────────────────┬─────────────────────┘          │
│                    │                                 │
│                    ▼                                 │
│               dotfiles-export/                       │
└────────────────────────────────────────────────────┘
                     │
                     │ Transfer to Arch
                     ▼
┌─────────────────────────────────────────────────────┐
│           Arch Machine (TARGET)                      │
│                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────┐│
│  │  setup-gpu   │  │setup-volumes │  │validate.sh  ││
│  │   (drivers)  │  │  (dirs/perms)│  │ (checks)    ││
│  └──────┬───────┘  └──────┬───────┘  └─────┬──────┘│
│         │                  │                │        │
│         └──────────────────┴────────────────┘        │
│                         │                            │
│                         ▼                            │
│                  Deployed System                     │
│         (containers + services + dotfiles)           │
└─────────────────────────────────────────────────────┘
```

---

## 📦 Tools Overview

| Tool | Runs On | Purpose | Priority |
|------|---------|---------|----------|
| `nix-evaluator.py` | NixOS | Extract evaluated configs (fixes 80% of extraction issues) | 🔴 CRITICAL |
| `migrate-secrets.sh` | NixOS | Decrypt agenix → SOPS migration | 🔴 CRITICAL |
| `extract-dotfiles.sh` | NixOS | Copy home-manager configs → Stow | 🔴 CRITICAL |
| `setup-gpu.sh` | Arch | Install GPU drivers, configure Docker | 🟠 HIGH |
| `setup-volumes.sh` | Arch | Create directories, set permissions | 🟠 HIGH |
| `validate.sh` | Arch | Pre-flight & post-deploy checks | 🟢 MEDIUM |

---

## 🚀 Complete Migration Workflow

### **Phase 1: Preparation (On NixOS Machine)**

#### 1.1 Evaluate Nix Configuration

**WHY:** Get accurate container configs instead of regex-parsed nonsense

```bash
cd /home/user/nixos-hwc

# For server
python3 workspace/utilities/nixos-translator/tools/nix-evaluator.py \
  --flake . \
  --machine server \
  --output /tmp/server-evaluated.json \
  --verbose

# For laptop
python3 workspace/utilities/nixos-translator/tools/nix-evaluator.py \
  --flake . \
  --machine laptop \
  --output /tmp/laptop-evaluated.json \
  --verbose
```

**Output:** `server-evaluated.json` with actual evaluated container configs

#### 1.2 Migrate Secrets

**WHY:** Decrypt all agenix secrets and prepare for SOPS

**⚠️ Must run as root to access `/etc/age/keys.txt`**

```bash
cd /home/user/nixos-hwc/workspace/utilities/nixos-translator/tools

sudo ./migrate-secrets.sh \
  --nixos-path /home/user/nixos-hwc \
  --age-key /etc/age/keys.txt \
  --output /tmp/secrets-export \
  --verbose
```

**Output:**
```
/tmp/secrets-export/
├── system/          # user-ssh-public-key, emergency-password, etc.
├── home/            # gmail-oauth, proton-bridge, etc.
├── infrastructure/  # vpn-password, camera-rtsp, etc.
├── server/          # arr-api-keys, couchdb-admin, etc.
└── sops/
    ├── secrets.yaml.template  # Fill this in!
    ├── deploy-secrets.sh      # Run on Arch
    └── .sops.yaml             # SOPS config
```

**IMPORTANT:** Read `MIGRATION_SUMMARY.md` for next steps

#### 1.3 Extract Dotfiles

**WHY:** Get actual config files, not just inventory

```bash
cd /home/user/nixos-hwc/workspace/utilities/nixos-translator/tools

./extract-dotfiles.sh \
  --user eric \
  --output ~/dotfiles-export
```

**Output:**
```
~/dotfiles-export/
├── zsh/
│   ├── .zshrc
│   └── .config/zsh/...
├── neovim/
│   └── .config/nvim/...
├── hyprland/
│   └── .config/hypr/...
├── stow-all.sh     # Quick deploy script
└── INSTALL.md      # Detailed instructions
```

#### 1.4 Package Everything for Transfer

```bash
# Create transfer archive
cd /tmp
tar czf migration-bundle.tar.gz \
  server-evaluated.json \
  secrets-export/ \
  ~/dotfiles-export/

# Transfer to Arch machine (via encrypted USB, scp, etc.)
scp migration-bundle.tar.gz arch-machine:/tmp/
```

---

### **Phase 2: Base System Setup (On Arch Machine)**

#### 2.1 Install Arch Base

(Assuming Arch is already installed)

```bash
# Update system
sudo pacman -Syu

# Install essential tools
sudo pacman -S base-devel git docker docker-compose yq age sops stow
```

#### 2.2 Run Validation (Pre-flight)

```bash
cd ~/arch-hwc/tools
./validate.sh --mode pre-flight
```

**This checks:**
- Docker installed and running
- Required tools present (yq, age, sops, stow)
- Directory structure correct
- Docker Compose files valid

**Fix any failures before continuing!**

---

### **Phase 3: Infrastructure Setup (On Arch Machine)**

#### 3.1 Set Up GPU

**WHY:** Critical for Jellyfin transcoding, Frigate AI, Immich ML

```bash
cd ~/arch-hwc/tools
./setup-gpu.sh

# If looks good, run for real:
./setup-gpu.sh
```

**Then verify:**
```bash
# For NVIDIA:
nvidia-smi
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi

# For Intel/AMD:
ls -la /dev/dri/
```

**⚠️ REBOOT after GPU setup!**

#### 3.2 Set Up Volumes

**WHY:** Containers need these directories to exist

```bash
cd ~/arch-hwc/tools

# Generate default config
./setup-volumes.sh

# Edit volumes.yaml to match your disks
nano volumes.yaml

# Apply configuration
./setup-volumes.sh volumes.yaml
```

**Critical paths:**
- `/mnt/hot` - SSD for downloads (500GB+)
- `/mnt/media` - HDD for media library (4TB+)
- `/opt/downloads` - Download staging
- `/opt/arr` - *arr configs
- `/opt/secrets` - Secrets deployment

---

### **Phase 4: Secrets Deployment (On Arch Machine)**

#### 4.1 Set Up SOPS

```bash
# Extract migration bundle
cd /tmp
tar xzf migration-bundle.tar.gz

# Generate age key
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt

# Get public key
age-keygen -y ~/.config/sops/age/keys.txt
# Copy this public key!
```

#### 4.2 Create & Encrypt Secrets

```bash
cd secrets-export/sops

# Edit .sops.yaml - replace REPLACE_WITH_YOUR_AGE_PUBLIC_KEY
nano .sops.yaml

# Copy template to secrets.yaml
cp secrets.yaml.template secrets.yaml

# Fill in all secrets (use decrypted files in ../system/, ../home/, etc. as reference)
nano secrets.yaml

# Encrypt with SOPS
sops -e -i secrets.yaml
```

#### 4.3 Deploy Secrets

```bash
cd secrets-export/sops

# Deploy to /opt/secrets/
sudo ./deploy-secrets.sh secrets.yaml

# Verify
sudo ls -la /opt/secrets/
sudo cat /opt/secrets/system/user-initial-password  # Test one
```

**⚠️ SECURE CLEANUP:**
```bash
# On NixOS machine
cd /tmp/secrets-export
shred -uvz -n 3 **//*

# On Arch machine
shred -uvz -n 3 secrets.yaml  # After deploying
```

---

### **Phase 5: Container Deployment (On Arch Machine)**

#### 5.1 Create Docker Network

```bash
docker network create media-network
```

#### 5.2 Deploy Stacks

```bash
cd ~/arch-hwc/compose

# Start each stack
cd downloaders && docker-compose up -d && cd ..
cd arr-stack && docker-compose up -d && cd ..
cd media-management && docker-compose up -d && cd ..
cd infrastructure && docker-compose up -d && cd ..
```

#### 5.3 Verify Containers

```bash
# Check all running
docker ps

# Check logs
docker-compose -f downloaders/docker-compose.yml logs -f gluetun
docker-compose -f arr-stack/docker-compose.yml logs -f sonarr
```

---

### **Phase 6: Dotfiles Deployment (On Arch Machine)**

```bash
cd /tmp/dotfiles-export

# Quick install all
./stow-all.sh

# Or selective install
stow zsh starship tmux neovim git hyprland waybar kitty
```

**Verify:**
```bash
ls -la ~ | grep ' -> '  # Check symlinks
source ~/.zshrc  # Test shell config
```

---

### **Phase 7: Validation (On Arch Machine)**

```bash
cd ~/arch-hwc/tools
./validate.sh --mode post-deploy
```

**This checks:**
- ✅ Secrets deployed
- ✅ Docker networks exist
- ✅ Containers running
- ✅ GPU accessible
- ✅ Services responding
- ✅ Dotfiles symlinked

**Review any failures and fix!**

---

## 🛠️ Tool-Specific Documentation

### `nix-evaluator.py` - Accurate Config Extraction

**Purpose:** Use Nix itself to evaluate configs instead of regex parsing

**Why it matters:** Your container configs use dynamic expressions like:
- `${paths.hot}/downloads` - Regex can't resolve these
- `lib.optionals (cfg.network.mode != "vpn")` - Conditional logic missed
- `toString cfg.webPort` - Port calculations broken

**Usage:**
```bash
python3 nix-evaluator.py \
  --flake /home/user/nixos-hwc \
  --machine server \
  --output server-evaluated.json \
  --verbose
```

**Output format:**
```json
{
  "machine": "server",
  "containers": {
    "qbittorrent": {
      "image": "lscr.io/linuxserver/qbittorrent:latest",
      "ports": [{"host": "8080", "container": "8080", "proto": "tcp"}],
      "volumes": [{
        "host": "/mnt/hot/downloads",
        "container": "/downloads",
        "mode": "rw"
      }],
      "environment": {"WEBUI_PORT": "8080", "TZ": "America/Denver"}
    }
  }
}
```

**Integration with translator:** Future version will use this instead of regex scanner

---

### `migrate-secrets.sh` - Decrypt & Prepare Secrets

**Purpose:** Automate the painful process of migrating 32+ secrets

**What it does:**
1. Finds all `.age` files in `domains/secrets/parts/`
2. Decrypts each one using `/etc/age/keys.txt`
3. Organizes by category (system, home, infrastructure, server)
4. Generates SOPS YAML template
5. Creates deployment script for Arch

**Critical notes:**
- **MUST RUN AS ROOT** (to access `/etc/age/keys.txt`)
- Output directory contains **PLAIN TEXT SECRETS** - handle with care!
- Use encrypted volumes or secure transfer methods
- Delete decrypted export after migration

**Example:**
```bash
sudo ./migrate-secrets.sh \
  --nixos-path /home/user/nixos-hwc \
  --age-key /etc/age/keys.txt \
  --output /tmp/secrets-export

# Output shows progress:
#  [migrate-secrets] Decrypting: system/vpn-password.age
#  [migrate-secrets] Decrypting: server/sonarr-api-key.age
#  ...
#  [migrate-secrets] Decrypted 32 secrets, 0 failed
```

---

### `extract-dotfiles.sh` - Copy Home-Manager Configs

**Purpose:** Get actual config files that home-manager generated

**What it extracts:**
- **Shell:** .zshrc, starship.toml, tmux.conf, nvim configs
- **Desktop:** Hyprland, Waybar, Kitty, Swaync configs
- **Apps:** Chromium, LibreWolf, Aerc, Obsidian configs
- **Tools:** Git, GPG configs

**Critical feature:** Dereferences symlinks (copies actual files, not links)

**Priority system:**
- 100: Shell & editor (zsh, neovim, tmux, git)
- 90: Desktop environment (hyprland, waybar, kitty)
- 80: Applications (browsers, mail clients)
- 70: Productivity tools

**Example:**
```bash
./extract-dotfiles.sh --user eric --output ~/dotfiles-export

# Creates:
#  ~/dotfiles-export/zsh/.zshrc
#  ~/dotfiles-export/neovim/.config/nvim/init.lua
#  ~/dotfiles-export/hyprland/.config/hypr/hyprland.conf
#  ...
```

---

### `setup-gpu.sh` - Automated GPU Configuration

**Purpose:** Detect GPU, install correct drivers, configure Docker runtime

**Supports:**
- **NVIDIA:** Detects generation, installs driver, configures nvidia-container-toolkit
- **AMD:** Installs mesa, vulkan-radeon, ROCm support
- **Intel:** Installs mesa, vulkan-intel, VA-API

**What it does:**
1. Detects GPU using `lspci`
2. Determines correct driver package
3. Installs drivers and utilities
4. Configures container runtime (`nvidia-ctk` for NVIDIA)
5. Adds user to `video` and `render` groups
6. Loads kernel modules
7. Provides verification commands

**Example:**
```bash
./setup-gpu.sh --dry-run  # See what it would do

./setup-gpu.sh  # For real

# Then verify:
nvidia-smi
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
```

---

### `setup-volumes.sh` - Directory Initialization

**Purpose:** Create required directories with correct permissions

**Uses YAML config:**
```yaml
volumes:
  - path: /mnt/hot
    type: mount_point  # Expects this to be mounted
    size_required: 500GB
    owner: eric:eric
    mode: "0755"

  - path: /opt/downloads
    type: directory  # Will be created
    owner: eric:eric
    mode: "0755"
```

**What it checks:**
- Mount points are actually mounted
- Sufficient disk space
- Correct ownership and permissions

**Example:**
```bash
./setup-volumes.sh  # Generates default volumes.yaml

nano volumes.yaml  # Customize

./setup-volumes.sh volumes.yaml  # Apply
```

---

### `validate.sh` - Pre/Post Migration Checks

**Purpose:** Catch issues before they cause deployment failures

**Pre-flight checks:**
- Docker installed and running
- Required tools present (yq, age, sops)
- Docker Compose files valid
- Required mount points exist

**Post-deploy checks:**
- Secrets deployed correctly
- Containers running
- GPU accessible
- Services responding on expected ports
- Systemd services active
- Dotfiles symlinked

**Example:**
```bash
# Before migration
./validate.sh --mode pre-flight

# After deployment
./validate.sh --mode post-deploy
```

**Generates:** `validation-report-TIMESTAMP.json` with test results

---

## 🔧 Troubleshooting

### Secrets Migration

**Problem:** `age: error: cannot open "/etc/age/keys.txt": permission denied`
**Solution:** Run with `sudo`

**Problem:** Some secrets failed to decrypt
**Solution:** Check that the age key matches what was used to encrypt them

### GPU Setup

**Problem:** `nvidia-smi: command not found` after install
**Solution:** Reboot to load new drivers

**Problem:** GPU not accessible in containers
**Solution:** Ensure nvidia-container-toolkit is installed and Docker restarted

### Dotfiles

**Problem:** `stow: WARNING! stowing zsh would cause conflicts`
**Solution:** Backup existing file (`mv ~/.zshrc ~/.zshrc.backup`) and retry

### Containers

**Problem:** Container immediately exits
**Solution:** Check logs (`docker-compose logs <service>`), usually secrets or volume issues

---

## 📚 Additional Resources

- **Arch Wiki - NVIDIA:** https://wiki.archlinux.org/title/NVIDIA
- **Docker Compose Documentation:** https://docs.docker.com/compose/
- **SOPS Guide:** https://github.com/mozilla/sops
- **GNU Stow Manual:** https://www.gnu.org/software/stow/manual/

---

## ⚠️ Security Warnings

1. **Secrets Export:** Contains PLAIN TEXT secrets - encrypt volume, delete after use
2. **Secrets Transfer:** Use secure methods (encrypted USB, scp over VPN)
3. **Never commit:** Decrypted secrets or `secrets.yaml` (before SOPS encryption)
4. **GPG Keys:** If migrating GPG keys, verify permissions (`chmod 700 ~/.gnupg`)

---

## 🎯 Success Criteria

Your migration is successful when:

- ✅ All containers running (`docker ps`)
- ✅ GPU accessible (`nvidia-smi` in container)
- ✅ Services responding (Jellyfin on :8096, Sonarr on :8989, etc.)
- ✅ No secret errors in logs
- ✅ Desktop environment works (Hyprland, Waybar)
- ✅ Shell configured (zsh, starship, tmux)
- ✅ `./validate.sh --mode post-deploy` passes

---

**Questions? Issues? Check the tool-specific sections above or run with `--help` flag.**
