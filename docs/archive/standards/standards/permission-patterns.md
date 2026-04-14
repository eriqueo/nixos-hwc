# Permission Patterns - nixos-hwc

**Authority**: CHARTER.md v6.0 compliance
**Last Updated**: 2025-12-11
**Version**: 1.0

---

## Unified Permission Model

**Principle**: Single-user system using `eric:users` (UID 1000, GID 100)

All services run as `eric:users` for simplicity in a personal infrastructure.
Service isolation is achieved through directory structure, not user separation.

### Core UID/GID Assignments

| Entity | UID | GID | Purpose |
|--------|-----|-----|---------|
| eric (user) | 1000 | - | Primary system user |
| users (group) | - | 100 | Primary user group |
| secrets (group) | - | (dynamic) | Secret access control |
| root | 0 | 0 | System administration |

**CRITICAL**: The `users` group is GID **100**, not 1000!

---

## Standard Patterns

### Pattern 1: Container Services

**When to Use**: Podman containers for ARR stack, downloaders, media tools

**Configuration**:
```nix
# In container module (e.g., domains/server/radarr/index.nix)
virtualisation.oci-containers.containers.myservice = {
  image = "...";
  environment = {
    PUID = "1000";  # eric UID
    PGID = "100";   # users GID (CRITICAL!)
    TZ = config.time.timeZone;
  };
  volumes = [
    "/mnt/media:/media:rw"
    "${cfg.dataDir}:/config:rw"
  ];
};
```

