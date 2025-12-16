# Systemd Service Refactoring Proposals

This document contains **concrete diff patches** for refactoring the most problematic systemd services identified in the audit.

---

## Diff 1: Fix GPU Monitor Service

**File:** `domains/infrastructure/hardware/parts/gpu.nix`
**Lines:** 154-172
**Severity:** HIGH
**Issues:** Runs as root, uses bash while-loop, hard-coded paths, no hardening

### Proposed Changes

```diff
--- a/domains/infrastructure/hardware/parts/gpu.nix
+++ b/domains/infrastructure/hardware/parts/gpu.nix
@@ -151,23 +151,54 @@
       ];

-      # Optional: nvidia-smi monitoring
-      systemd.services.gpu-monitor = lib.mkIf cfg.nvidia.enableMonitoring {
-        description = "NVIDIA GPU utilization monitoring";
+      # Optional: nvidia-smi monitoring (converted to timer-based)
+      systemd.services.gpu-metrics-collect = lib.mkIf cfg.nvidia.enableMonitoring {
+        description = "Collect NVIDIA GPU metrics";
         serviceConfig = {
-          Type = "simple";
-          User = "root";
-          ExecStart = pkgs.writeShellScript "gpu-monitor" ''
-            #!/usr/bin/env bash
-            while true; do
-              ${config.boot.kernelPackages.nvidiaPackages.${cfg.nvidia.driver}}/bin/nvidia-smi \
-                --query-gpu=timestamp,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.total \
-                --format=csv,noheader,nounits >> ${paths.logs}/gpu/gpu-usage.log
-              sleep 60
-            done
-          '';
-          Restart = "always";
-          RestartSec = "10";
+          Type = "oneshot";
+          DynamicUser = true;
+          Group = "video";
+          SupplementaryGroups = [ "video" ];
+
+          # Use systemd directory options
+          LogsDirectory = "gpu";
+
+          ExecStart = pkgs.writeShellScript "gpu-metrics-collect" ''
+            #!${pkgs.bash}/bin/bash
+            set -euo pipefail
+
+            # Query GPU metrics and output to journal in structured format
+            ${config.boot.kernelPackages.nvidiaPackages.${cfg.nvidia.driver}}/bin/nvidia-smi \
+              --query-gpu=timestamp,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.total \
+              --format=csv,noheader,nounits | while IFS=, read -r timestamp name temp gpu_util mem_util mem_used mem_total; do
+              # Output as structured journal log
+              echo "GPU_TIMESTAMP=$timestamp GPU_NAME=$name GPU_TEMP=$temp GPU_UTIL=$gpu_util MEM_UTIL=$mem_util MEM_USED=$mem_used MEM_TOTAL=$mem_total"
+            done
+          '';
+
+          # Security hardening
+          NoNewPrivileges = true;
+          ProtectSystem = "strict";
+          ProtectHome = true;
+          PrivateTmp = true;
+          ProtectKernelTunables = true;
+          ProtectKernelModules = true;
+          ProtectControlGroups = true;
+          RestrictAddressFamilies = [ "AF_UNIX" ];
+          RestrictNamespaces = true;
+
+          # Allow device access for nvidia-smi
+          DeviceAllow = [ "/dev/nvidia0" "/dev/nvidiactl" "/dev/nvidia-modeset" "/dev/nvidia-uvm" ];
+
+          StandardOutput = "journal";
+          StandardError = "journal";
         };
-        wantedBy = [ ];
+      };
+
+      # Timer for GPU metrics collection
+      systemd.timers.gpu-metrics-collect = lib.mkIf cfg.nvidia.enableMonitoring {
+        description = "GPU metrics collection timer";
+        wantedBy = [ "timers.target" ];
+        timerConfig = {
+          OnBootSec = "1min";
+          OnUnitActiveSec = "1min";
+          AccuracySec = "10s";
+        };
       };
     })
```

