---
name: Add Server Container
description: Automated workflow to deploy a new Podman container in nixos-hwc server domain with networking, storage, secrets, and reverse proxy integration
---

# Add Server Container Workflow

This skill provides a **complete automated workflow** to deploy a new Podman container to the nixos-hwc server.

## What This Skill Does

When you need to add a new containerized service (Postgres, Redis, Sonarr, etc.), this skill:

1. ✅ Creates proper module structure
2. ✅ Generates `options.nix` with correct namespace
3. ✅ Generates container definition with networking and volumes
4. ✅ Sets up secrets integration
5. ✅ Configures reverse proxy (if needed)
6. ✅ Creates state directories
7. ✅ Validates build and deployment

**Token savings**: ~80% compared to manual exploration and setup.

## Usage

Just say: **"Add server container for [service-name]"**

Examples:
- "Add server container for PostgreSQL"
- "Add server container for Sonarr"
- "Add server container for Redis"

## Workflow Steps

### Step 1: Gather Information

I'll ask you:
- **Service name** (kebab-case, e.g., `postgres`)
- **Docker image** (e.g., `postgres:16`)
- **Port(s)** (e.g., 5432)
- **Category** (media/services/databases/monitoring/business)
- **Needs secrets?** (Yes/No → environment files, API keys, passwords)
- **Needs reverse proxy?** (Yes/No → domain name)
- **Volumes needed** (config, data, etc.)
- **Network mode** (host/port-mapping/custom)
- **Dependencies** (other containers, native services)

### Step 2: Create Directory Structure

```bash
mkdir -p domains/server/containers/<name>
```

Creates: `domains/server/containers/<name>/`

### Step 3: Generate `options.nix`

```nix
# domains/server/containers/<name>/options.nix
{ lib, ... }: {
  options.hwc.server.containers.<name> = {
    enable = lib.mkEnableOption "<name> container";

    port = lib.mkOption {
      type = lib.types.port;
      default = <default-port>;
      description = "Port for <name> service";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "<name>.local";
      description = "Domain name for reverse proxy";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "<image>:<tag>";
      description = "Docker image to use";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/opt/<category>/<name>";
      description = "Directory for persistent data";
    };
  };
}
```

**Namespace**: `hwc.server.containers.<name>.*`

### Step 4: Generate Container Definition

**Template A: Simple Service**
```nix
# domains/server/containers/<name>/index.nix
{ config, pkgs, lib, ... }:
let
  cfg = config.hwc.server.containers.<name>;
in {
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    # IMPLEMENTATION
    virtualisation.oci-containers.containers.<name> = {
      image = cfg.image;

      ports = [
        "${toString cfg.port}:${toString cfg.port}"
      ];

      volumes = [
        "${cfg.dataDir}:/config"
      ];

      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/Los_Angeles";
      };
    };

    # Create state directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 1000 1000 -"
    ];

    # VALIDATION
  };
}
```

**Template B: Database (Localhost Only)**
```nix
{ config, pkgs, lib, ... }:
let
  cfg = config.hwc.server.containers.<name>;
in {
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    # IMPLEMENTATION
    virtualisation.oci-containers.containers.<name> = {
      image = cfg.image;

      # Bind to localhost only for security!
      ports = [
        "127.0.0.1:${toString cfg.port}:${toString cfg.port}"
      ];

      volumes = [
        "${cfg.dataDir}:/var/lib/<database>/data"
      ];

      environmentFiles = [
        config.age.secrets."<name>-env".path
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 999 999 -"  # Database UID
    ];

    # VALIDATION
    assertions = [{
      assertion = !cfg.enable || config.age.secrets."<name>-env".path != null;
      message = "hwc.server.containers.<name> requires secret '<name>-env'";
    }];
  };
}
```

**Template C: Media Service (*Arr Stack)**
```nix
{ config, pkgs, lib, ... }:
let
  cfg = config.hwc.server.containers.<name>;
in {
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    # IMPLEMENTATION
    virtualisation.oci-containers.containers.<name> = {
      image = cfg.image;

      ports = [
        "${toString cfg.port}:${toString cfg.port}"
      ];

      volumes = [
        "${cfg.dataDir}/config:/config"
        "/mnt/storage/media:/media"
        "/mnt/storage/downloads:/downloads"
      ];

      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/Los_Angeles";
      };

      environmentFiles = [
        config.age.secrets."<name>-api-key".path
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir}/config 0755 1000 1000 -"
    ];

    # VALIDATION
    assertions = [{
      assertion = !cfg.enable || config.age.secrets."<name>-api-key".path != null;
      message = "hwc.server.containers.<name> requires API key secret";
    }];
  };
}
```

