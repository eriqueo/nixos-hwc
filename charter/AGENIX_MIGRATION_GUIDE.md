# SOPS to Agenix Migration Guide

## Overview
I've migrated your system from SOPS to agenix for simpler secrets management. Agenix uses the same age encryption but with a much simpler workflow.

## What I've Done

### 1. Updated Flake Configuration
- ✅ Replaced `sops-nix` with `agenix` input
- ✅ Updated both machine configurations to use agenix
- ✅ Created `secrets.nix` with age key configuration

### 2. Created Security Module
- ✅ Created `modules/security/secrets.nix` with Charter v3 toggles
- ✅ All secrets organized by category (VPN, database, services, etc.)
- ✅ Proper file permissions and ownership

### 3. Prepared Secret Structure
- ✅ Created `/secrets/` directory for `.age` files
- ✅ Mapped all your current SOPS secrets to agenix equivalents

## What You Need to Do

### Step 1: Install agenix CLI
```bash
nix profile install github:ryantm/agenix
```

### Step 2: Copy Age Keys
Your age keys are already in `/etc/nixos/secrets/keys/`:
```bash
# Copy keys to new location
sudo mkdir -p /etc/age
sudo cp /etc/nixos/secrets/keys/laptop.txt /etc/age/keys.txt    # On laptop
sudo cp /etc/nixos/secrets/keys/server.txt /etc/age/keys.txt    # On server
sudo chmod 600 /etc/age/keys.txt
```

### Step 3: Decrypt SOPS Secrets and Re-encrypt with Agenix

I'll provide the commands to extract your current secrets and re-encrypt them:

```bash
cd /home/eric/03-tech/nixos-hwc

# VPN credentials (from admin.yaml)
sops -d /etc/nixos/secrets/admin.yaml | yq '.vpn.protonvpn.username' | agenix -e secrets/vpn-username.age
sops -d /etc/nixos/secrets/admin.yaml | yq '.vpn.protonvpn.password' | agenix -e secrets/vpn-password.age

# Database credentials (from database.yaml)
sops -d /etc/nixos/secrets/database.yaml | yq '.postgres.password' | agenix -e secrets/database-password.age
sops -d /etc/nixos/secrets/database.yaml | yq '.postgres.user' | agenix -e secrets/database-user.age
sops -d /etc/nixos/secrets/database.yaml | yq '.postgres.database' | agenix -e secrets/database-name.age

# CouchDB credentials (from admin.yaml)
sops -d /etc/nixos/secrets/admin.yaml | yq '.couchdb.admin_username' | agenix -e secrets/couchdb-admin-username.age
sops -d /etc/nixos/secrets/admin.yaml | yq '.couchdb.admin_password' | agenix -e secrets/couchdb-admin-password.age

# User credentials (from admin.yaml)
sops -d /etc/nixos/secrets/admin.yaml | yq '.users.eric.initial_password' | agenix -e secrets/user-initial-password.age
sops -d /etc/nixos/secrets/admin.yaml | yq '.users.eric.ssh_public_key' | agenix -e secrets/user-ssh-public-key.age

# Service credentials (these appear to be empty in your current config, so create empty files)
echo "" | agenix -e secrets/jellyfin-admin.age
echo "" | agenix -e secrets/homeassistant-admin.age
echo "" | agenix -e secrets/caddy-admin.age

# ARR API keys (from arr_api_keys.env - you'll need to extract these manually)
# Look at /etc/nixos/secrets/arr_api_keys.env and create secrets for each API key
```

### Step 4: Migrate ARR API Keys
Your ARR API keys are in `/etc/nixos/secrets/arr_api_keys.env`. Extract each one:

```bash
# Example (replace with actual values from your env file):
echo "YOUR_SONARR_API_KEY" | agenix -e secrets/sonarr-api-key.age
echo "YOUR_RADARR_API_KEY" | agenix -e secrets/radarr-api-key.age
echo "YOUR_LIDARR_API_KEY" | agenix -e secrets/lidarr-api-key.age
echo "YOUR_PROWLARR_API_KEY" | agenix -e secrets/prowlarr-api-key.age
```

### Step 5: Create Empty Secrets for Optional Services
```bash
# NTFY and Surveillance (if you don't have these yet)
echo "" | agenix -e secrets/ntfy-token.age
echo "" | agenix -e secrets/surveillance-admin.age
```

## Simplified Usage Compared to SOPS

### Old SOPS Way:
```nix
sops.secrets."vpn/protonvpn/username" = {
  sopsFile = ../secrets/admin.yaml;
  key = "vpn/protonvpn/username";
  format = "yaml";
};
```

### New Agenix Way:
```nix
hwc.security.secrets.vpn = true;
# Secret is automatically available at config.age.secrets.vpn-username.path
```

## Benefits of Agenix

1. **Simpler Files**: Each secret is its own `.age` file, no complex YAML structure
2. **Better CLI**: `agenix -e file.age` to edit, automatic encryption/decryption
3. **Cleaner Config**: Toggle-based secret categories instead of individual SOPS definitions
4. **Same Security**: Uses age encryption (same as SOPS can use)

## Testing the Migration

After creating all the secret files:

1. Enable secrets in your profiles:
```nix
# In profiles/base.nix
hwc.security = {
  enable = true;
  secrets.user = true;
  secrets.vpn = true;
};

# In profiles/server.nix  
hwc.security.secrets = {
  database = true;
  couchdb = true;
  services = true;
  arr = true;
};
```

2. Test build:
```bash
nixos-rebuild build --flake .#hwc-laptop
nixos-rebuild build --flake .#hwc-server
```

3. Check secret paths (after switch):
```bash
ls -la /run/agenix/
```

## Migration Status

- ✅ Agenix infrastructure setup complete
- ⏳ **Next**: You decrypt and migrate secret values
- ⏳ Then: Update all service modules to use new secret paths
- ⏳ Finally: Remove old SOPS configuration

Once you've created the `.age` files, I'll continue with Phase 1 completion and update all the service modules to use the new secret paths.