### Benefits
- ✅ Runs as DynamicUser (not root)
- ✅ Uses timer instead of bash while-loop
- ✅ Comprehensive security hardening
- ✅ Outputs to systemd journal (structured logging)
- ✅ Uses LogsDirectory instead of hard-coded path
- ✅ Proper device access controls

---

## Diff 2: Fix Business API Service

**File:** `domains/server/business/api.nix`
**Lines:** 282-315
**Severity:** HIGH
**Issues:** Hard-coded user, secrets in environment, no hardening, Restart=always

### Proposed Changes

```diff
--- a/domains/server/business/api.nix
+++ b/domains/server/business/api.nix
@@ -279,37 +279,64 @@
     ####################################################################
     # BUSINESS API SYSTEMD SERVICE
     ####################################################################
     systemd.services.business-api = mkIf cfg.service.enable {
       description = "Heartwood Craft Business API";
       after = [
         "postgresql.service"
         "redis-business.service"
+        "agenix.service"
       ] ++ optionals config.hwc.services.ai.ollama.enable [ "ollama.service" ];

       wants = [
         "postgresql.service"
         "redis-business.service"
+        "agenix.service"
       ] ++ optionals config.hwc.services.ai.ollama.enable [ "ollama.service" ];

       serviceConfig = {
         Type = "simple";
-        User = cfg.service.user;
+        User = mkDefault cfg.service.user;
+        Group = mkDefault "users";
         WorkingDirectory = cfg.service.workingDirectory;
+
+        # Use StateDirectory for runtime data
+        StateDirectory = "business-api";
+        CacheDirectory = "business-api";
+
         ExecStart = "${pkgs.python3Packages.uvicorn}/bin/uvicorn main:app --host ${cfg.service.host} --port ${toString cfg.service.port}";
-        Restart = "always";
-        RestartSec = "10";
+        Restart = "on-failure";
+        RestartSec = "10s";
+
+        # Load secrets from agenix instead of embedding in environment
+        LoadCredential = [
+          "db-password:${config.age.secrets.business-db-password.path}"
+        ];

-        # Environment variables for the service
+        # Environment variables (no secrets here)
         Environment = [
-          "DATABASE_URL=postgresql://business_user@localhost:5432/heartwood_business"
+          "DATABASE_URL=postgresql://business_user@localhost:5432/heartwood_business"  # Password loaded separately
           "REDIS_URL=redis://localhost:6379/0"
           "BUSINESS_DATA_PATH=${paths.business.root}"
           "MEDIA_PATH=${paths.media}"
           "HOT_STORAGE_PATH=${paths.hot}"
           "COLD_STORAGE_PATH=${paths.cold}"
         ];
+
+        # Security hardening
+        NoNewPrivileges = true;
+        ProtectSystem = "strict";
+        ProtectHome = true;
+        PrivateTmp = true;
+        ProtectKernelTunables = true;
+        ProtectKernelModules = true;
+        ProtectControlGroups = true;
+        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
+        RestrictNamespaces = true;
+
+        # Allow access to business data paths
+        ReadWritePaths = [ paths.business.root ];
+
+        StandardOutput = "journal";
+        StandardError = "journal";
       };

       # Only auto-start if explicitly enabled
```

### Required Secret Addition

Add to `domains/secrets/declarations/apps.nix`:
```nix
age.secrets.business-db-password = {
  file = ../secrets/business-db-password.age;
  mode = "400";
  owner = "eric";  # Or cfg.service.user
};
```

### Benefits
- ✅ Secrets loaded via LoadCredential (not embedded in environment)
- ✅ Restart policy corrected to "on-failure"
- ✅ Comprehensive security hardening
- ✅ StateDirectory and CacheDirectory usage
- ✅ Proper read-write path restrictions
- ✅ Journal output

---

## Diff 3: Fix Gluetun Container (Remove --privileged)

