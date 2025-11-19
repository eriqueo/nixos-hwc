# domains/server/frigate/index.nix
#
# Frigate NVR - Network Video Recorder
# Charter v6.0 compliant module for Frigate surveillance system
#
# NAMESPACE: hwc.server.frigate.*
#
# DEPENDENCIES:
#   - hwc.infrastructure.hardware.gpu (for GPU acceleration)
#   - hwc.secrets (for RTSP credentials)
#   - virtualisation.oci-containers.backend = "podman"
#
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.frigate;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
    ./parts/mqtt.nix
    ./parts/container.nix
    ./parts/storage.nix
    ./parts/watchdog.nix
  ];

  #==========================================================================
  # IMPLEMENTATION & VALIDATION
  #==========================================================================
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      environment.systemPackages = with pkgs; [ ffmpeg ];


    })

    # Assertions
    {
      assertions = [
        {
          assertion = !cfg.gpu.enable || config.hwc.infrastructure.hardware.gpu.enable;
          message = "hwc.server.frigate.gpu requires hwc.infrastructure.hardware.gpu.enable = true";
        }
        {
          assertion = cfg.gpu.detector != "tensorrt" || cfg.gpu.enable;
          message = "hwc.server.frigate.gpu.detector = 'tensorrt' requires gpu.enable = true";
        }
        {
          assertion = cfg.gpu.detector != "onnx" || cfg.gpu.enable;
          message = "hwc.server.frigate.gpu.detector = 'onnx' requires gpu.enable = true";
        }
        {
          assertion = cfg.gpu.detector != "openvino" || (cfg.hwaccel.type == "vaapi" || cfg.hwaccel.type == "qsv-h264" || cfg.hwaccel.type == "qsv-h265");
          message = "hwc.server.frigate.gpu.detector = 'openvino' requires Intel hwaccel (vaapi or qsv)";
        }
        {
          assertion = cfg.hwaccel.type != "nvidia" || config.hwc.infrastructure.hardware.gpu.type == "nvidia";
          message = "hwc.server.frigate.hwaccel.type = 'nvidia' requires hwc.infrastructure.hardware.gpu.type = 'nvidia'";
        }
        {
          assertion = (cfg.hwaccel.type != "vaapi" && cfg.hwaccel.type != "qsv-h264" && cfg.hwaccel.type != "qsv-h265") || config.hwc.infrastructure.hardware.gpu.type == "intel";
          message = "hwc.server.frigate.hwaccel Intel types require hwc.infrastructure.hardware.gpu.type = 'intel'";
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
          assertion = !cfg.enable || config.hwc.secrets.enable;
          message = "hwc.server.frigate requires hwc.secrets.enable = true for RTSP credentials";
        }
        {
          assertion = !cfg.enable || (config.virtualisation.oci-containers.backend == "podman");
          message = "hwc.server.frigate requires Podman as OCI container backend";
        }
        {
          assertion = !cfg.enable || cfg.mqtt.enable;
          message = "hwc.server.frigate requires MQTT broker for event communication";
        }
      ];
    }
  ];
}
