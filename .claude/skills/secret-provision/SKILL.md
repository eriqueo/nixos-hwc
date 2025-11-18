---
name: Secret Provision
description: End-to-end workflow to add encrypted secrets to nixos-hwc using agenix with proper permissions and service integration
---

# Secret Provision Workflow

This skill provides **complete automated workflow** to add and wire up secrets using agenix encryption.

## What This Skill Does

When you need to add a secret (API key, password, token, etc.), this skill:

1. ✅ Gets machine public keys
2. ✅ Encrypts secret value
3. ✅ Saves to proper domain location
4. ✅ Adds declaration to secrets index
5. ✅ Wires up service/container to use secret
6. ✅ Validates permissions and build

**Token savings**: ~75% - automated encryption and integration.

## Usage

Say: **"Provision secret for [service]"** or **"Add secret [name]"**

Examples:
- "Provision secret for Postgres database"
- "Add secret for N8N API key"
- "Create encrypted secret for VPN config"

## Workflow Steps

### Step 1: Gather Information

I'll ask you:
- **Secret name** (kebab-case, e.g., `postgres-password`, `n8n-api-key`)
- **Domain** (server/infrastructure/home/system)
- **Secret type** (password/api-key/token/file/env-file)
- **Which services use it?** (for wiring up)
- **Target machines** (laptop/server/both)
- **Secret value** (will be encrypted immediately)

### Step 2: Get Machine Public Keys

```bash
# For local machine
if [ -f /etc/age/keys.txt ]; then
  LOCAL_PUBKEY=$(sudo age-keygen -y /etc/age/keys.txt)
  echo "Local: $LOCAL_PUBKEY"
fi

# For remote machine
REMOTE_PUBKEY=$(ssh server "sudo age-keygen -y /etc/age/keys.txt" 2>/dev/null)
if [ -n "$REMOTE_PUBKEY" ]; then
  echo "Server: $REMOTE_PUBKEY"
fi

# If no access to machine, ask user to provide pubkey
```

### Step 3: Encrypt Secret

**Type A: Simple Value (Password/Token)**
```bash
# User provides value (interactively or as parameter)
read -s SECRET_VALUE

# Encrypt for single machine
echo -n "$SECRET_VALUE" | age -r "$PUBKEY" > "domains/secrets/parts/<domain>/<name>.age"

# Encrypt for multiple machines (create recipient file)
cat > /tmp/recipients << EOF
$LAPTOP_PUBKEY
$SERVER_PUBKEY
EOF

echo -n "$SECRET_VALUE" | age -R /tmp/recipients > "domains/secrets/parts/<domain>/<name>.age"
rm /tmp/recipients
```

**Type B: Environment File**
```bash
# Create template
cat > /tmp/<name> << EOF
# Environment variables for <service>
API_KEY=<value>
DATABASE_URL=postgresql://user:pass@localhost/db
SECRET_TOKEN=<value>
EOF

# User edits template with real values
${EDITOR:-nano} /tmp/<name>

# Encrypt
age -r "$PUBKEY" -o "domains/secrets/parts/<domain>/<name>.age" < /tmp/<name>

# Clean up
rm /tmp/<name>
```

**Type C: File (Config/Certificate)**
```bash
# User provides path to file
SOURCE_FILE="$1"

# Encrypt file
age -r "$PUBKEY" -o "domains/secrets/parts/<domain>/<name>.age" < "$SOURCE_FILE"
```

### Step 4: Add Declaration

Edit `domains/secrets/index.nix`:

```nix
{ config, ... }:
{
  imports = [
    # ... existing imports ...
  ];

  # Add new secret declaration
  age.secrets."<name>" = {
    file = ./parts/<domain>/<name>.age;
    path = "/run/agenix/<name>";
    mode = "0440";
    group = "secrets";
  };

  # If machine-specific:
  age.secrets."<name>" = lib.mkIf (config.networking.hostName == "hwc-server") {
    file = ./parts/<domain>/<name>.age;
    path = "/run/agenix/<name>";
    mode = "0440";
    group = "secrets";
  };
}
```

### Step 5: Wire Up Service

**For Systemd Service**:

```nix
# In service module (e.g., domains/system/services/<service>/index.nix)
systemd.services.<service> = {
  serviceConfig = {
    # Ensure service can read secrets
    Group = "secrets";  # Add if not present

    # Load environment file
    EnvironmentFile = config.age.secrets."<name>".path;

    # Or use specific secret as env var
    Environment = [
      "API_KEY_FILE=${config.age.secrets."<name>".path}"
    ];
  };
};

# Add validation
assertions = [{
  assertion = !cfg.enable || config.age.secrets."<name>".path != null;
  message = "<service> requires secret '<name>' to be configured";
}];
```

**For Podman Container**:

```nix
# In container module (e.g., domains/server/containers/<service>/index.nix)
virtualisation.oci-containers.containers.<service> = {
  # Environment file method (preferred)
  environmentFiles = [
    config.age.secrets."<name>".path
  ];

  # OR volume mount method (for config files)
  volumes = [
    "${config.age.secrets."<name>".path}:/config/secret.json:ro"
  ];
};

# Add validation
assertions = [{
  assertion = !cfg.enable || config.age.secrets."<name>".path != null;
  message = "<service> container requires secret '<name>'";
}];
```

**For User Access**:

```nix
# In user definition (e.g., domains/system/users/eric.nix)
users.users.eric = {
  extraGroups = [
    # ... existing groups ...
    "secrets"  # Add this
  ];
};

# User can now read: /run/agenix/<name>
```

**For Home Manager Config**:

```nix
# In HM module
home.file.".config/<app>/credentials".text =
  builtins.readFile config.age.secrets."<name>".path;

# Note: This embeds secret in world-readable home-manager store!
# Better: Use systemd user service that reads from /run/agenix
```

### Step 6: Validate Build

```bash
# Check secret file exists
ls -la domains/secrets/parts/<domain>/<name>.age

# Check it's encrypted (not plaintext)
file domains/secrets/parts/<domain>/<name>.age
# Should show: ASCII text (age-encrypted)

# Validate build
nixos-rebuild dry-build --flake .#<machine>
```

### Step 7: Deploy and Verify

```bash
# Deploy
nixos-rebuild switch --flake .#<machine>

# Verify secret was decrypted
sudo ls -la /run/agenix/<name>

# Check permissions
sudo ls -la /run/agenix/<name>
# Should show: -r--r----- root secrets

# Verify content (if needed)
sudo cat /run/agenix/<name>

# Test service can access
sudo systemctl status <service>
sudo journalctl -u <service> | grep -i secret
```

### Step 8: Document

Update service documentation:

```nix
# Add comment in module
/*
  Secret: <name>
  Location: /run/agenix/<name>
  Format: <password|env-file|config-file>
  Used by: <service-name>

  To rotate:
    echo "new-value" | age -r <pubkey> > domains/secrets/parts/<domain>/<name>.age
    nixos-rebuild switch
    sudo systemctl restart <service>
*/
```

## Secret Types & Formats

### Password (Single Value)
```bash
# Plain password
echo -n "mysecurepassword" | age -r "$PUBKEY" > file.age

# Used in service:
EnvironmentFile with: PASSWORD=mysecurepassword
```

### API Key
```bash
# Environment variable format
echo "API_KEY=sk_live_abc123xyz" | age -r "$PUBKEY" > file.age

# Used in container:
environmentFiles = [ ... ]
```

### Database Credentials
```bash
# Environment file with multiple values
cat > /tmp/db-creds << EOF
POSTGRES_USER=myapp
POSTGRES_PASSWORD=securepass
POSTGRES_DB=myapp_production
DATABASE_URL=postgresql://myapp:securepass@localhost:5432/myapp_production
EOF

age -r "$PUBKEY" -o file.age < /tmp/db-creds
rm /tmp/db-creds
```

### OAuth Credentials
```bash
cat > /tmp/oauth << EOF
CLIENT_ID=abc123
CLIENT_SECRET=xyz789
REDIRECT_URI=https://example.com/callback
EOF

age -r "$PUBKEY" -o file.age < /tmp/oauth
rm /tmp/oauth
```

### SSH Private Key
```bash
age -r "$PUBKEY" -o ssh-key.age < ~/.ssh/id_ed25519
```

### TLS Certificate
```bash
age -r "$PUBKEY" -o cert.age < /path/to/certificate.pem
```

### Configuration File (JSON/YAML)
```bash
age -r "$PUBKEY" -o config.age < config.json
```

## Multi-Machine Secrets

### Same Secret, Different Machines
```bash
# Create recipients file
cat > /tmp/recipients << EOF
age1laptop...
age1server...
EOF

# Encrypt once for all machines
echo -n "$SECRET" | age -R /tmp/recipients > domains/secrets/parts/<domain>/<name>.age

rm /tmp/recipients
```