**File:** `domains/server/containers/gluetun/parts/config.nix`
**Lines:** 36-57
**Severity:** CRITICAL
**Issues:** --privileged flag, excessive capabilities, no resource limits

### Proposed Changes

```diff
--- a/domains/server/containers/gluetun/parts/config.nix
+++ b/domains/server/containers/gluetun/parts/config.nix
@@ -33,26 +33,35 @@
       '';
     };

     # Container definition
     virtualisation.oci-containers.containers.gluetun = {
-      image = cfg.image;
+      image = "${cfg.image}:${cfg.imageTag}";  # Pin version
       autoStart = true;
       extraOptions = [
+        # Only required capabilities (not privileged)
         "--cap-add=NET_ADMIN"
-        "--cap-add=SYS_MODULE"
+        # Removed SYS_MODULE - load modules on host instead
+
+        # Required device access
         "--device=/dev/net/tun:/dev/net/tun"
+
+        # Network configuration
         "--network=${mediaNetworkName}"
         "--network-alias=gluetun"
-        "--privileged"
+
+        # Resource limits
+        "--memory=512m"
+        "--memory-swap=1g"
+        "--cpus=0.5"
+        "--pids-limit=100"
+
+        # Security: no new privileges
+        "--security-opt=no-new-privileges:true"
       ];
       ports = [
         "0.0.0.0:8080:8080"  # qBittorrent UI
         "0.0.0.0:8081:8085"  # SABnzbd (container uses 8085 internally)
       ];
       volumes = [ "${cfgRoot}/gluetun:/gluetun" ];
       environmentFiles = [ "${cfgRoot}/.env" ];
       environment = {
         TZ = config.time.timeZone or "America/Denver";
+        LOG_LEVEL = "info";
       };
     };
+
+    # Ensure required kernel modules are loaded on host
+    boot.kernelModules = [ "tun" "iptable_mangle" "iptable_nat" ];

     # Service dependencies
     systemd.services."podman-gluetun".after = [ "network-online.target" "init-media-network.service" ];
```

### Additional: Harden gluetun-env-setup service

```diff
+++ b/domains/server/containers/gluetun/parts/config.nix
@@ -10,24 +10,40 @@
     # Gluetun environment file setup from agenix secrets
     systemd.services.gluetun-env-setup = {
       description = "Generate Gluetun env from agenix secrets";
       before   = [ "podman-gluetun.service" ];
-      wantedBy = [ "podman-gluetun.service" ];
       wants    = [ "agenix.service" ];
       after    = [ "agenix.service" ];
-      serviceConfig.Type = "oneshot";
+
+      serviceConfig = {
+        Type = "oneshot";
+        RemainAfterExit = true;
+
+        # Run as root (needed for file creation)
+        User = "root";
+
+        # Security hardening
+        NoNewPrivileges = true;
+        ProtectSystem = "strict";
+        ProtectHome = true;
+        PrivateTmp = true;
+        ProtectKernelTunables = true;
+        ProtectKernelModules = true;
+
+        # Allow writing to cfgRoot
+        ReadWritePaths = [ cfgRoot ];
+      };
+
       script = ''
+        set -euo pipefail
+
         mkdir -p ${cfgRoot}
         VPN_USERNAME=$(cat ${config.age.secrets.vpn-username.path})
         VPN_PASSWORD=$(cat ${config.age.secrets.vpn-password.path})
         cat > ${cfgRoot}/.env <<EOF
 VPN_SERVICE_PROVIDER=protonvpn
 VPN_TYPE=openvpn
 OPENVPN_USER=$VPN_USERNAME
 OPENVPN_PASSWORD=$VPN_PASSWORD
 SERVER_COUNTRIES=Netherlands
 HEALTH_VPN_DURATION_INITIAL=30s
 HEALTH_TARGET_ADDRESS=1.1.1.1:443
 EOF
         chmod 600 ${cfgRoot}/.env
         chown root:root ${cfgRoot}/.env
       '';
+
+      wantedBy = [ "multi-user.target" ];
     };
```

