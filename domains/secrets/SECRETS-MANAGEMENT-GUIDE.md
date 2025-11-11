# HWC Secrets Management - Comprehensive Guide

**The Ultimate Guide to Managing Secrets in Your NixOS Configuration**

Last Updated: 2025-11-08
Status: ✅ **PRODUCTION READY**

---

## 📋 Table of Contents

1. [Executive Summary](#executive-summary)
2. [Architecture Deep Dive](#architecture-deep-dive)
3. [How It Actually Works](#how-it-actually-works)
4. [Common Pain Points & Solutions](#common-pain-points--solutions)
5. [Daily Operations Guide](#daily-operations-guide)
6. [Workflow Improvements](#workflow-improvements)
7. [Helper Scripts & Aliases](#helper-scripts--aliases)
8. [Troubleshooting Decision Tree](#troubleshooting-decision-tree)
9. [Security Best Practices](#security-best-practices)
10. [Quick Reference](#quick-reference)

---

## Executive Summary

### What You Have
- **33 encrypted secrets** (`.age` files) organized by domain
- **Agenix** automatically decrypts them at boot to `/run/agenix/`
- **Domain-organized** structure (system, server, infrastructure, home, apps)
- **Stable API** via `config.hwc.secrets.api.*` for consumers

### What's Working
✅ Secrets automatically decrypt on boot
✅ Proper permissions (mode 0440, owner/group set)
✅ Services can read their secrets
✅ Organization by domain (clean structure)

### What's Painful (Current Pain Points)
❌ **No quick way to view/edit secrets** (manual encrypt/decrypt)
❌ **Permissions errors** when trying to read secrets as user
❌ **Unclear which services use which secrets**
❌ **No validation** if secrets decrypt successfully
❌ **Age key location confusion** (/etc/age/keys.txt vs SSH keys)
❌ **Manual workflow** for updating secrets (7+ commands)

---

## Architecture Deep Dive

### The Four Layers

```
┌──────────────────────────────────────────────────────────────┐
│  LAYER 4: CONSUMERS                                          │
│  (Services, containers, systemd units)                       │
│  Access via: config.hwc.secrets.api.secretNameFile           │
└────────────────────┬─────────────────────────────────────────┘
                     │ Read-only stable paths
┌────────────────────▼─────────────────────────────────────────┐
│  LAYER 3: API FACADE                                         │
│  (domains/secrets/secrets-api.nix)                           │
│  Maps secret names → /run/agenix/secret-name paths           │
└────────────────────┬─────────────────────────────────────────┘
                     │ age.secrets.*.path
┌────────────────────▼─────────────────────────────────────────┐
│  LAYER 2: DECLARATIONS                                       │
│  (domains/secrets/declarations/*.nix)                        │
│  Declares: file path, owner, group, mode                     │
└────────────────────┬─────────────────────────────────────────┘
                     │ Points to .age files
┌────────────────────▼─────────────────────────────────────────┐
│  LAYER 1: ENCRYPTED FILES                                    │
│  (domains/secrets/parts/**/*.age)                            │
│  Encrypted with age using /etc/age/keys.txt                  │
└──────────────────────────────────────────────────────────────┘
```

### Directory Structure (As-Built)

```
domains/secrets/
├── index.nix                    # Main aggregator
├── options.nix                  # All hwc.secrets options
├── secrets-api.nix              # Stable path facade (Layer 3)
├── emergency.nix                # Emergency root access
├── hardening.nix                # Security hardening config
├── README.md                    # Original documentation
│
├── declarations/                # Layer 2: Age secret declarations
│   ├── index.nix               # Aggregates all domains
│   ├── system.nix              # user-initial-password, emergency-password
│   ├── server.nix              # *arr API keys, couchdb, ntfy
│   ├── infrastructure.nix      # database, VPN, RTSP credentials
│   ├── home.nix                # email passwords
│   ├── apps.nix                # fabric-server-env, fabric-user-env
│   └── caddy.nix               # TLS certificates
│
└── parts/                       # Layer 1: Encrypted .age files
    ├── system/                  # 3 files
    ├── server/                  # 10 files  
    ├── infrastructure/          # 10 files
    ├── home/                    # 3 files
    ├── apps/                    # 2 files
    └── caddy/                   # 2 files (TLS cert/key)
```

---

## How It Actually Works

### Boot Process

1. **NixOS Activation**
   - systemd-tmpfiles creates `/etc/age/` directory
   - Agenix reads identity from `/etc/age/keys.txt`

2. **Secret Decryption**
   - For each `age.secrets.*` declaration:
   - Agenix decrypts `*.age` file using age key
   - Writes plaintext to `/run/agenix/secret-name`
   - Sets permissions (owner, group, mode)
   - Creates symlinks if needed

3. **Service Startup**
   - Services start after `/run/agenix.d.mount`
   - Read secrets via paths from `config.hwc.secrets.api.*`
   - Example: `EnvironmentFile = config.hwc.secrets.api.vpnPasswordFile`

---

## Common Pain Points & Solutions

### Pain Point #1: "I can't read my own secrets"

**Problem:**
```bash
$ cat /run/agenix/vpn-password
cat: /run/agenix/vpn-password: Permission denied
```

**Root Cause:** Secrets owned by `root:secrets` with mode `0440` (read for owner/group only)

**Solutions:**

**Option A: Use sudo (quick)**
```bash
sudo cat /run/agenix/vpn-password
```

**Option B: Add yourself to secrets group (permanent)**
```bash
sudo usermod -aG secrets eric
# Logout/login to apply
```

**Option C: Use the helper script (recommended - see below)**
```bash
secret-show vpn-password
```

---

### Pain Point #2: "Updating secrets requires 7+ manual steps"

**Current Painful Workflow:**
```bash
# 1. Get the public key
sudo cat /etc/age/keys.txt | grep "public key"

# 2. Copy the public key somewhere

# 3. Create/edit the secret value

# 4. Encrypt it
echo "new-value" | age -r age1xxxxx > /tmp/secret.age

# 5. Move to correct location
mv /tmp/secret.age domains/secrets/parts/server/my-secret.age

# 6. Fix permissions
chmod 644 domains/secrets/parts/server/my-secret.age

# 7. Rebuild
sudo nixos-rebuild switch --flake .#hwc-server
```

**Solution: See [Helper Scripts](#helper-scripts--aliases) below**

---

### Pain Point #3: "Which services use which secrets?"

**Secret Dependency Map:**

| Secret | Consumed By | Purpose |
|--------|-------------|---------|
| `vpn-username` | gluetun container | ProtonVPN auth |
| `vpn-password` | gluetun container | ProtonVPN auth |
| `sonarr-api-key` | Sonarr, Prowlarr, Jellyseerr | API integration |
| `radarr-api-key` | Radarr, Prowlarr, Jellyseerr | API integration |
| `lidarr-api-key` | Lidarr, Prowlarr | API integration |
| `prowlarr-api-key` | All *arr services | Indexer management |
| `slskd-api-key` | SLSKD, Soularr | Soulseek integration |
| `fabric-user-env` | User shell, Codex CLI | AI API keys |
| `fabric-server-env` | Fabric API server | AI provider keys |
| `couchdb-admin-*` | CouchDB native service | Admin access |
| `gemini-api-key` | AI services | Google Gemini access |
| `frigate-rtsp-password` | Frigate | Camera access |

---

## Daily Operations Guide

### Viewing a Secret

```bash
# Quick view (requires sudo)
sudo cat /run/agenix/secret-name

# List all decrypted secrets
sudo ls -la /run/agenix/

# Search for a secret
sudo rg "pattern" /run/agenix/
```

### Adding a New Secret

```bash
# 1. Get your age public key
AGE_KEY=$(sudo cat /etc/age/keys.txt | grep "public key:" | awk '{print $4}')

# 2. Create and encrypt the secret
echo "my-secret-value" | age -r $AGE_KEY > \
  domains/secrets/parts/server/new-secret.age

# 3. Add declaration to appropriate domain file
# Edit: domains/secrets/declarations/server.nix

# 4. Expose in API facade
# Edit: domains/secrets/secrets-api.nix

# 5. Rebuild to apply
sudo nixos-rebuild switch --flake .#hwc-server
```

### Updating an Existing Secret

```bash
# 1. Get age public key
AGE_KEY=$(sudo cat /etc/age/keys.txt | grep "public key:" | awk '{print $4}')

# 2. Re-encrypt with new value
echo "new-value" | age -r $AGE_KEY > \
  domains/secrets/parts/server/existing-secret.age

# 3. Rebuild
sudo nixos-rebuild switch --flake .#hwc-server
```

---

## Helper Scripts & Aliases

### Secret Management Aliases

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# === HWC Secrets Aliases ===

# Quick secret viewing
alias secret-list='sudo ls -la /run/agenix/'
alias secret-show='_secret_show() { sudo cat /run/agenix/"$1"; }; _secret_show'
alias secret-search='_secret_search() { sudo rg "$1" /run/agenix/; }; _secret_search'

# Age key management
alias age-pubkey='sudo cat /etc/age/keys.txt | grep "public key:" | awk "{print \$4}"'

# Secret encryption helpers
secret-encrypt() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: secret-encrypt <secret-name> <domain>"
    echo "Example: secret-encrypt my-api-key server"
    echo "Domains: system, server, infrastructure, home, apps, caddy"
    return 1
  fi

  local SECRET_NAME="$1"
  local DOMAIN="$2"
  local AGE_KEY=$(sudo cat /etc/age/keys.txt | grep "public key:" | awk '{print $4}')
  local TARGET="domains/secrets/parts/${DOMAIN}/${SECRET_NAME}.age"

  echo "Enter secret value (will be hidden):"
  read -s SECRET_VALUE

  echo "$SECRET_VALUE" | age -r "$AGE_KEY" > "$TARGET"
  echo "✅ Secret encrypted to: $TARGET"
  echo "Next steps:"
  echo "  1. Add declaration to domains/secrets/declarations/${DOMAIN}.nix"
  echo "  2. Expose in domains/secrets/secrets-api.nix"
  echo "  3. Run: sudo nixos-rebuild switch --flake .#\$(hostname)"
}

secret-update() {
  if [ -z "$1" ]; then
    echo "Usage: secret-update <secret-name>"
    echo "Example: secret-update vpn-password"
    return 1
  fi

  local SECRET_NAME="$1"
  local AGE_KEY=$(sudo cat /etc/age/keys.txt | grep "public key:" | awk '{print $4}')
  local SECRET_FILE=$(find domains/secrets/parts -name "${SECRET_NAME}.age" 2>/dev/null | head -1)

  if [ -z "$SECRET_FILE" ]; then
    echo "❌ Secret not found: $SECRET_NAME"
    return 1
  fi

  echo "Current value:"
  sudo age -d -i /etc/age/keys.txt "$SECRET_FILE"
  echo ""
  echo "Enter new value (will be hidden):"
  read -s NEW_VALUE

  echo "$NEW_VALUE" | age -r "$AGE_KEY" > "$SECRET_FILE"
  echo "✅ Secret updated: $SECRET_FILE"
  echo "Run: sudo nixos-rebuild switch --flake .#\$(hostname)"
}

secret-validate() {
  echo "=== Validating HWC Secrets Setup ==="
  echo ""

  echo "1. Age key exists:"
  if [ -f /etc/age/keys.txt ]; then
    echo "  ✅ /etc/age/keys.txt exists"
  else
    echo "  ❌ /etc/age/keys.txt NOT FOUND"
  fi
  echo ""

  echo "2. Secrets mount:"
  if mount | grep -q "/run/agenix"; then
    echo "  ✅ /run/agenix mounted"
  else
    echo "  ❌ /run/agenix NOT MOUNTED"
  fi
  echo ""

  echo "3. Decrypted secrets:"
  local SECRET_COUNT=$(sudo ls /run/agenix/ 2>/dev/null | wc -l)
  echo "  📊 $SECRET_COUNT secrets decrypted"
  echo ""

  echo "4. Encrypted files:"
  local ENCRYPTED_COUNT=$(find domains/secrets/parts -name "*.age" 2>/dev/null | wc -l)
  echo "  📊 $ENCRYPTED_COUNT .age files found"
}
```

---

## Quick Reference

### File Locations

| Item | Path |
|------|------|
| Age private key | `/etc/age/keys.txt` |
| Decrypted secrets | `/run/agenix/` |
| Encrypted files | `domains/secrets/parts/**/*.age` |
| Declarations | `domains/secrets/declarations/*.nix` |
| API facade | `domains/secrets/secrets-api.nix` |

### Commands Cheat Sheet

```bash
# View secrets
sudo ls -la /run/agenix/
sudo cat /run/agenix/secret-name

# Get age public key
age-pubkey

# Encrypt a secret
AGE_KEY=$(age-pubkey)
echo "value" | age -r $AGE_KEY > secret.age

# Update a secret
secret-update secret-name

# Validate setup
secret-validate

# Rebuild after changes
sudo nixos-rebuild switch --flake .#hwc-server
```

---

**🎉 You now have a complete understanding of your secrets management system!**
