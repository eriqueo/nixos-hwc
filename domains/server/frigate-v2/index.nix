# domains/server/frigate-v2/index.nix
#
# Frigate NVR - Config-First Pattern
# Charter v7.0 Section 19 compliant
#
# NAMESPACE: hwc.server.frigate-v2.*
#
# ARCHITECTURE:
#   - Nix: Container infrastructure (image, GPU, volumes, ports)
#   - YAML: Frigate configuration (cameras, detectors, recording)
#   - Config file: domains/server/frigate-v2/config/config.yml
#
# DEPENDENCIES:
#   - hwc.infrastructure.hardware.gpu (for GPU acceleration)
#   - hwc.secrets (for RTSP credentials)
#   - virtualisation.oci-containers.backend = "podman"
#
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.frigate-v2;

  # Path to canonical config file (version-controlled)
  configTemplate = ./config/config.yml;

in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {

    # Config generation service (minimal - only substitutes secrets)
    systemd.services.frigate-v2-config = {
      description = "Generate Frigate v2 NVR configuration";
      wantedBy = [ "podman-frigate-v2.service" ];
      before = [ "podman-frigate-v2.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        mkdir -p ${cfg.storage.configPath}

        # Read secrets
        RTSP_USER=$(cat /run/agenix/frigate-rtsp-username)
        RTSP_PASS=$(cat /run/agenix/frigate-rtsp-password)
        RTSP_PASS_ENCODED=$(echo "$RTSP_PASS" | ${pkgs.python3}/bin/python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))")

        CAMERA_IPS=$(cat /run/agenix/frigate-camera-ips)
        CAM1_IP=$(echo "$CAMERA_IPS" | ${pkgs.jq}/bin/jq -r '.cobra_cam_1')
        CAM2_IP=$(echo "$CAMERA_IPS" | ${pkgs.jq}/bin/jq -r '.cobra_cam_2')
        CAM3_IP=$(echo "$CAMERA_IPS" | ${pkgs.jq}/bin/jq -r '.cobra_cam_3')

        # Substitute secrets in config template
        export RTSP_USER RTSP_PASS_ENCODED CAM1_IP CAM2_IP CAM3_IP
        ${pkgs.envsubst}/bin/envsubst < ${configTemplate} > ${cfg.storage.configPath}/config.yaml

        chown eric:users ${cfg.storage.configPath}/config.yaml
      '';

      path = with pkgs; [ coreutils jq python3 envsubst ];
    };

    # Frigate container
    virtualisation.oci-containers.containers.frigate-v2 = {
      image = cfg.image;
      autoStart = true;

      ports = [
        "${toString cfg.port}:5000"  # Web UI
        "8556:8554"  # RTSP (mapped to avoid conflict with frigate on 8554)
        "8557:8555/tcp"  # WebRTC (mapped to avoid conflict with frigate on 8555)
        "8557:8555/udp"  # WebRTC
      ];

      extraOptions = [
        "--security-opt=label=disable"
        "--privileged"
        "--tmpfs=/tmp/cache:size=1g"
        "--shm-size=${cfg.resources.shmSize}"
        "--memory=${cfg.resources.memory}"
        "--cpus=${cfg.resources.cpus}"
        # Proper HTTP healthcheck (prevents empty 400 errors in logs)
        "--health-cmd=curl -fsS http://127.0.0.1:5000/api/stats || exit 1"
        "--health-interval=30s"
        "--health-timeout=5s"
        "--health-retries=3"
      ]
      # NVIDIA GPU device passthrough (for object detection)
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
        # GENERATED CONFIG (from template with secrets substituted)
        "${cfg.storage.configPath}:/config"

        # Model cache (ONNX model file goes here)
        "${cfg.storage.configPath}/models:/config/models:ro"

        # Labelmap (coco-80.txt)
        "${cfg.storage.configPath}/labelmap:/labelmap:ro"

        # Storage
        "${cfg.storage.mediaPath}:/media/frigate"
        "${cfg.storage.bufferPath}:/tmp/frigate"

        # System time
        "/etc/localtime:/etc/localtime:ro"
      ];
    };

    # Firewall rules
    networking.firewall = {
      # Always allow localhost for reverse proxy
      interfaces."lo".allowedTCPPorts = [ cfg.port ];

      # Optionally restrict external access to Tailscale only
      interfaces."tailscale0" = lib.mkIf cfg.firewall.tailscaleOnly {
        allowedTCPPorts = [ cfg.port 8556 8557 ];  # Web UI, RTSP, WebRTC
        allowedUDPPorts = [ 8557 ];  # WebRTC UDP
      };
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !cfg.gpu.enable || config.hwc.infrastructure.hardware.gpu.enable;
        message = "hwc.server.frigate-v2.gpu requires hwc.infrastructure.hardware.gpu.enable = true";
      }
      {
        assertion = !cfg.enable || (cfg.storage.mediaPath != "");
        message = "hwc.server.frigate-v2.storage.mediaPath must be set";
      }
      {
        assertion = !cfg.enable || (cfg.storage.bufferPath != "");
        message = "hwc.server.frigate-v2.storage.bufferPath must be set";
      }
      {
        assertion = !cfg.enable || config.hwc.secrets.enable;
        message = "hwc.server.frigate-v2 requires hwc.secrets.enable = true for RTSP credentials";
      }
      {
        assertion = !cfg.enable || (config.virtualisation.oci-containers.backend == "podman");
        message = "hwc.server.frigate-v2 requires Podman as OCI container backend";
      }
      {
        assertion = !cfg.enable || builtins.pathExists configTemplate;
        message = "hwc.server.frigate-v2 requires config/config.yml template to exist";
      }
    ];
  };
}