### Required Options Addition

Add to options file:
```nix
imageTag = mkOption {
  type = types.str;
  default = "v3.39.1";  # Pin to specific version
  description = "Gluetun container image tag";
};
```

### Benefits
- 🔴 **CRITICAL:** Removes `--privileged` flag (major security improvement)
- ✅ Removes SYS_MODULE capability (loads modules on host)
- ✅ Adds resource limits (prevents resource exhaustion)
- ✅ Adds security-opt no-new-privileges
- ✅ Pins image version (no floating :latest tag)
- ✅ Hardens env-setup service
- ✅ Adds proper error handling to script

---

## Diff 4: Fix Media Orchestrator Service

**File:** `domains/server/orchestration/media-orchestrator.nix`
**Severity:** HIGH
**Issues:** Runs as root, no hardening, Restart=always, hard-coded paths

### Proposed Changes

```diff
--- a/domains/server/orchestration/media-orchestrator.nix
+++ b/domains/server/orchestration/media-orchestrator.nix
@@ -XX,XX +XX,XX @@ # (Line numbers will vary)
     systemd.services.media-orchestrator = {
       description = "Event-driven *Arr nudger (no file moves)";
+
       after = [
         "agenix.service"
         "network-online.target"
         "media-orchestrator-install.service"
       ] ++ cfg.arrServices;
+
+      wants = [ "agenix.service" "network-online.target" ];

       serviceConfig = {
         Type = "simple";
-        User = "root";
-        Restart = "always";
-        RestartSec = "3s";
-        ExecStart = "${pythonEnv}/bin/python /var/lib/hwc/media-orchestrator/orchestrator.py";
+
+        # Run as dedicated user (not root)
+        DynamicUser = true;
+        Group = "media";
+        SupplementaryGroups = [ "media" ];
+
+        # Use systemd directory options
+        StateDirectory = "media-orchestrator";
+        CacheDirectory = "media-orchestrator";
+        RuntimeDirectory = "media-orchestrator";
+
+        WorkingDirectory = "/var/lib/media-orchestrator";
+
+        # Load secrets via LoadCredential instead of preStart
+        LoadCredential = lib.mapAttrsToList (name: secret:
+          "${name}:${secret.path}"
+        ) {
+          radarr-api-key = config.age.secrets.radarr-api-key;
+          sonarr-api-key = config.age.secrets.sonarr-api-key;
+          lidarr-api-key = config.age.secrets.lidarr-api-key;
+          prowlarr-api-key = config.age.secrets.prowlarr-api-key;
+        };
+
+        ExecStart = "${pythonEnv}/bin/python orchestrator.py";
+
+        Restart = "on-failure";
+        RestartSec = "10s";
+        StartLimitIntervalSec = 300;
+        StartLimitBurst = 5;
+
+        # Security hardening
+        NoNewPrivileges = true;
+        ProtectSystem = "strict";
+        ProtectHome = true;
+        PrivateTmp = true;
+        ProtectKernelTunables = true;
+        ProtectKernelModules = true;
+        ProtectControlGroups = true;
+        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
+        RestrictNamespaces = true;
+        CapabilityBoundingSet = "";
+
+        # Logging
+        StandardOutput = "journal";
+        StandardError = "journal";
       };
-
-      preStart = ''
-        # Create environment file with *arr API keys from agenix
-        cat > /var/lib/hwc/media-orchestrator/.env <<EOF
-RADARR_API_KEY=$(cat ${config.age.secrets.radarr-api-key.path})
-SONARR_API_KEY=$(cat ${config.age.secrets.sonarr-api-key.path})
-LIDARR_API_KEY=$(cat ${config.age.secrets.lidarr-api-key.path})
-PROWLARR_API_KEY=$(cat ${config.age.secrets.prowlarr-api-key.path})
-EOF
-        chmod 600 /var/lib/hwc/media-orchestrator/.env
-      '';
     };
```

