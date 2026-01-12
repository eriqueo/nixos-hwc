# Config-First Service Configuration Pattern

**Source**: Extracted from Charter v8.0 Section 22
**Related**: Charter v9.0 Section 2 (Server Domain - Config-First Rule)
**Applies To**: Complex services with substantial configuration schemas

## Overview

For **complex services** (Frigate, Jellyfin, SABnzbd, Home Assistant, Traefik, etc.), maintain canonical configuration in the service's native format (YAML/TOML/INI/XML) rather than generating it from Nix options.

**Core Principle**: Nix handles **infrastructure** (container image, volumes, ports, GPU). Service config stays in **service format** (YAML/TOML/etc.).

---

## The Config-First Rule

### Pattern Requirements

#### 1. Canonical Config File

- Maintain service configuration in the format the service expects (YAML/TOML/INI/XML)
- Store in module directory: `domains/server/<service>/config/config.yml`
- This file is **version-controlled** and **human-readable**
- This file is **portable** - can work on non-NixOS systems with minimal changes

#### 2. Nix Responsibilities (Infrastructure Only)

Nix code handles **only** these concerns:
- Container image/version pinning
- Volume mounts (including config file)
- Port mappings
- GPU/device passthrough
- Environment variables
- Resource limits

Nix does **NOT**:
- Generate service-specific YAML/TOML/INI/XML
- Encode complex service schemas in Nix options
- Interpolate service config from Nix strings

#### 3. Module Structure

```
domains/server/<service>/
├── options.nix         # Nix-level options (image, ports, GPU, etc.)
├── index.nix           # Container definition (infrastructure only)
├── config/
│   ├── config.yml      # Canonical service config (mounted into container)
│   └── config.example  # Template/example config (optional)
├── README.md           # Service documentation
└── SAFETY.md           # Safety notes (if applicable)
```

#### 4. Debug Workflow

**Config-First Debugging**:
1. Edit `config/config.yml` directly
2. Restart service to apply changes: `systemctl restart podman-<service>`
3. Test and verify
4. Once stable, commit the config file

**NOT** (Anti-Pattern):
1. Edit Nix options
2. Rebuild system to generate YAML
3. Hope generated YAML is correct
4. Debug by inspecting generated files
5. Repeat until it works

---

## Rationale

### Why Config-First?

✅ **Debuggability**
- Config is visible in version control
- Not hidden in Nix string interpolation or generated files
- Direct file editing without system rebuild

✅ **Portability**
- Config works on Docker/Podman/k8s with minimal changes
- Not tied to NixOS-specific patterns
- Can migrate to other platforms easily

✅ **Validation**
- Service's native validation tools work directly
- Upstream config checkers/linters apply
- Schema errors caught by service, not Nix

✅ **Documentation**
- Upstream documentation directly applicable
- Examples from community work as-is
- No translation between Nix and service config

✅ **Complexity Management**
- Service complexity stays in service format
- Nix complexity stays simple (infrastructure only)
- Clear separation of concerns

---

## Anti-Pattern (What NOT to Do)

### ❌ BAD: Encoding Service Config in Nix

```nix
# domains/server/frigate/options.nix (DON'T DO THIS)
hwc.server.frigate = {
  detectors.onnx = {
    type = "onnx";
    model = {
      path = "/config/model.onnx";
      input_dtype = "float";
      width = 320;
      height = 320;
    };
  };

  cameras.front_door = {
    ffmpeg.inputs = [
      {
        path = "rtsp://admin:password@192.168.1.10:554/stream";
        roles = [ "detect" "record" ];
      }
    ];
    detect = {
      width = 1920;
      height = 1080;
      fps = 5;
    };
    record = {
      enabled = true;
      retain.days = 7;
      events.retain.default = 30;
    };
    snapshots.enabled = true;
    # ... 50 more options per camera
  };

  cameras.back_door = {
    # ... another 50+ options
  };
};

# domains/server/frigate/index.nix (DON'T DO THIS)
config = lib.mkIf enabled {
  # Generate YAML from Nix options
  environment.etc."frigate/config.yml".text = lib.generators.toYAML {} {
    detectors = cfg.detectors;
    cameras = cfg.cameras;
    # ... complex YAML generation logic
  };
};
```

