# domains/server/frigate/parts/container.nix
#
# Frigate Container and Config Generation
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.frigate;

  # Hardware acceleration preset mapping
  hwaccelPreset =
    if cfg.hwaccel.preset != null then cfg.hwaccel.preset
    else if cfg.hwaccel.type == "vaapi" then "preset-vaapi"
    else if cfg.hwaccel.type == "qsv-h264" then "preset-intel-qsv-h264"
    else if cfg.hwaccel.type == "qsv-h265" then "preset-intel-qsv-h265"
    else null;  # nvidia and cpu use custom args

  # Generate hwaccel_args based on acceleration type
  hwaccelArgs =
    if cfg.hwaccel.type == "nvidia" then ''
hwaccel_args:
  - -hwaccel
  - nvdec
  - -hwaccel_device
  - "${cfg.hwaccel.device}"
  - -hwaccel_output_format
  - yuv420p''
    else if hwaccelPreset != null then ''
hwaccel_args: ${hwaccelPreset}''
    else "";  # cpu mode - no hwaccel args

  # Environment variables for NVIDIA GPU (object detection)
  gpuEnv = lib.optionalAttrs cfg.gpu.enable {
    NVIDIA_VISIBLE_DEVICES = "all";
    NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
    CUDA_VISIBLE_DEVICES = toString cfg.gpu.device;
    LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";
  };

  # Environment variables for Intel VAAPI
  intelEnv = lib.optionalAttrs (cfg.hwaccel.type == "vaapi" || cfg.hwaccel.type == "qsv-h264" || cfg.hwaccel.type == "qsv-h265") {
    LIBVA_DRIVER_NAME = cfg.hwaccel.vaapiDriver;
  };

  tensorrtEnv = lib.optionalAttrs (cfg.gpu.detector == "tensorrt") {
    YOLO_MODELS = "yolov7-320";
    USE_FP16 = lib.boolToString cfg.gpu.useFP16;
  };