### Update Orchestrator Script

The Python script needs to read credentials from `$CREDENTIALS_DIRECTORY`:

```python
import os
from pathlib import Path

# Read credentials from systemd LoadCredential
creds_dir = Path(os.environ.get('CREDENTIALS_DIRECTORY', '/run/credentials/media-orchestrator'))

radarr_api_key = (creds_dir / 'radarr-api-key').read_text().strip()
sonarr_api_key = (creds_dir / 'sonarr-api-key').read_text().strip()
lidarr_api_key = (creds_dir / 'lidarr-api-key').read_text().strip()
prowlarr_api_key = (creds_dir / 'prowlarr-api-key').read_text().strip()
```

### Benefits
- ✅ No longer runs as root (DynamicUser)
- ✅ Secrets loaded via LoadCredential (proper systemd way)
- ✅ Comprehensive security hardening
- ✅ StateDirectory usage (no hard-coded paths)
- ✅ Correct Restart policy
- ✅ Rate limiting (StartLimit*)
- ✅ CapabilityBoundingSet restriction

---

## Diff 5: Standardize Container Services with Shared Module

**New File:** `modules/services/hwc-container.nix`

This creates a reusable container abstraction:

```nix
# modules/services/hwc-container.nix
#
# Standardized HWC container service abstraction
# Provides consistent patterns for all containerized services
#
# USAGE:
#   services.hwc.container.radarr = {
#     enable = true;
#     image = "lscr.io/linuxserver/radarr";
#     imageTag = "5.14.0";
#     networkMode = "media";
#     secrets = [ "radarr-api-key" ];
#     volumes = {
#       config = "/config";
#       media = "${paths.media}:/media:ro";
#     };
#   };

{ config, lib, pkgs, ... }:

let
  cfg = config.services.hwc.container;

  # Helper to create a standardized container service
  mkHwcContainer = name: containerCfg: {
    # Container definition
    virtualisation.oci-containers.containers.${name} = {
      image = "${containerCfg.image}:${containerCfg.imageTag}";
      autoStart = true;

      extraOptions =
        # Network mode
        (if containerCfg.networkMode == "vpn"
         then [ "--network=container:gluetun" ]
         else if containerCfg.networkMode == "host"
         then [ "--network=host" ]
         else [ "--network=media-network" ])

        # GPU support
        ++ (lib.optionals containerCfg.gpu.enable (
          if containerCfg.gpu.type == "nvidia"
          then [ "--device=nvidia.com/gpu=all" ]  # CDI
          else [ "--device=/dev/dri:/dev/dri:rw" ]
        ))

        # Security
        ++ [ "--security-opt=no-new-privileges:true" ]

        # Resource limits
        ++ [
          "--memory=${containerCfg.resources.memory}"
          "--memory-swap=${containerCfg.resources.memorySwap}"
          "--cpus=${toString containerCfg.resources.cpus}"
          "--pids-limit=${toString containerCfg.resources.pidsLimit}"
        ]

        # Custom options
        ++ containerCfg.extraOptions;

      ports = containerCfg.ports;

      volumes = lib.mapAttrsToList (name: path:
        "${path}:${containerCfg.volumeMounts.${name}}"
      ) containerCfg.volumes;

      environment = {
        PUID = toString containerCfg.user.uid;
        PGID = toString containerCfg.user.gid;
        TZ = config.time.timeZone;
      } // containerCfg.environment;

      environmentFiles = lib.optional (containerCfg.secrets != [])
        "/run/secrets/${name}.env";
    };

    # Secret injection service (if secrets are defined)
    systemd.services."${name}-secrets" = lib.mkIf (containerCfg.secrets != []) {
      description = "Generate ${name} container secrets";
      before = [ "podman-${name}.service" ];
      wantedBy = [ "podman-${name}.service" ];
      wants = [ "agenix.service" ];
      after = [ "agenix.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;

        # Security
        DynamicUser = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;

        # Allow writing secrets file
        RuntimeDirectory = "secrets";
      };

      script = ''
        set -euo pipefail

        # Generate environment file from agenix secrets
        cat > /run/secrets/${name}.env <<EOF
        ${lib.concatMapStringsSep "\n" (secretName:
          "${lib.toUpper (lib.replaceStrings ["-"] ["_"] secretName)}=$(cat ${config.age.secrets.${secretName}.path})"
        ) containerCfg.secrets}
        EOF

        chmod 600 /run/secrets/${name}.env
      '';
    };

    # Enhanced service configuration
    systemd.services."podman-${name}" = {
      after = [
        "network-online.target"
        "agenix.service"
      ] ++ (lib.optional (containerCfg.networkMode == "media") "init-media-network.service")
        ++ (lib.optional (containerCfg.networkMode == "vpn") "podman-gluetun.service")
        ++ containerCfg.dependsOn;

      wants = [
        "network-online.target"
        "agenix.service"
      ];

      preStart = lib.mkIf (containerCfg.preStart != "") containerCfg.preStart;
    };
  };

in {
  options.services.hwc.container = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options = {
        enable = lib.mkEnableOption "HWC container ${name}";

        image = lib.mkOption {
          type = lib.types.str;
          description = "Container image (without tag)";
        };

        imageTag = lib.mkOption {
          type = lib.types.str;
          description = "Container image tag (version)";
        };

        networkMode = lib.mkOption {
          type = lib.types.enum [ "media" "vpn" "host" ];
          default = "media";
          description = "Network mode for container";
        };

        gpu = {
          enable = lib.mkEnableOption "GPU acceleration";
          type = lib.mkOption {
            type = lib.types.enum [ "nvidia" "intel" "amd" ];
            default = "intel";
          };
        };

        user = {
          uid = lib.mkOption {
            type = lib.types.int;
            default = 1000;
            description = "Container user UID (PUID)";
          };
          gid = lib.mkOption {
            type = lib.types.int;
            default = 1000;
            description = "Container group GID (PGID)";
          };
        };

        resources = {
          memory = lib.mkOption {
            type = lib.types.str;
            default = "2g";
          };
          memorySwap = lib.mkOption {
            type = lib.types.str;
            default = "4g";
          };
          cpus = lib.mkOption {
            type = lib.types.number;
            default = 1.0;
          };
          pidsLimit = lib.mkOption {
            type = lib.types.int;
            default = 200;
          };
        };

        volumes = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
          description = "Volume mappings (name = host-path)";
        };

        volumeMounts = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
          description = "Container mount paths (name = container-path)";
        };

        ports = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
        };

        environment = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
        };

        secrets = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "List of agenix secret names to inject";
        };

        extraOptions = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
        };

        dependsOn = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
        };

        preStart = lib.mkOption {
          type = lib.types.str;
          default = "";
        };
      };
    }));
    default = {};
  };

  config = {
    # Generate all container configurations
    virtualisation.oci-containers = lib.mkMerge (
      lib.mapAttrsToList mkHwcContainer (lib.filterAttrs (_: v: v.enable) cfg)
    );
  };
}
```

