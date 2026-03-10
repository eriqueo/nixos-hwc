# domains/media/frigate/parts/config.nix
#
# Frigate NVR configuration — nix-native structured config
# Generates YAML config template with ${VARIABLE} placeholders for secrets
# Runtime service substitutes secrets via envsubst
#
# Stream architecture (fixes green tint from resolution mismatch):
#   - Detect: Uses substreams (ch01/1 @ 1280x720) via go2rtc restream
#   - Record: Uses main streams (ch01/0 @ 4K) via go2rtc restream
#   - All streams flow through go2rtc for stability and WebRTC support
#
{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.media.frigate;
  yaml = pkgs.formats.yaml { };

  # Camera RTSP URL templates (secrets substituted at runtime)
  # Main stream: ch01/0 (4K @ 15fps) - for recording
  rtspUrl = camIpVar: "rtsp://\${RTSP_USER}:\${RTSP_PASS_ENCODED}@\${${camIpVar}}:554/ch01/0";
  # Substream: ch01/1 (1280x720 @ 15fps) - for detection
  rtspUrlSub = camIpVar: "rtsp://\${RTSP_USER}:\${RTSP_PASS_ENCODED}@\${${camIpVar}}:554/ch01/1";

  # Reolink RTSP URL template (different credentials and path)
  reolinkUrl = stream: "rtsp://\${REOLINK_USER}:\${REOLINK_PASS_ENCODED}@\${REOLINK_IP}:554/${stream}";

  # Shared ffmpeg configuration for go2rtc restreams
  # Uses CUDA hwaccel but outputs to CPU memory (nv12) to avoid color space issues
  # during IR mode transitions while still benefiting from GPU decoding
  ffmpegDefaults = {
    global_args = [ "-hide_banner" "-loglevel" "warning" ];
    hwaccel_args = [
      "-hwaccel" "cuda"
      "-hwaccel_device" "0"
    ];  # Let FFmpeg handle pixel format conversion automatically
    input_args = "preset-rtsp-restream";  # Optimized for go2rtc restreams
    output_args = {
      record = "preset-record-generic";
    };
  };

  # Full config structure
  frigateConfig = {
    version = "0.16.0";

    mqtt.enabled = false;

    telemetry.stats = {
      amd_gpu_stats = false;
      intel_gpu_stats = false;
      network_bandwidth = false;
    };

    detectors.onnx = {
      type = "onnx";
      device = "0";
      num_threads = 4;
      execution_providers = [ "cuda" "cpu" ];
    };

    model = {
      path = "/config/models/yolov9-s-320.onnx";
      model_type = "yolo-generic";
      input_tensor = "nchw";
      input_pixel_format = "bgr";
      input_dtype = "float";
      width = 320;
      height = 320;
      labelmap_path = "/labelmap/coco-80.txt";
    };

    record = {
      enabled = true;
      retain = {
        days = 7;
        mode = "motion";
      };
    };

    snapshots = {
      enabled = true;
      retain = {
        default = 10;
        objects = {
          person = 30;
          car = 14;
          truck = 14;
        };
      };
    };

    objects = {
      track = [ "person" "dog" "cat" "car" "truck" ];
      filters = {
        person = { min_score = 0.65; threshold = 0.7; min_area = 3000; };
        dog    = { min_score = 0.6;  threshold = 0.7; min_area = 2000; };
        cat    = { min_score = 0.6;  threshold = 0.7; min_area = 2000; };
      };
    };

    cameras = {
      # Cobra cameras use go2rtc restreams:
      # - Detect: substream (1280x720) via go2rtc - matches detect resolution exactly
      # - Record: main stream (4K) via go2rtc
      cobra_cam_1 = {
        enabled = true;
        audio.enabled = false;
        ffmpeg = ffmpegDefaults // {
          inputs = [
            { path = "rtsp://127.0.0.1:8554/cobra_cam_1_sub"; roles = [ "detect" ]; }
            { path = "rtsp://127.0.0.1:8554/cobra_cam_1"; roles = [ "record" ]; }
          ];
        };
        detect = { width = 1280; height = 720; fps = 5; };
        motion.mask = [
          "0,0,1280,100"      # Top strip (timestamp, etc)
          "0,620,200,720"     # Bottom-left corner
          "1080,620,1280,720" # Bottom-right corner
        ];
        zones.yard_gate = {
          coordinates = "200,620,1000,620,1000,400,200,400";  # Adjusted for 720p
          objects = [ "person" "dog" "cat" ];
          filters.person = { min_area = 5000; threshold = 0.75; };
        };
      };

      cobra_cam_2 = {
        enabled = true;
        audio.enabled = false;
        ffmpeg = ffmpegDefaults // {
          inputs = [
            { path = "rtsp://127.0.0.1:8554/cobra_cam_2_sub"; roles = [ "detect" ]; }
            { path = "rtsp://127.0.0.1:8554/cobra_cam_2"; roles = [ "record" ]; }
          ];
        };
        detect = { width = 1280; height = 720; fps = 5; };  # Match substream exactly
        motion.mask = [ "0,0,1280,120" ];  # Scaled from 640x360
        zones.porch_area = {
          coordinates = "100,680,1180,680,1180,400,100,400";  # Scaled for 1280x720
          objects = [ "person" "dog" "cat" ];
          filters.person = { min_area = 5000; threshold = 0.75; };  # Adjusted for higher res
        };
      };

      cobra_cam_3 = {
        enabled = true;
        audio.enabled = false;
        ffmpeg = ffmpegDefaults // {
          inputs = [
            { path = "rtsp://127.0.0.1:8554/cobra_cam_3_sub"; roles = [ "detect" ]; }
            { path = "rtsp://127.0.0.1:8554/cobra_cam_3"; roles = [ "record" ]; }
          ];
        };
        detect = { width = 1280; height = 720; fps = 5; };  # Match substream exactly
        objects = {
          track = [ "person" "car" "truck" "dog" "cat" ];
          filters = {
            car   = { min_score = 0.7; threshold = 0.75; min_area = 20000; };  # Scaled for 1280x720
            truck = { min_score = 0.7; threshold = 0.75; min_area = 24000; };
          };
        };
        motion.mask = [ "0,0,1280,120" ];  # Scaled from 640x480
        zones = {
          driveway_truck = {
            coordinates = "100,675,800,675,800,525,100,525";  # Scaled for 1280x720
            objects = [ "person" "car" "truck" ];
            filters = {
              car   = { min_area = 20000; };
              truck = { min_area = 24000; };
            };
          };
          sidewalk_front = {
            coordinates = "100,450,1180,450,1180,540,100,540";  # Scaled for 1280x720
            objects = [ "person" "dog" "cat" ];
          };
        };
      };

      # Reolink already uses go2rtc correctly - substream for detect, main for record
      reolink = {
        enabled = true;
        audio.enabled = false;
        ffmpeg = ffmpegDefaults // {
          inputs = [
            { path = "rtsp://127.0.0.1:8554/reolink_sub"; roles = [ "detect" ]; }
            { path = "rtsp://127.0.0.1:8554/reolink"; roles = [ "record" ]; }
          ];
        };
        detect = { width = 640; height = 360; fps = 5; };  # Matches reolink_sub exactly
        motion.mask = [ "0,0,640,40" ];
      };
    };

    go2rtc.streams = {
      # Cobra cameras - main streams (4K) for recording
      # #video=copy ensures no color space conversion during IR mode transitions
      cobra_cam_1 = [ "${rtspUrl "CAM1_IP"}#video=copy" ];
      cobra_cam_2 = [ "${rtspUrl "CAM2_IP"}#video=copy" ];
      cobra_cam_3 = [ "${rtspUrl "CAM3_IP"}#video=copy" ];
      # Cobra cameras - substreams (1280x720) for detection
      cobra_cam_1_sub = [ "${rtspUrlSub "CAM1_IP"}#video=copy" ];
      cobra_cam_2_sub = [ "${rtspUrlSub "CAM2_IP"}#video=copy" ];
      cobra_cam_3_sub = [ "${rtspUrlSub "CAM3_IP"}#video=copy" ];
      # Reolink - main (4K HEVC) for recording, sub (640x360 H264) for detection
      reolink = [ "${reolinkUrl "h264Preview_01_main"}#video=copy" ];
      reolink_sub = [ "${reolinkUrl "h264Preview_01_sub"}#video=copy" ];
    };

    ui.timezone = "America/Denver";
    detect.enabled = true;
  };

  # Generate the YAML config template file
  configTemplate = yaml.generate "frigate-config.yml" frigateConfig;
in
{
  config = lib.mkIf cfg.enable {
    # Export the generated config template for the runtime service to use
    hwc.media.frigate._configTemplate = configTemplate;
  };
}