**Key Rules**:
- ALWAYS use `PGID="100"` (users group)
- NEVER use `PGID="1000"` (doesn't exist!)
- Use shared libraries: `config.hwc.services.shared.lib.mkContainer`
- Volumes must point to directories owned by `eric:users`

**Common Containers**: radarr, sonarr, lidarr, prowlarr, qbittorrent, sabnzbd, slskd

---

### Pattern 2: Native System Services (with StateDirectory)

**When to Use**: NixOS native services (Grafana, Prometheus, Jellyfin, etc.)

**Configuration**:
```nix
# In service module (e.g., domains/server/jellyfin/index.nix)
systemd.services.jellyfin = {
  serviceConfig = {
    User = lib.mkForce "eric";
    Group = lib.mkForce "users";
    StateDirectory = "hwc/jellyfin";
    CacheDirectory = "hwc/jellyfin";
  };
};
```

**Key Rules**:
- Use `lib.mkForce` to override default service user
- StateDirectory automatically creates `/var/lib/hwc/<service>` as `eric:users`
- Document why service runs as eric (not dedicated user) in comments
- Add assertion validating user configuration in VALIDATION section

**Why mkForce?**: NixOS modules default to creating dedicated service users.
We override this for unified permission model.

**Common Services**: jellyfin, navidrome, grafana, prometheus, couchdb

---

### Pattern 3: Secret Access

**When to Use**: Services needing encrypted credentials from agenix

**Configuration**:
```nix
# In module using secrets
config = lib.mkIf cfg.enable {
  # Service configuration
  services.myservice = {
    passwordFile = config.age.secrets.myservice-password.path;
  };

  # Ensure service user in secrets group
  users.users.eric.extraGroups = [ "secrets" ];  # Already configured
};

# In domains/secrets/declarations/server.nix
age.secrets.myservice-password = {
  file = ../../parts/server/myservice-password.age;
  mode = "0440";
  owner = "root";
  group = "secrets";
};
```

**Key Rules**:
- All secrets: `mode = "0440"`, `group = "secrets"`
- Mounted at: `/run/agenix/<secret-name>`
- Service user MUST be in `secrets` group
- Use `config.age.secrets.<name>.path` for secret paths
- Never hardcode `/run/agenix` paths

**Secret Lifecycle**:
1. Encrypt: `age -r <pubkey> -e input > secret.age`
2. Declare in `domains/secrets/declarations/`
3. Reference via `config.age.secrets.<name>.path`
4. Service user must be in `secrets` group

---

### Pattern 4: Storage Tier Directories

**When to Use**: Bind mounts to /mnt/hot, /mnt/media, etc.

**Configuration**:
```nix
# In domains/infrastructure/storage/index.nix
systemd.tmpfiles.rules = [
  "d /mnt/hot 0755 root root -"
  "d /mnt/hot/downloads 0755 eric users -"
  "d /mnt/media/movies 0755 eric users -"
];
```

**Key Rules**:
- Mount points: `root:root` (system-level)
- Subdirectories: `eric:users` (user-accessible)
- Mode 0755 for directories (rwxr-xr-x)
- Mode 0644 for files (rw-r--r--)
- Use tmpfiles for declarative directory creation

**Storage Tiers**:
- `/mnt/hot` - SSD, active processing
- `/mnt/media` - HDD, media library
- `/mnt/archive` - Cold storage
- `/mnt/backup` - Backup storage

---

## Decision Tree

**Question**: What type of service am I adding?

```
Container (Podman/Docker)?
├─ YES → Use Pattern 1 (Container Services)
│         - PGID="100" (CRITICAL!)
│         - Use shared mkContainer helper
│
└─ NO → Is it a NixOS native service?
        ├─ YES → Use Pattern 2 (StateDirectory)
        │         - User = mkForce "eric"
        │         - StateDirectory = "hwc/<service>"
        │
        └─ NO → Does it need secrets?
                ├─ YES → Use Pattern 3 (Secret Access)
                │         - mode = "0440", group = "secrets"
                │
                └─ NO → Does it access storage tiers?
                        └─ YES → Use Pattern 4 (Storage Tier Directories)
                                  - Mount: root:root
                                  - Subdirs: eric:users
```

---

## Anti-Patterns (DO NOT DO)

❌ **Using PGID="1000"** (users is GID 100, not 1000!)

❌ **Creating dedicated service users** (breaks unified model)

❌ **Hardcoding /run/agenix paths** (use config.age.secrets.<name>.path)

❌ **Forgetting mkForce** (NixOS creates default users)

❌ **Missing secrets group** (service won't access secrets)

❌ **StateDirectory without User/Group** (ownership unclear)

❌ **root:root for user-accessible dirs** (containers can't write)

---

## Examples

### Good: Container with Correct PGID
```nix
virtualisation.oci-containers.containers.radarr = {
  image = "lscr.io/linuxserver/radarr:latest";
  environment = {
    PUID = "1000";
    PGID = "100";  # ✅ CORRECT
    TZ = "America/Denver";
  };
};
```

### Bad: Container with Wrong PGID
```nix
virtualisation.oci-containers.containers.radarr = {
  image = "lscr.io/linuxserver/radarr:latest";
  environment = {
    PUID = "1000";
    PGID = "1000";  # ❌ WRONG - will create files with incorrect group
    TZ = "America/Denver";
  };
};
```

### Good: Service with mkForce
```nix
systemd.services.jellyfin = {
  serviceConfig = {
    User = lib.mkForce "eric";  # ✅ Override default
    Group = lib.mkForce "users";
    StateDirectory = "hwc/jellyfin";
  };
};
```

### Bad: Service without mkForce
```nix
systemd.services.jellyfin = {
  serviceConfig = {
    User = "eric";  # ❌ Will be overridden by NixOS module defaults
    StateDirectory = "hwc/jellyfin";
  };
};
```

---

## Validation

Before deploying changes:

```bash
# Run charter linter
./workspace/utilities/lints/charter-lint.sh domains/server

# Check for PGID="1000" in code
rg 'PGID.*=.*"1000"' domains/server/containers/

# Test build
sudo nixos-rebuild test --flake .#hwc-server
```

After deployment:

```bash
# Verify container PGID
sudo podman inspect <container> | jq '.[0].Config.Env | .[] | select(contains("PGID"))'

# Check for GID=1000 files
find /mnt/hot /mnt/media -group 1000 2>/dev/null | wc -l

# Verify service user
systemctl show <service> | grep -E '^User=|^Group='
```

---

## References

- **CHARTER.md**: Permission Model section
- **docs/troubleshooting/permissions.md**: Troubleshooting guide
- **workspace/utilities/lints/charter-lint.sh**: Validation linter
- **Plan Document**: `/home/eric/.claude/plans/structured-dazzling-backus.md`

---

**Version History**:
- v1.0 (2025-12-11): Initial permission patterns documentation