### Example Usage: Convert Radarr to New Pattern

**File:** `domains/server/containers/radarr/index.nix`

```nix
{ config, lib, ... }:
let
  cfg = config.hwc.server.containers.radarr;
  paths = config.hwc.paths;
in {
  options.hwc.server.containers.radarr = {
    enable = lib.mkEnableOption "Radarr movie management";
    # Other options...
  };

  config = lib.mkIf cfg.enable {
    # Use standardized container module
    services.hwc.container.radarr = {
      enable = true;
      image = "lscr.io/linuxserver/radarr";
      imageTag = "5.14.0.9383";  # Pin version

      networkMode = "media";

      volumes = {
        config = "${paths.hot}/containers/radarr/config";
        media = paths.media;
        downloads = "${paths.hot}/downloads";
      };

      volumeMounts = {
        config = "/config";
        media = "/media";
        downloads = "/downloads";
      };

      ports = [ "7878:7878" ];

      secrets = [ "radarr-api-key" ];

      resources = {
        memory = "1g";
        memorySwap = "2g";
        cpus = 0.5;
      };
    };
  };
}
```

### Benefits of Standardized Module
- ✅ Eliminates code duplication across 15+ containers
- ✅ Enforces resource limits on all containers
- ✅ Standardizes secret injection pattern
- ✅ Enforces version pinning (no floating tags)
- ✅ Consistent security options (no-new-privileges)
- ✅ Automatic dependency management
- ✅ Configurable UID/GID (no hard-coding)
- ✅ Easy to add new containers with consistent behavior