### Machine-Specific Secrets
```bash
# Laptop secret
echo -n "$LAPTOP_SECRET" | age -r "$LAPTOP_PUBKEY" > \
  domains/secrets/parts/<domain>/<name>-laptop.age

# Server secret
echo -n "$SERVER_SECRET" | age -r "$SERVER_PUBKEY" > \
  domains/secrets/parts/<domain>/<name>-server.age

# In secrets/index.nix:
age.secrets."<name>" = lib.mkMerge [
  (lib.mkIf (config.networking.hostName == "hwc-laptop") {
    file = ./parts/<domain>/<name>-laptop.age;
  })
  (lib.mkIf (config.networking.hostName == "hwc-server") {
    file = ./parts/<domain>/<name>-server.age;
  })
  {
    path = "/run/agenix/<name>";
    mode = "0440";
    group = "secrets";
  }
];
```

## Secret Rotation

To update/rotate a secret:

```bash
# 1. Generate new value
NEW_SECRET="new-secure-value"

# 2. Re-encrypt with same public key(s)
echo -n "$NEW_SECRET" | age -r "$PUBKEY" > domains/secrets/parts/<domain>/<name>.age

# 3. Commit
git add domains/secrets/parts/<domain>/<name>.age
git commit -m "chore(secrets): rotate <name>"

# 4. Deploy
nixos-rebuild switch --flake .#<machine>

# 5. Restart affected services
sudo systemctl restart <service>
```

## Security Best Practices

✅ **Do**:
- Always use `mode = "0440"` and `group = "secrets"`
- Encrypt before committing (never commit plaintext!)
- Use environment files for containers
- Add service to `secrets` group
- Add assertions for secret dependencies
- Use descriptive names (`postgres-admin-password`, not `password`)
- Clean up temporary unencrypted files immediately

❌ **Don't**:
- Commit unencrypted secrets (ever!)
- Use mode "0444" (too permissive)
- Hardcode secrets in configs
- Share secrets between unrelated services
- Use generic names (`secret1`, `key`)
- Leave plaintext files in /tmp
- Forget to restart services after rotation

## Troubleshooting

### Secret Not Decrypted
```bash
# Check age key exists on machine
sudo ls -la /etc/age/keys.txt

# Test manual decryption
sudo age -d -i /etc/age/keys.txt domains/secrets/parts/<domain>/<name>.age
```

### Permission Denied
```bash
# Check secret permissions
sudo ls -la /run/agenix/<name>
# Should be: -r--r----- root secrets

# Check service is in secrets group
sudo systemctl cat <service> | grep Group

# Add if missing:
systemd.services.<service>.serviceConfig.Group = "secrets";
```

### Secret Not Loading in Container
```bash
# Check secret path is accessible
sudo podman exec <container> ls -la /run/agenix/<name>

# Check environmentFiles is set correctly
sudo podman inspect <container> | grep -A5 EnvironmentFiles

# Verify file is mounted
sudo podman inspect <container> | grep -A10 Mounts
```

### Wrong Pubkey Used
```bash
# Verify which pubkey was used
age-keygen -y /etc/age/keys.txt

# Compare with encrypted file's recipients (not directly visible)
# Re-encrypt with correct pubkey
```

## Checklist

Before marking complete:

- [ ] Secret value obtained (from user or generated)
- [ ] Machine public key(s) obtained
- [ ] Secret encrypted: `domains/secrets/parts/<domain>/<name>.age`
- [ ] File is actually encrypted (not plaintext!)
- [ ] Declaration added to `domains/secrets/index.nix`
- [ ] Service configured to use secret (environmentFiles/volumes)
- [ ] Service in `secrets` group (if needed)
- [ ] Assertion added for secret dependency
- [ ] Build succeeds: `nixos-rebuild dry-build`
- [ ] Secret decrypted: `sudo ls /run/agenix/<name>`
- [ ] Permissions correct: `-r--r----- root secrets`
- [ ] Service can access secret (test startup)
- [ ] Plaintext temp files cleaned up
- [ ] Documented in module comments

## Remember

**Secrets are critical infrastructure!**

- Encrypt immediately, never commit plaintext
- Use proper permissions (0440, secrets group)
- Validate service integration with assertions
- Test decryption on target machine
- Clean up temporary files
- Document which services use each secret

Security mistakes are expensive - double-check everything!
