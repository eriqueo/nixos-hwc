# Agenix Secrets Management Skill

This skill automates common agenix/age secret management workflows to minimize token usage.

## Skill Trigger

Use this skill when the user requests:
- "Add a new secret"
- "Create an age secret"
- "Update a secret"
- "Add secret for [service]"
- Any task involving agenix/age encrypted secrets

## Prerequisites Check

Before starting, verify:
```bash
# Check age key exists
sudo test -f /etc/age/keys.txt && echo "✓ Age key found" || echo "✗ No age key - run: workspace/utilities/scripts/deploy-age-keys.sh"
```

## Workflow Decision Tree

Ask user ONE question to determine workflow:

**"What would you like to do?"**
1. Add a new secret
2. Update an existing secret
3. View a secret (decrypt for testing)
4. List all secrets

Based on answer, execute the appropriate workflow below.

---

## Workflow 1: Add a New Secret

**Required inputs from user:**
- Secret name (e.g., "plex-api-key")
- Domain (system/server/infrastructure/home/apps/caddy)
- Secret value (or ask if they want to input it securely)
- Optional: owner (default: root), group (default: secrets), mode (default: 0440)

**Steps:**

### 1. Get age public key
```bash
AGE_KEY=$(sudo cat /etc/age/keys.txt | grep "public key:" | awk '{print $4}')
echo "Using public key: $AGE_KEY"
```

### 2. Create encrypted file
```bash
# Interactive (secure - won't show in history)
read -s -p "Enter secret value: " SECRET_VALUE
echo "$SECRET_VALUE" | age -r $AGE_KEY > domains/secrets/parts/[DOMAIN]/[SECRET-NAME].age

# Or non-interactive (if user provides value)
echo "[SECRET-VALUE]" | age -r $AGE_KEY > domains/secrets/parts/[DOMAIN]/[SECRET-NAME].age
```

### 3. Add declaration
Edit `domains/secrets/declarations/[DOMAIN].nix`:
```nix
age.secrets = {
  # ... existing secrets ...

  [SECRET-NAME] = {
    file = ../parts/[DOMAIN]/[SECRET-NAME].age;
    mode = "[MODE]";      # e.g., "0440"
    owner = "[OWNER]";    # e.g., "root"
    group = "[GROUP]";    # e.g., "secrets"
  };
};
```

### 4. Add to API facade
Edit `domains/secrets/secrets-api.nix`:
```nix
config.hwc.secrets.api = {
  # ... existing ...
  [secretNameCamelCase]File = pathOrNull "[SECRET-NAME]";
};
```

### 5. Add option definition
Edit `domains/secrets/options.nix`:
```nix
options.hwc.secrets.api = {
  # ... existing ...
  [secretNameCamelCase]File = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    readOnly = true;
    description = "Path to decrypted [description] file";
  };
};
```

### 6. Verify and rebuild
```bash
# Check syntax
nix-instantiate --parse domains/secrets/declarations/[DOMAIN].nix > /dev/null
nix-instantiate --parse domains/secrets/secrets-api.nix > /dev/null

# Rebuild
sudo nixos-rebuild switch --flake .#[HOSTNAME]
```

**Token-saving tips:**
- Only ask for required inputs (name, domain, value)
- Use defaults for owner/group/mode unless user specifies
- Auto-generate camelCase name from hyphenated name
- Auto-detect if secret is for server/laptop based on current hostname

---

## Workflow 2: Update an Existing Secret

**Required inputs:**
- Secret name (or path to .age file)
- New secret value

**Steps:**

### 1. Locate the .age file
```bash
# User provides name
find domains/secrets/parts -name "[SECRET-NAME].age"

# Or user provides path directly
```

### 2. Show current value (optional)
```bash
sudo age -d -i /etc/age/keys.txt [PATH-TO-AGE-FILE]
```

### 3. Re-encrypt with new value
```bash
AGE_KEY=$(sudo cat /etc/age/keys.txt | grep "public key:" | awk '{print $4}')

# Interactive
read -s -p "Enter new secret value: " NEW_VALUE
echo "$NEW_VALUE" | age -r $AGE_KEY > [PATH-TO-AGE-FILE]

# Or non-interactive
echo "[NEW-VALUE]" | age -r $AGE_KEY > [PATH-TO-AGE-FILE]
```

### 4. Rebuild
```bash
sudo nixos-rebuild switch --flake .#[HOSTNAME]
```

**Token-saving tips:**
- Skip showing current value unless user asks
- No need to edit any .nix files - just re-encrypt
- Auto-find .age file if user gives just the name

---

## Workflow 3: View a Secret (Decrypt)

**Required inputs:**
- Secret name or path

**Steps:**

