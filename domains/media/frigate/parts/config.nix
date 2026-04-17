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

    # MQTT for event publishing to n8n workflows
    # Frigate uses --network=host so 127.0.0.1 reaches host mosquitto
    mqtt = {
      enabled = true;
      host = "127.0.0.1";
      port = 1883;
      topic_prefix = "frigate";
      client_id = "frigate-nvr";
      stats_interval = 60;
    };

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
        days = 3;
        mode = "motion";
      };
      alerts.retain = {
        days = 14;
        mode = "motion";
      };
      detections.retain = {
        days = 14;
        mode = "active_objects";
      };
    };

    snapshots = {
      enabled = true;
      bounding_box = true;
      crop = false;
      quality = 70;
      retain = {
        default = 10;
        objects = {
          person = 30;
          car = 7;   # Reduced retention for vehicles
          truck = 7;
        };
      };
    };

    objects = {
      track = [ "person" "dog" "cat" ];
      filters = {
        # Raised thresholds to reduce false positives
        person = { min_score = 0.75; threshold = 0.80; min_area = 5000; };
        dog    = { min_score = 0.70; threshold = 0.75; min_area = 3000; };
        cat    = { min_score = 0.70; threshold = 0.75; min_area = 3000; };
      };
    };

    cameras = {
      # Cobra cameras use go2rtc restreams:
      # - Detect: substream (1280x720) via go2rtc - matches detect resolution exactly
      # - Record: main stream (4K) via go2rtc
      # cobra_cam_1: Carport — road at top, driveway/yard below
      # Events only (no continuous motion recording; saves ~8 GB/day)
      cobra_cam_1 = {
        enabled = true;
        audio.enabled = false;
        ffmpeg = ffmpegDefaults // {
          inputs = [
            { path = "rtsp://127.0.0.1:8554/cobra_cam_1_sub"; roles = [ "detect" ]; }
            { path = "rtsp://127.0.0.1:8554/cobra_cam_1"; roles = [ "record" ]; }
          ];
        };
        detect = { width = 1280; height = 720; fps = 3; };
        motion.mask = [
          "0,0,1280,50"       # Timestamp strip
          "350,0,750,200"     # Bright light area (top center)
          "0,0,1280,300"      # Road and beyond (top ~40%)
        ];
        zones.carport = {
          coordinates = "0,300,1280,300,1280,720,0,720";
          objects = [ "person" "dog" "cat" ];
        };
        review.alerts.required_zones = [ "carport" ];
        review.detections.required_zones = [ "carport" ];
      };

      # cobra_cam_2: Side yard — currently offline (disabled to stop retry storm)
      # TODO: Re-enable and add zones when camera is back online — similar setup to cobra_cam_1
      cobra_cam_2 = {
        enabled = false;
        audio.enabled = false;
        ffmpeg = ffmpegDefaults // {
          inputs = [
            { path = "rtsp://127.0.0.1:8554/cobra_cam_2_sub"; roles = [ "detect" ]; }
            { path = "rtsp://127.0.0.1:8554/cobra_cam_2"; roles = [ "record" ]; }
          ];
        };
        detect = { width = 1280; height = 720; fps = 5; };
        motion.mask = [
          "0,0,1280,50"       # Timestamp strip
          "0,0,1280,280"      # Street and warehouse area (top third)
          "1150,600,1280,720" # Green bin corner (bottom right)
        ];
      };

      # cobra_cam_3: Front porch — mask street beyond fence, detect only in yard
      cobra_cam_3 = {
        enabled = true;
        audio.enabled = false;
        ffmpeg = ffmpegDefaults // {
          inputs = [
            { path = "rtsp://127.0.0.1:8554/cobra_cam_3_sub"; roles = [ "detect" ]; }
            { path = "rtsp://127.0.0.1:8554/cobra_cam_3"; roles = [ "record" ]; }
          ];
        };
        detect = { width = 1280; height = 720; fps = 3; };
        motion.mask = [
          "0,0,1280,50"       # Timestamp strip
          # Street and sidewalk beyond the fence (polygon covering top area)
          "0,0,0,320,400,280,900,280,1280,320,1280,0"
          # Left side neighbor area
          "0,0,0,450,180,380,180,0"
          # Right side street/cars
          "1100,0,1100,400,1280,400,1280,0"
          # Porch deck/railing foreground (bottom strip)
          "0,620,1280,620,1280,720,0,720"
        ];
        # Focus detection on yard area inside fence
        zones.front_yard = {
          coordinates = "180,380,1100,380,1100,700,180,700";
          objects = [ "person" "dog" "cat" ];
        };
        review.alerts.required_zones = [ "front_yard" ];
        review.detections.required_zones = [ "front_yard" ];
      };

      # Reolink (front yard) — fence defines property boundary, driveway on left
      reolink = {
        enabled = true;
        audio.enabled = false;
        ffmpeg = ffmpegDefaults // {
          inputs = [
            { path = "rtsp://127.0.0.1:8554/reolink_sub"; roles = [ "detect" ]; }
            { path = "rtsp://127.0.0.1:8554/reolink_record"; roles = [ "record" ]; }
          ];
        };
        detect = { width = 480; height = 270; fps = 2; };
        motion.mask = [
          "0,0,480,23"        # Timestamp strip (scaled from 640x360)
          "0,0,0,150,75,135,75,0"  # Neighbor's area (left side with blue car)
          "435,0,435,90,480,90,480,0"  # Far right edge
        ];
        objects = {
          track = [ "person" "dog" "cat" "car" "truck" ];
          filters = {
            person = { min_score = 0.70; threshold = 0.75; min_area = 675; };
            dog    = { min_score = 0.65; threshold = 0.70; min_area = 420;  };
            cat    = { min_score = 0.65; threshold = 0.70; min_area = 420;  };
            car    = { min_score = 0.80; threshold = 0.85; min_area = 1690; };
            truck  = { min_score = 0.80; threshold = 0.85; min_area = 1970; };
          };
        };
        # Property zone — yard inside the fence + driveway
        zones.property = {
          coordinates = "75,120,435,120,435,270,75,270";
          objects = [ "person" "dog" "cat" "car" "truck" ];
        };
        review.alerts.required_zones = [ "property" ];
        review.detections.required_zones = [ "property" ];
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
      # Reolink - main (4K HEVC), sub (640x360 H264) for detection
      # Record uses main stream directly (no transcode) — transcode was unstable
      # with kernel/driver mismatch and poisoned go2rtc, killing all camera streams.
      # TODO: Re-enable 1080p transcode after reboot: "ffmpeg:reolink#video=h264#hardware#width=1920#height=1080"
      reolink = [ "${reolinkUrl "h264Preview_01_main"}#video=copy" ];
      reolink_sub = [ "${reolinkUrl "h264Preview_01_sub"}#video=copy" ];
      reolink_record = [ "${reolinkUrl "h264Preview_01_main"}#video=copy" ];
    };

    ui.timezone = "America/Denver";
    detect.enabled = true;

    # Stationary object handling - reduces noise from parked cars
    detect.stationary = {
      interval = 50;  # Check stationary objects every 50 frames (10 seconds at 5fps)
      threshold = 50;  # Frames without movement to be considered stationary
      max_frames = {
        default = 3000;  # Stop tracking stationary objects after ~10 minutes
        objects = {
          car = 300;    # Stop tracking stationary cars after ~1 minute
          truck = 300;  # Stop tracking stationary trucks after ~1 minute
        };
      };
    };
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