**Why This Fails**:
- YAML structure errors hidden in Nix indentation
- Service schema changes require Nix module updates
- Debugging requires inspecting generated files in `/nix/store/`
- Not portable outside NixOS
- Upstream docs don't map to Nix options
- Config validation must be reimplemented in Nix

---

## Correct Pattern (Config-First)

### ✅ GOOD: Nix Handles Infrastructure, Config in Native Format

**domains/server/frigate/options.nix** (Infrastructure only):
```nix
{ lib, ... }:
{
  options.hwc.server.frigate = {
    enable = lib.mkEnableOption "Frigate NVR";

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/blakeblackshear/frigate:0.16.2";
      description = "Container image (explicit version pinning)";
    };

    gpu.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable GPU acceleration";
    };

    ports = {
      web = lib.mkOption {
        type = lib.types.int;
        default = 5000;
        description = "Web UI port";
      };
      rtsp = lib.mkOption {
        type = lib.types.int;
        default = 8554;
        description = "RTSP restream port";
      };
    };
  };
}
```

**domains/server/frigate/index.nix** (Container definition):
```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.server.frigate;
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.containers.frigate = {
      image = cfg.image;

      volumes = [
        # Mount canonical config file
        "${./config/config.yml}:/config/config.yml:ro"
        "${config.hwc.paths.media.surveillance}/frigate/media:/media"
        "${config.hwc.paths.hot.surveillance}/frigate/buffer:/tmp/cache"
      ];

      ports = [
        "${toString cfg.ports.web}:5000"
        "${toString cfg.ports.rtsp}:8554"
      ];

      # Infrastructure concerns only
      environment = {
        PUID = "1000";
        PGID = "100";
        TZ = config.time.timeZone;
      };

      extraOptions = lib.optionals cfg.gpu.enable [
        "--device=/dev/dri:/dev/dri"
      ];
    };
  };
}
```

**domains/server/frigate/config/config.yml** (Canonical service config):
```yaml
# Frigate Configuration
# This is the canonical config - edit directly and restart service

mqtt:
  enabled: true
  host: 192.168.1.5

detectors:
  onnx:
    type: onnx
    device: GPU
    model:
      path: /config/model_cache/yolov7-320.onnx

cameras:
  front_door:
    ffmpeg:
      inputs:
        - path: rtsp://admin:{FRIGATE_RTSP_PASSWORD}@192.168.1.10:554/stream
          roles:
            - detect
            - record
    detect:
      width: 1920
      height: 1080
      fps: 5
    record:
      enabled: true
      retain:
        days: 7
      events:
        retain:
          default: 30
    snapshots:
      enabled: true

  back_door:
    # ... similar structure for other cameras
```

---

## When to Use Config-First

### Use Config-First For:

✅ Services with **>50 lines** of configuration
✅ Services with **complex nested schemas** (Frigate, Home Assistant, Traefik)
✅ Services where **upstream docs reference config files** directly
✅ Services you need to **debug frequently**
✅ Services with **frequent schema changes** upstream

**Examples**: Frigate, Jellyfin, Home Assistant, Traefik, Caddy, Grafana

### Nix Options Are Fine For:

✅ Simple services with **<20 config options**
✅ Services where **Nix options ARE the canonical interface** (NixOS services)
✅ **Infrastructure concerns** (ports, volumes, env vars) only
✅ Services with **stable, simple schemas**

**Examples**: Most NixOS services, simple utilities, infrastructure components

---

## Secrets Integration

Secrets (passwords, API keys) still use agenix, but referenced in config files:

### Option 1: File Path References

