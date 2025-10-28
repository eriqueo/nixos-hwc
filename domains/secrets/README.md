# HWC Secrets Domain - Secrets Management

> **Single source of truth for all secrets, credentials, and authentication in the HWC nixos configuration**

## 📋 Table of Contents
- [Architecture Overview](#-architecture-overview)
- [Directory Structure](#-directory-structure)
- [How It Works](#-how-it-works)
- [Managing Secrets](#-managing-secrets)
- [Consumer Usage](#-consumer-usage)
- [Migration Guide](#-migration-guide)
- [Troubleshooting](#-troubleshooting)

## 🏗️ Architecture Overview

The HWC Secrets Domain follows a clean **domain-organized** approach with **stable interfaces** and **backward compatibility**:

```
┌─────────────────────────────────────────┐
│                CONSUMERS                │
│  (domains/system/, domains/services/)   │
└──────────────┬──────────────────────────┘
               │ hwc.security.materials.*
               │ (stable read-only paths)
┌──────────────▼──────────────────────────┐
│             MATERIALS FACADE            │
│        (domains/secrets/materials.nix) │
└──────────────┬──────────────────────────┘
               │ age.secrets.*.path
               │
┌──────────────▼──────────────────────────┐
│           DOMAIN SECRETS                │
│     (domains/secrets/secrets/*.nix)    │
└──────────────┬──────────────────────────┘
               │ *.age files
               │
┌──────────────▼──────────────────────────┐
│          ENCRYPTED SECRETS              │
│            (secrets/*.age)              │
└─────────────────────────────────────────┘
```

**Key Principles:**
- **Domain Separation**: Secrets organized by functional domain (system, services, infrastructure, networking)
- **Single Source of Truth**: All secrets managed in `domains/secrets/`
- **Stable Interface**: Consumers use `hwc.security.materials.*` paths
- **Backward Compatibility**: Legacy paths work during migration
- **No Whack-a-Mole**: Changes don't break existing consumers

## 📁 Directory Structure

```
domains/secrets/
├── README.md                 # This documentation
├── index.nix                 # Main aggregator (imports everything)
├── materials.nix             # Stable read-only path facade
├── compat.nix                # Backward compatibility aliases
├── emergency-access.nix      # Emergency root access (existing)
└── secrets/
    ├── index.nix             # Aggregates all domain secrets
    ├── system.nix            # System authentication secrets
    ├── services.nix          # Application/service credentials
    ├── infrastructure.nix    # Database/infrastructure secrets
    └── networking.nix        # VPN/network authentication
```

## 🔧 How It Works

### 1. **Domain Files** (Data-Only)
Each domain file contains **only** `age.secrets` declarations:

```nix
# domains/secrets/secrets/system.nix
{
  age.secrets = {
    user-initial-password = {
      file = ../../../secrets/user-initial-password.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
    # ... more system secrets
  };
}
```

### 2. **Materials Facade** (Stable Interface)
Provides consistent paths that consumers use:

```nix
# Consumer code
let passwordFile = config.hwc.security.materials.userInitialPasswordFile;
in {
  users.users.eric.initialHashedPasswordFile = 
    lib.mkIf (passwordFile != null) passwordFile;
}
```

### 3. **Automatic Import**
The security profile imports everything automatically:

```nix
# profiles/security.nix
imports = [ ../domains/secrets/index.nix ];
hwc.security.enable = true;
```

## 🔐 Managing Secrets

### Adding a New Secret

**Step 1: Create the encrypted file**
```bash
# Create and encrypt the secret
echo "my-secret-value" | age -r $(cat age-key.pub) > secrets/new-service-token.age
```

**Step 2: Add to appropriate domain file**
```nix
# domains/secrets/secrets/services.nix (if it's a service credential)
age.secrets = {
  # ... existing secrets ...
  new-service-token = {
    file = ../../../secrets/new-service-token.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };
};
```

**Step 3: Expose via materials facade**
```nix
# domains/secrets/materials.nix
options.hwc.security.materials = {
  # ... existing options ...
  newServiceTokenFile = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    readOnly = true;
    description = "Path to decrypted new service token file";
  };
};

config.hwc.security.materials = {
  # ... existing mappings ...
  newServiceTokenFile = pathOrNull "new-service-token";
};
```

**Step 4: Use in consumer modules**
```nix
# domains/services/my-service.nix
let tokenFile = config.hwc.security.materials.newServiceTokenFile;
in {
  systemd.services.my-service = {
    serviceConfig = {
      EnvironmentFile = lib.mkIf (tokenFile != null) tokenFile;
    };
  };
}
```

### Updating an Existing Secret

**Update the encrypted file:**
```bash
# Re-encrypt with new value
echo "new-secret-value" | age -r $(cat age-key.pub) > secrets/existing-secret.age
```

**Rebuild to apply:**
```bash
sudo nixos-rebuild switch --flake .#hwc-laptop
```

### Removing a Secret

**Step 1: Remove from consumers** (check with grep first)
```bash
# Find all usages
rg "oldSecretFile" --type nix
```

**Step 2: Remove from materials facade**
```nix
# domains/secrets/materials.nix - remove the option and mapping
```

**Step 3: Remove from domain file**
```nix
# domains/secrets/secrets/*.nix - remove the age.secrets entry
```

**Step 4: Delete encrypted file**
```bash
rm secrets/old-secret.age
```

## 🔌 Consumer Usage

### For System Modules
```nix
# domains/system/core/eric.nix
let 
  passwordFile = config.hwc.security.materials.userInitialPasswordFile;
  sshKeyFile = config.hwc.security.materials.userSshPublicKeyFile;
in {
  users.users.eric = {
    initialHashedPasswordFile = lib.mkIf (passwordFile != null) passwordFile;
    openssh.authorizedKeys.keyFiles = lib.optional (sshKeyFile != null) sshKeyFile;
  };
}
```

### For Service Modules
```nix
# domains/services/media/arr-stack.nix
let apiKeyFile = config.hwc.security.materials.radarrApiKeyFile;
in {
  services.radarr = lib.mkIf (apiKeyFile != null) {
    enable = true;
    # Use the secret file path
    apiKeyFile = apiKeyFile;
  };
}
```

### For Infrastructure Modules
```nix
# domains/infrastructure/database.nix
let 
  dbUser = config.hwc.security.materials.databaseUserFile;
  dbPass = config.hwc.security.materials.databasePasswordFile;
in {
  services.postgresql = lib.mkIf (dbUser != null && dbPass != null) {
    enable = true;
    authentication = ''
      local all $(cat ${dbUser}) trust
    '';
  };
}
```

## 🚀 Migration Guide

### From Direct age.secrets Access

**Old Pattern:**
```nix
# DON'T DO THIS ANYMORE
let secretPath = config.age.secrets."vpn-username".path;
```

**New Pattern:**
```nix
# DO THIS INSTEAD
let secretPath = config.hwc.security.materials.vpnUsernameFile;
```

### From System Domain Secrets

**Old Import:**
```nix
# domains/system/core/secrets.nix - REMOVED
```

**New Usage:**
```nix
# Everything now via security profile (automatically imported)
let passwordFile = config.hwc.security.materials.userInitialPasswordFile;
```

### Gradual Migration

The compatibility shim allows gradual migration:

1. **Legacy paths still work** (with deprecation warnings)
2. **Update consumers at your own pace**
3. **Remove compat.nix when migration complete**

## 🐛 Troubleshooting

### Build Fails with "path does not exist"

**Cause:** Secret file missing or path incorrect

**Solution:**
```bash
# Check if file exists
ls -la secrets/the-secret.age

# Verify path in domain file is correct (should be ../../../secrets/)
```

### "No identity paths configured"

**Cause:** Missing age keys

**Solution:**
```bash
# Ensure age key exists
sudo ls -la /etc/age/keys.txt

# Or configure in security profile
age.identityPaths = [ "/etc/age/keys.txt" ];
```

### Consumer Gets Null Instead of Secret Path

**Cause:** Secret not properly declared or materials facade not updated

**Debug Steps:**
1. Check secret exists in domain file: `age.secrets.secret-name = { ... }`
2. Check materials facade has option: `secretNameFile = lib.mkOption { ... }`
3. Check materials mapping: `secretNameFile = pathOrNull "secret-name"`

### Legacy Option Warnings

**Expected Behavior:** Deprecation warnings guide migration

**To Silence:** Update consumers to use `hwc.security.materials.*`

```nix
# OLD (shows warning)
config.age.secrets."vpn-username".path

# NEW (no warning)
config.hwc.security.materials.vpnUsernameFile
```

## 🔍 Available Secrets

Current secrets organized by domain:

### System Domain
- `userInitialPasswordFile` - User authentication
- `emergencyPasswordFile` - Emergency root access
- `userSshPublicKeyFile` - SSH key authentication

### Services Domain  
- `radarrApiKeyFile`, `sonarrApiKeyFile`, `lidarrApiKeyFile`, `prowlarrApiKeyFile` - ARR stack APIs
- `couchdbAdminUsernameFile`, `couchdbAdminPasswordFile` - Database admin
- `ntfyUserFile` - Notification service

### Infrastructure Domain
- `databaseNameFile`, `databaseUserFile`, `databasePasswordFile` - Database credentials
- `surveillanceRtspUsernameFile`, `surveillanceRtspPasswordFile` - Surveillance system
- `frigateRtspPasswordFile` - Frigate RTSP access

### Networking Domain
- `vpnUsernameFile`, `vpnPasswordFile` - VPN authentication

---

**💡 Remember:** Always use the **materials facade** (`hwc.security.materials.*`) in consumer code for a stable, future-proof interface!