### Step 5: Create Secrets (If Needed)

```bash
# Create environment file template
cat > /tmp/<name>-env << EOF
# Database credentials
POSTGRES_PASSWORD=CHANGEME
POSTGRES_USER=<name>
POSTGRES_DB=<name>

# API keys (if applicable)
API_KEY=CHANGEME
EOF

# Get server public key
SERVER_PUBKEY=$(ssh server "sudo age-keygen -y /etc/age/keys.txt")

# Encrypt
age -r "$SERVER_PUBKEY" -o domains/secrets/parts/server/<name>-env.age < /tmp/<name>-env

# Clean up
rm /tmp/<name>-env

echo "Secret created: domains/secrets/parts/server/<name>-env.age"
echo "IMPORTANT: Edit the secret with real values before committing!"
```

Add declaration to `domains/secrets/index.nix`:
```nix
age.secrets."<name>-env" = {
  file = ./parts/server/<name>-env.age;
  path = "/run/agenix/<name>-env";
  mode = "0440";
  group = "secrets";
};
```

### Step 6: Add Caddy Route (If Public)

Create `domains/server/containers/caddy/routes/<name>.nix`:

```nix
# domains/server/containers/caddy/routes/<name>.nix
{ config, ... }:
let
  cfg = config.hwc.server.containers.<name>;
in {
  "${cfg.domain}" = {
    reverse_proxy = {
      to = "http://localhost:${toString cfg.port}";
    };
  };
}
```

Import in `domains/server/containers/caddy/index.nix`:
```nix
imports = [
  # ... existing routes ...
  ./routes/<name>.nix
];
```

### Step 7: Add to Profile

Edit `profiles/server.nix` in **OPTIONAL FEATURES** section:

```nix
# profiles/server.nix
{
  #==========================================================================
  # OPTIONAL FEATURES
  #==========================================================================

  imports = [
    # ... existing imports ...
    ../domains/server/containers/<name>
  ];

  # Default enabled for production server
  hwc.server.containers.<name>.enable = lib.mkDefault true;
}
```

### Step 8: Validate Build

```bash
# Dry build
nixos-rebuild dry-build --flake .#server

# If successful, proceed to deployment
nixos-rebuild switch --flake .#server
```

### Step 9: Verify Deployment

```bash
# Check container status
sudo podman ps | grep <name>

# View logs
sudo podman logs -f <name>

# Check state directory
ls -la /opt/<category>/<name>/

# Test endpoint
curl http://localhost:<port>

# Test reverse proxy (if configured)
curl http://<domain>
```

## Category Guidelines

Choose the right category for organization:

### `/opt/media/<name>` - Media Stack
- Sonarr, Radarr, Lidarr, Readarr
- Prowlarr, Jackett
- Overseerr, Requestrr
- qBittorrent, SABnzbd, Transmission

### `/opt/services/<name>` - General Services
- N8N (automation)
- Home Assistant
- Paperless-ngx
- Vaultwarden

### `/opt/databases/<name>` - Databases
- PostgreSQL, MySQL, MariaDB
- MongoDB, Redis, Memcached
- InfluxDB, TimescaleDB

### `/opt/monitoring/<name>` - Observability
- Prometheus, Grafana
- Loki, Promtail
- Uptime Kuma
- Netdata

### `/opt/business/<name>` - Business Apps
- Invoicing, accounting
- CRM, project management
- Custom business apps

## Networking Patterns

### Port Mapping (Default)
```nix
ports = [
  "8080:8080"  # External:Internal
];
```

**Use when**: Most services, need external access

### Localhost Only (Databases)
```nix
ports = [
  "127.0.0.1:5432:5432"  # Bind to localhost only
];
```

**Use when**: Databases, internal-only services

### Host Network
```nix
extraOptions = [ "--network=host" ];
# No ports needed
```