```bash
# Find the file
AGE_FILE=$(find domains/secrets/parts -name "[SECRET-NAME].age" | head -1)

# Decrypt and show
sudo age -d -i /etc/age/keys.txt "$AGE_FILE"
```

**Token-saving tips:**
- Single command, minimal output
- Only show the secret value, not explanatory text

---

## Workflow 4: List All Secrets

**Steps:**

```bash
# List by domain
find domains/secrets/parts -name "*.age" -type f | sort

# Or structured output
echo "=== Secrets by Domain ==="
for domain in system server infrastructure home apps caddy; do
  count=$(find domains/secrets/parts/$domain -name "*.age" 2>/dev/null | wc -l)
  if [ $count -gt 0 ]; then
    echo "$domain: $count secrets"
    find domains/secrets/parts/$domain -name "*.age" 2>/dev/null | sed 's|.*/||; s|\.age$||' | sed 's/^/  - /'
  fi
done
```

**Token-saving tips:**
- Provide both formats, ask which they prefer
- Cache the list for the conversation

---

## Common Patterns & Shortcuts

### Auto-detect domain from secret name
```
*-api-key, *-username, *-password, slskd-* → server
database-*, vpn-*, rtsp-*, frigate-* → infrastructure
*-bridge-*, gmail-*, proton-* → home
user-*, emergency-*, ssh-* → system
fabric-* → apps
*.crt, *.key, *.pem → caddy
```

### CamelCase conversion
```
radarr-api-key → radarrApiKey
vpn-username → vpnUsername
user-initial-password → userInitialPassword
```

### Common owner/group/mode combinations
```
Service secret: root:secrets 0440
User secret: eric:users 0440
Certificate: caddy:caddy 0440
Strict secret: root:root 0400
```

---

## Error Handling

### If age key doesn't exist:
```
Error: /etc/age/keys.txt not found

Run: sudo nix-shell -p age --run "age-keygen > /etc/age/keys.txt"
Then: sudo chmod 600 /etc/age/keys.txt
```

### If declaration fails syntax check:
```
Re-read the declaration file and check:
- Commas between attributes
- Semicolons after closing braces
- Proper indentation
- No duplicate secret names
```

### If rebuild fails with "secret not found":
```
Check:
1. .age file exists at the path specified in declaration
2. Path in declaration matches actual file location
3. File is readable by root: sudo ls -la [PATH]
```

---

## Usage Examples

**Example 1: Simple secret addition**
```
User: "Add a secret for jellyfin api key"

1. Auto-detect: domain=server, name=jellyfin-api-key
2. Ask: "What's the API key value?"
3. User provides value
4. Execute Workflow 1 with defaults (root:secrets:0440)
5. Report: "✓ Created jellyfin-api-key in server domain, accessible via config.hwc.secrets.api.jellyfinApiKeyFile"
```

**Example 2: Update existing secret**
```
User: "Update the sonarr api key"

1. Find: domains/secrets/parts/server/sonarr-api-key.age
2. Ask: "New API key value?"
3. Re-encrypt
4. Rebuild
5. Report: "✓ Updated sonarr-api-key"
```

**Example 3: Custom permissions**
```
User: "Add ntfy admin password for user eric"

1. Detect: domain=server, name=ntfy-admin-password
2. Ask: "Password value?"
3. User specifies: owner=eric, group=users
4. Execute with custom permissions
5. Report: "✓ Created with owner=eric"
```

---

## Skill Output Format

Always provide:
1. **Summary** - What was done in 1 sentence
2. **Files modified** - List of .nix and .age files changed
3. **Next step** - Rebuild command or how to use the secret
4. **Access path** - How consumers should reference it

**Example output:**
```
✓ Added radarr-api-key secret

Files modified:
- domains/secrets/parts/server/radarr-api-key.age (created)
- domains/secrets/declarations/server.nix (added declaration)
- domains/secrets/secrets-api.nix (added radarrApiKeyFile)
- domains/secrets/options.nix (added option)

Next: sudo nixos-rebuild switch --flake .#hwc-server

Access in modules:
  config.hwc.secrets.api.radarrApiKeyFile
  → /run/agenix/radarr-api-key (after rebuild)
```

---

## Token Optimization Rules

1. **Don't explore** - Use the domain/pattern detection to know where files are
2. **Minimize questions** - Auto-detect as much as possible, use defaults
3. **Batch operations** - Edit all related files in one go
4. **Skip explanations** - User knows agenix, just execute
5. **Use templates** - Don't read existing files unless necessary
6. **Cache context** - Remember secret names/paths mentioned in conversation

---

## Security Reminders

- ⚠️ Never log or display secret values in git commits
- ⚠️ Use `read -s` for interactive input (doesn't show in history)
- ⚠️ Verify .age files are added to git (they're encrypted, safe to commit)
- ⚠️ Check that secrets group exists: `users.groups.secrets = {};`
