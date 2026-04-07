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
in
{
  imports = [
    ./parts/config.nix
    ./exporter/index.nix
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
      description = "Web UI port (exposed directly via --network=host, proxied by Caddy on 5443)";
    };

    gpu = {
      enable = lib.mkEnableOption "GPU acceleration for object detection";
      device = lib.mkOption { type = lib.types.int; default = 0; description = "GPU device number (NVIDIA)"; };
    };

    storage = {
      configPath = lib.mkOption { type = lib.types.str; default = "/var/lib/frigate/config"; description = "Configuration directory path"; };
      mediaPath = lib.mkOption { type = lib.types.str; default = "${config.hwc.paths.media.root}/surveillance/frigate/media"; description = "Media storage path (recordings)"; };
      bufferPath = lib.mkOption { type = lib.types.str; default = "${config.hwc.paths.hot.surveillance}/frigate/buffer"; description = "Buffer storage path (hot storage)"; };
    };

    resources = {
      memory = lib.mkOption { type = lib.types.str; default = "4g"; description = "Container memory limit"; };
      cpus = lib.mkOption { type = lib.types.str; default = "1.5"; description = "Container CPU limit"; };
      shmSize = lib.mkOption { type = lib.types.str; default = "1g"; description = "Shared memory size"; };
    };

    firewall.tailscaleOnly = lib.mkOption { type = lib.types.bool; default = true; description = "Restrict access to Tailscale interface only"; };

    _configTemplate = lib.mkOption { type = lib.types.package; internal = true; description = "Generated YAML config template"; };
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
      };

      script = ''
        # Create COCO-80 labelmap if it doesn't exist
        if [ ! -f ${cfg.storage.configPath}/labelmap/coco-80.txt ]; then
          cat > ${cfg.storage.configPath}/labelmap/coco-80.txt << 'LABELMAP_EOF'
person
bicycle
car
motorcycle
airplane
bus
train
truck
boat
traffic light
fire hydrant
street sign
stop sign
parking meter
bench
bird
cat
dog
horse
sheep
cow
elephant
bear
zebra
giraffe
hat
backpack
umbrella
shoe
eye glasses
handbag
tie
suitcase
frisbee
skis
snowboard
sports ball
kite
baseball bat
baseball glove
skateboard
surfboard
tennis racket
bottle
plate
wine glass
cup
fork
knife
spoon
bowl
banana
apple
sandwich
orange
broccoli
carrot
hot dog
pizza
donut
cake
chair
couch
potted plant
bed
mirror
dining table
window
desk
toilet
door
tv
laptop
mouse
remote
keyboard
cell phone
microwave
oven
toaster
sink
refrigerator
blender
book
clock
vase
scissors
teddy bear
hair drier
toothbrush
LABELMAP_EOF
          chown eric:users ${cfg.storage.configPath}/labelmap/coco-80.txt
        fi

        # Read secrets - Cobra cameras
        RTSP_USER=$(cat /run/agenix/frigate-rtsp-username)
        RTSP_PASS=$(cat /run/agenix/frigate-rtsp-password)
        RTSP_PASS_ENCODED=$(echo "$RTSP_PASS" | ${pkgs.python3}/bin/python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))")

        CAMERA_IPS=$(cat /run/agenix/frigate-camera-ips)
        CAM1_IP=$(echo "$CAMERA_IPS" | ${pkgs.jq}/bin/jq -r '.cobra_cam_1')
        CAM2_IP=$(echo "$CAMERA_IPS" | ${pkgs.jq}/bin/jq -r '.cobra_cam_2')
        CAM3_IP=$(echo "$CAMERA_IPS" | ${pkgs.jq}/bin/jq -r '.cobra_cam_3')

        # Read secrets - Reolink camera
        REOLINK_USER=$(cat /run/agenix/frigate-reolink-username)
        REOLINK_PASS=$(cat /run/agenix/frigate-reolink-password)
        REOLINK_PASS_ENCODED=$(echo "$REOLINK_PASS" | ${pkgs.python3}/bin/python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))")
        REOLINK_IP=$(echo "$CAMERA_IPS" | ${pkgs.jq}/bin/jq -r '.reolink')

        # Substitute secrets into nix-generated config template
        export RTSP_USER RTSP_PASS_ENCODED CAM1_IP CAM2_IP CAM3_IP REOLINK_USER REOLINK_PASS_ENCODED REOLINK_IP
        ${pkgs.envsubst}/bin/envsubst < ${cfg._configTemplate} > ${cfg.storage.configPath}/config.yaml

        chown eric:users ${cfg.storage.configPath}/config.yaml
      '';

      path = with pkgs; [ coreutils jq python3 envsubst ];
    };

    # Create all required directories
    systemd.tmpfiles.rules = [
      "d ${cfg.storage.configPath} 0755 eric users -"
      "d ${cfg.storage.configPath}/models 0755 eric users -"
      "d ${cfg.storage.configPath}/labelmap 0755 eric users -"
      "d ${cfg.storage.mediaPath} 0755 eric users -"
      "d ${cfg.storage.bufferPath} 0755 eric users -"
    ];

    # Ensure Frigate starts after mosquitto (for MQTT events) and CDI spec generation
    systemd.services.podman-frigate = {
      after = [ "mosquitto.service" ]
        ++ lib.optional cfg.gpu.enable "nvidia-container-toolkit-cdi-generator.service";
      wants = [ "mosquitto.service" ];
      requires = lib.optionals cfg.gpu.enable [ "nvidia-container-toolkit-cdi-generator.service" ];
    };

    # Frigate container
    virtualisation.oci-containers.containers.frigate = {
      image = cfg.image;
      autoStart = true;

      ports = [
        "${toString cfg.port}:5000"
        "8554:8554"
        "8555:8555/tcp"
        "8555:8555/udp"
        # NOTE: 9191:9090 removed — ignored with --network=host and caused
        # false ServiceDown alerts. Use frigate-exporter module for metrics.
      ];

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
        "${cfg.storage.bufferPath}:/tmp/frigate"
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

    # Prometheus integration: handled by frigate-exporter module (exporter/index.nix)
    # The frigate container itself does not expose Prometheus metrics natively.

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
        assertion = cfg.storage.bufferPath != "";
        message = "hwc.media.frigate.storage.bufferPath must be set";
      }
      {
        assertion = builtins.match "^/mnt/.*" cfg.storage.bufferPath != null;
        message = "hwc.media.frigate.storage.bufferPath must be under /mnt";
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
        assertion = config.hwc.monitoring.prometheus.enable;
        message = "Frigate metrics require Prometheus (hwc.monitoring.prometheus.enable = true)";
      }
    ];
  };
}