---

## Diff 6: Create Monitoring Pattern Module

**New File:** `modules/services/hwc-monitor.nix`

```nix
# modules/services/hwc-monitor.nix
#
# Standardized monitoring/health-check service pattern
# Replaces ad-hoc while-loop monitors with timer-based checks
#
# USAGE:
#   services.hwc.monitor.couchdb = {
#     enable = true;
#     description = "CouchDB health check";
#     script = ''
#       curl -f http://localhost:5984/_up || exit 1
#     '';
#     schedule = "every-5-minutes";
#     dependsOn = [ "couchdb.service" ];
#   };

{ config, lib, pkgs, ... }:

let
  cfg = config.services.hwc.monitor;

  scheduleOptions = {
    "every-minute" = "*:0/1";
    "every-5-minutes" = "*:0/5";
    "every-15-minutes" = "*:0/15";
    "hourly" = "hourly";
    "daily" = "daily";
    "weekly" = "weekly";
  };

  mkMonitorService = name: monitorCfg: {
    systemd.services."hwc-monitor-${name}" = {
      description = monitorCfg.description;
      after = monitorCfg.dependsOn;

      serviceConfig = {
        Type = "oneshot";

        # Run as unprivileged user unless explicitly required
        DynamicUser = !monitorCfg.requireRoot;
        User = lib.mkIf monitorCfg.requireRoot "root";

        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
        RestrictNamespaces = true;
        CapabilityBoundingSet = lib.mkIf (!monitorCfg.requireRoot) "";

        # Allow network access if needed
        PrivateNetwork = !monitorCfg.networkAccess;

        # Timeout
        TimeoutSec = toString monitorCfg.timeout;

        ExecStart = pkgs.writeShellScript "monitor-${name}" ''
          #!${pkgs.bash}/bin/bash
          set -euo pipefail

          ${monitorCfg.script}
        '';

        # Failure handling
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    systemd.timers."hwc-monitor-${name}" = {
      description = "${monitorCfg.description} timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnBootSec = monitorCfg.onBootDelay;
        OnCalendar = scheduleOptions.${monitorCfg.schedule} or monitorCfg.schedule;
        Persistent = monitorCfg.persistent;
        AccuracySec = monitorCfg.accuracy;
      };
    };
  };

in {
  options.services.hwc.monitor = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options = {
        enable = lib.mkEnableOption "monitoring for ${name}";

        description = lib.mkOption {
          type = lib.types.str;
          default = "Monitor ${name}";
        };

        script = lib.mkOption {
          type = lib.types.lines;
          description = "Monitoring script content";
        };

        schedule = lib.mkOption {
          type = lib.types.str;
          default = "every-5-minutes";
          description = "Schedule (preset or systemd calendar format)";
        };

        dependsOn = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Services this monitor depends on";
        };

        requireRoot = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether monitor requires root privileges";
        };

        networkAccess = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether monitor needs network access";
        };

        timeout = lib.mkOption {
          type = lib.types.int;
          default = 30;
          description = "Timeout in seconds";
        };

        onBootDelay = lib.mkOption {
          type = lib.types.str;
          default = "1min";
          description = "Delay after boot before first run";
        };

        persistent = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Run missed timers on boot";
        };

        accuracy = lib.mkOption {
          type = lib.types.str;
          default = "1min";
          description = "Timer accuracy window";
        };
      };
    }));
    default = {};
  };

  config = lib.mkMerge (
    lib.mapAttrsToList mkMonitorService (lib.filterAttrs (_: v: v.enable) cfg)
  );
}
```

