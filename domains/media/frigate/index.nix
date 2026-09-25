# domains/media/frigate/index.nix
#
# Frigate NVR — nix-native configuration
# Namespace: hwc.media.frigate.*
#
# Config is generated from nix (parts/config.nix) with runtime secret substitution.
#
# DEPENDENCIES:
#   - hwc.system.hardware.gpu (for GPU acceleration)
#   - hwc.secrets (for RTSP credentials)
#   - virtualisation.oci-containers.backend = "podman"
#
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.frigate;
  labelPython = pkgs.python3.withPackages (p: [ p.onnx ]);
in
{
  imports = [
    ./parts/config.nix
    ./parts/cleanup.nix
  ];

  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.frigate = {
    enable = lib.mkEnableOption "Frigate NVR (config-first pattern)";

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/blakeblackshear/frigate:0.16.2-tensorrt";
      description = ''
        Container image for Frigate NVR.
        Uses -tensorrt variant which includes CUDA support for ONNX detector.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5000;
      description = "Frigate internal HTTP port (host networking; fixed at 5000)";
    };

    gpu = {
      enable = lib.mkEnableOption "GPU acceleration for object detection";
      device = lib.mkOption { type = lib.types.int; default = 0; description = "GPU device number (NVIDIA)"; };
    };

    storage = {
      configPath = lib.mkOption { type = lib.types.str; default = "/var/lib/frigate/config"; description = "Configuration directory path"; };
      mediaPath = lib.mkOption { type = lib.types.str; default = "${config.hwc.paths.media.root}/surveillance/frigate/media"; description = "Media storage path (recordings)"; };
    };

    resources = {
      memory = lib.mkOption { type = lib.types.str; default = "4g"; description = "Container memory limit"; };
      cpus = lib.mkOption { type = lib.types.str; default = "1.5"; description = "Container CPU limit"; };
      shmSize = lib.mkOption { type = lib.types.str; default = "1g"; description = "Shared memory size"; };
    };

    cleanup = {
      enable = lib.mkEnableOption "Automated surveillance recording cleanup";

      schedule = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "systemd OnCalendar schedule for cleanup";
      };

    };

    firewall.tailscaleOnly = lib.mkOption { type = lib.types.bool; default = true; description = "Restrict access to Tailscale interface only"; };

    _configTemplate = lib.mkOption { type = lib.types.package; internal = true; description = "Generated YAML config template"; };
    _settings = lib.mkOption { type = lib.types.attrs; internal = true; readOnly = true; description = "Structured config shared by YAML generation and camera expectations"; };
  };

  config = lib.mkIf cfg.enable {

    # Config generation service (substitutes secrets into nix-generated YAML template)
    systemd.services.frigate-config = {
      description = "Generate Frigate NVR configuration";
      wantedBy = [ "podman-frigate.service" ];
      before = [ "podman-frigate.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = lib.mkForce "eric";
        Group = "users";
        # PID 1 reads root-only agenix mounts; the service receives private,
        # read-only copies without broadening permissions on the source files.
        LoadCredential = map (name: "${name}:${config.age.secrets.${name}.path}") [
          "frigate-rtsp-username" "frigate-rtsp-password" "frigate-camera-ips"
          "frigate-reolink-username" "frigate-reolink-password"
        ];
        UMask = "0077";
      };

      script = ''
        # REPLACEABLE: derived on every run from the model, including upgrades.
        ${labelPython}/bin/python3 ${./parts/labelmap.py} \
          ${cfg.storage.configPath}/models/${builtins.baseNameOf cfg._settings.model.path} \
          ${cfg.storage.configPath}/labelmap/coco-80.txt

        # Read secrets - Cobra cameras
        RTSP_USER=$(cat "$CREDENTIALS_DIRECTORY/frigate-rtsp-username")
        RTSP_PASS=$(cat "$CREDENTIALS_DIRECTORY/frigate-rtsp-password")
        RTSP_PASS_ENCODED=$(echo "$RTSP_PASS" | ${pkgs.python3}/bin/python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))")

        CAMERA_IPS=$(cat "$CREDENTIALS_DIRECTORY/frigate-camera-ips")
        CAM1_IP=$(echo "$CAMERA_IPS" | ${pkgs.jq}/bin/jq -r '.cobra_cam_1')
        CAM2_IP=$(echo "$CAMERA_IPS" | ${pkgs.jq}/bin/jq -r '.cobra_cam_2')
        CAM3_IP=$(echo "$CAMERA_IPS" | ${pkgs.jq}/bin/jq -r '.cobra_cam_3')

        # Read secrets - Reolink camera
        REOLINK_USER=$(cat "$CREDENTIALS_DIRECTORY/frigate-reolink-username")
        REOLINK_PASS=$(cat "$CREDENTIALS_DIRECTORY/frigate-reolink-password")
        REOLINK_PASS_ENCODED=$(echo "$REOLINK_PASS" | ${pkgs.python3}/bin/python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))")
        REOLINK_IP=$(echo "$CAMERA_IPS" | ${pkgs.jq}/bin/jq -r '.reolink')

        # Substitute secrets into nix-generated config template
        export RTSP_USER RTSP_PASS_ENCODED CAM1_IP CAM2_IP CAM3_IP REOLINK_USER REOLINK_PASS_ENCODED REOLINK_IP
        # Idempotent derived configuration. Replace atomically; never expose a
        # partially written credential-bearing file to a restarting container.
        temporary=$(mktemp ${cfg.storage.configPath}/.config.XXXXXX)
        trap 'rm -f "$temporary"' EXIT
        ${pkgs.envsubst}/bin/envsubst < ${cfg._configTemplate} > "$temporary"
        chmod 0600 "$temporary"
        mv -f "$temporary" ${cfg.storage.configPath}/config.yaml
      '';

      path = with pkgs; [ coreutils jq python3 envsubst ];
    };

    # Create all required directories
    systemd.tmpfiles.rules = [
      "d ${cfg.storage.configPath} 0755 eric users -"
      "d ${cfg.storage.configPath}/models 0755 eric users -"
      "d ${cfg.storage.configPath}/labelmap 0755 eric users -"
      "d ${cfg.storage.mediaPath} 0755 eric users -"
    ];

    # Ensure Frigate starts after mosquitto (for MQTT events) and CDI spec generation
    systemd.services.podman-frigate = {
      after = [ "mosquitto.service" "frigate-config.service" ]
        ++ lib.optional cfg.gpu.enable "nvidia-container-toolkit-cdi-generator.service";
      wants = [ "mosquitto.service" ];
      requires = [ "frigate-config.service" ] ++ lib.optionals cfg.gpu.enable [ "nvidia-container-toolkit-cdi-generator.service" ];
      restartTriggers = [ cfg._configTemplate ./parts/labelmap.py ];
      # Report startup only after the API health check passes. Bound a failed
      # initialization instead of inheriting the container module's infinity.
      serviceConfig.TimeoutStartSec = lib.mkForce 120;
    };

    # Frigate container
    # HWC-EXCEPTION(Law 5): NVR needs device/GPU access mkContainer does not model
    # Justification: privileged devices (coral/GPU), shm sizing, and camera-network specifics; media-app helper assumptions (PUID/PGID linuxserver images) do not hold
    # Plan: permanent by design (revisit if an infra-shaped helper grows to fit)
    # Revocable: yes
    virtualisation.oci-containers.containers.frigate = {
      image = cfg.image;
      autoStart = true;

      # Host networking exposes the application's listeners directly.

      extraOptions = [
        "--network=host"
        "--security-opt=label=disable"
        "--privileged"
        "--tmpfs=/tmp/cache:size=1g"
        "--shm-size=${cfg.resources.shmSize}"
        "--memory=${cfg.resources.memory}"
        "--cpus=${cfg.resources.cpus}"
        "--health-cmd=curl -fsS http://127.0.0.1:5000/api/stats || exit 1"
        "--health-interval=30s"
        "--health-timeout=5s"
        "--health-retries=3"
        "--sdnotify=healthy"
      ]
      ++ lib.optionals cfg.gpu.enable [
        "--device=nvidia.com/gpu=${toString cfg.gpu.device}"
      ];

      environment = {
        TZ = "America/Denver";
      } // lib.optionalAttrs cfg.gpu.enable {
        NVIDIA_VISIBLE_DEVICES = "all";
        NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
        CUDA_VISIBLE_DEVICES = toString cfg.gpu.device;
        LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";
      };

      volumes = [
        "${cfg.storage.configPath}:/config"
        "${cfg.storage.configPath}/models:/config/models:ro"
        "${cfg.storage.configPath}/labelmap:/labelmap:ro"
        "${cfg.storage.mediaPath}:/media/frigate"
        "/etc/localtime:/etc/localtime:ro"
      ];
    };

    # Firewall rules
    networking.firewall = {
      interfaces."lo".allowedTCPPorts = [ cfg.port ];
      interfaces."tailscale0" = lib.mkIf cfg.firewall.tailscaleOnly {
        allowedTCPPorts = [ cfg.port 8554 8555 ];
        allowedUDPPorts = [ 8555 ];
      };
    };

    # Frigate owns its metrics. The former sidecar duplicated /api/metrics.
    hwc.monitoring.prometheus.scrapeConfigs = [{
      job_name = "frigate";
      metrics_path = "/api/metrics";
      static_configs = [{ targets = [ "127.0.0.1:${toString cfg.port}" ]; }];
      scrape_interval = "30s";
      # Process command lines are unnecessary high-cardinality labels.
      metric_relabel_configs = [{ action = "labeldrop"; regex = "cmdline"; }];
    }];
    # Exported: the central Prometheus (another host) loads it.
    hwc.monitoring.prometheus.rules = [ (builtins.toJSON {
      groups = [{
        name = "frigate_configuration";
        rules = lib.mapAttrsToList (name: camera: {
          record = "frigate_camera_expected_fps";
          expr = "vector(${toString (if camera.enabled then camera.detect.fps else 0)})";
          labels.camera_name = name;
        }) cfg._settings.cameras;
      }];
    }) ];

    assertions = [
      {
        assertion = !cfg.gpu.enable || config.hwc.system.hardware.gpu.enable;
        message = "hwc.media.frigate.gpu requires hwc.system.hardware.gpu.enable = true";
      }
      {
        assertion = cfg.storage.mediaPath != "";
        message = "hwc.media.frigate.storage.mediaPath must be set";
      }
      {
        assertion = cfg.port == 5000;
        message = "Frigate uses host networking and listens on 5000; port mappings cannot change it";
      }
      {
        assertion = builtins.match "^/mnt/.*" cfg.storage.mediaPath != null;
        message = "hwc.media.frigate.storage.mediaPath must be under /mnt";
      }
      {
        assertion = config.hwc.secrets.enable;
        message = "hwc.media.frigate requires hwc.secrets.enable = true for RTSP credentials";
      }
      {
        assertion = config.virtualisation.oci-containers.backend == "podman";
        message = "hwc.media.frigate requires Podman as OCI container backend";
      }
      {
        assertion = config.hwc.monitoring.prometheus.agent.enable;
        message = "Frigate exports its metrics through this host's agent (hwc.monitoring.prometheus.agent.enable = true)";
      }
    ];
  };
}