in
{
  config = lib.mkIf cfg.enable {
    # Config generation service
    systemd.services.frigate-config = {
      description = "Generate Frigate NVR configuration";
      wantedBy = [ "podman-frigate.service" ];
      before = [ "podman-frigate.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        mkdir -p ${cfg.storage.configPath}

        RTSP_USER=$(cat /run/agenix/frigate-rtsp-username)
        RTSP_PASS=$(cat /run/agenix/frigate-rtsp-password)
        RTSP_PASS_ENCODED=$(echo "$RTSP_PASS" | ${pkgs.python3}/bin/python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))")

        CAMERA_IPS=$(cat /run/agenix/frigate-camera-ips)
        CAM1_IP=$(echo "$CAMERA_IPS" | ${pkgs.jq}/bin/jq -r '.cobra_cam_1')
        CAM2_IP=$(echo "$CAMERA_IPS" | ${pkgs.jq}/bin/jq -r '.cobra_cam_2')
        CAM3_IP=$(echo "$CAMERA_IPS" | ${pkgs.jq}/bin/jq -r '.cobra_cam_3')

        cat > ${cfg.storage.configPath}/config.yaml <<EOF
mqtt:
  enabled: ${lib.boolToString cfg.mqtt.enable}
  host: ${cfg.mqtt.host}
  port: ${toString cfg.mqtt.port}

${lib.optionalString (cfg.gpu.detector == "tensorrt") ''
detectors:
  tensorrt:
    type: tensorrt
    device: ${toString cfg.gpu.device}
''}
${lib.optionalString (cfg.gpu.detector == "onnx" && cfg.gpu.enable) ''
detectors:
  onnx:
    type: onnx
    num_threads: 3
    model:
      path: /config/models/yolov9-s-320.onnx
      model_type: yolo-generic
      input_tensor: nchw
      input_pixel_format: rgb
      input_dtype: float
      width: 320
      height: 320
      labelmap_path: /labelmap/coco-80.txt
''}

ffmpeg: &ffmpeg_defaults
  ${lib.optionalString (cfg.hwaccel.type != "cpu") hwaccelArgs}
  input_args:
    - -rtsp_transport
    - tcp
    - -fflags
    - +genpts+discardcorrupt

cameras:
  cobra_cam_1:
    enabled: true
    ffmpeg:
      <<: *ffmpeg_defaults
      inputs:
        - path: rtsp://$RTSP_USER:$RTSP_PASS_ENCODED@$CAM1_IP:554/ch01/0
          roles: [ detect, record ]
    detect:
      width: 1280
      height: 720
      fps: 1
    record:
      enabled: true
      retain:
        days: 7
        mode: active_objects

  cobra_cam_2:
    enabled: true
    ffmpeg:
      <<: *ffmpeg_defaults
      inputs:
        - path: rtsp://$RTSP_USER:$RTSP_PASS_ENCODED@$CAM2_IP:554/ch01/0
          roles: [ detect, record ]
    detect:
      width: 640
      height: 360
      fps: 1
    record:
      enabled: true
      retain:
        days: 7

  cobra_cam_3:
    enabled: true
    ffmpeg:
      <<: *ffmpeg_defaults
      inputs:
        - path: rtsp://$RTSP_USER:$RTSP_PASS_ENCODED@$CAM3_IP:554/ch01/0
          roles: [ detect, record ]
    detect:
      width: 320
      height: 240
      fps: 1
    zones:
      sidewalk:
        coordinates: "0.132,0.468,0.996,0.7,0.993,0.998,0.003,0.996,0.007,0.5"

objects:
  track: [ person, car, truck, bicycle, dog, cat ]

go2rtc:
  streams:
    cobra_cam_1: [ "rtsp://$RTSP_USER:$RTSP_PASS_ENCODED@$CAM1_IP:554/ch01/0" ]
    cobra_cam_2: [ "rtsp://$RTSP_USER:$RTSP_PASS_ENCODED@$CAM2_IP:554/ch01/0" ]
    cobra_cam_3: [ "rtsp://$RTSP_USER:$RTSP_PASS_ENCODED@$CAM3_IP:554/ch01/0" ]

ui:
  live_mode: mse
  timezone: ${cfg.settings.timezone}
EOF

        chown eric:users ${cfg.storage.configPath}/config.yaml
      '';

      path = with pkgs; [ coreutils jq python3 ];
    };

    # Frigate container
    virtualisation.oci-containers.containers.frigate = {
      image = cfg.image;
      autoStart = true;

      extraOptions = [
        "--network=host"
        "--security-opt=label=disable"
        "--privileged"
        "--tmpfs=/tmp/cache:size=1g"
        "--shm-size=${cfg.resources.shmSize}"
        "--memory=${cfg.resources.memory}"
        "--cpus=${cfg.resources.cpus}"
      ]
      # NVIDIA GPU device passthrough (for object detection)
      ++ lib.optionals cfg.gpu.enable [
        "--device=nvidia.com/gpu=${toString cfg.gpu.device}"
      ]
      # Intel iGPU device passthrough (for VAAPI/QSV video acceleration)
      ++ lib.optionals (cfg.hwaccel.type == "vaapi" || cfg.hwaccel.type == "qsv-h264" || cfg.hwaccel.type == "qsv-h265") [
        "--device=${cfg.hwaccel.device}:${cfg.hwaccel.device}"
      ];

      environment = {
        TZ = cfg.settings.timezone;
      } // gpuEnv // intelEnv // tensorrtEnv;

      volumes = [
        "${cfg.storage.configPath}:/config"
        "${cfg.storage.configPath}/models:/config/models:ro"
        "${cfg.storage.mediaPath}:/media/frigate"
        "${cfg.storage.bufferPath}:/tmp/frigate"
        "/etc/localtime:/etc/localtime:ro"
      ];
    };

    # Firewall
    networking.firewall = {
      # Always allow localhost access for reverse proxy
      interfaces."lo".allowedTCPPorts = [ cfg.settings.port ];

      # Optionally restrict external access to Tailscale only
      interfaces."tailscale0" = lib.mkIf cfg.firewall.tailscaleOnly {
        allowedTCPPorts = [ cfg.settings.port 8554 8555 ]
          ++ lib.optionals cfg.mqtt.enable [ cfg.mqtt.port ];
        allowedUDPPorts = [ 8555 ];
      };
    };
  };
}