### Example: Convert WinApps Monitor

**Old** (`domains/infrastructure/winapps/index.nix`):
```nix
systemd.services.winapps-monitor = {
  description = "Monitor WinApps Windows VM health";
  serviceConfig = {
    Type = "simple";
    User = "root";
    Restart = "always";
    RestartSec = "30";
  };
  script = ''
    while true; do
      # Check VM state
      # Check RDP connectivity
      sleep 60
    done
  '';
};
```

**New**:
```nix
services.hwc.monitor.winapps-vm = {
  enable = true;
  description = "WinApps Windows VM health check";
  schedule = "every-minute";
  requireRoot = true;  # Needs virsh access

  script = ''
    # Check VM state
    VM_STATE=$(${pkgs.libvirt}/bin/virsh domstate "${cfg.vmName}" 2>/dev/null || echo "error")

    if [[ "$VM_STATE" != "running" ]]; then
      echo "VM ${cfg.vmName} is not running (state: $VM_STATE)"
      exit 1
    fi

    # Check RDP connectivity
    if ! ${pkgs.netcat}/bin/nc -zv localhost 3389 -w 5 2>/dev/null; then
      echo "RDP port 3389 is not accessible"
      exit 1
    fi

    echo "VM health check passed"
  '';

  dependsOn = [ "libvirtd.service" "winapps-vm-autostart.service" ];
};
```

### Benefits
- ✅ Eliminates bash while-loops
- ✅ Standardizes monitoring pattern
- ✅ Consistent hardening across all monitors
- ✅ Configurable scheduling with presets
- ✅ Proper timeout handling
- ✅ DynamicUser by default

---

## Implementation Priority

### Phase 1: Critical Security (Week 1)
1. ✅ **Diff 3:** Remove `--privileged` from Gluetun (CRITICAL)
2. ✅ **Diff 2:** Fix Business API secrets handling (HIGH)
3. ✅ **Diff 4:** Fix Media Orchestrator root access (HIGH)

### Phase 2: Standardization (Week 2)
4. ✅ **Diff 5:** Implement standardized container module
5. ✅ **Diff 6:** Implement monitoring pattern module
6. ✅ Convert all containers to use new pattern

### Phase 3: Refinement (Week 3)
7. ✅ **Diff 1:** Fix GPU monitor service
8. ✅ Apply hardening to all remaining services
9. ✅ Remove all hard-coded paths

---

## Testing Strategy

### For Each Diff:

1. **Apply diff to feature branch**
2. **Build configuration:**
   ```bash
   nixos-rebuild build --flake .#hwc-server
   ```

3. **Test in VM:**
   ```bash
   nixos-rebuild build-vm --flake .#hwc-server
   ```

4. **Check service status:**
   ```bash
   systemctl status <service-name>
   journalctl -u <service-name> -f
   ```

5. **Verify functionality:**
   - Containers start correctly
   - Secrets are properly loaded
   - Services run as non-root
   - No permission errors

6. **Security validation:**
   ```bash
   systemd-analyze security <service-name>
   ```

---

## Rollback Plan

Each change is isolated and can be reverted independently:

```bash
git revert <commit-hash>
nixos-rebuild switch --flake .#hwc-server
```

For container changes, old images are retained by Podman for 30 days.

---