```yaml
# config.yml
database:
  password_file: /run/agenix/frigate-db-password
```

### Option 2: Environment Variable Substitution

```yaml
# config.yml
rtsp:
  password: "{FRIGATE_RTSP_PASSWORD}"  # Substituted by container
```

```nix
# index.nix
environmentFiles = [ config.age.secrets.frigate-env.path ];
```

### What NOT to Do:

❌ **Don't inline secrets** in version-controlled config files:
```yaml
# config.yml (DON'T DO THIS)
database:
  password: "hunter2"  # Plaintext secret in git!
```

---

## Validation Requirements

Modules using config-first pattern **MUST**:

1. **Document config file location** in `README.md`
   ```markdown
   ## Configuration

   Service config: `domains/server/frigate/config/config.yml`

   Edit this file directly and restart service to apply changes.
   ```

2. **Provide example/template config** (optional but recommended)
   - Include `config/config.example` with documented defaults
   - Or link to upstream examples

3. **Include verification script** (if possible)
   ```bash
   # Validate config before applying
   nix-shell -p frigate --run "frigate --validate-config config.yml"
   ```

4. **Document validation method** (service's native tools)
   ```markdown
   ## Validation

   Validate config with Frigate's built-in checker:
   ```bash
   podman exec frigate python3 -m frigate --validate-config
   ```
   ```

---

## Migration from Nix-Generated Configs

When migrating existing modules from Nix-generated to config-first:

### Step-by-Step Migration

1. **Extract current runtime config**
   ```bash
   # Get the config that's currently working
   podman exec frigate cat /config/config.yml > domains/server/frigate/config/config.yml
   ```

2. **Save to module directory and commit**
   ```bash
   git add domains/server/frigate/config/config.yml
   git commit -m "feat(frigate): extract canonical config (baseline)"
   ```

3. **Modify Nix to mount file instead of generating**
   ```nix
   # Before
   environment.etc."frigate/config.yml".text = lib.generators.toYAML {} {...};

   # After
   volumes = [
     "${./config/config.yml}:/config/config.yml:ro"
   ];
   ```

4. **Verify service works identically**
   ```bash
   sudo nixos-rebuild test --flake .#hwc-server
   systemctl status podman-frigate
   # Test service functionality
   ```

5. **Only then refactor config as needed**
   - Clean up redundant options
   - Add comments/documentation
   - Organize sections logically

### Preserve-First Doctrine

Follow Charter Section 0 (Preserve-First):
- **Start with exact copy** of working config
- **Verify identical behavior** before refactoring
- **100% feature parity** during migration
- **Never switch on red builds**

---

## Benefits Summary

| Aspect | Config-First | Nix-Generated |
|--------|-------------|---------------|
| **Debuggability** | Direct file editing | Inspect generated files |
| **Portability** | Works anywhere | NixOS-specific |
| **Validation** | Native tools | Reimplemented in Nix |
| **Documentation** | Upstream applies | Translation needed |
| **Complexity** | Service format | Nix + service format |
| **Rebuild** | Service restart only | Full system rebuild |

---

## Real-World Examples

### Frigate
- **Config**: `domains/server/native/frigate/config/config.yml`
- **Complexity**: 200+ lines, nested camera configs, detection zones
- **Why Config-First**: Frequent camera adjustments, complex RTSP configs

### Jellyfin
- **Config**: Network config, library paths, transcoding settings
- **Why Config-First**: Complex media library structure, transcoding profiles

### Caddy
- **Config**: `domains/server/containers/caddy/config/Caddyfile`
- **Complexity**: Reverse proxy routes, TLS config, middleware
- **Why Config-First**: Frequent route changes, upstream Caddyfile docs apply directly

---

## See Also

- **Charter v9.0 Section 2**: Server Domain Overview (Config-First Rule)
- **domains/server/README.md**: Container patterns and standards
- **docs/patterns/container-standard.md**: mkContainer helper usage