**Use when**: Services need device discovery, multicast, or complex networking

**Warning**: Less isolation, use sparingly!

### Custom Network
```nix
# Create network first
systemd.services.podman-network-media = {
  serviceConfig.Type = "oneshot";
  wantedBy = [ "default.target" ];
  script = ''
    ${pkgs.podman}/bin/podman network inspect media || \
    ${pkgs.podman}/bin/podman network create media --subnet 10.88.0.0/24
  '';
};

# Use in container
extraOptions = [ "--network=media" ];
```

**Use when**: Containers need to communicate, isolation from host

## Common Patterns

### LinuxServer.io Image
```nix
virtualisation.oci-containers.containers.<name> = {
  image = "linuxserver/<name>:latest";
  environment = {
    PUID = "1000";  # Standard user
    PGID = "1000";  # Standard group
    TZ = "America/Los_Angeles";
  };
  volumes = [
    "/opt/<category>/<name>:/config"
  ];
};
```

### Database with Initialization
```nix
virtualisation.oci-containers.containers.postgres = {
  image = "postgres:16";
  environmentFiles = [ config.age.secrets."postgres-env".path ];
  volumes = [
    "/opt/databases/postgres/data:/var/lib/postgresql/data"
    "/opt/databases/postgres/init:/docker-entrypoint-initdb.d:ro"
  ];
};
```

### Service with Health Check
```nix
virtualisation.oci-containers.containers.<name> = {
  # ... config ...

  extraOptions = [
    "--health-cmd=curl -f http://localhost:8080/health || exit 1"
    "--health-interval=30s"
    "--health-retries=3"
    "--health-start-period=40s"
  ];
};
```

## Secrets Best Practices

**Environment File Format**:
```bash
# Good - environment variable format
DATABASE_URL=postgresql://user:pass@localhost/db
API_KEY=abc123xyz
SECRET_TOKEN=random-secure-token

# Bad - shell script
export DATABASE_URL=...  # Don't use 'export'
```

**Multiple Secrets**:
```nix
environmentFiles = [
  config.age.secrets."<name>-db".path
  config.age.secrets."<name>-api".path
];
```

**File Secrets**:
```nix
volumes = [
  "/run/agenix/<name>-cert:/config/cert.pem:ro"
];
```

## Checklist

Before marking complete:

- [ ] Directory created: `domains/server/containers/<name>/`
- [ ] `options.nix` with `hwc.server.containers.<name>.*` namespace
- [ ] `index.nix` with container definition
- [ ] Secrets created and encrypted (if needed)
- [ ] Secrets declared in `domains/secrets/index.nix`
- [ ] Caddy route added (if public-facing)
- [ ] Added to `profiles/server.nix` OPTIONAL section
- [ ] State directory will be created via tmpfiles.rules
- [ ] Dependencies have assertions
- [ ] Build succeeds: `nixos-rebuild dry-build --flake .#server`
- [ ] Container starts: `sudo podman ps | grep <name>`
- [ ] Service accessible on expected port
- [ ] Reverse proxy works (if configured)

## Troubleshooting

### Container Won't Start
```bash
# Check logs
sudo podman logs <name>

# Check systemd service
sudo systemctl status podman-<name>
sudo journalctl -u podman-<name>
```

### Permission Denied on Volumes
```bash
# Check ownership
ls -la /opt/<category>/<name>

# Fix
sudo chown -R 1000:1000 /opt/<category>/<name>
```

### Can't Access Service
```bash
# Check container is running
sudo podman ps

# Check port binding
sudo podman port <name>

# Test from localhost
curl http://localhost:<port>

# Check firewall (if accessing from other machine)
sudo iptables -L | grep <port>
```

### Secret Not Loading
```bash
# Verify secret exists
sudo ls -la /run/agenix/<name>-env

# Test decryption
sudo cat /run/agenix/<name>-env

# Check container has access
sudo podman exec <name> env | grep <VAR>
```

## Remember

This is a **complete deployment workflow**:
1. Gather requirements
2. Create structure
3. Generate container definition
4. Set up secrets
5. Configure networking/proxy
6. Integrate with profiles
7. Validate build
8. Deploy and verify

Don't skip validation steps - containers that build but don't start waste time!
