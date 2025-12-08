# domains/server/frigate/index.nix
#
# Frigate NVR - Config-First Pattern
# Charter v7.0 Section 19 compliant
#
# NAMESPACE: hwc.server.frigate.*
#
# ARCHITECTURE:
#   - Nix: Container infrastructure (image, GPU, volumes, ports)
#   - YAML: Frigate configuration (cameras, detectors, recording)
#   - Config file: domains/server/frigate/config/config.yml
#
# DEPENDENCIES:
#   - hwc.infrastructure.hardware.gpu (for GPU acceleration)
#   - hwc.secrets (for RTSP credentials)
#   - virtualisation.oci-containers.backend = "podman"
#
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.frigate;

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
    systemd.services.frigate-config = {
      description = "Generate Frigate NVR configuration";
      wantedBy = [ "podman-frigate.service" ];
      before = [ "podman-frigate.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        # Directories created by systemd.tmpfiles.rules
        # Only handle config file generation here

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

    # Create all required directories early in boot (Charter-compliant pattern)
    systemd.tmpfiles.rules = [
      # Config directories
      "d ${cfg.storage.configPath} 0755 eric users -"
      "d ${cfg.storage.configPath}/models 0755 eric users -"
      "d ${cfg.storage.configPath}/labelmap 0755 eric users -"

      # Storage directories
      "d ${cfg.storage.mediaPath} 0755 eric users -"
      "d ${cfg.storage.bufferPath} 0755 eric users -"
    ];

    # Frigate container
    virtualisation.oci-containers.containers.frigate = {
      image = cfg.image;
      autoStart = true;

      ports = [
        "${toString cfg.port}:5000"  # Web UI
        "8554:8554"  # RTSP
        "8555:8555/tcp"  # WebRTC
        "8555:8555/udp"  # WebRTC
        "9191:9090"  # Prometheus metrics
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
        allowedTCPPorts = [ cfg.port 8554 8555 ];  # Web UI, RTSP, WebRTC
        allowedUDPPorts = [ 8555 ];  # WebRTC UDP
      };
    };

    #==========================================================================
    # PROMETHEUS INTEGRATION
    #==========================================================================
    # Add Frigate metrics endpoint to Prometheus scraping
    hwc.server.monitoring.prometheus.scrapeConfigs = lib.mkIf cfg.enable [
      {
        job_name = "frigate-nvr";
        static_configs = [{
          targets = [ "localhost:9191" ];
        }];
        scrape_interval = "30s";
        scrape_timeout = "10s";
        metrics_path = "/metrics";
      }
    ];

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !cfg.gpu.enable || config.hwc.infrastructure.hardware.gpu.enable;
        message = "hwc.server.frigate.gpu requires hwc.infrastructure.hardware.gpu.enable = true";
      }
      {
        assertion = !cfg.enable || (cfg.storage.mediaPath != "");
        message = "hwc.server.frigate.storage.mediaPath must be set";
      }
      {
        assertion = !cfg.enable || (cfg.storage.bufferPath != "");
        message = "hwc.server.frigate.storage.bufferPath must be set";
      }
      {
        assertion = !cfg.enable || (builtins.match "^/mnt/.*" cfg.storage.bufferPath != null);
        message = "hwc.server.frigate.storage.bufferPath must be under /mnt (e.g., /mnt/hot/surveillance/frigate/buffer)";
      }
      {
        assertion = !cfg.enable || (builtins.match "^/mnt/.*" cfg.storage.mediaPath != null);
        message = "hwc.server.frigate.storage.mediaPath must be under /mnt (e.g., /mnt/media/surveillance/frigate/media)";
      }
      {
        assertion = !cfg.enable || config.hwc.secrets.enable;
        message = "hwc.server.frigate requires hwc.secrets.enable = true for RTSP credentials";
      }
      {
        assertion = !cfg.enable || (config.virtualisation.oci-containers.backend == "podman");
        message = "hwc.server.frigate requires Podman as OCI container backend";
      }
      {
        assertion = !cfg.enable || builtins.pathExists configTemplate;
        message = "hwc.server.frigate requires config/config.yml template to exist";
      }
      {
        assertion = !cfg.enable || config.hwc.server.monitoring.prometheus.enable;
        message = "Frigate metrics require Prometheus to be enabled (hwc.server.monitoring.prometheus.enable = true)";
      }
    ];
  };
}
